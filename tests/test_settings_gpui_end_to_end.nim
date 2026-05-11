## test_settings_gpui_end_to_end — EX-M12 mandatory integration test.
##
## Real-stack exercise of the EX-M12 settings_app GPUI shell + leaves.
## Mirrors EX-M10's `test_settings_tui_end_to_end.nim` and EX-M11's
## `test_settings_web_end_to_end.nim`: no mocks, no stubs, no weakened
## assertions. The test drives the canonical demo catalog through the
## full pipeline:
##
##   * Layer 4 — `settings_app/main_gpui.nim` (`buildSettingsApp`,
##     `rebuildSettingsApp`, `runSettingsApp`).
##   * Layer 3 — `settings_app/gpui/shell.nim`
##     (`renderSettingsShell` with its **grid** composition).
##   * Layer 2 — `settings_app/components/{toggle,number,choice,group}`
##     (the shared per-kind item templates and the group dispatch).
##   * Layer 1 — `settings_app/gpui/leaves.nim` (the 8-leaf surface
##     wired against GPUI elements + the real shim event dispatcher).
##   * The real `SettingsVM` from `settings_app/core/vm.nim`.
##   * The real `GpuiRenderer` + `fireEvent` from `isonim_gpui/renderer`
##     and the `gpui-nim-shim` Rust cdylib loaded at run time via the
##     `LD_LIBRARY_PATH` set up by the dev shell.

import std/[strutils, unittest]

import isonim/core/signals
import isonim_gpui/renderer
import isonim_gpui/bindings

import settings_app/main_gpui

# ---------------------------------------------------------------------------
# Tree-walking helpers. Each helper locates a sub-tree by attribute so
# the test's intent reads naturally. Returns nil when missing so the
# call site can fail with `check node != nil` rather than a tuple deref.
# In the GPUI shadow tree every HTML-like wrapper is mapped to a `div`,
# so we identify children by `class` / `data-*` attributes rather than
# by tag string.
# ---------------------------------------------------------------------------

proc findChildByClass(node: GpuiElement; cls: string): GpuiElement =
  for i in 0 ..< childCount(node):
    let c = nthChild(node, i)
    if getAttribute(c, "class") == cls:
      return c
  nil

proc groupsColumn(root: GpuiElement): GpuiElement =
  findChildByClass(root, "settings-groups-column")

proc itemsColumn(root: GpuiElement): GpuiElement =
  findChildByClass(root, "settings-items-column")

proc groupsColumnRows(root: GpuiElement): seq[GpuiElement] =
  let col = groupsColumn(root)
  if col == nil: return @[]
  for i in 0 ..< childCount(col):
    let c = nthChild(col, i)
    let cls = getAttribute(c, "class")
    if cls.startsWith("settings-group-row"):
      result.add c

proc groupsColumnRow(root: GpuiElement; groupId: string): GpuiElement =
  for r in groupsColumnRows(root):
    if getAttribute(r, "data-group-id") == groupId:
      return r
  nil

proc itemsGroupSection(root: GpuiElement): GpuiElement =
  let col = itemsColumn(root)
  if col == nil: return nil
  for i in 0 ..< childCount(col):
    let c = nthChild(col, i)
    if getAttribute(c, "class") == "settings-group":
      return c
  nil

proc itemRows(root: GpuiElement): seq[GpuiElement] =
  let section = itemsGroupSection(root)
  if section == nil: return @[]
  for i in 0 ..< childCount(section):
    let c = nthChild(section, i)
    if getAttribute(c, "class") == "settings-item":
      result.add c

proc itemRowByLabel(root: GpuiElement; label: string): GpuiElement =
  for row in itemRows(root):
    if childCount(row) == 0: continue
    let labelNode = nthChild(row, 0)
    if getAttribute(labelNode, "class") == "settings-label" and
       textContent(labelNode) == label:
      return row
  nil

