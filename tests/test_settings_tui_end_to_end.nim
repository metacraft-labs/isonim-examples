## test_settings_tui_end_to_end — EX-M10 mandatory integration test.
##
## Real-stack exercise of the EX-M10 settings_app TUI shell + leaves.
## Mirrors the EX-M2 reference (`test_tui_leaves_end_to_end.nim`):
## no mocks, no stubs, no weakened assertions. The test drives the
## canonical demo catalog through the full pipeline:
##
##   * Layer 4 — `settings_app/main_tui.nim` (`buildSettingsApp`,
##     `runSettingsApp`).
##   * Layer 3 — `settings_app/tui/shell.nim` (`renderSettingsShell`
##     with its expand-collapse list-of-groups composition).
##   * Layer 2 — `settings_app/components/{toggle,number,choice,group}`
##     (the shared per-kind item templates and the group dispatch).
##   * Layer 1 — `settings_app/tui/leaves.nim` (the 8-leaf surface
##     wired against real `Switch` / `Input` / `OptionList`
##     widgets).
##   * The real `SettingsVM` from `settings_app/core/vm.nim`.
##   * The real `TerminalRenderer` + `TerminalTestHarness` from
##     `isonim-tui` consumed via `--path:../isonim-tui/src`.
##
## Scripted scenario:
##
##   1. Mount the app; assert the catalog's first group ("appearance")
##      is the active one.
##   2. Switch to a non-default initial state and re-render; assert
##      the data-expanded attribute moves accordingly.
##   3. Toggle `appearance.dark_mode` via the captured Switch handler
##      and assert the VM signal flipped.
##   4. Set `appearance.font_size` to 18 via the Input widget's submit
##      handler.
##   5. Set `appearance.theme` to "Solarized" via the OptionList's
##      select handler.
##   6. Switch the active group to `editor` and assert only the
##      editor rows render.
##   7. Toggle `editor.tabs_to_spaces` via its Switch.
##   8. Drive the number clamping path (above-max -> max).
##   9. Drive the choice rejection path (invalid value -> no change).
##  10. Collapse all groups; assert no item rows render under any
##      group.
##
## Each step asserts the VM state AND the rendered tree's relevant
## attributes / class markers / nested widget node states. EX-M16
## replaced the explicit `rebuildSettingsApp` re-paint with reactive
## shell bindings (`createRenderEffect` over `vm.activeGroupId.val`),
## so the scripted scenarios mount once and assert directly on the
## in-place mutated tree after VM writes. Per-item widget state
## (Switch glyphs, Input value, OptionList highlight) updates through
## each widget's own keydown / click listener which writes the new
## attribute on the same DOM/terminal node.

import std/[strutils, tables, unittest]

import nim_everywhere
import nim_everywhere/async_compat

import isonim/core/signals
import isonim_tui
import isonim_tui/events

import settings_app/main_tui

# EX-M17: install a global FakeAsyncContext so every async VM write
# resolves on the next drain.

var fakeCtx {.threadvar.}: FakeAsyncContext

template installFakeCtx() =
  if fakeCtx == nil:
    fakeCtx = newFakeAsyncContext()
    fakeCtx.install()

proc flushAll() =
  if fakeCtx != nil:
    for _ in 0 ..< 2:
      fakeCtx.advance(100)
      fakeCtx.runPending()
      drainPlatformCallbacks()

proc mountSettingsVM(catalog: SettingsCatalog): SettingsVM =
  installFakeCtx()
  result = newSettingsVM(catalog)
  flushAll()

# ---------------------------------------------------------------------------
# Helpers — locate the rendered group section / item row by attribute. Each
# helper returns the node so a callsite can chain attribute / child
# assertions without re-walking the whole tree.
# ---------------------------------------------------------------------------

proc findGroupSection(root: TerminalNode; groupId: string): TerminalNode =
  for child in root.children:
    if child.attributes.getOrDefault("data-group-id") == groupId:
      return child
  nil

