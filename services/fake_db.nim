## services/fake_db.nim — EX-M17: Fake async database backing the demo apps.
##
## Simulates a backend with 30-50 ms per-operation latency (configurable
## via `fakeDb.latencyMin` / `fakeDb.latencyMax`) using nim-everywhere's
## `sleepFor` + `FakeAsyncContext` primitives. Tests that install a
## `FakeAsyncContext` advance simulated time to skip the latency
## entirely; production code (the editor's EX-M14 bridge launchers)
## experiences the real latency.
##
## Why a shared fake_db: both demos (task_app and settings_app) need a
## simulated async data source to exercise the loading/refreshing/errored
## state machine through `Resource[T]`. Keeping one module means a single
## place to tune latencies, seed test data, and inject failures —
## downstream IsoNim consumers see the same pattern regardless of which
## demo they're inspecting.
##
## Fault injection (test hook): `scriptFailure(db, opName, times)`
## arms the next `times` calls of `opName` to fail. The VM surfaces
## the failure through `r.error.val` (for resource fetches) or
## `vm.lastError.val` (for mutation writes). This is the canonical
## way the demos' tests drive the error path of an async ViewModel.
##
## Latency reproducibility: pass a `seed` to `newFakeDb` to make the
## random latency sequence deterministic — same seed always picks the
## same latencies. Tests use a fixed seed; production code uses the
## default.
##
## EX-M17 spec:
## `codetracer-specs/Front-Ends/IsoNim/Async-Demo-Story.md`.

import std/[json, options, random, tables]

import nim_everywhere/time
  # `time` re-exports `async_compat` (PlatformFuture, newFuture,
  # onCompleteVoid, …) and ships the relocated `sleepFor` that this
  # module relies on. NE-Time-M0 moved `sleepFor` out of
  # `async_compat.nim`, so direct importers of `async_compat` would no
  # longer see it; this single import covers both surfaces.

import task_app/core/types as task_types
import settings_app/core/types as settings_types

export task_types
export settings_types

# ---------------------------------------------------------------------------
# FakeDb type + construction
# ---------------------------------------------------------------------------

type
  FakeDb* = ref object
    ## In-memory store + simulated latency knobs. Tests seed `tasks` /
    ## `settings` directly; production demo launchers populate them via
    ## the same API path as the UI (so the simulated latency is exercised
    ## even at launch time).
    tasks*: seq[Task]
    nextTaskId*: int
    settings*: SettingsCatalog
    settingsToggles*: Table[string, bool]
    settingsNumbers*: Table[string, int]
    settingsChoices*: Table[string, string]
    latencyMin*: int                       ## ms; default 30
    latencyMax*: int                       ## ms; default 50
    rng*: Rand
    failureScript*: Table[string, int]     ## opName → countdown of next-N-failures

proc newFakeDb*(seed: int64 = 1; latencyMin = 30; latencyMax = 50): FakeDb =
  ## Construct a fresh fake_db. The `seed` parameter makes the random
  ## latency reproducible — same seed always picks the same sequence of
  ## latencies. Tests use a fixed seed (typically 42) so retries don't
  ## change the latency profile.
  ##
  ## `latencyMin == latencyMax == 0` is supported for tests that want
  ## zero-latency ops — every operation completes on the next drain
  ## without advancing the fake clock.
  result = FakeDb(
    tasks: @[],
    nextTaskId: 1,
    settings: nil,
    settingsToggles: initTable[string, bool](),
    settingsNumbers: initTable[string, int](),
    settingsChoices: initTable[string, string](),
    latencyMin: latencyMin,
    latencyMax: latencyMax,
    rng: initRand(seed),
    failureScript: initTable[string, int]())

proc scriptFailure*(db: FakeDb; opName: string; times = 1) =
  ## Test hook: arm the next `times` calls of `opName` to fail with a
  ## synthetic error. After the countdown reaches zero, subsequent calls
  ## resolve normally again. This is the canonical way the demos' tests
  ## drive the error path through a ViewModel.
  db.failureScript[opName] = times

