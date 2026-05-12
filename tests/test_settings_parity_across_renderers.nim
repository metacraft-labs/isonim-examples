## test_settings_parity_across_renderers — EX-M13 cross-renderer
## SettingsVM-parity test (canonical home).
##
## A single set of scripted scenarios runs against every available
## settings_app renderer; the resulting `SettingsVMSnapshot` is asserted
## byte-identical across every renderer. This is the settings_app
## sibling of EX-M7's `test_vm_parity_across_renderers.nim` for the
## task_app demo — the same shape, the same `RendererDriver` table, the
## same `assertParity` helper.
##
## Coverage on Linux (today, 2026-05-11):
##   * 4 renderers   — TUI, web (MockRenderer), GPUI, Freya.
##   * 5 scenarios   — basic life-cycle, empty/re-init, all-groups,
##                     number clamp, choice rejection.
##   * 20 byte-identical SettingsVMSnapshot assertions per run
##     (5 scenarios * 4 renderers).
##
## Cocoa / Android: the EX-M10..M12 series only built TUI/web/GPUI
## settings_app shells. The Cocoa + Android shells (would be the
## settings_app sibling of EX-M5 / EX-M6 for task_app) do not yet
## exist; the EX-M14 / EX-M15 milestones — when scheduled — pick those
## up. We gate the per-renderer driver registration with
## `when defined(macosx)` / `when defined(android)` so the file
## *source* parses on every host but the matrix stays at 3 on Linux.
## When the Cocoa/Android settings shells land, this matrix grows by
## one each automatically (the macOS host completes the analogue of
## the EX-M5 hand-off, the Android one completes the analogue of
## EX-M6).
##
## Adding a new renderer to this matrix is a one-line append to the
## `drivers` table below — see the `RendererDriver` helper.
##
## Per-renderer event differences (carried forward from EX-M10..M12):
##
##   * TUI uses keyboard events (`space` for Switch, `Ctrl-U` + digits +
##     `enter` for Input, arrow keys + `enter` for OptionList) routed
##     through `fireEventWith`.
##   * Web uses real DOM events (`click` for the checkbox, `change` for
##     `<input type=number>` / `<select>`) routed through `fireEvent`
##     after `setAttribute`.
##   * GPUI uses `click` for everything (the shim only exposes a click
##     listener registry); for number/choice the test mutates
##     `data-value` via `setAttribute` then fires `click`.
##   * Freya uses `click` for everything (same as GPUI — the shim's
##     `<input>` / `<select>`-mapped elements expose no native change /
##     submit event). The Freya shell stacks every group as its own
##     visible card simultaneously, so the driver locates rows by
##     `data-card-id` + the shared `settings-item` row class regardless
##     of which group is currently active.
##
## Each scripted scenario therefore *drives the VM through whatever
## event path that renderer exposes* — the parity invariant is that
## the resulting VM snapshot does not depend on which path was taken.
##
## The choice-rejection scenario (E) deliberately uses a direct
## `vm.setChoice(...)` call because no real renderer surfaces an
## invalid option in production (the picker / OptionList rows are
## seeded from the catalog), and the VM action is the only path that
## can be exercised from the parity test without forging a synthetic
## widget child. This matches the carve-out documented in the EX-M10 /
## EX-M11 / EX-M12 per-renderer test suites.

import std/[json, strutils, tables, unittest]
when defined(macosx) or defined(android):
  import std/sequtils  # `mapIt` for the platform-gated check below

import nim_everywhere

# Settings-app VM types + snapshot helper (shared across drivers).
import settings_app/core/vm
import settings_app/core/demo_catalog
import services/fake_db
import ./helpers/settings_parity_snapshot
import ./helpers/async_drive

# TUI: full import — `TerminalNode` / `TerminalRenderer` / `TerminalEvent` /
# `KeyEvent` are concrete and don't clash with anything else we pull in.
import isonim_tui
import isonim_tui/events

# Web: `MockRenderer`, `MockNode`, `fireEvent`, `setAttribute`.
import isonim/testing/mock_dom

# Composition roots for each renderer. We use `from ... import` so the
# `buildSettingsApp` / `runSettingsApp` overloads (one per renderer,
# distinguished by their renderer argument type) live in the same
# lexical scope but don't pull in renderer-internal pointer aliases that
# could collide.
#
# EX-M16: the explicit `rebuildSettingsApp` re-mount path is gone. The
# reactive shells observe `vm.activeGroupId.val` via
# `createRenderEffect`, so a scripted `vm.setActiveGroup(...)` call
# updates the rendered tree through the reactive graph without any
# rebuild follow-up.
from settings_app/main_tui as tui_app import
  buildSettingsApp, runSettingsApp
from settings_app/main_web as web_app import
  buildSettingsApp
from settings_app/main_gpui as gpui_app import
  buildSettingsApp, runSettingsApp