proc itemRowsOf(groupSection: TerminalNode): seq[TerminalNode] =
  ## Every child after the header is an item-row container.
  for i in 1 ..< groupSection.children.len:
    result.add groupSection.children[i]

proc isExpanded(groupSection: TerminalNode): bool =
  groupSection.attributes.getOrDefault("data-expanded") == "true"

proc findSwitchNode(itemRow: TerminalNode): TerminalNode =
  ## The toggle leaf is the last child of an item row. Its first
  ## child is the Switch widget's node (which carries `data-widget=switch`).
  let leaf = itemRow.children[^1]
  for c in leaf.children:
    if c.attributes.getOrDefault("data-widget") == "switch":
      return c
  nil

proc findOptionListNode(itemRow: TerminalNode): TerminalNode =
  let leaf = itemRow.children[^1]
  for c in leaf.children:
    if c.attributes.getOrDefault("data-widget") == "option-list":
      return c
  nil

proc findInputNode(itemRow: TerminalNode): TerminalNode =
  let leaf = itemRow.children[^1]
  for c in leaf.children:
    if c.attributes.getOrDefault("data-widget") == "input":
      return c
  nil

proc findItemRowByLabel(groupSection: TerminalNode;
                       label: string): TerminalNode =
  for row in itemRowsOf(groupSection):
    if row.children.len > 0 and
       row.children[0].attributes.getOrDefault("class") == "settings-label":
      if textContent(row.children[0]) == label:
        return row
  nil

# ---------------------------------------------------------------------------
# Test fixture — fresh VM + harness per `setUp` to avoid leftover state.
# ---------------------------------------------------------------------------

