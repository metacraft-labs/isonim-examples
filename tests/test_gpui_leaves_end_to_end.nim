## test_gpui_leaves_end_to_end — EX-M3 mandatory integration test.
##
## Real-stack exercise of the new GPUI leaves + composition root
## (`task_app/main_gpui.nim`, `task_app/gpui/leaves.nim`). This test
## proves the GPUI flavour consumes the canonical Layer-3 ViewModel and
## Layer-2 view template the same way the TUI/web flavours do, and
## produces real output through the GPUI Rust shim's shadow tree.
##
## What this exercises (no mocks):
##   * `newTaskAppVM`        — the canonical Layer-3 ViewModel
##                              (`isonim-examples/task_app/core/vm.nim`).
##   * `runTaskApp`          — Layer-4 GPUI composition root
##                              (`isonim-examples/task_app/main_gpui.nim`).
##   * `buildTaskApp` ->
##     `renderTaskApp` (Layer-2 view template) ->
##     `appShell` / `taskInput` / `filterBar` / `taskList` /
##     `summaryBar`           — the new Layer-1 GPUI leaves
##                              (`isonim-examples/task_app/gpui/leaves.nim`).
##   * `GpuiRenderer`         — the real renderer wrapping the Rust
##                              `gpui-nim-shim` cdylib, loaded at run
##                              time via the `LD_LIBRARY_PATH` set up
##                              by the dev shell.
##   * `fireEvent`            — the real shim event dispatcher.
##
## A scripted scenario adds tasks via the input + Add-button click
## handler, toggles tasks via the per-row toggle button, and switches
## the filter via the filter-bar buttons. The test asserts the full
## pipeline stays consistent: VM state, tree topology, list-row text,
## summary-row text, filter-button selection state.
##
## EX-M7 will land the formal cross-renderer parity check; an
## additional VM-state parity assertion across (TUI, web, GPUI) lives
## here too as an early proof point per the EX-M3 milestone brief.

import std/[unittest, strutils]

import isonim/core/signals
import isonim_gpui/renderer

# Composition root — drags in the leaves + the Layer-2 view template
# (including `bindings.fireEvent`, `bindings.gpui_reset_tree`, ...).
import task_app/main_gpui as gpui_app

# Pull in the TUI + web flavours for the cross-renderer parity check.
# Each flavour exposes its own `buildTaskApp` / `runTaskApp`; we alias
# them so the parity test names are unambiguous.
import task_app/main_tui as tui_app
import task_app/main_web as web_app
import isonim_tui  # newTerminalTestHarness
import ./helpers/async_drive

suite "EX-M3: GPUI leaves drive the canonical core through the real shim":

  test "scripted scenario: add 3, toggle 1, filter switches stay consistent":
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    let vm = newTaskAppVM(drv.db)
    let root = gpui_app.runTaskApp(vm)
    drv.flush()

    # ── Topology: appShell wrapper + 4 leaves (input / filter / list /
    #    summary). Mirrors the TUI/web checks so the cross-renderer
    #    invariants stay visible.
    check root != nil
    check childCount(root) == 4
    check getAttribute(root, "class") == "task-app"
    check getAttribute(root, "data-app") == "task-app"

    # The first child is the input wrapper (taskInput leaf), exposing
    # the Add button handle through the leaves table.
    let s = gpui_app.leavesFor(vm)
    check s.inputNode != nil
    check s.addBtn != nil
    check s.listNode != nil
    check s.summaryNode != nil
    check s.filterButtons.len == 3

    # ── 1. Add three tasks via the real Add-button click handler.
    #    The leaves' click handler reads `vm.inputText.val`; the test
    #    seeds it through `setInputText` (the equivalent of a user
    #    typing into the input field).
    vm.setInputText("buy milk")
    fireEvent(s.addBtn, "click"); drv.flush()
    vm.setInputText("write specs")
    fireEvent(s.addBtn, "click"); drv.flush()
    vm.setInputText("review pr")
    fireEvent(s.addBtn, "click"); drv.flush()

    check vm.tasks.data.val.len == 3
    check vm.activeCount == 3
    check vm.completedCount == 0
    check childCount(s.listNode) == 3
    # First row's toggle marker reads "[ ]"; the label span carries the
    # task name. We probe via `textContent` on the row (which dumps the
    # full subtree text).
    let row0 = nthChild(s.listNode, 0)
    check row0 != nil
    check getAttribute(row0, "data-task-id") == "1"
    check "buy milk" in textContent(row0)
    check "[ ]" in textContent(row0)
    # Summary reads "3 of 3 remaining".
    check "3 of 3 remaining" in textContent(s.summaryNode)

    # ── 2. Toggle the first task via its per-row toggle button.
    #    The leaf factory wired a closure that calls vm.toggleTask(id)
    #    and re-renders.
    let toggleBtn0 = nthChild(row0, 0)
    check toggleBtn0 != nil
    fireEvent(toggleBtn0, "click"); drv.flush()

    check vm.tasks.data.val[0].completed == true
    check vm.activeCount == 2
    check vm.completedCount == 1
    # After re-render, the matching row carries the [x] marker and the
    # "completed" class.
    let row0After = nthChild(s.listNode, 0)
    check row0After != nil
    check getAttribute(row0After, "class") == "completed"
    check "[x]" in textContent(row0After)
    check "2 of 3 remaining" in textContent(s.summaryNode)

    # ── 3. Switch filter to Active via the second filter button.
    fireEvent(s.filterButtons[1], "click")
    check vm.filter.val == fmActive
    check vm.visibleTasks.len == 2
    check childCount(s.listNode) == 2
    # Selected button picks up the "selected" class; the others lose it.
    check getAttribute(s.filterButtons[0], "class") == ""
    check getAttribute(s.filterButtons[1], "class") == "selected"
    check getAttribute(s.filterButtons[2], "class") == ""
    check getAttribute(s.filterButtons[1], "aria-pressed") == "true"
    # Every visible row is active (no [x] marker).
    for i in 0 ..< childCount(s.listNode):
      let row = nthChild(s.listNode, i)
      check "[x]" notin textContent(row)
      check "[ ]" in textContent(row)

    # ── 4. Switch filter to Completed; only the toggled task shows.
    fireEvent(s.filterButtons[2], "click")
    check vm.filter.val == fmCompleted
    check vm.visibleTasks.len == 1
    check childCount(s.listNode) == 1
    let onlyRow = nthChild(s.listNode, 0)
    check "[x]" in textContent(onlyRow)
    check "buy milk" in textContent(onlyRow)
    check getAttribute(s.filterButtons[2], "class") == "selected"

    # ── 5. Empty-state placeholder for a fresh VM.
    let vm2 = newTaskAppVM(newFakeDb(seed = 99))
    let root2 = gpui_app.runTaskApp(vm2)
    drv.flush()
    check root2 != nil
    let s2 = gpui_app.leavesFor(vm2)
    # The list has exactly one child — the placeholder paragraph.
    check childCount(s2.listNode) == 1
    let placeholder = nthChild(s2.listNode, 0)
    check "(no tasks yet)" in textContent(placeholder)

  test "render plan: GPUI shim builds a valid plan over the leaf tree":
    ## Sanity check: the shim's render-plan inspection (used by the
    ## RS-M2 streaming bridge later) treats the leaf tree as valid.
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    let vm = newTaskAppVM(drv.db)
    let root = gpui_app.runTaskApp(vm)
    drv.flush()
    let r = GpuiRenderer()
    vm.setInputText("first")
    let s = gpui_app.leavesFor(vm)
    fireEvent(s.addBtn, "click"); drv.flush()
    check r.verifyRenderPlan(root)
    check r.renderPlanElementCount(root) > 0

