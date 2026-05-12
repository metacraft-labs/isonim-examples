## test_fake_db — EX-M17 strong integration test for the fake_db service.
##
## Drives `services/fake_db.nim` directly under a `FakeAsyncContext`
## so the suite is fully deterministic. Every assertion exercises the
## real db type — no mocks. The fake-time machinery (from
## nim_everywhere/fake_time) is the only thing that distinguishes this
## test from a production use of `fake_db`.

import std/[json, strutils, unittest]

import nim_everywhere
import nim_everywhere/async_compat

import services/fake_db
import settings_app/core/demo_catalog

suite "EX-M17: fake_db real-stack behaviour":

  test "loadTasks resolves with seeded store after advancing the clock":
    let ctx = newFakeAsyncContext()
    ctx.install()
    defer: ctx.uninstall()
    let db = newFakeDb(seed = 42)
    db.tasks = @[
      Task(id: 1, name: "one", completed: false),
      Task(id: 2, name: "two", completed: true)]
    db.nextTaskId = 3
    var got: seq[Task] = @[]
    var resolved = false
    db.loadTasks().onComplete(
      onSuccess = proc(v: seq[Task]) =
        got = v
        resolved = true,
      onError = proc(m: string) = discard)
    # Still pending — the latency window is 30-50 ms; we haven't
    # advanced the clock yet.
    check not resolved
    # Advance past the maximum latency.
    ctx.advance(60)
    ctx.runPending()
    drainPlatformCallbacks()
    check resolved
    check got.len == 2
    check got[0].name == "one"
    check got[1].completed

  test "scriptFailure causes the next call to fail then recover":
    let ctx = newFakeAsyncContext()
    ctx.install()
    defer: ctx.uninstall()
    let db = newFakeDb(seed = 42)
    db.scriptFailure("saveTask", times = 1)
    var saw: string = ""
    db.saveTask(Task(id: 0, name: "x", completed: false)).onComplete(
      onSuccess = proc() = saw = "ok",
      onError = proc(m: string) = saw = m)
    ctx.advance(60)
    ctx.runPending()
    drainPlatformCallbacks()
    check saw.len > 0
    check saw != "ok"
    check "scripted failure" in saw
    # Next call should succeed — the script countdown was 1.
    saw = ""
    db.saveTask(Task(id: 0, name: "y", completed: false)).onComplete(
      onSuccess = proc() = saw = "ok",
      onError = proc(m: string) = saw = m)
    ctx.advance(60)
    ctx.runPending()
    drainPlatformCallbacks()
    check saw == "ok"
    check db.tasks.len == 1
    check db.tasks[0].name == "y"

  test "concurrent loads complete independently":
    let ctx = newFakeAsyncContext()
    ctx.install()
    defer: ctx.uninstall()
    let db = newFakeDb(seed = 42)
    db.tasks = @[Task(id: 1, name: "alpha", completed: false)]
    var resolutions = 0
    var seenLens: seq[int] = @[]
    proc onLoad(v: seq[Task]) =
      seenLens.add v.len
      inc resolutions
    proc onLoadFail(m: string) = discard
    for i in 0 ..< 3:
      db.loadTasks().onComplete(onSuccess = onLoad, onError = onLoadFail)
    check resolutions == 0
    # The three loads all queue with random latencies in [30, 50] ms;
    # advancing 60 ms is enough to fire every one.
    ctx.advance(60)
    ctx.runPending()
    drainPlatformCallbacks()
    check resolutions == 3
    for l in seenLens:
      check l == 1

  test "saveTask assigns a monotonic id when input id is 0":
    let ctx = newFakeAsyncContext()
    ctx.install()
    defer: ctx.uninstall()
    let db = newFakeDb(seed = 42)
    db.saveTask(Task(id: 0, name: "first", completed: false)).onComplete(
      onSuccess = proc() = discard,
      onError = proc(m: string) = discard)
    ctx.advance(60); ctx.runPending(); drainPlatformCallbacks()
    db.saveTask(Task(id: 0, name: "second", completed: false)).onComplete(
      onSuccess = proc() = discard,
      onError = proc(m: string) = discard)
    ctx.advance(60); ctx.runPending(); drainPlatformCallbacks()
    check db.tasks.len == 2
    check db.tasks[0].id == 1
    check db.tasks[1].id == 2
    check db.tasks[0].name == "first"
    check db.tasks[1].name == "second"

  test "deleteTask drops the matching row":
    let ctx = newFakeAsyncContext()
    ctx.install()
    defer: ctx.uninstall()
    let db = newFakeDb(seed = 42)
    db.tasks = @[
      Task(id: 1, name: "a", completed: false),
      Task(id: 2, name: "b", completed: false),
      Task(id: 3, name: "c", completed: false)]
    db.nextTaskId = 4
    db.deleteTask(2).onComplete(
      onSuccess = proc() = discard,
      onError = proc(m: string) = discard)
    ctx.advance(60); ctx.runPending(); drainPlatformCallbacks()
    check db.tasks.len == 2
    check db.tasks[0].id == 1
    check db.tasks[1].id == 3

  test "loadSettings + saveSetting round-trip":
    let ctx = newFakeAsyncContext()
    ctx.install()
    defer: ctx.uninstall()
    let db = newFakeDb(seed = 42)
    db.seedSettings(buildDemoSettingsCatalog())
    var snap: SettingsSnapshot
    db.loadSettings().onComplete(
      onSuccess = proc(v: SettingsSnapshot) = snap = v,
      onError = proc(m: string) = discard)
    ctx.advance(60); ctx.runPending(); drainPlatformCallbacks()
    check snap.toggles["appearance.dark_mode"] == false

    # Save a new value.
    db.saveSetting("appearance.dark_mode", %true).onComplete(
      onSuccess = proc() = discard,
      onError = proc(m: string) = discard)
    ctx.advance(60); ctx.runPending(); drainPlatformCallbacks()
    check db.settingsToggles["appearance.dark_mode"] == true

  test "latency is deterministic for a given seed":
    # Two dbs with the same seed produce the same latency sequence.
    # We measure by capturing how much clock advance is needed to
    # resolve the first op on each.
    let ctxA = newFakeAsyncContext()
    ctxA.install()
    let dbA = newFakeDb(seed = 7)
    var aDoneAt = -1
    dbA.loadTasks().onComplete(
      onSuccess = proc(v: seq[Task]) =
        aDoneAt = ctxA.nowMs.int,
      onError = proc(m: string) = discard)
    # Advance in 1 ms increments to find the exact resolution time.
    for _ in 0 ..< 100:
      if aDoneAt >= 0: break
      ctxA.advance(1)
      ctxA.runPending()
      drainPlatformCallbacks()
    ctxA.uninstall()

    let ctxB = newFakeAsyncContext()
    ctxB.install()
    let dbB = newFakeDb(seed = 7)
    var bDoneAt = -1
    dbB.loadTasks().onComplete(
      onSuccess = proc(v: seq[Task]) =
        bDoneAt = ctxB.nowMs.int,
      onError = proc(m: string) = discard)
    for _ in 0 ..< 100:
      if bDoneAt >= 0: break
      ctxB.advance(1)
      ctxB.runPending()
      drainPlatformCallbacks()
    ctxB.uninstall()

    check aDoneAt > 0
    check aDoneAt == bDoneAt

  test "latencyMin == latencyMax == 0 resolves on the next drain":
    let ctx = newFakeAsyncContext()
    ctx.install()
    defer: ctx.uninstall()
    let db = newFakeDb(seed = 1, latencyMin = 0, latencyMax = 0)
    var resolved = false
    db.loadTasks().onComplete(
      onSuccess = proc(v: seq[Task]) = resolved = true,
      onError = proc(m: string) = discard)
    # Advance 0 ms — runPending drains zero-latency ops.
    ctx.advance(0)
    ctx.runPending()
    drainPlatformCallbacks()
    check resolved