suite "EX-M10: settings TUI shell + leaves end-to-end":

  test "mount: shell paints every group header and only expanded items":
    let catalog = buildDemoSettingsCatalog()
    let vm = mountSettingsVM(catalog)
    let h = newTerminalTestHarness(80, 24)
    let root = runSettingsApp(h, vm)

    check root != nil
    check root.tag == "div"
    check root.attributes.getOrDefault("data-app") == "settings-app"
    # Three groups in the demo catalog -> three top-level sections.
    check root.children.len == 3
    # Default active group is the first one.
    check vm.activeGroupId.val == "appearance"

    let appearance = findGroupSection(root, "appearance")
    let editor = findGroupSection(root, "editor")
    let notifications = findGroupSection(root, "notifications")
    check appearance != nil
    check editor != nil
    check notifications != nil
    check isExpanded(appearance) == true
    check isExpanded(editor) == false
    check isExpanded(notifications) == false
    # Only the expanded section has item rows; the collapsed ones
    # only carry the header.
    check appearance.children.len == 1 + catalog.findGroup("appearance").items.len
    check editor.children.len == 1
    check notifications.children.len == 1

    h.dispose()

  test "group header text + description land in the cell-grid root":
    let catalog = buildDemoSettingsCatalog()
    let vm = mountSettingsVM(catalog)
    let h = newTerminalTestHarness(80, 24)
    let root = runSettingsApp(h, vm)

    let appearance = findGroupSection(root, "appearance")
    let header = appearance.children[0]
    check header.tag == "header"
    check header.attributes.getOrDefault("data-label") == "Appearance"
    # The Appearance group has no description; assert it's absent.
    check not header.attributes.hasKey("data-description")
    # The header's label row must contain the visible label text.
    check textContent(header).contains("Appearance")

    h.dispose()

  test "expanded group renders one row per catalog item, in order":
    let catalog = buildDemoSettingsCatalog()
    let vm = mountSettingsVM(catalog)
    let h = newTerminalTestHarness(80, 24)
    let root = runSettingsApp(h, vm)

    let appearance = findGroupSection(root, "appearance")
    let g = catalog.findGroup("appearance")
    let rows = itemRowsOf(appearance)
    check rows.len == g.items.len
    # Each row's label leaf carries the catalog item's label.
    for i, row in rows:
      let labelNode = row.children[0]
      check labelNode.attributes.getOrDefault("class") == "settings-label"
      check textContent(labelNode) == g.items[i].label

    h.dispose()

  test "appearance.dark_mode toggle: Switch widget paints + VM flips":
    let catalog = buildDemoSettingsCatalog()
    let vm = mountSettingsVM(catalog)
    let h = newTerminalTestHarness(80, 24)
    var root = runSettingsApp(h, vm)

    var appearance = findGroupSection(root, "appearance")
    var darkRow = findItemRowByLabel(appearance, "Dark mode")
    check darkRow != nil
    var switchNode = findSwitchNode(darkRow)
    check switchNode != nil
    # The Switch widget seeds `data-value=off` for `value=false`.
    check switchNode.attributes.getOrDefault("data-value") == "off"
    # And paints the `[●·]` glyph for off.
    check textContent(switchNode).contains("[\xe2\x97\x8f\xc2\xb7]")

    # Drive the captured onChange handler — equivalent to a `Space`
    # keypress on the focused Switch. We synthesise the keydown event
    # directly so the test does not depend on the focus manager
    # state; the captured handler still mutates the VM.
    let switchEv = TerminalEvent(
      kind: ekKey,
      key: KeyEvent(key: "space", kind: kkNamed, rune: 0))
    fireEventWith(switchNode, "keydown", switchEv); flushAll()

    check vm.toggleValue("appearance.dark_mode") == true

    # The Switch widget's own keydown handler flipped its `data-value`
    # attribute and re-painted its glyph row in place — assert against
    # the same node.
    check switchNode.attributes.getOrDefault("data-value") == "on"
    check textContent(switchNode).contains("[\xc2\xb7\xe2\x97\x8f]")

    h.dispose()

  test "appearance.font_size: Input submit clamps + writes through VM":
    let catalog = buildDemoSettingsCatalog()
    let vm = mountSettingsVM(catalog)
    let h = newTerminalTestHarness(80, 24)
    var root = runSettingsApp(h, vm)

    var appearance = findGroupSection(root, "appearance")
    var fontRow = findItemRowByLabel(appearance, "Font size")
    check fontRow != nil
    var inputNode = findInputNode(fontRow)
    check inputNode != nil
    check inputNode.attributes.getOrDefault("value") == "14"
    # Setting a fresh value via the Input widget's mutator triggers
    # the validator + the suggester; submitting fires onSubmit.
    let parentLeaf = fontRow.children[^1]
    check parentLeaf.attributes.getOrDefault("data-suffix") == "pt"

    # Drive the Input widget's keydown handler. The Input's seeded
    # value is "14" with the cursor parked at the end; we issue a
    # Ctrl+U keystroke to clear back to the start, then type "18",
    # then submit with Enter. The widget's onSubmit closure parses,
    # clamps to [10, 32], and writes through `vm.setNumber`.
    block submitNewValue:
      let ctrlU = TerminalEvent(
        kind: ekKey,
        key: KeyEvent(
          key: "u",
          kind: kkChar,
          rune: uint32('u'.ord),
          modifiers: {modCtrl}))
      fireEventWith(inputNode, "keydown", ctrlU); flushAll()
      for ch in ['1', '8']:
        let ev = TerminalEvent(
          kind: ekKey,
          key: KeyEvent(
            key: $ch,
            kind: kkChar,
            rune: uint32(ch.ord)))
        fireEventWith(inputNode, "keydown", ev); flushAll()
      let enter = TerminalEvent(
        kind: ekKey,
        key: KeyEvent(key: "enter", kind: kkNamed, rune: 0))
      fireEventWith(inputNode, "keydown", enter); flushAll()

    # After the Enter submit the captured onSubmit closure clamps + writes
    # to the VM via `setNumber`. 18 is within [10, 32] so it commits as-is.
    check vm.numberValue("appearance.font_size") == 18

    # The number leaf's submit closure also writes `data-value` on the
    # host wrapper in place — assert against the same node.
    check fontRow.children[^1].attributes.getOrDefault("data-value") == "18"

    h.dispose()

  test "appearance.theme: OptionList select dispatches choice to VM":
    let catalog = buildDemoSettingsCatalog()
    let vm = mountSettingsVM(catalog)
    let h = newTerminalTestHarness(80, 24)
    var root = runSettingsApp(h, vm)

    var appearance = findGroupSection(root, "appearance")
    var themeRow = findItemRowByLabel(appearance, "Theme")
    check themeRow != nil
    var optionListNode = findOptionListNode(themeRow)
    check optionListNode != nil
    let leafHost = themeRow.children[^1]
    check leafHost.attributes.getOrDefault("data-value") == "Default"
    check leafHost.attributes.getOrDefault("data-options") ==
      "Default|Solarized|Dracula"

    # Drive the OptionList: Down twice to highlight "Dracula",
    # then Up once to land on "Solarized", then Enter to select.
    let down = TerminalEvent(kind: ekKey,
      key: KeyEvent(key: "down", kind: kkNamed, rune: 0))
    let up = TerminalEvent(kind: ekKey,
      key: KeyEvent(key: "up", kind: kkNamed, rune: 0))
    let enter = TerminalEvent(kind: ekKey,
      key: KeyEvent(key: "enter", kind: kkNamed, rune: 0))
    fireEventWith(optionListNode, "keydown", down); flushAll()
    fireEventWith(optionListNode, "keydown", down); flushAll()
    fireEventWith(optionListNode, "keydown", up); flushAll()
    fireEventWith(optionListNode, "keydown", enter); flushAll()

    check vm.choiceValue("appearance.theme") == "Solarized"

    # The choice leaf's onSelect closure also writes `data-value` on
    # the host wrapper in place.
    check themeRow.children[^1].attributes.getOrDefault("data-value") ==
      "Solarized"

    h.dispose()

  test "setActiveGroup to editor: accordion expands editor, collapses appearance":
    let catalog = buildDemoSettingsCatalog()
    let vm = mountSettingsVM(catalog)
    let h = newTerminalTestHarness(80, 24)
    let root = runSettingsApp(h, vm)

    # The shell's `createRenderEffect` over `vm.activeGroupId.val`
    # toggles each section's `data-expanded` and its item rows in place
    # — no explicit re-render call needed.
    discard vm.setActiveGroup("editor")

    let appearance = findGroupSection(root, "appearance")
    let editor = findGroupSection(root, "editor")
    check isExpanded(appearance) == false
    check isExpanded(editor) == true
    check appearance.children.len == 1            # header only
    let g = catalog.findGroup("editor")
    check editor.children.len == 1 + g.items.len

    h.dispose()

  test "editor.tabs_to_spaces toggle off-state-and-flip":
    let catalog = buildDemoSettingsCatalog()
    let vm = mountSettingsVM(catalog)
    let h = newTerminalTestHarness(80, 24)
    discard vm.setActiveGroup("editor")
    var root = runSettingsApp(h, vm)

    var editor = findGroupSection(root, "editor")
    var tabsRow = findItemRowByLabel(editor, "Insert spaces for tabs")
    check tabsRow != nil
    var switchNode = findSwitchNode(tabsRow)
    # Catalog default is true -> Switch seeds `on`.
    check switchNode.attributes.getOrDefault("data-value") == "on"
    check vm.toggleValue("editor.tabs_to_spaces") == true

    let switchEv = TerminalEvent(kind: ekKey,
      key: KeyEvent(key: "space", kind: kkNamed, rune: 0))
    fireEventWith(switchNode, "keydown", switchEv); flushAll()

    check vm.toggleValue("editor.tabs_to_spaces") == false

    # The Switch widget flipped its own `data-value` in place.
    check switchNode.attributes.getOrDefault("data-value") == "off"

    h.dispose()

  test "number clamping: above-max submit clamps to numberMax":
    let catalog = buildDemoSettingsCatalog()
    let vm = mountSettingsVM(catalog)
    let h = newTerminalTestHarness(80, 24)
    discard vm.setActiveGroup("editor")
    var root = runSettingsApp(h, vm)

    var editor = findGroupSection(root, "editor")
    var tabWidthRow = findItemRowByLabel(editor, "Tab width")
    check tabWidthRow != nil
    var inputNode = findInputNode(tabWidthRow)
    check inputNode != nil

    # The editor.tab_width item is [1, 8]; submitting "99" clamps to 8.
    let ctrlU = TerminalEvent(kind: ekKey,
      key: KeyEvent(
        key: "u",
        kind: kkChar,
        rune: uint32('u'.ord),
        modifiers: {modCtrl}))
    fireEventWith(inputNode, "keydown", ctrlU); flushAll()
    for ch in ['9', '9']:
      let ev = TerminalEvent(kind: ekKey,
        key: KeyEvent(
          key: $ch,
          kind: kkChar,
          rune: uint32(ch.ord)))
      fireEventWith(inputNode, "keydown", ev); flushAll()
    let enter = TerminalEvent(kind: ekKey,
      key: KeyEvent(key: "enter", kind: kkNamed, rune: 0))
    fireEventWith(inputNode, "keydown", enter); flushAll()

    check vm.numberValue("editor.tab_width") == 8

    # The number leaf's submit closure wrote `data-value` on the host
    # wrapper in place.
    check tabWidthRow.children[^1].attributes.getOrDefault("data-value") == "8"

    h.dispose()

  test "choice rejection: invalid programmatic write leaves VM unchanged":
    let catalog = buildDemoSettingsCatalog()
    let vm = mountSettingsVM(catalog)
    let h = newTerminalTestHarness(80, 24)
    discard runSettingsApp(h, vm)

    # Direct VM call with an invalid option: VM rejects, signal stays
    # put. (The OptionList widget itself never offers an invalid value
    # because its rows are seeded from the catalog options, so the
    # rejection branch is best exercised against the VM directly.)
    let ok = vm.setChoice("appearance.theme", "Polonez")
    check ok == false
    check vm.choiceValue("appearance.theme") == "Default"

    h.dispose()

  test "collapseAll: no group renders any item rows":
    let catalog = buildDemoSettingsCatalog()
    let vm = mountSettingsVM(catalog)
    let h = newTerminalTestHarness(80, 24)
    var root = runSettingsApp(h, vm)

    # `vm.setActiveGroup("")` is rejected by the VM (the empty id is
    # not a catalog group). Set the signal directly to bypass the
    # validation — the shell's `createRenderEffect` fires on signal
    # write and mutates the tree in place.
    vm.activeGroupId.val = ""
    for child in root.children:
      check isExpanded(child) == false
      check child.children.len == 1   # header only

    h.dispose()

  test "header click activates the group via setActiveGroup":
    let catalog = buildDemoSettingsCatalog()
    let vm = mountSettingsVM(catalog)
    let h = newTerminalTestHarness(80, 24)
    var root = runSettingsApp(h, vm)
    check vm.activeGroupId.val == "appearance"

    let notifications = findGroupSection(root, "notifications")
    let header = notifications.children[0]
    check header.tag == "header"
    let click = TerminalEvent(kind: ekMouseDown, `type`: "click",
      mouse: MouseEvent(button: mbLeft, row: 0, col: 0))
    fireEventWith(header, "click", click); flushAll()

    check vm.activeGroupId.val == "notifications"
    # Header click → setActiveGroup → shell's `createRenderEffect`
    # flips data-expanded on every section in place.
    check isExpanded(findGroupSection(root, "notifications")) == true
    check isExpanded(findGroupSection(root, "appearance")) == false

    h.dispose()

  test "every group's items render with the catalog's labels and order":
    let catalog = buildDemoSettingsCatalog()
    let vm = mountSettingsVM(catalog)
    let h = newTerminalTestHarness(80, 24)
    let root = runSettingsApp(h, vm)
    for groupIdx in 0 ..< catalog.groups.len:
      let g = catalog.groups[groupIdx]
      discard vm.setActiveGroup(g.id)
      let section = findGroupSection(root, g.id)
      check section != nil
      check isExpanded(section) == true
      let rows = itemRowsOf(section)
      check rows.len == g.items.len
      for i, row in rows:
        check textContent(row.children[0]) == g.items[i].label
    h.dispose()
