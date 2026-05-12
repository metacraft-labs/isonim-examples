## test_settings_components_compile_cross_renderer — EX-M9 mandatory
## integration test.
##
## Driver test that compiles + runs the EX-M9 shared components
## (`settings_app/components/{toggle_item,number_item,choice_item,group}.nim`)
## against four per-platform leaf surfaces. Each renderer fixture lives
## in its own helper module (because the include-pattern the components
## rely on requires the leaf-name procs to live at module scope, and a
## single test module can't sensibly host four include-instances
## without the leaf names colliding):
##
##   * `helpers/settings_compile_tui.nim`   — components compile + run
##     against `TerminalRenderer` (TUI target).
##   * `helpers/settings_compile_web.nim`   — components compile + run
##     against `MockRenderer` (web target; browser `WebRenderer` shares
##     the same proc shape).
##   * `helpers/settings_compile_gpui.nim`  — components compile + run
##     against `GpuiRenderer` (real Rust shim).
##   * `helpers/settings_compile_freya.nim` — components compile + run
##     against `FreyaRenderer` (real Rust shim).
##
## Each helper exposes four builders (`buildToggleRow`, `buildNumberRow`,
## `buildChoiceRow`, `buildGroup`) that wire the real `SettingsVM` from
## `settings_app/core/vm.nim` through the renderer-specific stub leaves
## and into the EX-M9 shared component templates.
##
## The leaves are deliberately minimal stubs — EX-M10..M12 bring real
## platform leaves into `isonim-examples/settings_app/{tui,web,gpui}/leaves.nim`.
## The point of EX-M9's compile-cross check is the *template-include
## pattern + the leaf contract*, not leaf functionality, so reusing the
## EX-M10..M12 leaves here would obscure what's being tested.
##
## Cocoa and Android are not in the Linux test loop today (their
## renderers are gated behind `--os:macosx` / `--os:android` cross-
## compilation). The compile-cross pattern still applies — when those
## fixtures land in EX-M9+ follow-ups they will mirror this driver's
## structure 1:1.
##
## What we assert at run time:
##
##   * The static type of each builder's return value matches the
##     renderer's `Node` type (`TerminalNode` / `MockNode` /
##     `GpuiElement` / `FreyaElement`) — proves the per-platform leaf
##     surface really binds through the template's untyped scope.
##   * The resulting trees have the documented topology (toggle row
##     with label + toggle, group with header + N rows, ...).
##   * Driving `vm.setToggle` / `vm.setNumber` / `vm.setChoice` through
##     the wired-up `onChange` closures updates the real `SettingsVM`
##     signals (the closures must be real — the components don't drop
##     them on the floor).
##
## No mocks of the renderer or the VM. Only the leaf bundle is the
## smallest set of mutators that lets the include compile.

import std/tables
import std/unittest

import settings_app/core/types
import settings_app/core/vm
import settings_app/core/demo_catalog

import ./helpers/settings_compile_tui as tuiCompile
import ./helpers/settings_compile_web as webCompile
import ./helpers/settings_compile_gpui as gpuiCompile
import ./helpers/settings_compile_freya as freyaCompile

# Pull the renderer modules in so we can reference their Node types in
# the `static:` assertions below.
import isonim_tui/renderer as tui_renderer
import isonim/testing/mock_dom as web_renderer
import isonim_gpui/renderer as gpui_renderer
import isonim_freya/renderer as freya_renderer

# ---------------------------------------------------------------------------
# Static type checks: verify each builder's return type matches the
# renderer's documented Node type. These would fail to compile if the
# include-pattern resolved against the wrong leaves or if a future
# refactor changed a leaf's return type.
# ---------------------------------------------------------------------------