proc pickLatency(db: FakeDb): int =
  ## Internal: pick a latency in `[latencyMin, latencyMax]` using the
  ## seeded RNG. The exposed RNG state advances on every call so test
  ## sequences are deterministic.
  if db.latencyMax <= db.latencyMin:
    return db.latencyMin
  db.rng.rand(db.latencyMin .. db.latencyMax)

proc consumeFailure(db: FakeDb; opName: string): bool =
  ## Internal: decrement the failure-script countdown for `opName` and
  ## return true if this call should fail. Reaching zero removes the
  ## entry so future calls resolve normally.
  if not db.failureScript.hasKey(opName):
    return false
  let remaining = db.failureScript[opName]
  if remaining <= 0:
    db.failureScript.del(opName)
    return false
  if remaining == 1:
    db.failureScript.del(opName)
  else:
    db.failureScript[opName] = remaining - 1
  true

# ---------------------------------------------------------------------------
# Internal: schedule a result on the fake clock (or the real backend)
# ---------------------------------------------------------------------------

template scheduleResult[T](db: FakeDb; opName: string; body: untyped):
                         PlatformFuture[T] =
  ## Internal building block: pick a latency, then either complete with
  ## a value (`body` evaluates to `T`) or fail with a synthetic error
  ## per the failure script. Latency is honoured via `sleepFor` so the
  ## same code path drives both real and fake time.
  let opNameLit = opName
  let shouldFail = db.consumeFailure(opNameLit)
  let latency = db.pickLatency()
  let fut = newFuture[T]("fake_db." & opNameLit)
  let slept = sleepFor(latency)
  slept.onCompleteVoid(
    onSuccess = proc() =
      if shouldFail:
        fut.fail(newException(CatchableError,
          "fake_db: scripted failure for " & opNameLit))
      else:
        let value: T = body
        fut.complete(value),
    onError = proc(msg: string) =
      fut.fail(newException(CatchableError, msg)))
  fut

template scheduleVoidResult(db: FakeDb; opName: string; body: untyped):
                          PlatformFuture[void] =
  let opNameLit = opName
  let shouldFail = db.consumeFailure(opNameLit)
  let latency = db.pickLatency()
  let fut = newFuture[void]("fake_db." & opNameLit)
  let slept = sleepFor(latency)
  slept.onCompleteVoid(
    onSuccess = proc() =
      if shouldFail:
        fut.fail(newException(CatchableError,
          "fake_db: scripted failure for " & opNameLit))
      else:
        body
        fut.complete(),
    onError = proc(msg: string) =
      fut.fail(newException(CatchableError, msg)))
  fut

# ---------------------------------------------------------------------------
# Task operations
# ---------------------------------------------------------------------------

proc loadTasks*(db: FakeDb): PlatformFuture[seq[Task]] =
  ## Async read of every task in the store. Returns a deep value-copy so
  ## consumers can't mutate the store by aliasing.
  scheduleResult[seq[Task]](db, "loadTasks"):
    var snapshot: seq[Task] = @[]
    for t in db.tasks:
      snapshot.add t
    snapshot

proc saveTask*(db: FakeDb; t: Task): PlatformFuture[void] =
  ## Async upsert: if `t.id == 0` (or unknown), append with a fresh id;
  ## otherwise replace the existing entry. The store is mutated only on
  ## success.
  scheduleVoidResult(db, "saveTask"):
    var stored = t
    if stored.id == 0:
      stored.id = db.nextTaskId
      inc db.nextTaskId
    else:
      if stored.id >= db.nextTaskId:
        db.nextTaskId = stored.id + 1
    var replaced = false
    for i in 0 ..< db.tasks.len:
      if db.tasks[i].id == stored.id:
        db.tasks[i] = stored
        replaced = true
        break
    if not replaced:
      db.tasks.add stored

