## test_freya_leaves_end_to_end — EX-M4 mandatory integration test.
##
## Real-stack exercise of the new Freya leaves + composition root
## (`task_app/main_freya.nim`, `task_app/freya/leaves.nim`). This test
## proves the Freya flavour consumes the canonical Layer-3 ViewModel and
## Layer-2 view template the same way the TUI/web/GPUI flavours do, and
## produces real output through the Freya Rust shim's shadow tree.
##
## What this exercises (no mocks):
##   * `newTaskAppVM`        — the canonical Layer-3 ViewModel
##                              (`isonim-examples/task_app/core/vm.nim`).
##   * `runTaskApp`          — Layer-4 Freya composition root
##                              (`isonim-examples/task_app/main_freya.nim`).
##   * `buildTaskApp` ->
##     `renderTaskApp` (Layer-2 view template) ->
##     `appShell` / `taskInput` / `filterBar` / `taskList` /
##     `summaryBar`           — the new Layer-1 Freya leaves
##                              (`isonim-examples/task_app/freya/leaves.nim`).
##   * `FreyaRenderer`        — the real renderer wrapping the Rust
##                              `freya-nim-shim` cdylib, loaded at run
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
## additional VM-state parity assertion across (TUI, web, GPUI, Freya)
## lives here too as an early proof point per the EX-M4 milestone brief.
## EX-M3 already shipped the (TUI, web, GPUI) trio — EX-M4 extends it
## to four flavours.

import std/[unittest, strutils]

import isonim/core/signals
import isonim_freya/renderer

# Composition root — drags in the leaves + the Layer-2 view template
# (including `bindings.fireEvent`, `bindings.freya_reset_tree`, ...).
import task_app/main_freya as freya_app

# Pull in the TUI + web + GPUI flavours for the cross-renderer parity
# check. Each flavour exposes its own `buildTaskApp` / `runTaskApp`; we
# alias them so the parity test names are unambiguous.
#
# `main_gpui` re-exports `isonim_gpui/renderer` and `isonim_gpui/bindings`
# whose `childCount` / `getAttribute` / etc. take `GpuiElement = pointer`.
# `main_freya`'s helpers + the `isonim_freya/renderer` import above take
# `FreyaElement = pointer`. Both are aliases of `pointer`, so a bare
# `childCount(x)` call from inside a `unittest.check` macro would be
# ambiguous to overload resolution. We import the GPUI flavour with
# `from ... import ...` listing only the names we use in the parity
# test, which keeps the bare `childCount(...)` etc. resolving against
# the Freya overloads imported above.
import task_app/main_tui as tui_app
import task_app/main_web as web_app
from task_app/main_gpui as gpui_app import
  runTaskApp, rerender, resetGpuiLeaves
import isonim_tui  # newTerminalTestHarness

suite "EX-M4: Freya leaves drive the canonical core through the real shim":

  test "scripted scenario: add 3, toggle 1, filter switches stay consistent":
    let vm = newTaskAppVM()
    let root = freya_app.runTaskApp(vm)

    # ── Topology: appShell wrapper + 4 leaves (input / filter / list /
    #    summary). Mirrors the TUI/web/GPUI checks so the cross-renderer
    #    invariants stay visible.
    check root != nil
    check childCount(root) == 4
    check getAttribute(root, "class") == "task-app"
    check getAttribute(root, "data-app") == "task-app"

    # The first child is the input wrapper (taskInput leaf), exposing
    # the Add button handle through the leaves table.
    let s = freya_app.leavesFor(vm)
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
    fireEvent(s.addBtn, "click")
    vm.setInputText("write specs")
    fireEvent(s.addBtn, "click")
    vm.setInputText("review pr")
    fireEvent(s.addBtn, "click")

    check vm.tasks.val.len == 3
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
    fireEvent(toggleBtn0, "click")

    check vm.tasks.val[0].completed == true
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
    let vm2 = newTaskAppVM()
    let root2 = freya_app.runTaskApp(vm2)
    check root2 != nil
    let s2 = freya_app.leavesFor(vm2)
    # The list has exactly one child — the placeholder paragraph.
    check childCount(s2.listNode) == 1
    let placeholder = nthChild(s2.listNode, 0)
    check "(no tasks yet)" in textContent(placeholder)

  test "render plan: Freya shim builds a valid plan over the leaf tree":
    ## Sanity check: the shim's render-plan inspection (used by the
    ## RS-M4 streaming bridge later) treats the leaf tree as valid.
    let vm = newTaskAppVM()
    let root = freya_app.runTaskApp(vm)
    vm.setInputText("first")
    let s = freya_app.leavesFor(vm)
    fireEvent(s.addBtn, "click")
    check verifyRenderPlan(root)
    check renderPlanElementCount(root) > 0

suite "EX-M4: cross-renderer VM-state parity (TUI, web, GPUI, Freya)":

  test "same scripted scenario yields byte-identical VM snapshots":
    ## Drive the same script through every renderer and verify that the
    ## VM's terminal state (tasks + filter + inputText) is byte-
    ## identical. This is the EX-M7 invariant landed early as part of
    ## EX-M3 (TUI/web/GPUI); EX-M4 extends it to include Freya so all
    ## four Linux-buildable flavours stay locked together.

    proc script(vm: TaskAppVM) =
      vm.addTask("alpha")
      vm.addTask("beta")
      vm.addTask("gamma")
      let id1 = vm.tasks.val[0].id
      vm.toggleTask(id1)
      vm.setFilter(fmActive)

    # ── TUI flavour
    let vmTui = newTaskAppVM()
    let h = newTerminalTestHarness(60, 14)
    discard tui_app.runTaskApp(h, vmTui)
    script(vmTui)
    tui_app.rerender(vmTui)
    let snapTui = vmTui.snapshot

    # ── Web flavour (MockRenderer)
    let vmWeb = newTaskAppVM()
    let rWeb = MockRenderer()
    discard web_app.buildTaskApp(rWeb, vmWeb)
    script(vmWeb)
    web_app.rerender(vmWeb)
    let snapWeb = vmWeb.snapshot

    # ── GPUI flavour
    let vmGpui = newTaskAppVM()
    discard gpui_app.runTaskApp(vmGpui)
    script(vmGpui)
    gpui_app.rerender(vmGpui)
    let snapGpui = vmGpui.snapshot

    # ── Freya flavour
    let vmFreya = newTaskAppVM()
    discard freya_app.runTaskApp(vmFreya)
    script(vmFreya)
    freya_app.rerender(vmFreya)
    let snapFreya = vmFreya.snapshot

    # All four snapshots are byte-identical (same field values, same
    # task ids — `nextId` is deterministic per fresh VM).
    check snapTui == snapWeb
    check snapWeb == snapGpui
    check snapGpui == snapFreya
    # Spot-check the actual values so a cross-renderer regression
    # surfaces as a meaningful failure rather than just a generic
    # snapshot diff.
    check snapFreya.tasks.len == 3
    check snapFreya.tasks[0].name == "alpha"
    check snapFreya.tasks[0].completed == true
    check snapFreya.tasks[1].completed == false
    check snapFreya.tasks[2].completed == false
    check snapFreya.filter == fmActive
    check snapFreya.inputText == ""

    h.dispose()
    # Reset per-thread leaf tables so subsequent test cases (in
    # whatever order Nim's unittest picks) start clean.
    tui_app.resetTuiLeaves()
    web_app.resetWebLeaves()
    gpui_app.resetGpuiLeaves()
    freya_app.resetFreyaLeaves()