static:
  doAssert typeof(tuiCompile.buildToggleRow) is
    proc(vm: SettingsVM; item: SettingsItem): TerminalNode {.nimcall.}
  doAssert typeof(tuiCompile.buildNumberRow) is
    proc(vm: SettingsVM; item: SettingsItem): TerminalNode {.nimcall.}
  doAssert typeof(tuiCompile.buildChoiceRow) is
    proc(vm: SettingsVM; item: SettingsItem): TerminalNode {.nimcall.}
  doAssert typeof(tuiCompile.buildGroup) is
    proc(vm: SettingsVM; group: SettingsGroup): TerminalNode {.nimcall.}

  doAssert typeof(webCompile.buildToggleRow) is
    proc(vm: SettingsVM; item: SettingsItem): MockNode {.nimcall.}
  doAssert typeof(webCompile.buildNumberRow) is
    proc(vm: SettingsVM; item: SettingsItem): MockNode {.nimcall.}
  doAssert typeof(webCompile.buildChoiceRow) is
    proc(vm: SettingsVM; item: SettingsItem): MockNode {.nimcall.}
  doAssert typeof(webCompile.buildGroup) is
    proc(vm: SettingsVM; group: SettingsGroup): MockNode {.nimcall.}

  doAssert typeof(gpuiCompile.buildToggleRow) is
    proc(vm: SettingsVM; item: SettingsItem): GpuiElement {.nimcall.}
  doAssert typeof(gpuiCompile.buildNumberRow) is
    proc(vm: SettingsVM; item: SettingsItem): GpuiElement {.nimcall.}
  doAssert typeof(gpuiCompile.buildChoiceRow) is
    proc(vm: SettingsVM; item: SettingsItem): GpuiElement {.nimcall.}
  doAssert typeof(gpuiCompile.buildGroup) is
    proc(vm: SettingsVM; group: SettingsGroup): GpuiElement {.nimcall.}

  doAssert typeof(freyaCompile.buildToggleRow) is
    proc(vm: SettingsVM; item: SettingsItem): FreyaElement {.nimcall.}
  doAssert typeof(freyaCompile.buildNumberRow) is
    proc(vm: SettingsVM; item: SettingsItem): FreyaElement {.nimcall.}
  doAssert typeof(freyaCompile.buildChoiceRow) is
    proc(vm: SettingsVM; item: SettingsItem): FreyaElement {.nimcall.}
  doAssert typeof(freyaCompile.buildGroup) is
    proc(vm: SettingsVM; group: SettingsGroup): FreyaElement {.nimcall.}

# ---------------------------------------------------------------------------
# Helpers for the run-time assertions: fetch the canonical demo catalog
# and pick one item of each kind so every sub-test exercises the same
# items in the same order.
# ---------------------------------------------------------------------------

proc demoToggleItem(vm: SettingsVM): SettingsItem =
  vm.catalog.findItem("appearance.dark_mode")

proc demoNumberItem(vm: SettingsVM): SettingsItem =
  ## Picks an item *without* a description so the assertions in the
  ## per-renderer suites can rely on a 2-child row (label + numberLeaf).
  ## The descriptioned variants (`appearance.font_size`,
  ## `notifications.poll_interval_ms`) are covered indirectly by the
  ## group test below — that suite iterates the full Appearance group.
  vm.catalog.findItem("editor.tab_width")

proc demoChoiceItem(vm: SettingsVM): SettingsItem =
  vm.catalog.findItem("appearance.theme")

proc demoNumberItemWithSuffix(vm: SettingsVM): SettingsItem =
  ## Picks the number item that *does* have a suffix + description so
  ## the suffix-forwarding branch is exercised at least once per
  ## renderer with a per-leaf assertion. (The Appearance group's
  ## iteration also touches it but only through `childCount`.)
  vm.catalog.findItem("appearance.font_size")

proc demoGroupValue(vm: SettingsVM): SettingsGroup =
  vm.catalog.findGroup("appearance")

# ---------------------------------------------------------------------------
# TUI checks (TerminalRenderer)
# ---------------------------------------------------------------------------

suite "EX-M9: settings components compile-cross — TUI (TerminalRenderer)":
  test "renderToggleItem produces label + toggle row, wires VM action":
    let vm = newSettingsVM(buildDemoSettingsCatalog())
    let item = vm.demoToggleItem
    let row = tuiCompile.buildToggleRow(vm, item)
    check row != nil
    check row.tag == "div"
    # Row children: label, description (dark_mode has a description), toggle.
    check row.children.len == 3
    check row.children[0].tag == "span"           # labelLeaf
    check row.children[1].tag == "span"           # descriptionLeaf
    check row.children[2].tag == "button"         # toggleLeaf

    # Initial signal value is the catalog default (false).
    check vm.toggleValue(item.id) == false

  test "renderNumberItem forwards min/max/step/suffix to the leaf":
    let vm = newSettingsVM(buildDemoSettingsCatalog())
    let item = vm.demoNumberItem
    let row = tuiCompile.buildNumberRow(vm, item)
    let leaf = row.children[^1]
    check leaf.tag == "input"
    check leaf.attributes["min"] == $item.numberMin
    check leaf.attributes["max"] == $item.numberMax
    check leaf.attributes["step"] == $item.numberStep
    # `editor.tab_width` has no suffix, so the leaf does not set
    # `data-suffix`.
    check not leaf.attributes.hasKey("data-suffix")

  test "renderNumberItem forwards a non-empty suffix":
    let vm = newSettingsVM(buildDemoSettingsCatalog())
    let item = vm.demoNumberItemWithSuffix
    let row = tuiCompile.buildNumberRow(vm, item)
    let leaf = row.children[^1]
    check leaf.attributes["data-suffix"] == item.numberSuffix
    check item.numberSuffix == "pt"

  test "renderChoiceItem forwards options to the leaf":
    let vm = newSettingsVM(buildDemoSettingsCatalog())
    let item = vm.demoChoiceItem
    let row = tuiCompile.buildChoiceRow(vm, item)
    check row.children[^1].tag == "select"
    # Three options joined by '|' (Default|Solarized|Dracula).
    check row.children[^1].attributes["data-options"] ==
      "Default|Solarized|Dracula"

  test "renderSettingsGroup dispatches per-item kind":
    let vm = newSettingsVM(buildDemoSettingsCatalog())
    let g = vm.demoGroupValue
    let groupNode = tuiCompile.buildGroup(vm, g)
    check groupNode.tag == "section"
    # 1 header + 3 items (the Appearance group has 3 items).
    check groupNode.children.len == 1 + g.items.len
    check groupNode.children[0].tag == "header"
    # Each item row is the container produced by itemContainerLeaf.
    for i in 0 ..< g.items.len:
      check groupNode.children[1 + i].tag == "div"