from settings_app/main_freya as freya_app import
  buildSettingsApp, runSettingsApp

# GPUI: keep the renderer / bindings under a qualified name to avoid
# overload clashes with the TUI / web `textContent`, `setAttribute`,
# `fireEvent`, etc. Each call site uses `gpuiR.<proc>(...)` so the
# compiler picks the GPUI variant explicitly.
import isonim_gpui/renderer as gpuiR
import isonim_gpui/bindings as gpuiB

# Freya: same pattern as GPUI — qualified imports keep the introspection
# helpers (`textContent`, `getAttribute`, `fireEvent`, ...) unambiguous.
import isonim_freya/renderer as freyaR
import isonim_freya/bindings as freyaB

# Cocoa / Android — Linux build skips the body entirely.
when defined(macosx):
  # NOTE: not yet built. The Cocoa settings_app shell is a future
  # milestone (settings analogue of EX-M5). When it lands, replace
  # this comment with the actual import + driver registration below.
  discard
when defined(android):
  # NOTE: not yet built. The Android settings_app shell is a future
  # milestone (settings analogue of EX-M6). When it lands, replace
  # this comment with the actual import + driver registration below.
  discard

# ---------------------------------------------------------------------------
# Scenarios — every entry mutates the VM through the renderer's native
# event surface (Space on a Switch for TUI; click on a checkbox for web;
# click for everything on GPUI). The shell observers paint the new state
# through the reactive graph (EX-M16: `createRenderEffect` over
# `vm.activeGroupId.val` swaps the active group's items / highlights
# the active sidebar entry in place); the parity invariant is that the
# VM's terminal snapshot is identical regardless of which renderer
# drove it.
# ---------------------------------------------------------------------------

type
  ScenarioKind = enum
    skBasic, skEmpty, skAllGroups, skClamp, skChoiceReject

  Scenario = object
    ## A scripted scenario is identified by `kind`; each renderer
    ## driver dispatches on the kind to drive the appropriate event
    ## sequence in its native surface. The expected VM state is the
    ## same across all renderers (that's the whole point of EX-M13).
    name: string
    kind: ScenarioKind

proc scenarioBasic(): Scenario =
  ## Scenario A — switch to "appearance" (already the default, but
  ## the action is idempotent), toggle dark_mode, set font_size 18,
  ## set theme "Solarized".
  Scenario(
    name: "A: basic (activate appearance, toggle dark_mode, font_size=18, theme=Solarized)",
    kind: skBasic)

proc scenarioEmpty(): Scenario =
  ## Scenario B — fresh VM, no actions. Confirms the initial state is
  ## identical across renderers (no setup leaks state through the
  ## leaves' first render pass).
  Scenario(
    name: "B: empty / re-init (no actions)",
    kind: skEmpty)

proc scenarioAllGroups(): Scenario =
  ## Scenario C — visit each group, toggle the first toggle item it
  ## contains. Tests the cross-group switch + per-item write sequence.
  Scenario(
    name: "C: all-groups (visit + toggle first toggle in each group)",
    kind: skAllGroups)

proc scenarioClamp(): Scenario =
  ## Scenario D — set appearance.font_size to 5 (below min=10). The
  ## VM clamps to 10 on every renderer.
  Scenario(
    name: "D: clamp (font_size=5 below min=10 -> clamps to 10)",
    kind: skClamp)

proc scenarioChoiceReject(): Scenario =
  ## Scenario E — try to set appearance.theme to "InvalidName". VM
  ## rejects; signal stays at the catalog default ("Default"). The
  ## widget surface never offers an invalid option in production (the
  ## picker is seeded from the catalog), so this scenario exercises
  ## the rejection path through `vm.setChoice` directly. The parity
  ## invariant is unaffected: every renderer's VM ends in the same
  ## state regardless of which call path drove the rejection.
  Scenario(
    name: "E: choice rejection (invalid theme -> VM unchanged)",
    kind: skChoiceReject)

let allScenarios* = @[
  scenarioBasic(),
  scenarioEmpty(),
  scenarioAllGroups(),
  scenarioClamp(),
  scenarioChoiceReject(),
]

# ---------------------------------------------------------------------------
# Per-renderer driver helpers.
# ---------------------------------------------------------------------------

type
  RendererDriver = object
    name: string
    mountAndDrive: proc(vm: SettingsVM; s: Scenario;
                        drv: AsyncDriver) {.closure.}

# ---------------------------------------------------------------------------
# TUI driver. Drives Switch / Input / OptionList through the real
# keyboard event dispatch documented in EX-M10's per-renderer test
# (`fireEventWith(node, "keydown", ev)`).
# ---------------------------------------------------------------------------

var tuiHarness: TerminalTestHarness = nil

proc tuiFindGroupSection(root: TerminalNode;
                         groupId: string): TerminalNode =
  for child in root.children:
    if child.attributes.getOrDefault("data-group-id") == groupId:
      return child
  nil

