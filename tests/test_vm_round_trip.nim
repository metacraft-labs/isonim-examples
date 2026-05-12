## test_vm_round_trip — EX-M1 mandatory integration test (EX-M17 update).
##
## EX-M17: every mutation action is now async (it enqueues a `saveTask`
## / `deleteTask` / `clearCompletedTasks` through a `FakeDb` and
## refreshes the `Resource[seq[Task]]` on completion). This test
## installs a `FakeAsyncContext`, drives the VM through the same
## scripted scenarios, and advances the simulated clock after each
## action so the assertions see the post-resolution state.
##
## This is the same VM behaviour the existing M22 test suite in
## `isonim-tui` exercises against the renderer-side stack — but here
## it runs against the canonical `isonim-examples` location, proving
## the EX-M1 move did not perturb any semantics and EX-M17 preserved
## the action surface.

import std/unittest

import isonim/core/signals
import task_app/core/vm
import ./helpers/async_drive

suite "EX-M17: TaskAppVM async round-trip via fake_db":
  test "fresh VM starts empty with All filter (post-initial-load)":
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    let vm = newTaskAppVM(drv.db)
    drv.flush()  # resolve the initial loadTasks
    check vm.tasks.data.val.len == 0
    check vm.filter.val == fmAll
    check vm.inputText.val == ""
    check vm.totalCount == 0
    check vm.activeCount == 0
    check vm.completedCount == 0
    check vm.visibleTasks.len == 0

  test "addTask appends in insertion order with monotonic ids":
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    let vm = newTaskAppVM(drv.db)
    drv.flush()
    vm.addTask("foo"); drv.flush()
    vm.addTask("bar"); drv.flush()
    vm.addTask("baz"); drv.flush()
    check vm.totalCount == 3
    check vm.tasks.data.val[0].name == "foo"
    check vm.tasks.data.val[1].name == "bar"
    check vm.tasks.data.val[2].name == "baz"
    check vm.tasks.data.val[0].id == 1
    check vm.tasks.data.val[1].id == 2
    check vm.tasks.data.val[2].id == 3
    for t in vm.tasks.data.val:
      check not t.completed
    check vm.inputText.val == ""

  test "addTask trims whitespace and ignores empty names":
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    let vm = newTaskAppVM(drv.db)
    drv.flush()
    vm.addTask("   "); drv.flush()
    vm.addTask("\t\t"); drv.flush()
    vm.addTask(""); drv.flush()
    check vm.totalCount == 0
    vm.addTask("   trimmed   "); drv.flush()
    check vm.totalCount == 1
    check vm.tasks.data.val[0].name == "trimmed"

  test "toggleTask flips completed flag for the matching id":
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    let vm = newTaskAppVM(drv.db)
    drv.flush()
    vm.addTask("foo"); drv.flush()
    vm.addTask("bar"); drv.flush()
    let fooId = vm.tasks.data.val[0].id
    vm.toggleTask(fooId); drv.flush()
    check vm.tasks.data.val[0].completed
    check not vm.tasks.data.val[1].completed
    check vm.activeCount == 1
    check vm.completedCount == 1
    vm.toggleTask(fooId); drv.flush()
    check not vm.tasks.data.val[0].completed
    check vm.activeCount == 2
    check vm.completedCount == 0

  test "toggleTask is a no-op for unknown ids":
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    let vm = newTaskAppVM(drv.db)
    drv.flush()
    vm.addTask("foo"); drv.flush()
    let snap = vm.snapshot
    vm.toggleTask(99999); drv.flush()
    check vm.snapshot == snap

  test "setFilter mutates the filter signal and visibleTasks reflects it":
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    let vm = newTaskAppVM(drv.db)
    drv.flush()
    vm.addTask("foo"); drv.flush()
    vm.addTask("bar"); drv.flush()
    vm.toggleTask(vm.tasks.data.val[0].id); drv.flush()

    check vm.filter.val == fmAll
    check vm.visibleTasks.len == 2

    vm.setFilter(fmActive)
    check vm.filter.val == fmActive
    let active = vm.visibleTasks
    check active.len == 1
    check active[0].name == "bar"
    check not active[0].completed

    vm.setFilter(fmCompleted)
    check vm.filter.val == fmCompleted
    let completed = vm.visibleTasks
    check completed.len == 1
    check completed[0].name == "foo"
    check completed[0].completed

    vm.setFilter(fmAll)
    check vm.filter.val == fmAll
    check vm.visibleTasks.len == 2

  test "removeTask drops the matching row, preserves order, no-op on miss":
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    let vm = newTaskAppVM(drv.db)
    drv.flush()
    vm.addTask("a"); drv.flush()
    vm.addTask("b"); drv.flush()
    vm.addTask("c"); drv.flush()
    let bId = vm.tasks.data.val[1].id
    vm.removeTask(bId); drv.flush()
    check vm.totalCount == 2
    check vm.tasks.data.val[0].name == "a"
    check vm.tasks.data.val[1].name == "c"
    let before = vm.snapshot
    vm.removeTask(99999); drv.flush()
    check vm.snapshot == before

  test "clearCompleted removes only completed tasks in one batch":
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    let vm = newTaskAppVM(drv.db)
    drv.flush()
    vm.addTask("a"); drv.flush()
    vm.addTask("b"); drv.flush()
    vm.addTask("c"); drv.flush()
    vm.addTask("d"); drv.flush()
    vm.toggleTask(vm.tasks.data.val[0].id); drv.flush()
    vm.toggleTask(vm.tasks.data.val[2].id); drv.flush()
    check vm.completedCount == 2
    vm.clearCompleted(); drv.flush()
    check vm.totalCount == 2
    check vm.tasks.data.val[0].name == "b"
    check vm.tasks.data.val[1].name == "d"
    check vm.completedCount == 0

  test "setInputText writes through to the inputText signal":
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    let vm = newTaskAppVM(drv.db)
    drv.flush()
    vm.setInputText("draft")
    check vm.inputText.val == "draft"
    vm.addTask("draft"); drv.flush()
    check vm.inputText.val == ""
    check vm.totalCount == 1

  test "snapshot captures a value-copy of all live signals":
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    let vm = newTaskAppVM(drv.db)
    drv.flush()
    vm.addTask("foo"); drv.flush()
    vm.addTask("bar"); drv.flush()
    vm.setFilter(fmActive)
    vm.setInputText("draft")
    let snap = vm.snapshot
    check snap.tasks.len == 2
    check snap.filter == fmActive
    check snap.inputText == "draft"
    vm.addTask("baz"); drv.flush()
    check snap.tasks.len == 2
    check vm.totalCount == 3

  test "full M22 scenario — the same script the pilot test runs":
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    let vm = newTaskAppVM(drv.db)
    drv.flush()

    vm.addTask("Buy milk"); drv.flush()
    check vm.totalCount == 1
    check vm.tasks.data.val[0].name == "Buy milk"
    check not vm.tasks.data.val[0].completed
    check vm.inputText.val == ""

    vm.addTask("Write specs"); drv.flush()
    check vm.totalCount == 2
    check vm.tasks.data.val[1].name == "Write specs"

    vm.toggleTask(vm.tasks.data.val[1].id); drv.flush()
    check vm.activeCount == 1
    check vm.completedCount == 1

    vm.setFilter(fmActive)

    let snap = vm.snapshot
    check snap.tasks.len == 2
    check snap.tasks[0].name == "Buy milk"
    check not snap.tasks[0].completed
    check snap.tasks[1].name == "Write specs"
    check snap.tasks[1].completed
    check snap.filter == fmActive
    check snap.inputText == ""

    let visible = vm.visibleTasks
    check visible.len == 1
    check visible[0].name == "Buy milk"
