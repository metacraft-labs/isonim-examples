## helpers/async_drive.nim — test helpers for driving the EX-M17 async VMs
## through a `FakeAsyncContext`.
##
## EX-M17 turned every mutation action on `TaskAppVM` / `SettingsVM` into
## an async op (the action enqueues a `saveTask` / `saveSetting` through
## the `FakeDb`, refreshes the resource on success, and updates
## `pendingOps` / `lastError`). Tests that previously expected
## synchronous semantics ("addTask(foo); check totalCount == 1") now
## need to advance simulated time after every action and drain platform
## callbacks before observing.
##
## The pattern:
##
##   let drv = newAsyncDriver()
##   defer: drv.shutdown()
##   let vm = newTaskAppVM(drv.db)
##   drv.flush()          # initial load
##   vm.addTask("foo")
##   drv.flush()
##   check vm.totalCount == 1
##
## `flush` advances the fake clock by a fixed window (large enough to
## fire every scheduled callback under the default 30-50 ms latency)
## and drains platform callbacks. Tests that exercise the *loading*
## state explicitly call `drv.ctx.advance(small)` themselves and skip
## `flush`.

import nim_everywhere
import nim_everywhere/async_compat

import services/fake_db
export fake_db

type
  AsyncDriver* = ref object
    ## Bundles a `FakeAsyncContext` + a `FakeDb` so tests don't need
    ## to import both individually. `db` exposes the same surface as
    ## `newFakeDb()`; tests seed it before constructing the VM.
    ctx*: FakeAsyncContext
    db*: FakeDb

proc newAsyncDriver*(seed: int64 = 42;
                     latencyMin = 30; latencyMax = 50): AsyncDriver =
  ## Install a fresh `FakeAsyncContext` on the current thread and build
  ## a deterministic `FakeDb`. The default latency window matches the
  ## production demo (30-50 ms), so tests exercise the same code path
  ## as the editor's bridge launchers.
  let ctx = newFakeAsyncContext()
  ctx.install()
  AsyncDriver(
    ctx: ctx,
    db: newFakeDb(seed = seed, latencyMin = latencyMin, latencyMax = latencyMax))

proc shutdown*(drv: AsyncDriver) =
  ## Restore the previous fake context (or nil). Tests that own the
  ## driver should `defer drv.shutdown()` to keep thread-local state
  ## clean across test cases.
  drv.ctx.uninstall()

proc flush*(drv: AsyncDriver; ms = 100) =
  ## Advance simulated time by `ms` and drain platform callbacks until
  ## the queue is empty. The default `ms = 100` is large enough to
  ## resolve any op under the 30-50 ms latency window; tests that
  ## launch multiple ops in sequence may need to call `flush` once per
  ## op or pass a larger `ms`.
  drv.ctx.advance(ms)
  drv.ctx.runPending()
  drainPlatformCallbacks()
  # A second drain catches cascaded ops queued from the first batch's
  # success callbacks (the resource's refresh triggers another
  # loadTasks / loadSettings, which schedules another sleepFor).
  drv.ctx.advance(ms)
  drv.ctx.runPending()
  drainPlatformCallbacks()