proc tuiItemRowsOf(section: TerminalNode): seq[TerminalNode] =
  for i in 1 ..< section.children.len:
    result.add section.children[i]

proc tuiFindItemRowByLabel(section: TerminalNode;
                           label: string): TerminalNode =
  for row in tuiItemRowsOf(section):
    if row.children.len > 0 and
       row.children[0].attributes.getOrDefault("class") == "settings-label":
      if textContent(row.children[0]) == label:
        return row
  nil

proc tuiFindSwitch(itemRow: TerminalNode): TerminalNode =
  let leaf = itemRow.children[^1]
  for c in leaf.children:
    if c.attributes.getOrDefault("data-widget") == "switch":
      return c
  nil

proc tuiFindInput(itemRow: TerminalNode): TerminalNode =
  let leaf = itemRow.children[^1]
  for c in leaf.children:
    if c.attributes.getOrDefault("data-widget") == "input":
      return c
  nil

proc tuiFindOptionList(itemRow: TerminalNode): TerminalNode =
  let leaf = itemRow.children[^1]
  for c in leaf.children:
    if c.attributes.getOrDefault("data-widget") == "option-list":
      return c
  nil

proc tuiToggleSwitch(node: TerminalNode) =
  let ev = TerminalEvent(
    kind: ekKey,
    key: KeyEvent(key: "space", kind: kkNamed, rune: 0))
  fireEventWith(node, "keydown", ev)

proc tuiTypeNumber(inputNode: TerminalNode; value: int) =
  let ctrlU = TerminalEvent(
    kind: ekKey,
    key: KeyEvent(
      key: "u", kind: kkChar, rune: uint32('u'.ord),
      modifiers: {modCtrl}))
  fireEventWith(inputNode, "keydown", ctrlU)
  for ch in $value:
    let ev = TerminalEvent(
      kind: ekKey,
      key: KeyEvent(key: $ch, kind: kkChar, rune: uint32(ch.ord)))
    fireEventWith(inputNode, "keydown", ev)
  let enter = TerminalEvent(
    kind: ekKey,
    key: KeyEvent(key: "enter", kind: kkNamed, rune: 0))
  fireEventWith(inputNode, "keydown", enter)

proc tuiSelectOption(optList: TerminalNode; target: string;
                     options: seq[string]) =
  ## OptionList starts with the current value highlighted; we walk down
  ## by index difference and press Enter. Falls back to a no-op if the
  ## target isn't in `options` (matches the choice-reject path).
  var tgtIdx = -1
  for i, opt in options:
    if opt == target: tgtIdx = i
  var curIdx = -1
  let curStr = optList.attributes.getOrDefault("data-selected")
  for i, opt in options:
    if opt == curStr: curIdx = i
  if curIdx < 0: curIdx = 0
  if tgtIdx < 0: return
  let down = TerminalEvent(
    kind: ekKey,
    key: KeyEvent(key: "down", kind: kkNamed, rune: 0))
  let up = TerminalEvent(
    kind: ekKey,
    key: KeyEvent(key: "up", kind: kkNamed, rune: 0))
  while curIdx < tgtIdx:
    fireEventWith(optList, "keydown", down)
    inc curIdx
  while curIdx > tgtIdx:
    fireEventWith(optList, "keydown", up)
    dec curIdx
  let enter = TerminalEvent(
    kind: ekKey,
    key: KeyEvent(key: "enter", kind: kkNamed, rune: 0))
  fireEventWith(optList, "keydown", enter)

proc tuiApply(vm: SettingsVM; s: Scenario; drv: AsyncDriver) =
  if tuiHarness == nil:
    tuiHarness = newTerminalTestHarness(80, 24)
  let root = runSettingsApp(tuiHarness, vm)
  drv.flush()  # initial load
  case s.kind
  of skBasic:
    discard vm.setActiveGroup("appearance")
    var section = tuiFindGroupSection(root, "appearance")
    var row = tuiFindItemRowByLabel(section, "Dark mode")
    let sw = tuiFindSwitch(row)
    tuiToggleSwitch(sw); drv.flush()

    section = tuiFindGroupSection(root, "appearance")
    row = tuiFindItemRowByLabel(section, "Font size")
    let inp = tuiFindInput(row)
    tuiTypeNumber(inp, 18); drv.flush()

    section = tuiFindGroupSection(root, "appearance")
    row = tuiFindItemRowByLabel(section, "Theme")
    let optList = tuiFindOptionList(row)
    tuiSelectOption(optList, "Solarized",
                    @["Default", "Solarized", "Dracula"])
    drv.flush()
  of skEmpty:
    discard
  of skAllGroups:
    for g in vm.catalog.groups:
      discard vm.setActiveGroup(g.id)
      let section = tuiFindGroupSection(root, g.id)
      for row in tuiItemRowsOf(section):
        let sw = tuiFindSwitch(row)
        if sw != nil:
          tuiToggleSwitch(sw); drv.flush()
          break
  of skClamp:
    discard vm.setActiveGroup("appearance")
    let section = tuiFindGroupSection(root, "appearance")
    let row = tuiFindItemRowByLabel(section, "Font size")
    let inp = tuiFindInput(row)
    tuiTypeNumber(inp, 5); drv.flush()  # below min=10; VM clamps to 10.
  of skChoiceReject:
    discard vm.setChoice("appearance.theme", "InvalidName")
    drv.flush()

