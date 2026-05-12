## test_task_app_async_vm — EX-M17 strong integration test for the
## TaskAppVM async lifecycle.
##
## Drives the VM through a `FakeAsyncContext` so the full async
## pipeline (vm.addTask → db.saveTask → resource.refresh →
## db.loadTasks → tasks.data update) is exercised end to end.
## Asserts the rsPending → rsReady transition, the pendingOps
## counter, and the lastError surface.

import std/[options, strutils, unittest]

import nim_everywhere
import nim_everywhere/async_compat

import isonim/core/signals
import isonim/core/resource
import task_app/core/vm
import ./helpers/async_drive

suite "EX-M17: TaskAppVM with fake_db":

  test "initial load transitions rsPending to rsReady":
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    drv.db.tasks = @[Task(id: 1, name: "one", completed: false)]
    drv.db.nextTaskId = 2
    let vm = newTaskAppVM(drv.db)
    # Before the clock advances we should be pending.
    check vm.tasks.state.val == rsPending
    check vm.tasks.data.val.len == 0
    drv.flush()
    check vm.tasks.state.val == rsReady
    check vm.tasks.data.val.len == 1
    check vm.tasks.data.val[0].name == "one"

  test "addTask marks pending and resolves":
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    let vm = newTaskAppVM(drv.db)
    drv.flush()
    check vm.pendingOps.val == 0
    vm.addTask("foo")
    check vm.pendingOps.val == 1
    drv.flush()
    check vm.pendingOps.val == 0
    check vm.tasks.data.val.len == 1
    check vm.tasks.data.val[0].name == "foo"
    check vm.lastError.val.isNone

  test "addTask failure sets lastError, leaves tasks unchanged":
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    let vm = newTaskAppVM(drv.db)
    drv.flush()
    # Arm the next saveTask to fail.
    drv.db.scriptFailure("saveTask", times = 1)
    vm.addTask("doomed")
    check vm.pendingOps.val == 1
    drv.flush()
    check vm.pendingOps.val == 0
    check vm.lastError.val.isSome
    check "scripted failure" in vm.lastError.val.get
    check vm.tasks.data.val.len == 0  # unchanged

  test "addTask success clears lastError that was previously set":
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    let vm = newTaskAppVM(drv.db)
    drv.flush()
    drv.db.scriptFailure("saveTask", times = 1)
    vm.addTask("doomed"); drv.flush()
    check vm.lastError.val.isSome
    vm.addTask("survives"); drv.flush()
    check vm.lastError.val.isNone
    check vm.tasks.data.val.len == 1

  test "loading flag follows the resource state":
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    let vm = newTaskAppVM(drv.db)
    check vm.loading
    drv.flush()
    check not vm.loading
    vm.addTask("hello")
    drv.flush()
    check not vm.loading

  test "multiple in-flight writes correctly track pendingOps":
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    let vm = newTaskAppVM(drv.db)
    drv.flush()
    # Fire 3 ops without advancing in between.
    vm.addTask("a")
    vm.addTask("b")
    vm.addTask("c")
    check vm.pendingOps.val == 3
    drv.flush()
    check vm.pendingOps.val == 0
    check vm.tasks.data.val.len == 3

  test "toggleTask round-trip mutates the stored task":
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    let vm = newTaskAppVM(drv.db)
    drv.flush()
    vm.addTask("toggleable"); drv.flush()
    let id = vm.tasks.data.val[0].id
    check not vm.tasks.data.val[0].completed
    vm.toggleTask(id); drv.flush()
    check vm.tasks.data.val[0].completed
    vm.toggleTask(id); drv.flush()
    check not vm.tasks.data.val[0].completed

  test "removeTask actually removes":
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    let vm = newTaskAppVM(drv.db)
    drv.flush()
    vm.addTask("a"); drv.flush()
    vm.addTask("b"); drv.flush()
    let aId = vm.tasks.data.val[0].id
    vm.removeTask(aId); drv.flush()
    check vm.tasks.data.val.len == 1
    check vm.tasks.data.val[0].name == "b"

  test "clearCompleted removes only completed via the async path":
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    let vm = newTaskAppVM(drv.db)
    drv.flush()
    vm.addTask("a"); drv.flush()
    vm.addTask("b"); drv.flush()
    vm.addTask("c"); drv.flush()
    vm.toggleTask(vm.tasks.data.val[0].id); drv.flush()
    vm.toggleTask(vm.tasks.data.val[2].id); drv.flush()
    check vm.completedCount == 2
    vm.clearCompleted(); drv.flush()
    check vm.tasks.data.val.len == 1
    check vm.tasks.data.val[0].name == "b"

  test "newTaskAppVM() zero-latency convenience overload":
    # The no-arg constructor builds a zero-latency db. Without a fake
    # context, ops would still queue through the real event loop —
    # which here means asyncdispatch. We install one to drain
    # synchronously.
    let ctx = newFakeAsyncContext()
    ctx.install()
    defer: ctx.uninstall()
    let vm = newTaskAppVM()
    ctx.advance(0); ctx.runPending(); drainPlatformCallbacks()
    check vm.tasks.state.val == rsReady
    vm.addTask("hi")
    ctx.advance(0); ctx.runPending(); drainPlatformCallbacks()
    ctx.advance(0); ctx.runPending(); drainPlatformCallbacks()
    check vm.tasks.data.val.len == 1
