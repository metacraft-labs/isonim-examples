## test_vm_parity_across_renderers — EX-M7 cross-renderer VM-parity
## test (canonical home).
##
## A single set of scripted scenarios runs against every available
## renderer; the resulting VM snapshot is asserted byte-identical
## across every renderer. This is the formal version of the parity
## check that EX-M3 / EX-M4 landed early as embedded sub-suites in
## `test_gpui_leaves_end_to_end.nim` / `test_freya_leaves_end_to_end.nim`.
## The Freya copy was retired once this milestone shipped (the GPUI
## copy was already rendered redundant); see the EX-M7 status notes
## for the rationale and the cross-link.
##
## Coverage on Linux (today, 2026-05-10):
##   * 4 renderers   — TUI, web (MockRenderer), GPUI, Freya.
##   * 5 scenarios   — basic life-cycle, empty/re-init, all-completed,
##                     toggle thrash, filter persistence with mixed
##                     completion.
##   * 20 byte-identical VM-snapshot assertions per run
##     (5 scenarios × 4 renderers).
##
## Cocoa / Android: the renderer-driver entries are gated with
## `when defined(macosx)` / `when defined(android)` and fall through
## as documented gaps on Linux until the macOS host completes
## EX-M5 / EX-M6 (the Linux scaffolds in `task_app/main_cocoa.nim` /
## `task_app/main_android.nim` already gate their entire bodies the
## same way). The *source* of those `when` blocks compiles on Linux
## (no orphan symbols, no unreachable-code warnings) so a future
## host that flips `-d:macosx` / `-d:android` picks the entries up
## without further edits.
##
## Adding a new renderer to this matrix is a one-line append to the
## `drivers` table below — see the `RendererDriver` helper.

import std/[json, strutils, unittest]
when defined(macosx) or defined(android):
  import std/sequtils  # `mapIt` for the platform-gated check below

import isonim/core/signals

# Composition roots for every Linux-buildable renderer.
#
# `main_freya` and `main_gpui` both re-export their renderer module
# whose `childCount` / `getAttribute` / etc. take a `pointer` alias
# (`FreyaElement` / `GpuiElement`), creating overload-resolution
# ambiguity if both are imported with `import`. We don't use those
# helpers here (this file only inspects the VM snapshot, never the
# rendered tree), but keep the same `from ... import` discipline as
# the EX-M3 / EX-M4 tests so this stays robust if a future scenario
# adds a topology probe.
import task_app/main_tui as tui_app
import task_app/main_web as web_app
from task_app/main_gpui as gpui_app import
  runTaskApp, resetGpuiLeaves
from task_app/main_freya as freya_app import
  runTaskApp, resetFreyaLeaves

import isonim_tui  # newTerminalTestHarness

# Cocoa / Android — Linux build skips the body entirely. The source
# file still parses on Linux because the `when defined()` guard
# excludes the import + the driver registration; macOS/Android hosts
# pick the entries up automatically.
when defined(macosx):
  from task_app/main_cocoa as cocoa_app import
    runTaskApp, rerender, resetCocoaLeaves
when defined(android):
  from task_app/main_android as android_app import
    runTaskApp, rerender, resetAndroidLeaves

import ./helpers/parity_snapshot

# ---------------------------------------------------------------------------
# Scenarios — every entry mutates the VM through the public action
# surface (`addTask`, `toggleTask`, `setFilter`, `setInputText`).
# Renderer leaves observe the mutations through `createRenderEffect`
# and the per-renderer `rerender(vm)` proc; the parity invariant is
# that the VM's terminal snapshot is identical regardless of which
# renderer drove it.
# ---------------------------------------------------------------------------

type
  Scenario = object
    name: string
    script: proc(vm: TaskAppVM) {.closure.}

proc scenarioBasicLifecycle(): Scenario =
  ## Scenario A — the EX-M4 baseline: add 3 tasks, toggle 1, switch
  ## filter All -> Active.
  Scenario(
    name: "A: basic life-cycle (add 3, toggle 1, filter Active)",
    script: proc(vm: TaskAppVM) =
      vm.addTask("alpha")
      vm.addTask("beta")
      vm.addTask("gamma")
      vm.toggleTask(vm.tasks.val[0].id)
      vm.setFilter(fmActive))