# ---------------------------------------------------------------------------
# Web driver. Drives raw DOM `click` / `change` events through
# `fireEvent`. Mirrors the EX-M11 per-renderer test.
# ---------------------------------------------------------------------------

proc webSidebar(root: MockNode): MockNode =
  for child in root.children:
    if child.tag == "nav" and
       child.attributes.getOrDefault("class") == "settings-sidebar":
      return child
  nil

proc webSidebarEntries(root: MockNode): seq[MockNode] =
  let sb = webSidebar(root)
  if sb == nil: return @[]
  for child in sb.children:
    if child.tag == "ul":
      for li in child.children:
        if li.tag == "li":
          result.add li
      return result

proc webSidebarEntry(root: MockNode; groupId: string): MockNode =
  for li in webSidebarEntries(root):
    if li.attributes.getOrDefault("data-group-id") == groupId:
      return li
  nil

proc webSidebarButton(entry: MockNode): MockNode =
  for child in entry.children:
    if child.tag == "button":
      return child
  nil

proc webPane(root: MockNode): MockNode =
  for child in root.children:
    if child.tag == "section" and
       child.attributes.getOrDefault("class") == "settings-pane":
      return child
  nil

proc webPaneSection(root: MockNode): MockNode =
  let p = webPane(root)
  if p == nil: return nil
  for child in p.children:
    if child.tag == "section" and
       child.attributes.getOrDefault("class") == "settings-group":
      return child
  nil

proc webPaneItemRows(root: MockNode): seq[MockNode] =
  let section = webPaneSection(root)
  if section == nil: return @[]
  for child in section.children:
    if child.tag == "div" and
       child.attributes.getOrDefault("class") == "settings-item":
      result.add child

proc webItemRowByLabel(root: MockNode; label: string): MockNode =
  for row in webPaneItemRows(root):
    if row.children.len == 0: continue
    let labelNode = row.children[0]
    if labelNode.tag == "label" and textContent(labelNode) == label:
      return row
  nil

proc webCheckboxOf(row: MockNode): MockNode =
  let leaf = row.children[^1]
  if leaf.tag == "input" and
     leaf.attributes.getOrDefault("type") == "checkbox":
    return leaf
  nil

proc webNumberInputOf(row: MockNode): MockNode =
  let leaf = row.children[^1]
  for c in leaf.children:
    if c.tag == "input" and
       c.attributes.getOrDefault("type") == "number":
      return c
  nil

proc webSelectOf(row: MockNode): MockNode =
  let leaf = row.children[^1]
  for c in leaf.children:
    if c.tag == "select":
      return c
  nil

proc webApply(vm: SettingsVM; s: Scenario; drv: AsyncDriver) =
  let r = MockRenderer()
  let root = buildSettingsApp(r, vm)
  drv.flush()
  case s.kind
  of skBasic:
    fireEvent(webSidebarButton(webSidebarEntry(root, "appearance")), "click")
    let darkCb = webCheckboxOf(webItemRowByLabel(root, "Dark mode"))
    fireEvent(darkCb, "click"); drv.flush()
    let fontInp = webNumberInputOf(webItemRowByLabel(root, "Font size"))
    r.setAttribute(fontInp, "value", "18")
    fireEvent(fontInp, "change"); drv.flush()
    let themeSel = webSelectOf(webItemRowByLabel(root, "Theme"))
    r.setAttribute(themeSel, "value", "Solarized")
    fireEvent(themeSel, "change"); drv.flush()
  of skEmpty:
    discard
  of skAllGroups:
    for g in vm.catalog.groups:
      fireEvent(webSidebarButton(webSidebarEntry(root, g.id)), "click")
      for row in webPaneItemRows(root):
        let cb = webCheckboxOf(row)
        if cb != nil:
          fireEvent(cb, "click"); drv.flush()
          break
  of skClamp:
    fireEvent(webSidebarButton(webSidebarEntry(root, "appearance")), "click")
    let fontInp = webNumberInputOf(webItemRowByLabel(root, "Font size"))
    r.setAttribute(fontInp, "value", "5")
    fireEvent(fontInp, "change"); drv.flush()
  of skChoiceReject:
    discard vm.setChoice("appearance.theme", "InvalidName"); drv.flush()

# ---------------------------------------------------------------------------
# GPUI driver. Drives `click` for everything; for number/choice the
# data-value is mutated via `setAttribute` then `click` is fired.
# ---------------------------------------------------------------------------

