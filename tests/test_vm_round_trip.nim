## test_vm_round_trip — EX-M1 mandatory integration test.
##
## Real-stack exercise of the canonical task-app ViewModel that now
## lives in this repo (`task_app/core/vm.nim`). The test instantiates
## a real `TaskAppVM`, drives it through the full action surface
## (`addTask`, `toggleTask`, `setFilter`), and asserts both the
## live signal values and the `visibleTasks` derived projection
## reflect every operation byte-for-byte.
##
## This is the same VM behaviour the existing M22 test suite in
## `isonim-tui` exercises against the renderer-side stack — but here
## it runs against the canonical `isonim-examples` location, proving
## the EX-M1 move did not perturb any semantics.
##
## No mocks: the `TaskAppVM` is the real type from
## `task_app/core/vm.nim`, the signals are the real `Signal[T]`
## primitives from `isonim/core/signals`, and every assertion reads
## the live signal `.val` (no recorded snapshot indirection).

import std/unittest

import isonim/core/signals
import task_app/core/vm

suite "EX-M1: canonical TaskAppVM round-trip":
  test "fresh VM starts empty with All filter":
    let vm = newTaskAppVM()
    check vm.tasks.val.len == 0
    check vm.filter.val == fmAll
    check vm.inputText.val == ""
    check vm.totalCount == 0
    check vm.activeCount == 0
    check vm.completedCount == 0
    check vm.visibleTasks.len == 0

  test "addTask appends in insertion order with monotonic ids":
    let vm = newTaskAppVM()
    vm.addTask("foo")
    vm.addTask("bar")
    vm.addTask("baz")
    check vm.totalCount == 3
    check vm.tasks.val[0].name == "foo"
    check vm.tasks.val[1].name == "bar"
    check vm.tasks.val[2].name == "baz"
    # Ids are monotonic and unique.
    check vm.tasks.val[0].id == 1
    check vm.tasks.val[1].id == 2
    check vm.tasks.val[2].id == 3
    # New tasks are not completed.
    for t in vm.tasks.val:
      check not t.completed
    # addTask clears the input text after submission.
    check vm.inputText.val == ""

  test "addTask trims whitespace and ignores empty names":
    let vm = newTaskAppVM()
    vm.addTask("   ")
    vm.addTask("\t\t")
    vm.addTask("")
    check vm.totalCount == 0
    vm.addTask("   trimmed   ")
    check vm.totalCount == 1
    check vm.tasks.val[0].name == "trimmed"

  test "toggleTask flips completed flag for the matching id":
    let vm = newTaskAppVM()
    vm.addTask("foo")
    vm.addTask("bar")
    let fooId = vm.tasks.val[0].id
    vm.toggleTask(fooId)
    check vm.tasks.val[0].completed
    check not vm.tasks.val[1].completed
    check vm.activeCount == 1
    check vm.completedCount == 1
    # Toggle back.
    vm.toggleTask(fooId)
    check not vm.tasks.val[0].completed
    check vm.activeCount == 2
    check vm.completedCount == 0

  test "toggleTask is a no-op for unknown ids":
    let vm = newTaskAppVM()
    vm.addTask("foo")
    let snap = vm.snapshot
    vm.toggleTask(99999)
    check vm.snapshot == snap

  test "setFilter mutates the filter signal and visibleTasks reflects it":
    let vm = newTaskAppVM()
    vm.addTask("foo")
    vm.addTask("bar")
    vm.toggleTask(vm.tasks.val[0].id)  # foo done, bar active

    # Default: All.
    check vm.filter.val == fmAll
    check vm.visibleTasks.len == 2

    # Active filter.
    vm.setFilter(fmActive)
    check vm.filter.val == fmActive
    let active = vm.visibleTasks
    check active.len == 1
    check active[0].name == "bar"
    check not active[0].completed

    # Completed filter.
    vm.setFilter(fmCompleted)
    check vm.filter.val == fmCompleted
    let completed = vm.visibleTasks
    check completed.len == 1
    check completed[0].name == "foo"
    check completed[0].completed

    # Back to All.
    vm.setFilter(fmAll)
    check vm.filter.val == fmAll
    check vm.visibleTasks.len == 2

  test "removeTask drops the matching row, preserves order, no-op on miss":
    let vm = newTaskAppVM()
    vm.addTask("a"); vm.addTask("b"); vm.addTask("c")
    let bId = vm.tasks.val[1].id
    vm.removeTask(bId)
    check vm.totalCount == 2
    check vm.tasks.val[0].name == "a"
    check vm.tasks.val[1].name == "c"
    let before = vm.snapshot
    vm.removeTask(99999)
    check vm.snapshot == before

  test "clearCompleted removes only completed tasks in one batch":
    let vm = newTaskAppVM()
    vm.addTask("a"); vm.addTask("b"); vm.addTask("c"); vm.addTask("d")
    vm.toggleTask(vm.tasks.val[0].id)
    vm.toggleTask(vm.tasks.val[2].id)
    check vm.completedCount == 2
    vm.clearCompleted()
    check vm.totalCount == 2
    check vm.tasks.val[0].name == "b"
    check vm.tasks.val[1].name == "d"
    check vm.completedCount == 0

  test "setInputText writes through to the inputText signal":
    let vm = newTaskAppVM()
    vm.setInputText("draft")
    check vm.inputText.val == "draft"
    # addTask still trims & clears.
    vm.addTask("draft")
    check vm.inputText.val == ""
    check vm.totalCount == 1

  test "snapshot captures a value-copy of all live signals":
    let vm = newTaskAppVM()
    vm.addTask("foo"); vm.addTask("bar")
    vm.setFilter(fmActive)
    vm.setInputText("draft")
    let snap = vm.snapshot
    check snap.tasks.len == 2
    check snap.filter == fmActive
    check snap.inputText == "draft"
    # Mutating the VM after snapshot doesn't change the snapshot.
    vm.addTask("baz")
    check snap.tasks.len == 2
    check vm.totalCount == 3

  test "full M22 scenario — the same script the pilot test runs":
    ## Same exact action sequence the `isonim-tui`
    ## `test_task_app_pilot_drive_real_stack` test plays back through
    ## the renderer; here we drive the VM directly so we can prove the
    ## terminal state matches without any renderer involvement.
    let vm = newTaskAppVM()
    vm.addTask("Buy milk")
    check vm.totalCount == 1
    check vm.tasks.val[0].name == "Buy milk"
    check not vm.tasks.val[0].completed
    check vm.inputText.val == ""

    vm.addTask("Write specs")
    check vm.totalCount == 2
    check vm.tasks.val[1].name == "Write specs"

    vm.toggleTask(vm.tasks.val[1].id)
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