suite "EX-M3: cross-renderer VM-state parity (TUI, web, GPUI)":

  test "same scripted scenario yields byte-identical VM snapshots":
    ## Drive the same script through every renderer and verify that the
    ## VM's terminal state (tasks + filter + inputText) is byte-
    ## identical. This is the EX-M7 invariant landed early as part of
    ## EX-M3 since we now have three working renderers in the canonical
    ## examples repo.

    proc script(vm: TaskAppVM; drv: AsyncDriver) =
      vm.addTask("alpha"); drv.flush()
      vm.addTask("beta"); drv.flush()
      vm.addTask("gamma"); drv.flush()
      let id1 = vm.tasks.data.val[0].id
      vm.toggleTask(id1); drv.flush()
      vm.setFilter(fmActive)

    # ── TUI flavour
    let drvTui = newAsyncDriver(seed = 42)
    let vmTui = newTaskAppVM(drvTui.db)
    let h = newTerminalTestHarness(60, 14)
    discard tui_app.runTaskApp(h, vmTui)
    drvTui.flush()
    script(vmTui, drvTui)
    let snapTui = vmTui.snapshot
    drvTui.shutdown()

    # ── Web flavour (MockRenderer)
    let drvWeb = newAsyncDriver(seed = 42)
    let vmWeb = newTaskAppVM(drvWeb.db)
    let rWeb = MockRenderer()
    discard web_app.buildTaskApp(rWeb, vmWeb)
    drvWeb.flush()
    script(vmWeb, drvWeb)
    let snapWeb = vmWeb.snapshot
    drvWeb.shutdown()

    # ── GPUI flavour
    let drvGpui = newAsyncDriver(seed = 42)
    let vmGpui = newTaskAppVM(drvGpui.db)
    discard gpui_app.runTaskApp(vmGpui)
    drvGpui.flush()
    script(vmGpui, drvGpui)
    let snapGpui = vmGpui.snapshot
    drvGpui.shutdown()

    # All three snapshots are byte-identical (same field values, same
    # task ids — `nextId` is deterministic per fresh VM).
    check snapTui == snapWeb
    check snapWeb == snapGpui
    # Spot-check the actual values so a cross-renderer regression
    # surfaces as a meaningful failure rather than just a generic
    # snapshot diff.
    check snapGpui.tasks.len == 3
    check snapGpui.tasks[0].name == "alpha"
    check snapGpui.tasks[0].completed == true
    check snapGpui.tasks[1].completed == false
    check snapGpui.tasks[2].completed == false
    check snapGpui.filter == fmActive
    check snapGpui.inputText == ""

    h.dispose()
    # Reset per-thread leaf tables so subsequent test cases (in
    # whatever order Nim's unittest picks) start clean.
    tui_app.resetTuiLeaves()
    web_app.resetWebLeaves()
    gpui_app.resetGpuiLeaves()