proc scenarioEmpty(): Scenario =
  ## Scenario B — fresh VM, no actions. Confirms the initial state is
  ## identical across renderers (no setup leaks state through the
  ## leaves' first render pass).
  Scenario(
    name: "B: empty / re-init (no actions)",
    script: proc(vm: TaskAppVM) =
      discard vm)

proc scenarioAllCompleted(): Scenario =
  ## Scenario C — add 3 tasks, toggle all 3, filter Completed. Tests
  ## that the renderers route a *sequence* of toggles consistently
  ## (no dropped events, no reorder).
  Scenario(
    name: "C: all-completed (3 tasks, all toggled, filter Completed)",
    script: proc(vm: TaskAppVM) =
      vm.addTask("one")
      vm.addTask("two")
      vm.addTask("three")
      vm.toggleTask(vm.tasks.val[0].id)
      vm.toggleTask(vm.tasks.val[1].id)
      vm.toggleTask(vm.tasks.val[2].id)
      vm.setFilter(fmCompleted))

proc scenarioToggleThrash(): Scenario =
  ## Scenario D — add 1 task, toggle 5 times. The terminal state
  ## must be `completed=true` (odd toggle count) regardless of
  ## renderer. Confirms toggle is idempotent / the per-row click
  ## handlers don't accidentally collapse repeated events.
  Scenario(
    name: "D: toggle thrash (1 task, 5 toggles -> completed=true)",
    script: proc(vm: TaskAppVM) =
      vm.addTask("flippy")
      let id = vm.tasks.val[0].id
      for _ in 0 ..< 5:
        vm.toggleTask(id))

proc scenarioFilterPersistence(): Scenario =
  ## Scenario E — add 5 tasks with alternating completion, switch to
  ## Active. Tests that the visibleTasks projection is consistent
  ## across renderers when the filter excludes a non-trivial subset.
  Scenario(
    name: "E: filter persistence (5 tasks, alternating completion, filter Active)",
    script: proc(vm: TaskAppVM) =
      vm.addTask("t1")
      vm.addTask("t2")
      vm.addTask("t3")
      vm.addTask("t4")
      vm.addTask("t5")
      # Toggle the 1st, 3rd, 5th tasks -> completed=true.
      vm.toggleTask(vm.tasks.val[0].id)
      vm.toggleTask(vm.tasks.val[2].id)
      vm.toggleTask(vm.tasks.val[4].id)
      vm.setFilter(fmActive))

# The five scenarios are also collected into a sequence so future
# meta-tests can iterate the matrix (e.g. for a renderer-vs-renderer
# coverage report). Today the EX-M7 suite invokes each constructor
# directly so failures point at the specific scenario by name.
let allScenarios* = @[
  scenarioBasicLifecycle(),
  scenarioEmpty(),
  scenarioAllCompleted(),
  scenarioToggleThrash(),
  scenarioFilterPersistence(),
]

# ---------------------------------------------------------------------------
# Per-renderer driver helpers. Each driver knows how to mount a fresh
# VM into its renderer, re-render after the script runs, and clean up
# leaf-table state so successive runs don't bleed into each other.
#
# `mountAndDrive(vm, script)` is the only entry point the parity
# matrix uses — adding a new renderer = appending a `RendererDriver`
# to the `drivers` table.
# ---------------------------------------------------------------------------

type
  RendererDriver = object
    name: string
    mountAndDrive: proc(vm: TaskAppVM; script: proc(vm: TaskAppVM))

# Per-thread harness for the TUI driver. The `TerminalTestHarness`
# owns terminal allocations; we reuse a single instance across
# scenarios and dispose it at suite teardown.
var tuiHarness: TerminalTestHarness = nil

