## test_web_target_compiles — EX-M2 mandatory integration test.
##
## After EX-M2 the web composition root + leaves live at
## `task_app/main_web.nim` and `task_app/web/leaves.nim` in
## `isonim-examples`. This test compiles + runs the web target through
## its `MockRenderer` leaves end-to-end. (A full Playwright run lives
## downstream once `isonim-website/` consumes the example.)
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

    # Drive via VM — the leaves rebuild on every rerender.
    vm.addTask("First")
    vm.addTask("Second")
    rerender(vm)
    check vm.totalCount == 2

    # Toggle the first task and check the visible list reflects it.
    let firstId = vm.tasks.val[0].id
    vm.toggleTask(firstId)
    rerender(vm)
    check vm.completedCount == 1

    # Filter to active and verify the projection.
    vm.setFilter(fmActive)
    rerender(vm)
    let visible = vm.visibleTasks
    check visible.len == 1
    check visible[0].name == "Second"

    # Filter to completed.
    vm.setFilter(fmCompleted)
    rerender(vm)
    let comp = vm.visibleTasks
    check comp.len == 1
    check comp[0].name == "First"

    # Clearing completed empties the completed view.
    vm.clearCompleted()
    rerender(vm)
    check vm.totalCount == 1
    check vm.visibleTasks.len == 0  # filter is still Completed

    vm.setFilter(fmAll)
    rerender(vm)
    check vm.visibleTasks.len == 1
    check vm.visibleTasks[0].name == "Second"

    # Reset for parallel test isolation.
    resetWebLeaves()