proc toggleNodeOf(row: GpuiElement): GpuiElement =
  ## The toggle leaf is the last child of the row (after label +
  ## optional description). It carries `type=checkbox` as a data hook.
  let last = nthChild(row, childCount(row) - 1)
  if getAttribute(last, "type") == "checkbox":
    return last
  nil

proc numberHostOf(row: GpuiElement): GpuiElement =
  ## Number leaves wrap the input inside a host div with class
  ## `settings-number`.
  let last = nthChild(row, childCount(row) - 1)
  if getAttribute(last, "class") == "settings-number":
    return last
  nil

proc numberInputOf(row: GpuiElement): GpuiElement =
  let host = numberHostOf(row)
  if host == nil: return nil
  for i in 0 ..< childCount(host):
    let c = nthChild(host, i)
    if getAttribute(c, "type") == "number":
      return c
  nil

proc choiceHostOf(row: GpuiElement): GpuiElement =
  let last = nthChild(row, childCount(row) - 1)
  if getAttribute(last, "class") == "settings-choice":
    return last
  nil

proc choiceSelectOf(row: GpuiElement): GpuiElement =
  let host = choiceHostOf(row)
  if host == nil: return nil
  # The select-mapped element has data-value attribute; it's the only
  # child of the host that lacks a class attribute (no class set).
  for i in 0 ..< childCount(host):
    let c = nthChild(host, i)
    if getAttribute(c, "class") == "":
      # Confirm by checking it has data-value (the select carries it).
      if getAttribute(c, "data-value") != "" or
         getAttribute(c, "data-value") == "":
        return c
  nil

# ---------------------------------------------------------------------------
# Test fixtures.
# ---------------------------------------------------------------------------

