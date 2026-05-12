## task_app/core/vm.nim — Layer-3 ViewModel (pure logic).
##
## EX-M17: the VM is restructured around `Resource[seq[Task]]` so the
## task list is fetched asynchronously from a `FakeDb` (see
## `services/fake_db.nim`). Mutation actions (`addTask`, `toggleTask`,
## `removeTask`, `clearCompleted`) are now async — they enqueue the
## write through the db and refresh the resource on completion. Two
## new signals surface the async state:
##
##   * `pendingOps: Signal[int]` — count of in-flight writes; the UI
##     uses this to drive a "saving…" indicator while it's > 0.
##   * `lastError: Signal[Option[string]]` — most-recent error message
##     for a write op, surfaced UI-friendly. None on success.
##
## Reactive surface (the signals leaves subscribe to):
##
##   * `vm.tasks: Resource[seq[Task]]` — the task list. Read via
##     `vm.tasks.data.val` (or the unchanged `vm.tasks.val` thanks to
##     `Resource[T]`'s exported `val` accessor). `vm.tasks.state.val`
##     surfaces the rsPending / rsReady / rsRefreshing / rsErrored
##     state. `vm.tasks.loading` is a derived bool.
##   * `vm.filter: Signal[FilterMode]` — unchanged from the sync VM.
##   * `vm.inputText: Signal[string]` — unchanged.
##
## Tests drive the async path through `FakeAsyncContext` (from
## nim_everywhere/fake_time). The same VM under a real event loop
## experiences the configured 30-50 ms per-op latency.
##
## EX-M1 migration history preserved.

import std/options

import isonim/core/signals
import isonim/core/resource
import nim_everywhere/async_compat

import task_app/core/types as task_types
import services/fake_db

export task_types
export resource, options
export fake_db.FakeDb, fake_db.newFakeDb, fake_db.scriptFailure

type
  FilterMode* {.pure.} = enum
    fmAll = "All"
    fmActive = "Active"
    fmCompleted = "Completed"

  TaskAppVM* = ref object
    ## The shared async ViewModel for the task app. Three reactive
    ## signals + one async resource:
    ##
    ##   * `tasks`       — the full task list, fetched async from `db`.
    ##   * `filter`      — which subset to render (sync local state).
    ##   * `inputText`   — current draft text (sync local state).
    ##   * `pendingOps`  — count of in-flight writes.
    ##   * `lastError`   — most-recent write error, UI-friendly.
    ##
    ## Every action proc below routes through `db`; on success the
    ## resource is refreshed (which triggers `loadTasks`); on failure
    ## `lastError` is populated.
    db*: FakeDb
    tasks*: Resource[seq[Task]]
    filter*: Signal[FilterMode]
    inputText*: Signal[string]
    pendingOps*: Signal[int]
    lastError*: Signal[Option[string]]

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newTaskAppVM*(db: FakeDb): TaskAppVM =
  ## Construct a VM bound to `db`. The initial `tasks` load fires
  ## immediately (`Resource[T]` async overload semantics) — under a
  ## `FakeAsyncContext` it sits in `rsPending` until the test advances
  ## the clock; under a real event loop it completes after the
  ## configured latency.
  result = TaskAppVM(
    db: db,
    filter: createSignal[FilterMode](fmAll),
    inputText: createSignal[string](""),
    pendingOps: createSignal[int](0),
    lastError: createSignal[Option[string]](none(string)))
  let dbRef = db
  result.tasks = createResource[seq[Task]](
    proc(info: ResourceFetcherInfo[seq[Task]]): PlatformFuture[seq[Task]] =
      dbRef.loadTasks(),
    initialValue = @[])

proc newTaskAppVM*(): TaskAppVM =
  ## Convenience overload for tests / callers that don't supply a db.
  ## Builds a zero-latency `FakeDb` with seed=1 — every op completes on
  ## the next drain without requiring a `FakeAsyncContext`. Useful for
  ## the existing sync-shape parity tests that pre-date EX-M17.
  ##
  ## NOTE: even with zero latency, `sleepFor(0)` still routes through
  ## the event loop. Callers should either install a `FakeAsyncContext`
  ## or call `drainPlatformCallbacks()` to make ops visible.
  newTaskAppVM(newFakeDb(seed = 1, latencyMin = 0, latencyMax = 0))

# ----------------------------------------------------------------------------
# Internal: bump pendingOps and clear lastError around a write
# ----------------------------------------------------------------------------

proc beginOp(vm: TaskAppVM) =
  vm.pendingOps.val = vm.pendingOps.val + 1

proc endOpOk(vm: TaskAppVM) =
  vm.pendingOps.val = vm.pendingOps.val - 1
  vm.lastError.val = none(string)

proc endOpFail(vm: TaskAppVM; msg: string) =
  vm.pendingOps.val = vm.pendingOps.val - 1
  vm.lastError.val = some(msg)

# ----------------------------------------------------------------------------
# Actions (mutate the VM through these — never poke the signals directly
# from outside the VM module).
# ----------------------------------------------------------------------------