proc gpuiFindChildByClass(node: gpuiR.GpuiElement;
                          cls: string): gpuiR.GpuiElement =
  for i in 0 ..< gpuiR.childCount(node):
    let c = gpuiR.nthChild(node, i)
    if gpuiR.getAttribute(c, "class") == cls:
      return c
  nil

proc gpuiGroupsColumn(root: gpuiR.GpuiElement): gpuiR.GpuiElement =
  gpuiFindChildByClass(root, "settings-groups-column")

proc gpuiItemsColumn(root: gpuiR.GpuiElement): gpuiR.GpuiElement =
  gpuiFindChildByClass(root, "settings-items-column")

proc gpuiGroupsRows(root: gpuiR.GpuiElement): seq[gpuiR.GpuiElement] =
  let col = gpuiGroupsColumn(root)
  if col == nil: return @[]
  for i in 0 ..< gpuiR.childCount(col):
    let c = gpuiR.nthChild(col, i)
    let cls = gpuiR.getAttribute(c, "class")
    if cls.startsWith("settings-group-row"):
      result.add c

proc gpuiGroupsRow(root: gpuiR.GpuiElement;
                   groupId: string): gpuiR.GpuiElement =
  for r in gpuiGroupsRows(root):
    if gpuiR.getAttribute(r, "data-group-id") == groupId:
      return r
  nil

proc gpuiItemsSection(root: gpuiR.GpuiElement): gpuiR.GpuiElement =
  let col = gpuiItemsColumn(root)
  if col == nil: return nil
  for i in 0 ..< gpuiR.childCount(col):
    let c = gpuiR.nthChild(col, i)
    if gpuiR.getAttribute(c, "class") == "settings-group":
      return c
  nil

proc gpuiItemRows(root: gpuiR.GpuiElement): seq[gpuiR.GpuiElement] =
  let section = gpuiItemsSection(root)
  if section == nil: return @[]
  for i in 0 ..< gpuiR.childCount(section):
    let c = gpuiR.nthChild(section, i)
    if gpuiR.getAttribute(c, "class") == "settings-item":
      result.add c

proc gpuiItemRowByLabel(root: gpuiR.GpuiElement;
                        label: string): gpuiR.GpuiElement =
  for row in gpuiItemRows(root):
    if gpuiR.childCount(row) == 0: continue
    let labelNode = gpuiR.nthChild(row, 0)
    if gpuiR.getAttribute(labelNode, "class") == "settings-label" and
       gpuiR.textContent(labelNode) == label:
      return row
  nil

proc gpuiToggleOf(row: gpuiR.GpuiElement): gpuiR.GpuiElement =
  let last = gpuiR.nthChild(row, gpuiR.childCount(row) - 1)
  if gpuiR.getAttribute(last, "type") == "checkbox":
    return last
  nil

proc gpuiNumberHostOf(row: gpuiR.GpuiElement): gpuiR.GpuiElement =
  let last = gpuiR.nthChild(row, gpuiR.childCount(row) - 1)
  if gpuiR.getAttribute(last, "class") == "settings-number":
    return last
  nil

proc gpuiNumberInputOf(row: gpuiR.GpuiElement): gpuiR.GpuiElement =
  let host = gpuiNumberHostOf(row)
  if host == nil: return nil
  for i in 0 ..< gpuiR.childCount(host):
    let c = gpuiR.nthChild(host, i)
    if gpuiR.getAttribute(c, "type") == "number":
      return c
  nil

proc gpuiChoiceHostOf(row: gpuiR.GpuiElement): gpuiR.GpuiElement =
  let last = gpuiR.nthChild(row, gpuiR.childCount(row) - 1)
  if gpuiR.getAttribute(last, "class") == "settings-choice":
    return last
  nil

proc gpuiChoiceSelectOf(row: gpuiR.GpuiElement): gpuiR.GpuiElement =
  let host = gpuiChoiceHostOf(row)
  if host == nil: return nil
  for i in 0 ..< gpuiR.childCount(host):
    let c = gpuiR.nthChild(host, i)
    if gpuiR.getAttribute(c, "class") == "":
      return c
  nil