# ---------------------------------------------------------------------------
# Web checks (MockRenderer)
# ---------------------------------------------------------------------------

suite "EX-M9: settings components compile-cross — web (MockRenderer)":
  test "renderToggleItem produces label + toggle row":
    let vm = newSettingsVM(buildDemoSettingsCatalog())
    let item = vm.demoToggleItem
    let row = webCompile.buildToggleRow(vm, item)
    check row != nil
    check row.tag == "div"
    check row.children.len == 3
    check row.children[0].tag == "label"
    check row.children[1].tag == "span"
    check row.children[2].tag == "input"
    check row.children[2].attributes["type"] == "checkbox"

  test "renderNumberItem forwards constraints":
    let vm = newSettingsVM(buildDemoSettingsCatalog())
    let item = vm.demoNumberItem
    let row = webCompile.buildNumberRow(vm, item)
    let leaf = row.children[^1]
    check leaf.tag == "input"
    check leaf.attributes["type"] == "number"
    check leaf.attributes["min"] == $item.numberMin
    check leaf.attributes["max"] == $item.numberMax
    check leaf.attributes["value"] == $item.numberDefault

  test "renderChoiceItem emits an <option> per choice":
    let vm = newSettingsVM(buildDemoSettingsCatalog())
    let item = vm.demoChoiceItem
    let row = webCompile.buildChoiceRow(vm, item)
    let leaf = row.children[^1]
    check leaf.tag == "select"
    check leaf.children.len == item.choiceOptions.len

  test "renderSettingsGroup dispatches per-item kind":
    let vm = newSettingsVM(buildDemoSettingsCatalog())
    let g = vm.demoGroupValue
    let groupNode = webCompile.buildGroup(vm, g)
    check groupNode.tag == "section"
    check groupNode.children.len == 1 + g.items.len
    check groupNode.children[0].tag == "header"

# ---------------------------------------------------------------------------
# GPUI checks (GpuiRenderer — real Rust shim)
# ---------------------------------------------------------------------------

suite "EX-M9: settings components compile-cross — GPUI (real Rust shim)":
  test "renderToggleItem produces a row containing the toggle leaf":
    let vm = newSettingsVM(buildDemoSettingsCatalog())
    let item = vm.demoToggleItem
    let row = gpuiCompile.buildToggleRow(vm, item)
    check row != nil
    # Row: label, description, toggle.
    check gpui_renderer.childCount(row) == 3

  test "renderNumberItem produces a row containing the number leaf":
    let vm = newSettingsVM(buildDemoSettingsCatalog())
    let item = vm.demoNumberItem
    let row = gpuiCompile.buildNumberRow(vm, item)
    check row != nil
    check gpui_renderer.childCount(row) == 2  # label + numberLeaf.
    let leaf = gpui_renderer.nthChild(row, 1)
    check gpui_renderer.getAttribute(leaf, "data-min") == $item.numberMin

  test "renderChoiceItem produces a row containing the choice leaf":
    let vm = newSettingsVM(buildDemoSettingsCatalog())
    let item = vm.demoChoiceItem
    let row = gpuiCompile.buildChoiceRow(vm, item)
    check row != nil
    # appearance.theme has a description -> 3 children.
    check gpui_renderer.childCount(row) == 3

  test "renderSettingsGroup builds a header + per-item rows":
    let vm = newSettingsVM(buildDemoSettingsCatalog())
    let g = vm.demoGroupValue
    let groupNode = gpuiCompile.buildGroup(vm, g)
    check groupNode != nil
    check gpui_renderer.childCount(groupNode) == 1 + g.items.len

# ---------------------------------------------------------------------------
# Freya checks (FreyaRenderer — real Rust shim)
# ---------------------------------------------------------------------------

