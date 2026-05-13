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

import nim_everywhere

import isonim/core/signals
import ./helpers/async_drive

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
#
# EX-M23c follow-up: Cocoa/Android leaves are now reactive (matching
# GPUI/Freya), so the imperative `rerender(vm)` proc is gone. The
# drivers below mount the tree once and let the leaves react to VM
# signal changes through `createRenderEffect`.
when defined(macosx):
  from task_app/main_cocoa as cocoa_app import
    runTaskApp, resetCocoaLeaves
when defined(android):
  from task_app/main_android as android_app import
    runTaskApp, resetAndroidLeaves

import ./helpers/parity_snapshot

# ---------------------------------------------------------------------------
# Scenarios — every entry mutates the VM through the public action
# surface (`addTask`, `toggleTask`, `setFilter`, `setInputText`).
# Renderer leaves observe the mutations through `createRenderEffect`
# (and, for the few renderers that previously needed it, a
# per-renderer `rerender(vm)` proc — removed in the EX-M23c follow-up
# in favour of the reactive pattern). The parity invariant is that
# the VM's terminal snapshot is identical regardless of which
# renderer drove it.
# ---------------------------------------------------------------------------

type
  Scenario = object
    ## EX-M17: scripts now take a `drv` so they can flush the fake
    ## clock between actions. Every action is async, so we drain
    ## after every state-mutating call to keep the test pattern
    ## explicit.
    name: string
    script: proc(vm: TaskAppVM; drv: AsyncDriver) {.closure.}

proc scenarioBasicLifecycle(): Scenario =
  Scenario(
    name: "A: basic life-cycle (add 3, toggle 1, filter Active)",
    script: proc(vm: TaskAppVM; drv: AsyncDriver) =
      vm.addTask("alpha"); drv.flush()
      vm.addTask("beta"); drv.flush()
      vm.addTask("gamma"); drv.flush()
      vm.toggleTask(vm.tasks.data.val[0].id); drv.flush()
      vm.setFilter(fmActive))

proc scenarioEmpty(): Scenario =
  Scenario(
    name: "B: empty / re-init (no actions)",
    script: proc(vm: TaskAppVM; drv: AsyncDriver) =
      discard vm)

proc scenarioAllCompleted(): Scenario =
  Scenario(
    name: "C: all-completed (3 tasks, all toggled, filter Completed)",
    script: proc(vm: TaskAppVM; drv: AsyncDriver) =
      vm.addTask("one"); drv.flush()
      vm.addTask("two"); drv.flush()
      vm.addTask("three"); drv.flush()
      vm.toggleTask(vm.tasks.data.val[0].id); drv.flush()
      vm.toggleTask(vm.tasks.data.val[1].id); drv.flush()
      vm.toggleTask(vm.tasks.data.val[2].id); drv.flush()
      vm.setFilter(fmCompleted))

proc scenarioToggleThrash(): Scenario =
  Scenario(
    name: "D: toggle thrash (1 task, 5 toggles -> completed=true)",
    script: proc(vm: TaskAppVM; drv: AsyncDriver) =
      vm.addTask("flippy"); drv.flush()
      let id = vm.tasks.data.val[0].id
      for _ in 0 ..< 5:
        vm.toggleTask(id); drv.flush())