proc gpuiApply(vm: SettingsVM; s: Scenario; drv: AsyncDriver) =
  gpuiB.gpui_reset_tree()
  gpuiR.resetCallbacks()
  let r = gpuiR.GpuiRenderer()
  let root = buildSettingsApp(r, vm)
  drv.flush()
  case s.kind
  of skBasic:
    gpuiR.fireEvent(gpuiGroupsRow(root, "appearance"), "click")
    let darkCb = gpuiToggleOf(gpuiItemRowByLabel(root, "Dark mode"))
    gpuiR.fireEvent(darkCb, "click"); drv.flush()
    let fontInp = gpuiNumberInputOf(gpuiItemRowByLabel(root, "Font size"))
    gpuiR.setAttribute(r, fontInp, "data-value", "18")
    gpuiR.fireEvent(fontInp, "click"); drv.flush()
    let themeSel = gpuiChoiceSelectOf(gpuiItemRowByLabel(root, "Theme"))
    gpuiR.setAttribute(r, themeSel, "data-value", "Solarized")
    gpuiR.fireEvent(themeSel, "click"); drv.flush()
  of skEmpty:
    discard
  of skAllGroups:
    for g in vm.catalog.groups:
      gpuiR.fireEvent(gpuiGroupsRow(root, g.id), "click")
      for row in gpuiItemRows(root):
        let cb = gpuiToggleOf(row)
        if cb != nil:
          gpuiR.fireEvent(cb, "click"); drv.flush()
          break
  of skClamp:
    gpuiR.fireEvent(gpuiGroupsRow(root, "appearance"), "click")
    let fontInp = gpuiNumberInputOf(gpuiItemRowByLabel(root, "Font size"))
    gpuiR.setAttribute(r, fontInp, "data-value", "5")
    gpuiR.fireEvent(fontInp, "click"); drv.flush()
  of skChoiceReject:
    discard vm.setChoice("appearance.theme", "InvalidName"); drv.flush()

# ---------------------------------------------------------------------------
# Freya driver. Drives `click` for everything; for number/choice the
# data-value is mutated via `setAttribute` then `click` is fired.
# Mirrors the GPUI driver's surface; the only structural difference is
# that the Freya shell renders *every* group's items simultaneously
# (each wrapped in a `settings-card`), so the row helpers below look
# inside the per-group `<section>` keyed by `data-group-id` rather than
# the GPUI shell's flat items column.
# ---------------------------------------------------------------------------

proc freyaCard(root: freyaR.FreyaElement;
               groupId: string): freyaR.FreyaElement =
  for i in 0 ..< freyaR.childCount(root):
    let c = freyaR.nthChild(root, i)
    let cls = freyaR.getAttribute(c, "class")
    if cls.startsWith("settings-card") and
       freyaR.getAttribute(c, "data-card-id") == groupId:
      return c
  nil

proc freyaGroupSection(card: freyaR.FreyaElement): freyaR.FreyaElement =
  if card == nil: return nil
  for i in 0 ..< freyaR.childCount(card):
    let c = freyaR.nthChild(card, i)
    if freyaR.getAttribute(c, "class") == "settings-group":
      return c
  nil

proc freyaCardHeader(card: freyaR.FreyaElement): freyaR.FreyaElement =
  let section = freyaGroupSection(card)
  if section == nil: return nil
  for i in 0 ..< freyaR.childCount(section):
    let c = freyaR.nthChild(section, i)
    if freyaR.getAttribute(c, "class") == "settings-group-header":
      return c
  nil

proc freyaItemRows(card: freyaR.FreyaElement): seq[freyaR.FreyaElement] =
  let section = freyaGroupSection(card)
  if section == nil: return @[]
  for i in 0 ..< freyaR.childCount(section):
    let c = freyaR.nthChild(section, i)
    if freyaR.getAttribute(c, "class") == "settings-item":
      result.add c

proc freyaItemRowByLabel(card: freyaR.FreyaElement;
                         label: string): freyaR.FreyaElement =
  for row in freyaItemRows(card):
    if freyaR.childCount(row) == 0: continue
    let labelNode = freyaR.nthChild(row, 0)
    if freyaR.getAttribute(labelNode, "class") == "settings-label" and
       freyaR.textContent(labelNode) == label:
      return row
  nil

proc freyaToggleOf(row: freyaR.FreyaElement): freyaR.FreyaElement =
  let last = freyaR.nthChild(row, freyaR.childCount(row) - 1)
  if freyaR.getAttribute(last, "type") == "checkbox":
    return last
  nil

proc freyaNumberHostOf(row: freyaR.FreyaElement): freyaR.FreyaElement =
  let last = freyaR.nthChild(row, freyaR.childCount(row) - 1)
  if freyaR.getAttribute(last, "class") == "settings-number":
    return last
  nil

proc freyaNumberInputOf(row: freyaR.FreyaElement): freyaR.FreyaElement =
  let host = freyaNumberHostOf(row)
  if host == nil: return nil
  for i in 0 ..< freyaR.childCount(host):
    let c = freyaR.nthChild(host, i)
    if freyaR.getAttribute(c, "type") == "number":
      return c
  nil

proc freyaChoiceHostOf(row: freyaR.FreyaElement): freyaR.FreyaElement =
  let last = freyaR.nthChild(row, freyaR.childCount(row) - 1)
  if freyaR.getAttribute(last, "class") == "settings-choice":
    return last
  nil