suite "EX-M9: settings components compile-cross — Freya (real Rust shim)":
  test "renderToggleItem produces a row containing the toggle leaf":
    let vm = newSettingsVM(buildDemoSettingsCatalog())
    let item = vm.demoToggleItem
    let row = freyaCompile.buildToggleRow(vm, item)
    check row != nil
    check freya_renderer.childCount(row) == 3

  test "renderNumberItem produces a row containing the number leaf":
    let vm = newSettingsVM(buildDemoSettingsCatalog())
    let item = vm.demoNumberItem
    let row = freyaCompile.buildNumberRow(vm, item)
    check row != nil
    check freya_renderer.childCount(row) == 2

  test "renderChoiceItem produces a row containing the choice leaf":
    let vm = newSettingsVM(buildDemoSettingsCatalog())
    let item = vm.demoChoiceItem
    let row = freyaCompile.buildChoiceRow(vm, item)
    check row != nil
    check freya_renderer.childCount(row) == 3

  test "renderSettingsGroup builds a header + per-item rows":
    let vm = newSettingsVM(buildDemoSettingsCatalog())
    let g = vm.demoGroupValue
    let groupNode = freyaCompile.buildGroup(vm, g)
    check groupNode != nil
    check freya_renderer.childCount(groupNode) == 1 + g.items.len

# ---------------------------------------------------------------------------
# onChange wiring round-trip: drives the captured-handler stub from the
# web helper to prove the components actually thread `vm.setToggle` /
# `vm.setNumber` / `vm.setChoice` through `onChange` (rather than
# silently dropping the parameter on the floor).
# ---------------------------------------------------------------------------

suite "EX-M17: components thread vmRef + itemId through to the real SettingsVM":
  test "toggle row binds vmRef + itemId to the leaf":
    webCompile.clearCapturedHandlers()
    let vm = newSettingsVM(buildDemoSettingsCatalog())
    let item = vm.demoToggleItem
    discard webCompile.buildToggleRow(vm, item)
    check webCompile.capturedToggleVm == vm
    check webCompile.capturedToggleItem == item.id

  test "number row binds vmRef + itemId to the leaf":
    webCompile.clearCapturedHandlers()
    let vm = newSettingsVM(buildDemoSettingsCatalog())
    let item = vm.demoNumberItem
    discard webCompile.buildNumberRow(vm, item)
    check webCompile.capturedNumberVm == vm
    check webCompile.capturedNumberItem == item.id

  test "choice row binds vmRef + itemId to the leaf":
    webCompile.clearCapturedHandlers()
    let vm = newSettingsVM(buildDemoSettingsCatalog())
    let item = vm.demoChoiceItem
    discard webCompile.buildChoiceRow(vm, item)
    check webCompile.capturedChoiceVm == vm
    check webCompile.capturedChoiceItem == item.id

  test "group dispatch binds vmRef + itemId for every item kind":
    webCompile.clearCapturedHandlers()
    let vm = newSettingsVM(buildDemoSettingsCatalog())
    let g = vm.catalog.findGroup("appearance")
    discard webCompile.buildGroup(vm, g)
    # The Appearance group has one toggle, one choice, one number (in
    # that catalog order). After the group renders, every kind has
    # been bound with the matching itemId — proving the group component
    # called the right item template for each kind.
    check webCompile.capturedToggleVm == vm
    check webCompile.capturedChoiceVm == vm
    check webCompile.capturedNumberVm == vm
    check webCompile.capturedToggleItem == "appearance.dark_mode"
    check webCompile.capturedChoiceItem == "appearance.theme"
    check webCompile.capturedNumberItem == "appearance.font_size"

# ---------------------------------------------------------------------------
# Cross-renderer topology fingerprint: the *number of children per
# group* must match across every renderer the components are wired
# against. If the include-pattern broke for any renderer, this check
# would diverge.
# ---------------------------------------------------------------------------

suite "EX-M9: cross-renderer topology fingerprint":
  test "settings-group child count matches across all four renderers":
    let cat = buildDemoSettingsCatalog()
    let tuiVM = newSettingsVM(cat)
    let webVM = newSettingsVM(cat)
    let gpuiVM = newSettingsVM(cat)
    let freyaVM = newSettingsVM(cat)
    let g = cat.findGroup("appearance")
    let expected = 1 + g.items.len

    let tuiTree = tuiCompile.buildGroup(tuiVM, g)
    let webTree = webCompile.buildGroup(webVM, g)
    let gpuiTree = gpuiCompile.buildGroup(gpuiVM, g)
    let freyaTree = freyaCompile.buildGroup(freyaVM, g)

    check tuiTree.children.len == expected
    check webTree.children.len == expected
    check gpui_renderer.childCount(gpuiTree) == expected
    check freya_renderer.childCount(freyaTree) == expected
