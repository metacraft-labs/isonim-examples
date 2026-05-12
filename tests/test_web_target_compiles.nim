## test_web_target_compiles — EX-M2 / EX-M17 mandatory integration test.
##
## After EX-M17 every VM mutation is async, so the test installs a
## `FakeAsyncContext` and drains the fake clock between scripted
## actions.

import std/[unittest, tables]

import isonim/core/signals
import task_app/main_web
import ./helpers/async_drive

suite "EX-M17: web composition root drives the canonical async VM":
  test "test_web_target_compiles":
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    let vm = newTaskAppVM(drv.db)
    let r = MockRenderer()
    let root = buildTaskApp(r, vm)
    drv.flush()
    check root != nil
    check root.tag == "div"
    check root.attributes.getOrDefault("class") == "task-app"
    check root.children.len == 4

    vm.addTask("First"); drv.flush()
    vm.addTask("Second"); drv.flush()
    check vm.totalCount == 2

    let firstId = vm.tasks.data.val[0].id
    vm.toggleTask(firstId); drv.flush()
    check vm.completedCount == 1

    vm.setFilter(fmActive)
    let visible = vm.visibleTasks
    check visible.len == 1
    check visible[0].name == "Second"

    vm.setFilter(fmCompleted)
    let comp = vm.visibleTasks
    check comp.len == 1
    check comp[0].name == "First"

    vm.clearCompleted(); drv.flush()
    check vm.totalCount == 1
    check vm.visibleTasks.len == 0  # filter is still Completed

    vm.setFilter(fmAll)
    check vm.visibleTasks.len == 1
    check vm.visibleTasks[0].name == "Second"

    resetWebLeaves()