proc scenarioFilterPersistence(): Scenario =
  Scenario(
    name: "E: filter persistence (5 tasks, alternating completion, filter Active)",
    script: proc(vm: TaskAppVM; drv: AsyncDriver) =
      vm.addTask("t1"); drv.flush()
      vm.addTask("t2"); drv.flush()
      vm.addTask("t3"); drv.flush()
      vm.addTask("t4"); drv.flush()
      vm.addTask("t5"); drv.flush()
      vm.toggleTask(vm.tasks.data.val[0].id); drv.flush()
      vm.toggleTask(vm.tasks.data.val[2].id); drv.flush()
      vm.toggleTask(vm.tasks.data.val[4].id); drv.flush()
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
    mountAndDrive: proc(vm: TaskAppVM; drv: AsyncDriver;
                        script: proc(vm: TaskAppVM; drv: AsyncDriver))

# Per-thread harness for the TUI driver. The `TerminalTestHarness`
# owns terminal allocations; we reuse a single instance across
# scenarios and dispose it at suite teardown.
var tuiHarness: TerminalTestHarness = nil

proc tuiDriver(): RendererDriver =
  RendererDriver(
    name: "tui",
    mountAndDrive: proc(vm: TaskAppVM; drv: AsyncDriver;
                        script: proc(vm: TaskAppVM; drv: AsyncDriver)) =
      if tuiHarness == nil:
        tuiHarness = newTerminalTestHarness(60, 14)
      discard tui_app.runTaskApp(tuiHarness, vm)
      drv.flush()  # initial load
      script(vm, drv)
      tui_app.resetTuiLeaves())

proc webDriver(): RendererDriver =
  RendererDriver(
    name: "web",
    mountAndDrive: proc(vm: TaskAppVM; drv: AsyncDriver;
                        script: proc(vm: TaskAppVM; drv: AsyncDriver)) =
      let r = MockRenderer()
      discard web_app.buildTaskApp(r, vm)
      drv.flush()
      script(vm, drv)
      web_app.resetWebLeaves())

proc gpuiDriver(): RendererDriver =
  RendererDriver(
    name: "gpui",
    mountAndDrive: proc(vm: TaskAppVM; drv: AsyncDriver;
                        script: proc(vm: TaskAppVM; drv: AsyncDriver)) =
      discard gpui_app.runTaskApp(vm)
      drv.flush()
      script(vm, drv)
      gpui_app.resetGpuiLeaves())

proc freyaDriver(): RendererDriver =
  RendererDriver(
    name: "freya",
    mountAndDrive: proc(vm: TaskAppVM; drv: AsyncDriver;
                        script: proc(vm: TaskAppVM; drv: AsyncDriver)) =
      discard freya_app.runTaskApp(vm)
      drv.flush()
      script(vm, drv)
      freya_app.resetFreyaLeaves())

# Build the driver table. Cocoa / Android entries are appended only
# when the host platform actually supports them; on Linux the matrix
# stays at 4 renderers and the assertion count is `scenarios * 4`.
var drivers = @[tuiDriver(), webDriver(), gpuiDriver(), freyaDriver()]

when defined(macosx):
  proc cocoaDriver(): RendererDriver =
    RendererDriver(
      name: "cocoa",
      mountAndDrive: proc(vm: TaskAppVM; drv: AsyncDriver;
                          script: proc(vm: TaskAppVM; drv: AsyncDriver)) =
        discard cocoa_app.runTaskApp(vm)
        drv.flush()
        script(vm, drv)
        # EX-M23c follow-up: the leaves are reactive (they observe
        # VM signal changes via `createRenderEffect`), so no manual
        # `rerender(vm)` call is needed. The driver only resets the
        # per-VM bookkeeping table so successive scenarios start clean.
        cocoa_app.resetCocoaLeaves())
  drivers.add cocoaDriver()

when defined(android):
  proc androidDriver(): RendererDriver =
    RendererDriver(
      name: "android",
      mountAndDrive: proc(vm: TaskAppVM; drv: AsyncDriver;
                          script: proc(vm: TaskAppVM; drv: AsyncDriver)) =
        discard android_app.runTaskApp(vm)
        drv.flush()
        script(vm, drv)
        # EX-M23c follow-up: same as cocoaDriver — leaves are reactive,
        # no manual `rerender(vm)` call is needed.
        android_app.resetAndroidLeaves())
  drivers.add androidDriver()

# ---------------------------------------------------------------------------
# Test bodies — one suite per scenario so failures point at exactly
# the scenario that diverged.
# ---------------------------------------------------------------------------

proc runScenarioAcrossDrivers(s: Scenario): seq[VMSnapshot] =
  ## Run a scenario through every registered renderer driver and
  ## collect the per-renderer terminal VM snapshot. Each driver gets
  ## its own `AsyncDriver` (fresh fake-time context + fresh fake_db
  ## with a fixed seed), so the per-renderer latency sequence is
  ## byte-identical across renderers — the parity assertion holds
  ## regardless of which renderer drove the same scripted operations.
  result = @[]
  for d in drivers:
    let drv = newAsyncDriver(seed = 42)
    let vm = newTaskAppVM(drv.db)
    d.mountAndDrive(vm, drv, s.script)
    result.add vmSnapshot(vm)
    drv.shutdown()

proc assertParity(s: Scenario; snaps: seq[VMSnapshot]) =
  doAssert snaps.len == drivers.len
  for i in 1 ..< snaps.len:
    if snaps[i] != snaps[0]:
      let drvA = newAsyncDriver(seed = 42)
      let vmA = newTaskAppVM(drvA.db)
      let drvB = newAsyncDriver(seed = 42)
      let vmB = newTaskAppVM(drvB.db)
      drvA.flush(); drvB.flush()
      s.script(vmA, drvA); s.script(vmB, drvB)
      let jsonA = vmSnapshotJson(vmA)
      let jsonB = vmSnapshotJson(vmB)
      drvA.shutdown(); drvB.shutdown()
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
      let drv = newAsyncDriver(seed = 42)
      let vm = newTaskAppVM(drv.db)
      d.mountAndDrive(vm, drv, s.script)
      jsons.add vmSnapshotJson(vm).pretty
      drv.shutdown()
    for i in 1 ..< jsons.len:
      check jsons[i] == jsons[0]

  test "teardown: dispose the per-thread TUI harness":
    ## Last test in the suite — Nim's `unittest` orders tests within a
    ## suite by source order, so this runs after the parity matrix.
    if tuiHarness != nil:
      tuiHarness.dispose()
      tuiHarness = nil
