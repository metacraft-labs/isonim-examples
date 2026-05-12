## test_settings_web_end_to_end — EX-M11 mandatory integration test.
##
## Real-stack exercise of the EX-M11 settings_app web shell + leaves.
## Mirrors EX-M10's `test_settings_tui_end_to_end.nim`: no mocks, no
## stubs, no weakened assertions. The test drives the canonical demo
## catalog through the full pipeline:
##
##   * Layer 4 — `settings_app/main_web.nim` (`buildSettingsApp`).
##   * Layer 3 — `settings_app/web/shell.nim` (`renderSettingsShell`
##     with its sidebar+pane composition).
##   * Layer 2 — `settings_app/components/{toggle,number,choice,group}`
##     (the shared per-kind item templates and the group dispatch).
##   * Layer 1 — `settings_app/web/leaves.nim` (the 8-leaf surface wired
##     against raw HTML tags + `MockRenderer`'s event dispatch).
##   * The real `SettingsVM` from `settings_app/core/vm.nim`.
##   * The real `MockRenderer` + `MockNode` + `fireEvent` from
##     `isonim/testing/mock_dom`.
##
## Scripted scenario:
##
##   1. Mount the app; assert the sidebar lists every group and the pane
##      shows the first group's items.
##   2. Click the sidebar entry for `editor`; assert `activeGroupId`
##      moves and the pane swaps to the editor group's items.
##   3. Click the toggle checkbox for `editor.tabs_to_spaces`; assert the
##      VM signal flips and the next render reflects it.
##   4. Type into the number input for `editor.tab_width` and dispatch
##      `change`; assert the VM is updated with the clamped value.
##   5. Select an option in `editor.line_endings`; assert the VM is
##      updated.
##   6. Drive the number-clamping path (above-max → clamped to numberMax).
##   7. Drive the choice-rejection path (invalid programmatic write).
##   8. Switch active group back to appearance; assert pane swaps back.
##   9. Reset to defaults; assert every value is back to the catalog
##      default.
##  10. Sidebar entries carry the `active` class for the current group
##      and the empty class for the rest; clicking a different entry
##      shifts the `active` marker.
##
## Each step asserts the VM state AND the rendered tree's relevant
## attributes / class markers / element types. EX-M16 replaced the
## explicit `rebuildSettingsApp` re-paint with reactive shell bindings
## (`createRenderEffect` over `vm.activeGroupId.val`), so the scripted
## scenarios mount once and assert directly on the in-place mutated
## tree after VM writes. Per-item DOM state (checkbox `checked`,
## numeric `value`, select `value`, and the host `data-value` mirrors)
## updates through each leaf's own event listener.

import std/[tables, unittest]

import isonim/core/signals
import isonim/testing/mock_dom

import settings_app/main_web

# ---------------------------------------------------------------------------
# Tree-walking helpers. Each helper locates a sub-tree by attribute so
# the test's intent reads naturally. Returns nil when missing so the
# call site can fail with `check node != nil` rather than a tuple deref.
# ---------------------------------------------------------------------------

proc sidebar(root: MockNode): MockNode =
  for child in root.children:
    if child.tag == "nav" and
       child.attributes.getOrDefault("class") == "settings-sidebar":
      return child
  nil

proc pane(root: MockNode): MockNode =
  for child in root.children:
    if child.tag == "section" and
       child.attributes.getOrDefault("class") == "settings-pane":
      return child
  nil

proc sidebarGroupList(root: MockNode): MockNode =
  let sb = sidebar(root)
  if sb == nil: return nil
  for child in sb.children:
    if child.tag == "ul":
      return child
  nil

proc sidebarEntries(root: MockNode): seq[MockNode] =
  let lst = sidebarGroupList(root)
  if lst == nil: return @[]
  for child in lst.children:
    if child.tag == "li":
      result.add child

proc sidebarEntry(root: MockNode; groupId: string): MockNode =
  for li in sidebarEntries(root):
    if li.attributes.getOrDefault("data-group-id") == groupId:
      return li
  nil

proc sidebarButton(entry: MockNode): MockNode =
  for child in entry.children:
    if child.tag == "button":
      return child
  nil