proc deleteTask*(db: FakeDb; id: int): PlatformFuture[void] =
  ## Async delete by id. No-op when the id is unknown — matches the VM's
  ## defensive `removeTask` contract.
  scheduleVoidResult(db, "deleteTask"):
    var idx = -1
    for i in 0 ..< db.tasks.len:
      if db.tasks[i].id == id:
        idx = i
        break
    if idx >= 0:
      db.tasks.delete(idx)

proc clearCompletedTasks*(db: FakeDb): PlatformFuture[void] =
  ## Async batch: drop every completed task.
  scheduleVoidResult(db, "clearCompletedTasks"):
    var kept: seq[Task] = @[]
    for t in db.tasks:
      if not t.completed: kept.add t
    db.tasks = kept

proc allocTaskId*(db: FakeDb): int =
  ## Synchronous helper for tests that need to seed task rows without
  ## driving through saveTask. The id is monotonic and stable.
  result = db.nextTaskId
  inc db.nextTaskId

# ---------------------------------------------------------------------------
# Settings operations
# ---------------------------------------------------------------------------

proc seedSettings*(db: FakeDb; catalog: SettingsCatalog) =
  ## Synchronous helper: seed the per-item value tables from a catalog's
  ## defaults. Used by `newFakeDb` callers and by tests that want a
  ## starting state without driving through saveSetting per item.
  db.settings = catalog
  db.settingsToggles.clear()
  db.settingsNumbers.clear()
  db.settingsChoices.clear()
  for g in catalog.groups:
    for it in g.items:
      case it.kind
      of sikToggle:
        db.settingsToggles[it.id] = it.toggleDefault
      of sikNumber:
        db.settingsNumbers[it.id] = it.numberDefault
      of sikChoice:
        db.settingsChoices[it.id] = it.choiceDefault

type
  SettingsSnapshot* = object
    ## Plain-value snapshot of all settings values. Used as the result
    ## type for `loadSettings`.
    catalog*: SettingsCatalog
    toggles*: Table[string, bool]
    numbers*: Table[string, int]
    choices*: Table[string, string]

proc loadSettings*(db: FakeDb): PlatformFuture[SettingsSnapshot] =
  ## Async read of the full settings catalog + per-item values.
  scheduleResult[SettingsSnapshot](db, "loadSettings"):
    SettingsSnapshot(
      catalog: db.settings,
      toggles: db.settingsToggles,
      numbers: db.settingsNumbers,
      choices: db.settingsChoices)

proc saveSetting*(db: FakeDb; id: string; value: JsonNode):
                PlatformFuture[void] =
  ## Async write for a single settings item. `value` must be a JBool /
  ## JInt / JString matching the item's kind; type mismatches fail with
  ## a synthetic error (the VM normally guarantees the right shape).
  scheduleVoidResult(db, "saveSetting"):
    if value.isNil:
      raise newException(CatchableError,
        "fake_db.saveSetting: nil value for " & id)
    case value.kind
    of JBool: db.settingsToggles[id] = value.getBool
    of JInt:  db.settingsNumbers[id] = value.getInt
    of JString: db.settingsChoices[id] = value.getStr
    else:
      raise newException(CatchableError,
        "fake_db.saveSetting: unsupported value kind for " & id)

# ---------------------------------------------------------------------------
# Convenience: are we using the fake event loop right now?
# ---------------------------------------------------------------------------

proc usingFakeContext*(): bool =
  ## True iff a `FakeAsyncContext` is installed on the current thread.
  ## Useful for the composition roots that need to decide whether to
  ## drain immediately (test path) or rely on the real event loop
  ## (production path).
  currentFakeContext() != nil

# Make `Option[string]` available to consumers of this module so VMs
# can declare `lastError*: Signal[Option[string]]` without an extra
# import.
export options