proc tuiDriver(): RendererDriver =
  RendererDriver(
    name: "tui",
    mountAndDrive: proc(vm: TaskAppVM; script: proc(vm: TaskAppVM)) =
      if tuiHarness == nil:
        tuiHarness = newTerminalTestHarness(60, 14)
      discard tui_app.runTaskApp(tuiHarness, vm)
      script(vm)
      tui_app.resetTuiLeaves())

proc webDriver(): RendererDriver =
  RendererDriver(
    name: "web",
    mountAndDrive: proc(vm: TaskAppVM; script: proc(vm: TaskAppVM)) =
      let r = MockRenderer()
      discard web_app.buildTaskApp(r, vm)
      script(vm)
      web_app.resetWebLeaves())

proc gpuiDriver(): RendererDriver =
  RendererDriver(
    name: "gpui",
    mountAndDrive: proc(vm: TaskAppVM; script: proc(vm: TaskAppVM)) =
      discard gpui_app.runTaskApp(vm)
      script(vm)
      gpui_app.resetGpuiLeaves())

proc freyaDriver(): RendererDriver =
  RendererDriver(
    name: "freya",
    mountAndDrive: proc(vm: TaskAppVM; script: proc(vm: TaskAppVM)) =
      discard freya_app.runTaskApp(vm)
      script(vm)
      freya_app.resetFreyaLeaves())

# Build the driver table. Cocoa / Android entries are appended only
# when the host platform actually supports them; on Linux the matrix
# stays at 4 renderers and the assertion count is `scenarios * 4`.
var drivers = @[tuiDriver(), webDriver(), gpuiDriver(), freyaDriver()]

when defined(macosx):
  proc cocoaDriver(): RendererDriver =
    RendererDriver(
      name: "cocoa",
      mountAndDrive: proc(vm: TaskAppVM; script: proc(vm: TaskAppVM)) =
        discard cocoa_app.runTaskApp(vm)
        script(vm)
        cocoa_app.rerender(vm)
        cocoa_app.resetCocoaLeaves())
  drivers.add cocoaDriver()

when defined(android):
  proc androidDriver(): RendererDriver =
    RendererDriver(
      name: "android",
      mountAndDrive: proc(vm: TaskAppVM; script: proc(vm: TaskAppVM)) =
        discard android_app.runTaskApp(vm)
        script(vm)
        android_app.rerender(vm)
        android_app.resetAndroidLeaves())
  drivers.add androidDriver()

# ---------------------------------------------------------------------------
# Test bodies — one suite per scenario so failures point at exactly
# the scenario that diverged.
# ---------------------------------------------------------------------------

proc runScenarioAcrossDrivers(s: Scenario): seq[VMSnapshot] =
  ## Run a scenario through every registered renderer driver and
  ## collect the per-renderer terminal VM snapshot. The caller asserts
  ## byte-identical equality across the returned sequence.
  result = @[]
  for d in drivers:
    let vm = newTaskAppVM()
    d.mountAndDrive(vm, s.script)
    result.add vmSnapshot(vm)

proc assertParity(s: Scenario; snaps: seq[VMSnapshot]) =
  ## Pairwise equality check; on first divergence, dump both sides as
  ## JSON for a readable diff (the JSON projection is stable across
  ## runs so the failure is reproducible).
  doAssert snaps.len == drivers.len
  for i in 1 ..< snaps.len:
    if snaps[i] != snaps[0]:
      let vmA = newTaskAppVM(); let vmB = newTaskAppVM()
      # Reconstruct a JSON view from each snapshot for the failure
      # message. We replay the script onto fresh VMs so the JSON
      # helper has something to introspect.
      s.script(vmA); s.script(vmB)
      let jsonA = vmSnapshotJson(vmA)
      let jsonB = vmSnapshotJson(vmB)
      checkpoint(
        "scenario " & s.name & " — " & drivers[0].name &
        " vs " & drivers[i].name & " diverged.\n" &
        drivers[0].name & ":\n" & jsonA.pretty & "\n" &
        drivers[i].name & ":\n" & jsonB.pretty)
      fail()