proc paneGroupSection(root: MockNode): MockNode =
  let p = pane(root)
  if p == nil: return nil
  for child in p.children:
    if child.tag == "section" and
       child.attributes.getOrDefault("class") == "settings-group":
      return child
  nil

proc paneItemRows(root: MockNode): seq[MockNode] =
  let section = paneGroupSection(root)
  if section == nil: return @[]
  for child in section.children:
    if child.tag == "div" and
       child.attributes.getOrDefault("class") == "settings-item":
      result.add child

proc paneItemRowByLabel(root: MockNode; label: string): MockNode =
  for row in paneItemRows(root):
    if row.children.len == 0: continue
    let labelNode = row.children[0]
    if labelNode.tag == "label" and textContent(labelNode) == label:
      return row
  nil

proc checkboxOf(itemRow: MockNode): MockNode =
  ## Toggle leaves return the `<input type="checkbox">` directly.
  let leaf = itemRow.children[^1]
  if leaf.tag == "input" and
     leaf.attributes.getOrDefault("type") == "checkbox":
    return leaf
  nil

proc numberInputOf(itemRow: MockNode): MockNode =
  ## Number leaves wrap an `<input type="number">` inside the host div.
  let leaf = itemRow.children[^1]
  for c in leaf.children:
    if c.tag == "input" and
       c.attributes.getOrDefault("type") == "number":
      return c
  nil

proc selectOf(itemRow: MockNode): MockNode =
  ## Choice leaves wrap a `<select>` inside the host div.
  let leaf = itemRow.children[^1]
  for c in leaf.children:
    if c.tag == "select":
      return c
  nil

# ---------------------------------------------------------------------------
# Test fixtures.
# ---------------------------------------------------------------------------