proc addTask*(vm: TaskAppVM; name: string) =
  ## Append a new task with the given name. Empty / whitespace-only
  ## names are ignored. After a successful save, `inputText` is
  ## cleared and `tasks` is refreshed. On failure, `lastError` is set
  ## and the state is unchanged.
  var trimmed = name
  while trimmed.len > 0 and (trimmed[0] == ' ' or trimmed[0] == '\t'):
    trimmed = trimmed[1 ..< trimmed.len]
  while trimmed.len > 0 and (trimmed[^1] == ' ' or trimmed[^1] == '\t'):
    trimmed = trimmed[0 ..< trimmed.len - 1]
  if trimmed.len == 0: return
  let newTask = Task(id: 0, name: trimmed, completed: false)
  vm.beginOp()
  let vmRef = vm
  vm.db.saveTask(newTask).onCompleteVoid(
    onSuccess = proc() =
      vmRef.inputText.val = ""
      vmRef.tasks.refresh()
      vmRef.endOpOk(),
    onError = proc(msg: string) =
      vmRef.endOpFail(msg))

proc toggleTask*(vm: TaskAppVM; id: int) =
  ## Flip the `completed` flag on the task with the given id. The
  ## current list is read from the resource's data; the modified task
  ## is then persisted via the db. No-op when the id is unknown.
  let current = vm.tasks.data.val
  var found: Task
  var hit = false
  for t in current:
    if t.id == id:
      found = t
      hit = true
      break
  if not hit: return
  var toSave = found
  toSave.completed = not toSave.completed
  vm.beginOp()
  let vmRef = vm
  vm.db.saveTask(toSave).onCompleteVoid(
    onSuccess = proc() =
      vmRef.tasks.refresh()
      vmRef.endOpOk(),
    onError = proc(msg: string) =
      vmRef.endOpFail(msg))

proc removeTask*(vm: TaskAppVM; id: int) =
  ## Drop the task with the given id. No-op when unknown — the db
  ## itself handles that case and resolves with success.
  vm.beginOp()
  let vmRef = vm
  vm.db.deleteTask(id).onCompleteVoid(
    onSuccess = proc() =
      vmRef.tasks.refresh()
      vmRef.endOpOk(),
    onError = proc(msg: string) =
      vmRef.endOpFail(msg))

proc clearCompleted*(vm: TaskAppVM) =
  ## Drop every completed task in one batch.
  vm.beginOp()
  let vmRef = vm
  vm.db.clearCompletedTasks().onCompleteVoid(
    onSuccess = proc() =
      vmRef.tasks.refresh()
      vmRef.endOpOk(),
    onError = proc(msg: string) =
      vmRef.endOpFail(msg))

proc setFilter*(vm: TaskAppVM; m: FilterMode) =
  ## Local-only state — no async involved.
  vm.filter.val = m

proc setInputText*(vm: TaskAppVM; text: string) =
  ## Local-only state.
  vm.inputText.val = text

proc refreshTasks*(vm: TaskAppVM) =
  ## Manually trigger a re-fetch of the task list. Useful after a
  ## scripted-failure test arms the next op to fail.
  vm.tasks.refresh()

# ----------------------------------------------------------------------------
# Derived state (read-only views over the resource + filter signal).
# ----------------------------------------------------------------------------

proc visibleTasks*(vm: TaskAppVM): seq[Task] =
  ## The subset of tasks matching the current filter. Reads
  ## `tasks.data` and `filter` so callers inside a `createRenderEffect`
  ## re-run when either changes.
  let f = vm.filter.val
  let ts = vm.tasks.data.val
  case f
  of fmAll: ts
  of fmActive:
    var keep: seq[Task] = @[]
    for t in ts:
      if not t.completed: keep.add t
    keep
  of fmCompleted:
    var keep: seq[Task] = @[]
    for t in ts:
      if t.completed: keep.add t
    keep

proc activeCount*(vm: TaskAppVM): int =
  var n = 0
  for t in vm.tasks.data.val:
    if not t.completed: inc n
  n

proc completedCount*(vm: TaskAppVM): int =
  var n = 0
  for t in vm.tasks.data.val:
    if t.completed: inc n
  n

proc totalCount*(vm: TaskAppVM): int =
  vm.tasks.data.val.len

proc loading*(vm: TaskAppVM): bool =
  ## True while the resource is fetching (initial load or refresh).
  vm.tasks.loading

# ----------------------------------------------------------------------------
# Snapshot — used by tests to assert the VM reached an expected state
# without depending on the rendered tree.
# ----------------------------------------------------------------------------

type
  VMSnapshot* = object
    ## Plain-value snapshot of the VM for golden comparisons. Captures
    ## only the *external* state (task list, filter, input text) — the
    ## async bookkeeping signals (`pendingOps`, `lastError`) are
    ## intentionally excluded so parity tests stay byte-identical when
    ## an op's failure window varies across renderers.
    tasks*: seq[Task]
    filter*: FilterMode
    inputText*: string

proc snapshot*(vm: TaskAppVM): VMSnapshot =
  VMSnapshot(
    tasks: vm.tasks.data.val,
    filter: vm.filter.val,
    inputText: vm.inputText.val)
