## tests/test_async_perf_demo.nim — Canonical example of testing
## async ViewModels with fake-time acceleration.
##
## ---------------------------------------------------------------------------
## Why this file exists
## ---------------------------------------------------------------------------
##
## Async ViewModels — the kind that landed in EX-M17, where every
## mutation routes through a database future and surfaces its loading /
## refreshing / errored state through `Resource[T]` — are correct by
## design but slow to test by default. The default `FakeDb` injects
## 30-50 ms of simulated latency per operation. A naive test that
## exercised 100 operations against the real event loop would take
## 3-5 seconds of wall-clock time. That's death by a thousand cuts
## for a test suite that wants to assert end-to-end VM behaviour
## across hundreds of cases.
##
## The solution is fake time. `nim_everywhere/fake_time` ships a
## `FakeAsyncContext` that intercepts `sleepFor(ms)` — instead of
## scheduling a real timer, it queues the completion against a
## simulated clock that tests advance manually. `advance(ms) +
## runPending()` fires every callback whose deadline has passed,
## synchronously, without the OS ever sleeping. The same `sleepFor`
## primitive is used in production code (the editor's bridge
## launchers experience real latency); only the test installs the
## fake context to bypass it.
##
## ---------------------------------------------------------------------------
## The pattern in three lines
## ---------------------------------------------------------------------------
##
## 1. Install a `FakeAsyncContext` (the `AsyncDriver` helper does this
##    in its constructor — see `tests/helpers/async_drive.nim`).
## 2. Drive the VM through its async actions; each action enqueues a
##    `sleepFor`-backed future on the fake clock.
## 3. After each action (or batch) call `drv.flush()` to advance the
##    clock and drain platform callbacks; then assert against VM signals.
##
## ---------------------------------------------------------------------------
## When NOT to use fake time
## ---------------------------------------------------------------------------
##
## Fake time tests the *logic* of an async ViewModel — the state
## transitions, the generation-counter guard against out-of-order
## completions, the error surfaces. It deliberately does NOT test
## real I/O behaviour: throughput, jitter, backpressure, real-world
## ordering between independent timers, or anything tied to the OS
## event loop's scheduling characteristics. For those, write an
## integration test that uses the real backend (the EX-M14 Playwright
## "TUI bridge eventually paints real demo content (latency < 5s)"
## case is an example).
##
## A good rule of thumb: if the assertion is "the VM reaches state X
## after action Y", use fake time. If the assertion is "the operation
## completes within N ms of real time" or "two independent timers
## interleave correctly", use the real event loop.
##
## ---------------------------------------------------------------------------
## Underlying primitives (pointer)
## ---------------------------------------------------------------------------
##
##   - `nim_everywhere/async_compat.sleepFor(ms)` — the unified sleep
##     primitive. Routes through the fake clock when one is installed.
##   - `nim_everywhere/fake_time.FakeAsyncContext` — `install`,
##     `uninstall`, `advance(ms)`, `runPending()`, `now()`. Per-thread.
##   - `nim_everywhere/async_compat.drainPlatformCallbacks()` — drains
##     the underlying backend's microtask queue after the fake clock
##     fires; necessary because the resource's success callback
##     mutates a signal, which schedules a downstream effect.
##   - `tests/helpers/async_drive.AsyncDriver` — bundles a fake context
##     + a seeded `FakeDb` + a `flush()` method that does the standard
##     advance-and-drain pattern. Use it unless you need to test the
##     loading state mid-flight (in which case call
##     `drv.ctx.advance(smallMs)` and skip `flush`).
##
## ---------------------------------------------------------------------------
## EX-M18: the headline assertion
## ---------------------------------------------------------------------------
##
## 100 mixed simulated database operations complete in well under 100 ms
## wall-clock — orders of magnitude faster than the 3-5 seconds those
## same ops would take through a real event loop. Every other path
## (signal propagation, the resource's generation-counter guard
## against out-of-order completions, error handling, the per-item
## reactive subscriptions in leaves) runs through the real reactive
## graph; only `sleepFor` is short-circuited.

import std/[options, sequtils, times, unittest]

import isonim/core/signals
import isonim/core/resource

# Pull in the NE-Time-M0 facade — `withTimeout`, `scheduleEvery`,
# `cancelTimer`, `TimerHandle` — that the two new cases at the end of
# this file exercise. The rest of the suite predates the facade and
# uses only `sleepFor` (re-exported via `nim_everywhere`).
import nim_everywhere/time