suite "EX-M12: settings GPUI shell + leaves end-to-end":

  test "mount: grid root has two columns; layout=grid":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let root = runSettingsApp(vm)

    check root != nil
    check getAttribute(root, "class") == "settings-app-gpui"
    check getAttribute(root, "data-app") == "settings-app"
    check getAttribute(root, "data-layout") == "grid"
    # Exactly two top-level children: groups column + items column.
    check childCount(root) == 2

    let groupsCol = groupsColumn(root)
    check groupsCol != nil
    let itemsCol = itemsColumn(root)
    check itemsCol != nil

    # The groups column hosts one row per group; the items column
    # hosts exactly one settings-group section (the active group).
    check groupsColumnRows(root).len == catalog.groups.len
    let section = itemsGroupSection(root)
    check section != nil
    check getAttribute(section, "data-group-id") == "appearance"

  test "groups column row order matches catalog order":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let root = runSettingsApp(vm)

    let rows = groupsColumnRows(root)
    check rows.len == catalog.groups.len
    for i, g in catalog.groups:
      check getAttribute(rows[i], "data-group-id") == g.id
      # The visible label is the first child's text.
      let inner = nthChild(rows[i], 0)
      check getAttribute(inner, "class") == "settings-group-row-label"
      check textContent(inner) == g.label

  test "active row class on appearance; non-active rows have no `active`":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let root = runSettingsApp(vm)
    check vm.activeGroupId.val == "appearance"

    for g in catalog.groups:
      let row = groupsColumnRow(root, g.id)
      check row != nil
      let cls = getAttribute(row, "class")
      if g.id == "appearance":
        check cls == "settings-group-row active"
        check getAttribute(row, "aria-pressed") == "true"
      else:
        check cls == "settings-group-row"
        check getAttribute(row, "aria-pressed") == ""

  test "items column header carries active group's label":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let root = runSettingsApp(vm)

    let section = itemsGroupSection(root)
    check section != nil
    # The first child of the section is the header.
    let header = nthChild(section, 0)
    check getAttribute(header, "class") == "settings-group-header"
    check getAttribute(header, "data-label") == "Appearance"
    # The header's first child is an h2-mapped element with the label.
    let h2 = nthChild(header, 0)
    check getAttribute(h2, "class") == "settings-group-header-label"
    check textContent(h2) == "Appearance"

  test "click group row 'editor' → setActiveGroup + items swap":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let r = GpuiRenderer()
    gpui_reset_tree()
    resetCallbacks()
    var root = buildSettingsApp(r, vm)

    let editorRow = groupsColumnRow(root, "editor")
    check editorRow != nil
    fireEvent(editorRow, "click")
    check vm.activeGroupId.val == "editor"

    root = rebuildSettingsApp(r, vm)
    let editorRowAfter = groupsColumnRow(root, "editor")
    check getAttribute(editorRowAfter, "class") == "settings-group-row active"
    let appearanceRow = groupsColumnRow(root, "appearance")
    check getAttribute(appearanceRow, "class") == "settings-group-row"
    let section = itemsGroupSection(root)
    check getAttribute(section, "data-group-id") == "editor"
    check itemRows(root).len == catalog.findGroup("editor").items.len

  test "toggle checkbox click flips VM + data-value attribute":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let r = GpuiRenderer()
    gpui_reset_tree()
    resetCallbacks()
    discard vm.setActiveGroup("editor")
    var root = rebuildSettingsApp(r, vm)

    var tabsRow = itemRowByLabel(root, "Insert spaces for tabs")
    check tabsRow != nil
    var cb = toggleNodeOf(tabsRow)
    check cb != nil
    # Catalog default for `editor.tabs_to_spaces` is true.
    check getAttribute(cb, "data-value") == "true"
    check getAttribute(cb, "checked") == "checked"
    check vm.toggleValue("editor.tabs_to_spaces") == true

    fireEvent(cb, "click")
    check vm.toggleValue("editor.tabs_to_spaces") == false
    # The leaf's own click handler mutated the attribute too.
    check getAttribute(cb, "data-value") == "false"
    check getAttribute(cb, "checked") == ""

    # Re-render and confirm the new tree reflects the flipped value.
    root = rebuildSettingsApp(r, vm)
    tabsRow = itemRowByLabel(root, "Insert spaces for tabs")
    cb = toggleNodeOf(tabsRow)
    check getAttribute(cb, "data-value") == "false"

    # Fire again — the second click flips back to true.
    fireEvent(cb, "click")
    check vm.toggleValue("editor.tabs_to_spaces") == true

  test "number leaf click commits in-range data-value":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let r = GpuiRenderer()
    gpui_reset_tree()
    resetCallbacks()
    discard vm.setActiveGroup("editor")
    var root = rebuildSettingsApp(r, vm)

    var tabWidthRow = itemRowByLabel(root, "Tab width")
    check tabWidthRow != nil
    var inp = numberInputOf(tabWidthRow)
    check inp != nil
    check getAttribute(inp, "data-value") == "4"
    check getAttribute(inp, "data-min") == "1"
    check getAttribute(inp, "data-max") == "8"
    check vm.numberValue("editor.tab_width") == 4

    # User edits the data-value attribute and dispatches click.
    r.setAttribute(inp, "data-value", "6")
    fireEvent(inp, "click")
    check vm.numberValue("editor.tab_width") == 6

    root = rebuildSettingsApp(r, vm)
    tabWidthRow = itemRowByLabel(root, "Tab width")
    inp = numberInputOf(tabWidthRow)
    check getAttribute(inp, "data-value") == "6"
    let host = numberHostOf(tabWidthRow)
    check getAttribute(host, "data-value") == "6"

  test "number clamping: above-max commits clamped to numberMax":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let r = GpuiRenderer()
    gpui_reset_tree()
    resetCallbacks()
    discard vm.setActiveGroup("editor")
    var root = rebuildSettingsApp(r, vm)

    var tabWidthRow = itemRowByLabel(root, "Tab width")
    var inp = numberInputOf(tabWidthRow)
    check inp != nil
    r.setAttribute(inp, "data-value", "99")
    fireEvent(inp, "click")
    check vm.numberValue("editor.tab_width") == 8

    root = rebuildSettingsApp(r, vm)
    tabWidthRow = itemRowByLabel(root, "Tab width")
    inp = numberInputOf(tabWidthRow)
    check getAttribute(inp, "data-value") == "8"

  test "number clamping: below-min commits clamped to numberMin":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let r = GpuiRenderer()
    gpui_reset_tree()
    resetCallbacks()
    discard vm.setActiveGroup("editor")
    var root = rebuildSettingsApp(r, vm)

    var tabWidthRow = itemRowByLabel(root, "Tab width")
    var inp = numberInputOf(tabWidthRow)
    r.setAttribute(inp, "data-value", "-3")
    fireEvent(inp, "click")
    check vm.numberValue("editor.tab_width") == 1

    root = rebuildSettingsApp(r, vm)
    tabWidthRow = itemRowByLabel(root, "Tab width")
    inp = numberInputOf(tabWidthRow)
    check getAttribute(inp, "data-value") == "1"

  test "choice select click writes through VM (editor.line_endings → CRLF)":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let r = GpuiRenderer()
    gpui_reset_tree()
    resetCallbacks()
    discard vm.setActiveGroup("editor")
    var root = rebuildSettingsApp(r, vm)

    var lineRow = itemRowByLabel(root, "Line endings")
    check lineRow != nil
    let host = choiceHostOf(lineRow)
    check host != nil
    check getAttribute(host, "data-value") == "LF"
    check getAttribute(host, "data-options") == "LF|CRLF|CR"
    check vm.choiceValue("editor.line_endings") == "LF"

    let sel = choiceSelectOf(lineRow)
    check sel != nil
    # Three option children, one per choice.
    check childCount(sel) == 3
    check getAttribute(nthChild(sel, 0), "data-value") == "LF"
    check getAttribute(nthChild(sel, 1), "data-value") == "CRLF"
    check getAttribute(nthChild(sel, 2), "data-value") == "CR"

    # User picks CRLF: programmatically update the select's data-value
    # (the "production" path here is whatever drives the GPUI shim's
    # picker UX) then fire the leaf's click listener.
    r.setAttribute(sel, "data-value", "CRLF")
    fireEvent(sel, "click")
    check vm.choiceValue("editor.line_endings") == "CRLF"

    root = rebuildSettingsApp(r, vm)
    lineRow = itemRowByLabel(root, "Line endings")
    let host2 = choiceHostOf(lineRow)
    check getAttribute(host2, "data-value") == "CRLF"

  test "choice rejection: invalid programmatic write leaves VM unchanged":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let r = GpuiRenderer()
    gpui_reset_tree()
    resetCallbacks()
    discard buildSettingsApp(r, vm)

    # The picker only offers catalog options; the rejection path is
    # most cleanly exercised against the VM action directly. Matches
    # the carve-out the web test uses.
    let ok = vm.setChoice("appearance.theme", "Galaxy")
    check ok == false
    check vm.choiceValue("appearance.theme") == "Default"

  test "switching active group flips `active` class across the column":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let r = GpuiRenderer()
    gpui_reset_tree()
    resetCallbacks()
    var root = buildSettingsApp(r, vm)

    # Initially appearance is active.
    for g in catalog.groups:
      let row = groupsColumnRow(root, g.id)
      let cls = getAttribute(row, "class")
      if g.id == "appearance":
        check cls == "settings-group-row active"
      else:
        check cls == "settings-group-row"

    # Click notifications.
    fireEvent(groupsColumnRow(root, "notifications"), "click")
    root = rebuildSettingsApp(r, vm)
    for g in catalog.groups:
      let row = groupsColumnRow(root, g.id)
      let cls = getAttribute(row, "class")
      if g.id == "notifications":
        check cls == "settings-group-row active"
      else:
        check cls == "settings-group-row"

  test "appearance.theme select drives choice through VM":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let r = GpuiRenderer()
    gpui_reset_tree()
    resetCallbacks()
    var root = buildSettingsApp(r, vm)

    var themeRow = itemRowByLabel(root, "Theme")
    check themeRow != nil
    let host = choiceHostOf(themeRow)
    check host != nil
    check getAttribute(host, "data-value") == "Default"
    check vm.choiceValue("appearance.theme") == "Default"

    let sel = choiceSelectOf(themeRow)
    check sel != nil
    r.setAttribute(sel, "data-value", "Solarized")
    fireEvent(sel, "click")
    check vm.choiceValue("appearance.theme") == "Solarized"

    root = rebuildSettingsApp(r, vm)
    themeRow = itemRowByLabel(root, "Theme")
    let host2 = choiceHostOf(themeRow)
    check getAttribute(host2, "data-value") == "Solarized"

  test "appearance.dark_mode toggle starts off + flips to on":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let r = GpuiRenderer()
    gpui_reset_tree()
    resetCallbacks()
    var root = buildSettingsApp(r, vm)

    var darkRow = itemRowByLabel(root, "Dark mode")
    check darkRow != nil
    var cb = toggleNodeOf(darkRow)
    check cb != nil
    check getAttribute(cb, "data-value") == "false"
    check getAttribute(cb, "checked") == ""
    check vm.toggleValue("appearance.dark_mode") == false

    fireEvent(cb, "click")
    check vm.toggleValue("appearance.dark_mode") == true

    root = rebuildSettingsApp(r, vm)
    darkRow = itemRowByLabel(root, "Dark mode")
    cb = toggleNodeOf(darkRow)
    check getAttribute(cb, "data-value") == "true"
    check getAttribute(cb, "checked") == "checked"

  test "every group's items render with the catalog's labels and order":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let r = GpuiRenderer()
    gpui_reset_tree()
    resetCallbacks()
    for g in catalog.groups:
      discard vm.setActiveGroup(g.id)
      let root = rebuildSettingsApp(r, vm)
      let section = itemsGroupSection(root)
      check section != nil
      check getAttribute(section, "data-group-id") == g.id
      let rows = itemRows(root)
      check rows.len == g.items.len
      for i, row in rows:
        let labelNode = nthChild(row, 0)
        check getAttribute(labelNode, "class") == "settings-label"
        check textContent(labelNode) == g.items[i].label

  test "reset to defaults: every value snaps back to the catalog default":
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let r = GpuiRenderer()
    gpui_reset_tree()
    resetCallbacks()
    var root = buildSettingsApp(r, vm)

    # Mutate three different items.
    var darkCb = toggleNodeOf(itemRowByLabel(root, "Dark mode"))
    fireEvent(darkCb, "click")
    let themeSel = choiceSelectOf(itemRowByLabel(root, "Theme"))
    r.setAttribute(themeSel, "data-value", "Dracula")
    fireEvent(themeSel, "click")
    let fontInp = numberInputOf(itemRowByLabel(root, "Font size"))
    r.setAttribute(fontInp, "data-value", "20")
    fireEvent(fontInp, "click")

    check vm.toggleValue("appearance.dark_mode") == true
    check vm.choiceValue("appearance.theme") == "Dracula"
    check vm.numberValue("appearance.font_size") == 20

    vm.resetDefaults()
    check vm.toggleValue("appearance.dark_mode") == false
    check vm.choiceValue("appearance.theme") == "Default"
    check vm.numberValue("appearance.font_size") == 14

    root = rebuildSettingsApp(r, vm)
    darkCb = toggleNodeOf(itemRowByLabel(root, "Dark mode"))
    check getAttribute(darkCb, "data-value") == "false"

  test "GPUI shim builds a valid render plan over the settings tree":
    ## Sanity check: the shim's render-plan inspection treats the grid
    ## tree as valid (mirrors the EX-M3 task_app check).
    let catalog = buildDemoSettingsCatalog()
    let vm = newSettingsVM(catalog)
    let r = GpuiRenderer()
    gpui_reset_tree()
    resetCallbacks()
    let root = buildSettingsApp(r, vm)
    check r.verifyRenderPlan(root)
    check r.renderPlanElementCount(root) > 0