proc freyaChoiceSelectOf(row: freyaR.FreyaElement): freyaR.FreyaElement =
  let host = freyaChoiceHostOf(row)
  if host == nil: return nil
  for i in 0 ..< freyaR.childCount(host):
    let c = freyaR.nthChild(host, i)
    if freyaR.getAttribute(c, "class") == "":
      return c
  nil

proc freyaApply(vm: SettingsVM; s: Scenario; drv: AsyncDriver) =
  freyaB.freya_reset_tree()
  freyaR.resetCallbacks()
  let r = freyaR.FreyaRenderer()
  let root = buildSettingsApp(r, vm)
  drv.flush()
  case s.kind
  of skBasic:
    let appearanceCard = freyaCard(root, "appearance")
    freyaR.fireEvent(freyaCardHeader(appearanceCard), "click")
    let darkCb = freyaToggleOf(freyaItemRowByLabel(
      freyaCard(root, "appearance"), "Dark mode"))
    freyaR.fireEvent(darkCb, "click"); drv.flush()
    let fontInp = freyaNumberInputOf(freyaItemRowByLabel(
      freyaCard(root, "appearance"), "Font size"))
    freyaR.setAttribute(r, fontInp, "data-value", "18")
    freyaR.fireEvent(fontInp, "click"); drv.flush()
    let themeSel = freyaChoiceSelectOf(freyaItemRowByLabel(
      freyaCard(root, "appearance"), "Theme"))
    freyaR.setAttribute(r, themeSel, "data-value", "Solarized")
    freyaR.fireEvent(themeSel, "click"); drv.flush()
  of skEmpty:
    discard
  of skAllGroups:
    for g in vm.catalog.groups:
      let cardHeader = freyaCardHeader(freyaCard(root, g.id))
      freyaR.fireEvent(cardHeader, "click")
      let card = freyaCard(root, g.id)
      for row in freyaItemRows(card):
        let cb = freyaToggleOf(row)
        if cb != nil:
          freyaR.fireEvent(cb, "click"); drv.flush()
          break
  of skClamp:
    let appearanceHeader = freyaCardHeader(freyaCard(root, "appearance"))
    freyaR.fireEvent(appearanceHeader, "click")
    let fontInp = freyaNumberInputOf(freyaItemRowByLabel(
      freyaCard(root, "appearance"), "Font size"))
    freyaR.setAttribute(r, fontInp, "data-value", "5")
    freyaR.fireEvent(fontInp, "click"); drv.flush()
  of skChoiceReject:
    discard vm.setChoice("appearance.theme", "InvalidName"); drv.flush()

# ---------------------------------------------------------------------------
# Driver registration.
# ---------------------------------------------------------------------------

proc tuiDriver(): RendererDriver =
  RendererDriver(
    name: "tui",
    mountAndDrive: proc(vm: SettingsVM; s: Scenario; drv: AsyncDriver) =
      tuiApply(vm, s, drv))

proc webDriver(): RendererDriver =
  RendererDriver(
    name: "web",
    mountAndDrive: proc(vm: SettingsVM; s: Scenario; drv: AsyncDriver) =
      webApply(vm, s, drv))

proc gpuiDriver(): RendererDriver =
  RendererDriver(
    name: "gpui",
    mountAndDrive: proc(vm: SettingsVM; s: Scenario; drv: AsyncDriver) =
      gpuiApply(vm, s, drv))

proc freyaDriver(): RendererDriver =
  RendererDriver(
    name: "freya",
    mountAndDrive: proc(vm: SettingsVM; s: Scenario; drv: AsyncDriver) =
      freyaApply(vm, s, drv))

var drivers = @[tuiDriver(), webDriver(), gpuiDriver(), freyaDriver()]

when defined(macosx):
  # Future: append a `cocoaDriver()` here once the settings_app Cocoa
  # shell lands (analogue of EX-M5 for task_app).
  discard
when defined(android):
  # Future: append an `androidDriver()` here once the settings_app
  # Android shell lands (analogue of EX-M6 for task_app).
  discard

# ---------------------------------------------------------------------------
# Test bodies.
# ---------------------------------------------------------------------------

proc runScenarioAcrossDrivers(s: Scenario): seq[SettingsVMSnapshot] =
  result = @[]
  for d in drivers:
    let drv = newAsyncDriver(seed = 42)
    drv.db.seedSettings(buildDemoSettingsCatalog())
    let vm = newSettingsVM(drv.db)
    d.mountAndDrive(vm, s, drv)
    result.add settingsVmSnapshot(vm)
    drv.shutdown()