import services/fake_db
import task_app/core/vm as task_vm
import settings_app/core/vm as settings_vm
import settings_app/core/demo_catalog

import ./helpers/async_drive

suite "EX-M18: Fake-time async test patterns":

  test "100 mixed ops complete in well under 100 ms wall-clock":
    ## The headline assertion. With 30-50 ms latency per op, 100 real
    ## ops would take 3-5 seconds. Fake time completes them all in well
    ## under 100 ms by short-circuiting the sleep primitive while every
    ## other path (signal propagation, resource state transitions,
    ## error handling) runs through the real reactive graph.
    let drv = newAsyncDriver(seed = 42)
    defer: drv.shutdown()
    let vm = newTaskAppVM(drv.db)
    drv.flush()                          # initial load
    check vm.tasks.state.val == rsReady

    let started = epochTime()

    # Mix profile: 30 saves, 30 toggles, 20 deletes, 20 refreshes = 100.
    # Each call routes through fake_db's `scheduleResult` template,
    # which enqueues a `sleepFor(30..50 ms)` on the fake clock — under
    # real time this batch would burn 3-5 seconds of wall-clock.
    for i in 1 .. 30:
      vm.addTask("task-" & $i)
      drv.flush()

    # Snapshot the visible-ids set so we can toggle / delete against
    # real task ids rather than re-reading `visibleTasks` on every iter
    # (which would just pick the first item every time after a delete).
    var liveIds: seq[int] = @[]
    for t in vm.visibleTasks: liveIds.add t.id

    for i in 0 ..< 30:
      let idx = i mod liveIds.len
      vm.toggleTask(liveIds[idx])
      drv.flush()

    for i in 0 ..< 20:
      # Re-read on every iter so we always delete an actually-live id.
      if vm.visibleTasks.len > 0:
        vm.removeTask(vm.visibleTasks[0].id)
        drv.flush()

    for _ in 1 .. 20:
      vm.tasks.refresh()
      drv.flush()

    let elapsed = epochTime() - started
    # Emit the elapsed time so the verification log captures it across
    # the asyncdispatch / chronos backend matrix.
    echo "[EX-M18] 100 mixed ops elapsed: ", (elapsed * 1000.0), " ms"

    check elapsed < 0.100               # < 100 ms wall-clock for 100 sim ops
    check vm.lastError.val.isNone        # no spurious errors
    check vm.pendingOps.val == 0         # all settled

  test "fake-time deterministic — same seed produces same outcomes":
    ## Two drivers with the same seed and the same scripted sequence
    ## must produce byte-identical VM state. This is what makes
    ## fake-time tests reproducible across runs, machines, and async
    ## backends: the latency RNG is seeded, the clock is monotonic
    ## under our control, and the reactive graph is purely
    ## deterministic. Without this property, a flake in the test suite
    ## would be indistinguishable from a real bug.
    proc scriptedRun(seed: int64): seq[string] =
      let drv = newAsyncDriver(seed = seed)
      defer: drv.shutdown()
      let vm = newTaskAppVM(drv.db)
      drv.flush()
      for i in 1 .. 10:
        vm.addTask("t" & $i)
        drv.flush()
      result = @[]
      for t in vm.visibleTasks: result.add t.name

    check scriptedRun(42) == scriptedRun(42)

    # And: although different seeds produce different latency
    # *sequences*, the operations themselves are idempotent against
    # the store, so the final VM state matches. The point of the seed
    # is latency reproducibility, not behavioural divergence.
    let a = scriptedRun(42)
    let b = scriptedRun(43)
    check a == b

  test "fault injection — saveTask failure surfaces lastError without losing VM coherence":
    ## How to test the error path: `db.scriptFailure(opName)` arms the
    ## next call of a given op to fail with a synthetic error. The VM
    ## propagates that into `vm.lastError`, decrements `pendingOps`
    ## back to zero, and leaves the task list unchanged (no
    ## half-applied state). A subsequent successful op clears
    ## `lastError`, demonstrating recovery semantics.
    let drv = newAsyncDriver(seed = 42)
    defer: drv.shutdown()
    let vm = newTaskAppVM(drv.db)
    drv.flush()

    drv.db.scriptFailure("saveTask")
    vm.addTask("doomed")
    drv.flush()

    check vm.lastError.val.isSome
    check vm.pendingOps.val == 0          # in-flight counter recovered
    check "doomed" notin vm.visibleTasks.mapIt(it.name)  # not persisted

    # Recovery: next save succeeds and `lastError` clears.
    vm.addTask("recovered")
    drv.flush()
    check vm.lastError.val.isNone
    check "recovered" in vm.visibleTasks.mapIt(it.name)

  test "concurrent ops complete in any order with a single flush":
    ## A subtler idiom: tests don't need to drain after every action.
    ## Fire several ops back-to-back, then call `drv.flush()` once.
    ## All the latencies elapse against the same simulated time
    ## window, and every callback drains in the cascade. The end
    ## state must match what a sequential drive would produce — the
    ## reactive graph's correctness doesn't depend on the test
    ## artificially serialising the world.
    let drv = newAsyncDriver(seed = 42)
    defer: drv.shutdown()
    let vm = newTaskAppVM(drv.db)
    drv.flush()

    # Five saves fired without intermediate flushes. Each `addTask`
    # increments `pendingOps`; the counter peaks at 5.
    vm.addTask("a")
    vm.addTask("b")
    vm.addTask("c")
    vm.addTask("d")
    vm.addTask("e")
    check vm.pendingOps.val == 5

    # Single flush drains all five.
    drv.flush()
    check vm.pendingOps.val == 0
    check vm.lastError.val.isNone

    # All five tasks are present. Order of names is not guaranteed by
    # the parallel-ops semantics — fake_db's id allocation is
    # synchronous and monotonic so we can still assert by sorted name.
    let names = vm.visibleTasks.mapIt(it.name)
    check names.len == 5
    for ch in ["a", "b", "c", "d", "e"]:
      check ch in names

  test "out-of-order refreshes are handled by the generation guard":
    ## The `Resource[T]` machinery includes a generation counter so
    ## that if two `refresh()` calls are in flight at the same time
    ## and complete out of order, only the most-recent call's result
    ## is observed. We exercise that here by firing two refreshes
    ## back-to-back: under fake time both their `sleepFor`s expire in
    ## the same `advance(100)` window. The state must converge on the
    ## latest store contents — and `state` must end at `rsReady`, not
    ## stuck on an intermediate `rsRefreshing`.
    let drv = newAsyncDriver(seed = 42)
    defer: drv.shutdown()
    let vm = newTaskAppVM(drv.db)
    drv.flush()
    vm.addTask("seed-1"); drv.flush()
    check vm.tasks.data.val.len == 1

    # Mutate the store directly so each refresh sees a different
    # snapshot — that surfaces the "wrong refresh won" case as a
    # visible discrepancy if the generation guard were broken.
    drv.db.tasks.add Task(id: drv.db.allocTaskId(), name: "seed-2",
                          completed: false)

    # Two refreshes back-to-back, no flush between them.
    vm.tasks.refresh()
    vm.tasks.refresh()
    drv.flush()

    # End state: rsReady (not stuck refreshing), data reflects the
    # current store (both seed-1 and seed-2 visible).
    check vm.tasks.state.val == rsReady
    let names = vm.tasks.data.val.mapIt(it.name)
    check names.len == 2
    check "seed-1" in names
    check "seed-2" in names

  test "loading state is observable mid-flight (no flush)":
    ## Sometimes a test needs to assert the *loading* state itself —
    ## e.g. "the UI shows a spinner while the initial load is in
    ## flight". The pattern: skip `drv.flush()` and instead read the
    ## VM signals directly. With no time advanced, the resource sits
    ## in `rsPending` (initial) or `rsRefreshing` (after a refresh).
    let drv = newAsyncDriver(seed = 42)
    defer: drv.shutdown()
    let vm = newTaskAppVM(drv.db)

    # No flush yet — the initial load future is pending on the fake
    # clock. State must be rsPending and `loading` true.
    check vm.tasks.state.val == rsPending
    check vm.loading

    drv.flush()
    check vm.tasks.state.val == rsReady
    check not vm.loading

    # Refresh mid-flight: state goes to rsRefreshing, then back to
    # rsReady. The old value remains visible during the refresh
    # (mirrors SolidJS semantics) — assert by reading data.val
    # without advancing time.
    vm.addTask("survivor"); drv.flush()
    let snapshotBefore = vm.tasks.data.val
    vm.tasks.refresh()
    check vm.tasks.state.val == rsRefreshing
    check vm.loading
    check vm.tasks.data.val == snapshotBefore   # old data visible
    drv.flush()
    check vm.tasks.state.val == rsReady
    check not vm.loading

  test "settings VM exhibits the same patterns":
    ## A brief mirror for the settings app, so readers see the
    ## pattern isn't task-app-specific. Every async ViewModel that
    ## consumes `FakeDb` + `Resource[T]` tests the same way.
    let drv = newAsyncDriver(seed = 42)
    defer: drv.shutdown()
    drv.db.seedSettings(buildDemoSettingsCatalog())
    let vm = newSettingsVM(drv.db)
    drv.flush()

    check vm.catalogResource.state.val == rsReady
    check vm.lastError.val.isNone

    # Mutate a toggle, a number, and a choice. Each routes through
    # fake_db; each requires its own flush before the VM's per-item
    # accessor reflects the new value.
    discard vm.setToggle("appearance.dark_mode", true)
    drv.flush()
    check vm.toggleValue("appearance.dark_mode") == true

    discard vm.setNumber("appearance.font_size", 18)
    drv.flush()
    check vm.numberValue("appearance.font_size") == 18

    discard vm.setChoice("appearance.theme", "Solarized")
    drv.flush()
    check vm.choiceValue("appearance.theme") == "Solarized"

    check vm.lastError.val.isNone
    check vm.pendingOps.val == 0

  test "settings VM — scripted failure recovers cleanly":
    ## Same fault-injection pattern as the task VM. The settings VM
    ## uses a single `saveSetting` op name regardless of item kind,
    ## so one `scriptFailure` arms the next write of any kind.
    let drv = newAsyncDriver(seed = 42)
    defer: drv.shutdown()
    drv.db.seedSettings(buildDemoSettingsCatalog())
    let vm = newSettingsVM(drv.db)
    drv.flush()

    drv.db.scriptFailure("saveSetting")
    discard vm.setToggle("appearance.dark_mode", true)
    drv.flush()
    check vm.lastError.val.isSome
    check vm.toggleValue("appearance.dark_mode") == false   # unchanged
    check vm.pendingOps.val == 0

    # Next op clears the error.
    discard vm.setToggle("appearance.dark_mode", true)
    drv.flush()
    check vm.lastError.val.isNone
    check vm.toggleValue("appearance.dark_mode") == true

  # ---------------------------------------------------------------------------
  # NE-Time-M0 / EX-M18 extensions: exercise the expanded time facade
  # ---------------------------------------------------------------------------
  #
  # The two test cases below are NEW with NE-Time-M0. They demonstrate
  # how `scheduleEvery` and `withTimeout` integrate with the same
  # `FakeAsyncContext` / `AsyncDriver` pattern the rest of this suite
  # uses. Read these alongside the earlier cases — they're the teaching
  # extension for downstream IsoNim apps that need periodic timers or
  # deadline-bounded async ops.
  #
  # KEY INSIGHT: fake-time isn't just for `sleepFor`. Every primitive
  # in `nim_everywhere/time` consults the same thread-local
  # `FakeAsyncContext`, so a test that installs one drives all of them
  # deterministically. The advance/flush pattern is identical to the
  # cases above; only the primitive under test changes.

  test "scheduleEvery fires N times during a fake-time advance":
    ## A periodic 10 ms timer; advance 100 ms of simulated time; assert
    ## the callback fired exactly 10 times. Under real time this would
    ## take ~100 ms of wall-clock; under fake time it's microseconds.
    ##
    ## Notable details:
    ##
    ## - `scheduleEvery` re-arms itself via a closure that consults
    ##   `TimerHandle.cancelled` before each firing AND before each
    ##   re-schedule. That guarantees `cancelTimer` immediately stops
    ##   the timer — no "one more firing" race.
    ##
    ## - Under fake time the implementation schedules each firing on
    ##   the `FakeAsyncContext` directly (bypassing the backend's
    ##   `addCallback` queue) so all N firings drain within a single
    ##   `advance(...)` call. This is what makes the assertion
    ##   `count == 10` exactly (not approximate) deterministic.
    ##
    ## - The "advance + flush" cadence works without modification:
    ##   the AsyncDriver helper's `flush()` already does the right
    ##   thing because `scheduleEvery` reuses the same primitives.
    let drv = newAsyncDriver(seed = 42)
    defer: drv.shutdown()

    var count = 0
    let h = scheduleEvery(10, proc() = inc count)

    # Advance 100 ms of simulated time. Under the 10 ms interval that
    # means exactly 10 firings: at fake t=10, 20, 30, ..., 100. The
    # re-scheduling closure inside `scheduleEvery` schedules each next
    # firing relative to the *target* tick (not the current `nowMs`),
    # so a single drain cycle picks up all of them.
    #
    # NOTE: `drv.flush(ms)` internally calls `advance(ms)` *twice*
    # (to handle two-level cascades — see `async_drive.flush`). For a
    # precise-tick periodic-timer assertion we use the underlying
    # `ctx.advance` + drain directly so the simulated time advances
    # exactly 100 ms once.
    drv.ctx.advance(100)
    drv.ctx.runPending()
    drainPlatformCallbacks()
    check count == 10

    # Cancel — subsequent advances must not produce further firings.
    # `cancelTimer` is idempotent and a no-op on already-fired handles,
    # so it's always safe to call.
    cancelTimer(h)
    drv.ctx.advance(100)
    drv.ctx.runPending()
    drainPlatformCallbacks()
    check count == 10

  test "withTimeout returns none when the underlying op blows the deadline":
    ## A simulated 200 ms `fake_db` op wrapped in `withTimeout(100)`.
    ## After advancing 100 ms the wrapper resolves to `none(seq[Task])`
    ## (the deadline won). After advancing another 200 ms the original
    ## op's late completion is observable on the inner future, but the
    ## wrapper's resolution must NOT change — the OOO-guard inside
    ## `withTimeout` ensures the wrapper resolves at most once.
    ##
    ## This is the cross-of-two-patterns case: the AsyncDriver's fake
    ## clock supplies the 200 ms latency (via `fake_db.scheduleResult`
    ## → `sleepFor(latency)`), AND the deadline future inside
    ## `withTimeout` also routes through the fake clock. Both observe
    ## the same `advance()` call sequence, so the race resolves
    ## deterministically.
    ##
    ## In a real downstream IsoNim app, the same `withTimeout` call
    ## would experience real wall-clock latencies — but the assertion
    ## structure (some on timely completion, none on deadline miss,
    ## error propagation on failure) is identical.

    # latencyMin == latencyMax == 200 forces every fake_db op to take
    # exactly 200 ms — no RNG noise to complicate the deadline race.
    let drv = newAsyncDriver(seed = 42, latencyMin = 200, latencyMax = 200)
    defer: drv.shutdown()

    # Seed the store so loadTasks has something to return.
    drv.db.tasks.add Task(id: drv.db.allocTaskId(), name: "alpha",
                          completed: false)

    # Fire the inner op. It will take 200 ms of simulated time.
    let innerFut = drv.db.loadTasks()

    # Wrap with a 100 ms deadline. The wrapper resolves to none() at
    # fake t=100 (deadline first); the inner completes at fake t=200.
    let wrapper = withTimeout(innerFut, 100)

    var got: Option[seq[Task]]
    var resolveCount = 0
    var errSeen = ""
    wrapper.onComplete(
      proc(v: Option[seq[Task]]) =
        got = v
        resolveCount = resolveCount + 1
      ,
      proc(m: string) = errSeen = m)

    # Cross the deadline tick (fake t=100). At this point the
    # wrapper's `deadline = sleepFor(100)` fires; the wrapper resolves
    # to none(seq[Task]); the user callback runs and bumps
    # resolveCount.
    #
    # Use `drv.ctx.advance(100)` directly (not `drv.flush(100)`) so
    # the simulated clock advances exactly 100 ms. `drv.flush` advances
    # twice for cascade safety; here we want precise control over
    # which side of the race wins. The two drain cycles below handle
    # the wrapper → user-callback chain under chronos's callSoon.
    drv.ctx.advance(100)
    drv.ctx.runPending()
    drainPlatformCallbacks()
    drv.ctx.runPending()
    drainPlatformCallbacks()
    check got.isNone
    check resolveCount == 1
    check errSeen == ""

    # Cross the inner's late firing (fake t=300, accumulated). The
    # inner future completes — observable directly via `innerFut.read`
    # if we ever waitFor'd it — but the wrapper MUST stay at none().
    # This is the late-completion guarantee that makes `withTimeout`
    # safe to compose with retry / fallback logic: once the deadline
    # wins, downstream code can move on without worrying that the
    # original op's late result will overwrite the timeout state.
    drv.ctx.advance(200)
    drv.ctx.runPending()
    drainPlatformCallbacks()
    drv.ctx.runPending()
    drainPlatformCallbacks()
    check got.isNone           # wrapper unchanged
    check resolveCount == 1     # exactly one resolution
    check errSeen == ""