suite "EX-M11: settings web shell + leaves end-to-end":

  test "mount: sidebar lists every group; pane shows the active one":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let r = MockRenderer()
    let root = buildSettingsApp(r, vm)

    check root != nil
    check root.tag == "div"
    check root.attributes.getOrDefault("data-app") == "settings-app"
    check root.attributes.getOrDefault("class") == "settings-app-web"
    # Two top-level children: <nav class="settings-sidebar"> +
    # <section class="settings-pane">.
    check root.children.len == 2

    let sb = sidebar(root)
    check sb != nil
    let entries = sidebarEntries(root)
    check entries.len == catalog.groups.len
    # Default active group is the first one.
    check vm.activeGroupId.val == "appearance"
    check sidebarEntry(root, "appearance")
      .attributes.getOrDefault("class") == "active"
    check sidebarEntry(root, "editor")
      .attributes.getOrDefault("class") == ""
    check sidebarEntry(root, "notifications")
      .attributes.getOrDefault("class") == ""

    # Pane: one settings-group section, containing one header + N rows.
    let section = paneGroupSection(root)
    check section != nil
    check section.attributes.getOrDefault("data-group-id") == "appearance"
    let rows = paneItemRows(root)
    check rows.len == catalog.findGroup("appearance").items.len

  test "sidebar entries label each group with its display label":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let r = MockRenderer()
    let root = buildSettingsApp(r, vm)

    for g in catalog.groups:
      let entry = sidebarEntry(root, g.id)
      check entry != nil
      let btn = sidebarButton(entry)
      check btn != nil
      check btn.attributes.getOrDefault("data-group-id") == g.id
      check textContent(btn) == g.label

  test "pane header carries the active group's label and description":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let r = MockRenderer()
    let root = buildSettingsApp(r, vm)

    let section = paneGroupSection(root)
    check section != nil
    let header = section.children[0]
    check header.tag == "header"
    check header.attributes.getOrDefault("data-label") == "Appearance"
    # The header's first child is an <h2> with the label text.
    let h2 = header.children[0]
    check h2.tag == "h2"
    check textContent(h2) == "Appearance"

  test "click sidebar 'Editor' entry → setActiveGroup + pane swaps":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let r = MockRenderer()
    let root = buildSettingsApp(r, vm)

    let editorEntry = sidebarEntry(root, "editor")
    check editorEntry != nil
    let editorBtn = sidebarButton(editorEntry)
    check editorBtn != nil
    fireEvent(editorBtn, "click")

    check vm.activeGroupId.val == "editor"

    # The shell's `createRenderEffect` over `vm.activeGroupId.val`
    # swaps the active sidebar entry's class and rebuilds the pane's
    # group section in place — no explicit re-render needed.
    check sidebarEntry(root, "editor")
      .attributes.getOrDefault("class") == "active"
    check sidebarEntry(root, "appearance")
      .attributes.getOrDefault("class") == ""
    let section = paneGroupSection(root)
    check section.attributes.getOrDefault("data-group-id") == "editor"
    let rows = paneItemRows(root)
    check rows.len == catalog.findGroup("editor").items.len

  test "toggle checkbox click flips VM + checked attribute":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let r = MockRenderer()
    discard vm.setActiveGroup("editor")
    let root = buildSettingsApp(r, vm)

    let tabsRow = paneItemRowByLabel(root, "Insert spaces for tabs")
    check tabsRow != nil
    let cb = checkboxOf(tabsRow)
    check cb != nil
    # Catalog default for `editor.tabs_to_spaces` is true.
    check cb.attributes.getOrDefault("checked") == "checked"
    check cb.attributes.getOrDefault("data-value") == "true"
    check vm.toggleValue("editor.tabs_to_spaces") == true

    fireEvent(cb, "click")
    check vm.toggleValue("editor.tabs_to_spaces") == false

    # The checkbox's click listener flipped `checked` + `data-value`
    # on the same node in place.
    check not cb.attributes.hasKey("checked")
    check cb.attributes.getOrDefault("data-value") == "false"

    # Fire again — the second click flips back to true.
    fireEvent(cb, "click")
    check vm.toggleValue("editor.tabs_to_spaces") == true

  test "number input change writes through VM (in-range)":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let r = MockRenderer()
    discard vm.setActiveGroup("editor")
    let root = buildSettingsApp(r, vm)

    let tabWidthRow = paneItemRowByLabel(root, "Tab width")
    check tabWidthRow != nil
    let inp = numberInputOf(tabWidthRow)
    check inp != nil
    check inp.attributes.getOrDefault("value") == "4"
    check inp.attributes.getOrDefault("min") == "1"
    check inp.attributes.getOrDefault("max") == "8"
    check vm.numberValue("editor.tab_width") == 4

    # Simulate the user editing the input value and committing it.
    r.setAttribute(inp, "value", "6")
    fireEvent(inp, "change")
    check vm.numberValue("editor.tab_width") == 6

    # The number leaf's change listener wrote `value` on the input and
    # `data-value` on the host wrapper in place.
    check inp.attributes.getOrDefault("value") == "6"
    let host = tabWidthRow.children[^1]
    check host.attributes.getOrDefault("data-value") == "6"

  test "number clamping: above-max input commits clamped to numberMax":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let r = MockRenderer()
    discard vm.setActiveGroup("editor")
    let root = buildSettingsApp(r, vm)

    let tabWidthRow = paneItemRowByLabel(root, "Tab width")
    let inp = numberInputOf(tabWidthRow)
    check inp != nil
    # editor.tab_width range is [1, 8] — typing 99 must clamp to 8.
    r.setAttribute(inp, "value", "99")
    fireEvent(inp, "change")
    check vm.numberValue("editor.tab_width") == 8

    # The number leaf's change listener clamped `value` + mirrored
    # `data-value` on the host in place.
    check inp.attributes.getOrDefault("value") == "8"
    let host = tabWidthRow.children[^1]
    check host.attributes.getOrDefault("data-value") == "8"

  test "number clamping: below-min input commits clamped to numberMin":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let r = MockRenderer()
    discard vm.setActiveGroup("editor")
    let root = buildSettingsApp(r, vm)

    let tabWidthRow = paneItemRowByLabel(root, "Tab width")
    let inp = numberInputOf(tabWidthRow)
    r.setAttribute(inp, "value", "-3")
    fireEvent(inp, "change")
    check vm.numberValue("editor.tab_width") == 1

    # Listener clamped `value` to "1" in place.
    check inp.attributes.getOrDefault("value") == "1"

  test "select change writes through VM (editor.line_endings → CRLF)":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let r = MockRenderer()
    discard vm.setActiveGroup("editor")
    let root = buildSettingsApp(r, vm)

    let lineRow = paneItemRowByLabel(root, "Line endings")
    check lineRow != nil
    let sel = selectOf(lineRow)
    check sel != nil
    check sel.attributes.getOrDefault("value") == "LF"
    let host = lineRow.children[^1]
    check host.attributes.getOrDefault("data-options") == "LF|CRLF|CR"
    check vm.choiceValue("editor.line_endings") == "LF"

    # Three <option> children, one per option, in order.
    check sel.children.len == 3
    check sel.children[0].attributes.getOrDefault("value") == "LF"
    check sel.children[1].attributes.getOrDefault("value") == "CRLF"
    check sel.children[2].attributes.getOrDefault("value") == "CR"

    r.setAttribute(sel, "value", "CRLF")
    fireEvent(sel, "change")
    check vm.choiceValue("editor.line_endings") == "CRLF"

    # Listener mirrored `data-value` onto the host wrapper in place.
    check sel.attributes.getOrDefault("value") == "CRLF"
    check host.attributes.getOrDefault("data-value") == "CRLF"

  test "choice rejection: invalid programmatic write leaves VM unchanged":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let r = MockRenderer()
    discard buildSettingsApp(r, vm)

    # The <select> only offers catalog options; the rejection path is
    # most cleanly exercised against the VM action directly. The VM
    # rejects, the signal does not change.
    let ok = vm.setChoice("appearance.theme", "Galaxy")
    check ok == false
    check vm.choiceValue("appearance.theme") == "Default"

  test "switching back to appearance restores pane":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let r = MockRenderer()
    let root = buildSettingsApp(r, vm)

    fireEvent(sidebarButton(sidebarEntry(root, "editor")), "click")
    # The shell's `createRenderEffect` rebuilds the pane section on
    # every active-group change in place.
    check paneGroupSection(root).attributes.getOrDefault("data-group-id") ==
      "editor"

    fireEvent(sidebarButton(sidebarEntry(root, "appearance")), "click")
    check paneGroupSection(root).attributes.getOrDefault("data-group-id") ==
      "appearance"
    check vm.activeGroupId.val == "appearance"
    check sidebarEntry(root, "appearance")
      .attributes.getOrDefault("class") == "active"
    check sidebarEntry(root, "editor")
      .attributes.getOrDefault("class") == ""

  test "appearance pane: dark_mode toggle starts off + flips to on":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let r = MockRenderer()
    let root = buildSettingsApp(r, vm)

    let darkRow = paneItemRowByLabel(root, "Dark mode")
    check darkRow != nil
    let cb = checkboxOf(darkRow)
    check cb != nil
    # Catalog default is false; checkbox carries data-value=false and
    # no `checked`.
    check cb.attributes.getOrDefault("data-value") == "false"
    check not cb.attributes.hasKey("checked")
    check vm.toggleValue("appearance.dark_mode") == false

    fireEvent(cb, "click")
    check vm.toggleValue("appearance.dark_mode") == true

    # Click listener wrote `checked` + `data-value` on the same node.
    check cb.attributes.getOrDefault("checked") == "checked"
    check cb.attributes.getOrDefault("data-value") == "true"

  test "appearance.theme select drives choice through VM":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let r = MockRenderer()
    let root = buildSettingsApp(r, vm)

    let themeRow = paneItemRowByLabel(root, "Theme")
    check themeRow != nil
    let sel = selectOf(themeRow)
    check sel != nil
    check sel.attributes.getOrDefault("value") == "Default"
    check vm.choiceValue("appearance.theme") == "Default"

    r.setAttribute(sel, "value", "Solarized")
    fireEvent(sel, "change")
    check vm.choiceValue("appearance.theme") == "Solarized"

    # The select's change listener mirrors the new value onto the
    # host wrapper and moves the `selected` marker to the matching
    # `<option>` in place.
    check sel.attributes.getOrDefault("value") == "Solarized"
    var solOpt: MockNode = nil
    var defaultOpt: MockNode = nil
    for child in sel.children:
      case child.attributes.getOrDefault("value")
      of "Solarized": solOpt = child
      of "Default":   defaultOpt = child
      else: discard
    check solOpt != nil
    check solOpt.attributes.getOrDefault("selected") == "selected"
    # The previously-selected option no longer carries the marker.
    check defaultOpt != nil
    check not defaultOpt.attributes.hasKey("selected")

  test "appearance.font_size number suffix and clamping cooperate":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let r = MockRenderer()
    let root = buildSettingsApp(r, vm)

    let fontRow = paneItemRowByLabel(root, "Font size")
    check fontRow != nil
    let host = fontRow.children[^1]
    check host.attributes.getOrDefault("data-suffix") == "pt"
    # Suffix span is the last child of the host.
    let suffixSpan = host.children[^1]
    check suffixSpan.tag == "span"
    check textContent(suffixSpan) == "pt"

    let inp = numberInputOf(fontRow)
    check inp.attributes.getOrDefault("value") == "14"

    # Within-range: 18 commits as-is.
    r.setAttribute(inp, "value", "18")
    fireEvent(inp, "change")
    check vm.numberValue("appearance.font_size") == 18

    # Above-max: 999 clamps to 32.
    r.setAttribute(inp, "value", "999")
    fireEvent(inp, "change")
    check vm.numberValue("appearance.font_size") == 32

    # The leaf's change listener clamped the input `value` in place.
    check inp.attributes.getOrDefault("value") == "32"

  test "reset to defaults: every value snaps back to the catalog default":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let r = MockRenderer()
    let root = buildSettingsApp(r, vm)

    # Mutate three different items.
    let darkCb = checkboxOf(paneItemRowByLabel(root, "Dark mode"))
    fireEvent(darkCb, "click")
    let themeSel = selectOf(paneItemRowByLabel(root, "Theme"))
    r.setAttribute(themeSel, "value", "Dracula")
    fireEvent(themeSel, "change")
    let fontInp = numberInputOf(paneItemRowByLabel(root, "Font size"))
    r.setAttribute(fontInp, "value", "20")
    fireEvent(fontInp, "change")

    check vm.toggleValue("appearance.dark_mode") == true
    check vm.choiceValue("appearance.theme") == "Dracula"
    check vm.numberValue("appearance.font_size") == 20

    # `resetDefaults` only mutates VM signals; the leaves don't
    # subscribe to per-item value signals (intentional — see EX-M16
    # § D in the umbrella spec), so the DOM `data-value` mirrors stay
    # at the user-driven values until the user interacts again. The
    # VM itself is the source of truth and reflects the reset.
    vm.resetDefaults()
    check vm.toggleValue("appearance.dark_mode") == false
    check vm.choiceValue("appearance.theme") == "Default"
    check vm.numberValue("appearance.font_size") == 14

  test "every group's items render with the catalog's labels and order":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let r = MockRenderer()
    let root = buildSettingsApp(r, vm)
    for g in catalog.groups:
      discard vm.setActiveGroup(g.id)
      # The shell's `createRenderEffect` rebuilds the pane section
      # for the new active group in place.
      let section = paneGroupSection(root)
      check section != nil
      check section.attributes.getOrDefault("data-group-id") == g.id
      let rows = paneItemRows(root)
      check rows.len == g.items.len
      for i, row in rows:
        let labelNode = row.children[0]
        check labelNode.tag == "label"
        check textContent(labelNode) == g.items[i].label

  test "non-active groups have empty class; click shifts active":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let r = MockRenderer()
    let root = buildSettingsApp(r, vm)

    # Initially appearance is active.
    for g in catalog.groups:
      let li = sidebarEntry(root, g.id)
      let cls = li.attributes.getOrDefault("class")
      if g.id == "appearance":
        check cls == "active"
      else:
        check cls == ""

    # Click notifications — the per-entry reactive effect flips the
    # `active` class on every sidebar entry in place.
    fireEvent(sidebarButton(sidebarEntry(root, "notifications")), "click")
    for g in catalog.groups:
      let li = sidebarEntry(root, g.id)
      let cls = li.attributes.getOrDefault("class")
      if g.id == "notifications":
        check cls == "active"
      else:
        check cls == ""

  test "sidebar contains a 'Settings' title above the group list":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let r = MockRenderer()
    let root = buildSettingsApp(r, vm)

    let sb = sidebar(root)
    check sb != nil
    # Two children: <h1> + <ul>.
    check sb.children.len == 2
    let titleNode = sb.children[0]
    check titleNode.tag == "h1"
    check titleNode.attributes.getOrDefault("class") ==
      "settings-sidebar-title"
    check textContent(titleNode) == "Settings"