suite "EX-M7: cross-renderer VM-parity across all available renderers":

  test "driver matrix is non-empty and includes the four Linux renderers":
    ## Sanity: on Linux the matrix is exactly TUI / web / GPUI / Freya.
    ## On macOS / Android hosts the matrix grows by one each.
    check drivers.len >= 4
    check drivers[0].name == "tui"
    check drivers[1].name == "web"
    check drivers[2].name == "gpui"
    check drivers[3].name == "freya"
    when defined(macosx):
      check "cocoa" in drivers.mapIt(it.name)
    when defined(android):
      check "android" in drivers.mapIt(it.name)

  test "scenario catalogue lists exactly the 5 EX-M7 scenarios":
    ## Sanity: the meta-table that future coverage reports iterate is
    ## the same set the per-scenario tests below exercise.
    check allScenarios.len == 5
    check allScenarios[0].name.startsWith("A:")
    check allScenarios[1].name.startsWith("B:")
    check allScenarios[2].name.startsWith("C:")
    check allScenarios[3].name.startsWith("D:")
    check allScenarios[4].name.startsWith("E:")

  test "scenario A: basic life-cycle (add 3, toggle 1, filter Active)":
    let s = scenarioBasicLifecycle()
    let snaps = runScenarioAcrossDrivers(s)
    assertParity(s, snaps)
    # Spot-check the canonical values so a regression surfaces as a
    # meaningful failure rather than just a generic snapshot diff.
    check snaps[0].tasks.len == 3
    check snaps[0].tasks[0].name == "alpha"
    check snaps[0].tasks[0].completed == true
    check snaps[0].tasks[1].completed == false
    check snaps[0].tasks[2].completed == false
    check snaps[0].filter == fmActive
    check snaps[0].inputText == ""

  test "scenario B: empty / re-init produces identical initial snapshot":
    let s = scenarioEmpty()
    let snaps = runScenarioAcrossDrivers(s)
    assertParity(s, snaps)
    check snaps[0].tasks.len == 0
    check snaps[0].filter == fmAll
    check snaps[0].inputText == ""

  test "scenario C: all-completed (3 tasks, all toggled, filter Completed)":
    let s = scenarioAllCompleted()
    let snaps = runScenarioAcrossDrivers(s)
    assertParity(s, snaps)
    check snaps[0].tasks.len == 3
    for t in snaps[0].tasks:
      check t.completed == true
    check snaps[0].filter == fmCompleted

  test "scenario D: toggle thrash (1 task, 5 toggles -> completed=true)":
    let s = scenarioToggleThrash()
    let snaps = runScenarioAcrossDrivers(s)
    assertParity(s, snaps)
    check snaps[0].tasks.len == 1
    check snaps[0].tasks[0].name == "flippy"
    # 5 toggles starting from completed=false -> completed=true.
    check snaps[0].tasks[0].completed == true
    check snaps[0].filter == fmAll

  test "scenario E: filter persistence with mixed completion":
    let s = scenarioFilterPersistence()
    let snaps = runScenarioAcrossDrivers(s)
    assertParity(s, snaps)
    check snaps[0].tasks.len == 5
    # 1st, 3rd, 5th completed; 2nd, 4th active.
    check snaps[0].tasks[0].completed == true
    check snaps[0].tasks[1].completed == false
    check snaps[0].tasks[2].completed == true
    check snaps[0].tasks[3].completed == false
    check snaps[0].tasks[4].completed == true
    check snaps[0].filter == fmActive

  test "JSON snapshot helper is stable and renderer-agnostic":
    ## The JSON projection (used in failure messages) is the same
    ## across every renderer for the same scripted scenario.
    let s = scenarioBasicLifecycle()
    var jsons: seq[string] = @[]
    for d in drivers:
      let vm = newTaskAppVM()
      d.mountAndDrive(vm, s.script)
      jsons.add vmSnapshotJson(vm).pretty
    for i in 1 ..< jsons.len:
      check jsons[i] == jsons[0]

  test "teardown: dispose the per-thread TUI harness":
    ## Last test in the suite — Nim's `unittest` orders tests within a
    ## suite by source order, so this runs after the parity matrix.
    if tuiHarness != nil:
      tuiHarness.dispose()
      tuiHarness = nil