proc assertParity(s: Scenario; snaps: seq[SettingsVMSnapshot]) =
  doAssert snaps.len == drivers.len
  for i in 1 ..< snaps.len:
    if snaps[i] != snaps[0]:
      let drvA = newAsyncDriver(seed = 42)
      drvA.db.seedSettings(buildDemoSettingsCatalog())
      let vmA = newSettingsVM(drvA.db)
      drivers[0].mountAndDrive(vmA, s, drvA)
      let drvB = newAsyncDriver(seed = 42)
      drvB.db.seedSettings(buildDemoSettingsCatalog())
      let vmB = newSettingsVM(drvB.db)
      drivers[i].mountAndDrive(vmB, s, drvB)
      let jsonA = settingsVmSnapshotJson(vmA)
      let jsonB = settingsVmSnapshotJson(vmB)
      drvA.shutdown(); drvB.shutdown()
      checkpoint(
        "scenario " & s.name & " — " & drivers[0].name &
        " vs " & drivers[i].name & " diverged.\n" &
        drivers[0].name & ":\n" & jsonA.pretty & "\n" &
        drivers[i].name & ":\n" & jsonB.pretty)
      fail()

suite "EX-M13: cross-renderer SettingsVM-parity across all available renderers":

  test "driver matrix is non-empty and includes the four Linux renderers":
    check drivers.len >= 4
    check drivers[0].name == "tui"
    check drivers[1].name == "web"
    check drivers[2].name == "gpui"
    check drivers[3].name == "freya"
    when defined(macosx):
      check "cocoa" in drivers.mapIt(it.name)
    when defined(android):
      check "android" in drivers.mapIt(it.name)

  test "scenario catalogue lists exactly the 5 EX-M13 scenarios":
    check allScenarios.len == 5
    check allScenarios[0].name.startsWith("A:")
    check allScenarios[1].name.startsWith("B:")
    check allScenarios[2].name.startsWith("C:")
    check allScenarios[3].name.startsWith("D:")
    check allScenarios[4].name.startsWith("E:")

  test "scenario A: basic (toggle dark_mode, font_size=18, theme=Solarized)":
    let s = scenarioBasic()
    let snaps = runScenarioAcrossDrivers(s)
    assertParity(s, snaps)
    check snaps[0].activeGroupId == "appearance"
    var dark = false
    for (k, v) in snaps[0].toggles:
      if k == "appearance.dark_mode": dark = v
    check dark == true
    var fontSize = 0
    for (k, v) in snaps[0].numbers:
      if k == "appearance.font_size": fontSize = v
    check fontSize == 18
    var theme = ""
    for (k, v) in snaps[0].choices:
      if k == "appearance.theme": theme = v
    check theme == "Solarized"

  test "scenario B: empty / re-init produces identical initial snapshot":
    let s = scenarioEmpty()
    let snaps = runScenarioAcrossDrivers(s)
    assertParity(s, snaps)
    check snaps[0].activeGroupId == "appearance"
    for (k, v) in snaps[0].toggles:
      case k
      of "appearance.dark_mode": check v == false
      of "editor.tabs_to_spaces": check v == true
      of "notifications.enable_sounds": check v == true
      of "notifications.show_badges": check v == false
      else: discard
    for (k, v) in snaps[0].numbers:
      case k
      of "appearance.font_size": check v == 14
      of "editor.tab_width": check v == 4
      of "notifications.poll_interval_ms": check v == 5000
      else: discard

  test "scenario C: all-groups (visit + toggle first toggle in each group)":
    let s = scenarioAllGroups()
    let snaps = runScenarioAcrossDrivers(s)
    assertParity(s, snaps)
    # Final active group is the last in the catalog ("notifications").
    check snaps[0].activeGroupId == "notifications"
    for (k, v) in snaps[0].toggles:
      case k
      of "appearance.dark_mode": check v == true
      of "editor.tabs_to_spaces": check v == false
      of "notifications.enable_sounds": check v == false
      else: discard

  test "scenario D: clamp (font_size=5 below min=10 -> clamps to 10)":
    let s = scenarioClamp()
    let snaps = runScenarioAcrossDrivers(s)
    assertParity(s, snaps)
    var fontSize = 0
    for (k, v) in snaps[0].numbers:
      if k == "appearance.font_size": fontSize = v
    check fontSize == 10

  test "scenario E: choice rejection (invalid theme -> VM unchanged)":
    let s = scenarioChoiceReject()
    let snaps = runScenarioAcrossDrivers(s)
    assertParity(s, snaps)
    var theme = ""
    for (k, v) in snaps[0].choices:
      if k == "appearance.theme": theme = v
    check theme == "Default"

  test "JSON snapshot helper is stable and renderer-agnostic":
    let s = scenarioBasic()
    var jsons: seq[string] = @[]
    for d in drivers:
      let drv = newAsyncDriver(seed = 42)
      drv.db.seedSettings(buildDemoSettingsCatalog())
      let vm = newSettingsVM(drv.db)
      d.mountAndDrive(vm, s, drv)
      jsons.add settingsVmSnapshotJson(vm).pretty
      drv.shutdown()
    for i in 1 ..< jsons.len:
      check jsons[i] == jsons[0]

  test "teardown: dispose the per-thread TUI harness":
    if tuiHarness != nil:
      tuiHarness.dispose()
      tuiHarness = nil
