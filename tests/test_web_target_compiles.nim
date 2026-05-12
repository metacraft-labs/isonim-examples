## test_web_target_compiles — EX-M2 mandatory integration test.
##
## After EX-M2 the web composition root + leaves live at
## `task_app/main_web.nim` and `task_app/web/leaves.nim` in
## `isonim-examples`. This test compiles + runs the web target through
## its `MockRenderer` leaves end-to-end. (A full Playwright run lives
## downstream once `isonim-website/` consumes the example.)
##
## EX-M16: the leaves now bind reactively via `createRenderEffect` and
## `forEachKeyed`; the test exercises the same scripted scenario but no
## longer calls a per-mutation `rerender(vm)` — VM mutations propagate
## to the rendered tree through the reactive graph automatically.
##
## Mirrors `isonim-tui`'s `test_task_app_web_target_compiles` but
## pointing at the canonical post-EX-M2 location. The two together
## guard the same invariant from both sides:
##
##   - Layer-3 vm.nim must not take a TUI dependency.
##   - Layer-2 views.nim must compile under both renderers.
##   - Action procs in vm.nim rely only on signal semantics that work
##     for every renderer.
##
## No mocks of the renderer or the VM. `MockRenderer` is the canonical
## headless web target; `WebRenderer` exposes the same proc surface so
## the same composition runs in the browser.

import std/[unittest, tables]

import isonim/core/signals
import task_app/main_web

suite "EX-M2: migrated web composition root drives the same VM":
  test "test_web_target_compiles":
    let vm = newTaskAppVM()
    let r = MockRenderer()
    let root = buildTaskApp(r, vm)
    check root != nil
    check root.tag == "div"
    check root.attributes.getOrDefault("class") == "task-app"
    # appShell contains: input, filter bar, list, summary.
    check root.children.len == 4

    # Drive via VM — the reactive leaves update automatically.
    vm.addTask("First")
    vm.addTask("Second")
    check vm.totalCount == 2

    # Toggle the first task and check the visible list reflects it.
    let firstId = vm.tasks.val[0].id
    vm.toggleTask(firstId)
    check vm.completedCount == 1

    # Filter to active and verify the projection.
    vm.setFilter(fmActive)
    let visible = vm.visibleTasks
    check visible.len == 1
    check visible[0].name == "Second"

    # Filter to completed.
    vm.setFilter(fmCompleted)
    let comp = vm.visibleTasks
    check comp.len == 1
    check comp[0].name == "First"

    # Clearing completed empties the completed view.
    vm.clearCompleted()
    check vm.totalCount == 1
    check vm.visibleTasks.len == 0  # filter is still Completed

    vm.setFilter(fmAll)
    check vm.visibleTasks.len == 1
    check vm.visibleTasks[0].name == "Second"

    # Reset for parallel test isolation.
    resetWebLeaves()
