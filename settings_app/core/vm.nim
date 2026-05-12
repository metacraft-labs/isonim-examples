## settings_app/core/vm.nim — Layer-3.5 ViewModel (pure logic).
##
## EX-M17: catalog values are sourced from a `FakeDb` and surfaced
## through a `Resource[SettingsSnapshot]`. Mutation actions (`setToggle`,
## `setNumber`, `setChoice`) are now async — they enqueue the write
## through the db and refresh the resource on completion.
##
## Reactive surface (the components / leaves subscribe to):
##
##   * `vm.catalogResource: Resource[SettingsSnapshot]` — the loaded
##     catalog + per-item values, async-fetched.
##   * `vm.activeGroupId: Signal[string]` — local UI state.
##   * `vm.pendingOps: Signal[int]` — in-flight writes.
##   * `vm.lastError: Signal[Option[string]]` — UI-friendly error.
##
## Per-item value accessors (`toggleValue`, `numberValue`,
## `choiceValue`) remain — they now read from the loaded snapshot's
## tables. The leaves subscribe to these accessors directly via
## `createRenderEffect`, so a programmatic mutation (post-load by the
## db) propagates to the rendered DOM without a re-mount.
##
## Validation policy (unchanged):
##   * Number writes are *clamped* before being sent to the db.
##   * Choice writes are *rejected* when the value is not in
##     `choiceOptions` — the action returns `false` and no db op is
##     enqueued.
##   * Unknown item ids return `false` with no signal mutation.

import std/algorithm
import std/json
import std/options
import std/tables

import isonim/core/signals
import isonim/core/resource
import nim_everywhere/async_compat

import ./types
import services/fake_db

export types, resource, options
export fake_db.FakeDb, fake_db.newFakeDb, fake_db.scriptFailure, fake_db.seedSettings

type
  SettingsVM* = ref object
    ## Reactive ViewModel for the settings demo. The `catalog`
    ## reference is shared across the lifetime of the VM and is
    ## treated as immutable. Per-item values are fetched async from
    ## `db` and surface through three derived signals so the leaves
    ## can subscribe per-item rather than rebuilding the whole pane.
    db*: FakeDb
    catalog*: SettingsCatalog
    catalogResource*: Resource[SettingsSnapshot]
    activeGroupId*: Signal[string]
    pendingOps*: Signal[int]
    lastError*: Signal[Option[string]]

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newSettingsVM*(db: FakeDb): SettingsVM =
  ## Construct a VM bound to `db`. The initial settings load fires
  ## immediately; under `FakeAsyncContext` the VM sits in rsPending
  ## until the test advances the clock.
  if db.settings == nil:
    raise newException(CatchableError,
      "newSettingsVM: FakeDb has no settings catalog — call seedSettings(db, catalog) first")
  result = SettingsVM(
    db: db,
    catalog: db.settings,
    activeGroupId: createSignal[string](db.settings.firstGroupId),
    pendingOps: createSignal[int](0),
    lastError: createSignal[Option[string]](none(string)))
  let dbRef = db
  result.catalogResource = createResource[SettingsSnapshot](
    proc(info: ResourceFetcherInfo[SettingsSnapshot]):
        PlatformFuture[SettingsSnapshot] =
      dbRef.loadSettings(),
    initialValue = SettingsSnapshot(
      catalog: db.settings,
      toggles: db.settingsToggles,
      numbers: db.settingsNumbers,
      choices: db.settingsChoices))

proc newSettingsVM*(catalog: SettingsCatalog): SettingsVM =
  ## Convenience overload: build a zero-latency db, seed it with the
  ## catalog defaults, and construct the VM. Mirrors the EX-M16-era
  ## constructor for tests that don't care about the async surface.
  let db = newFakeDb(seed = 1, latencyMin = 0, latencyMax = 0)
  db.seedSettings(catalog)
  newSettingsVM(db)

# ----------------------------------------------------------------------------
# Async write helpers
# ----------------------------------------------------------------------------

proc beginOp(vm: SettingsVM) =
  vm.pendingOps.val = vm.pendingOps.val + 1

proc endOpOk(vm: SettingsVM) =
  vm.pendingOps.val = vm.pendingOps.val - 1
  vm.lastError.val = none(string)

proc endOpFail(vm: SettingsVM; msg: string) =
  vm.pendingOps.val = vm.pendingOps.val - 1
  vm.lastError.val = some(msg)

# ----------------------------------------------------------------------------
# Internal helpers — find the catalog item for a given id and confirm
# it is of the expected kind.
# ----------------------------------------------------------------------------

proc lookupItem(vm: SettingsVM; itemId: string;
                expected: SettingsItemKind;
                outItem: var SettingsItem): bool =
  for g in vm.catalog.groups:
    for it in g.items:
      if it.id == itemId:
        if it.kind != expected:
          return false
        outItem = it
        return true
  false

# ----------------------------------------------------------------------------
# Actions
# ----------------------------------------------------------------------------

proc setActiveGroup*(vm: SettingsVM; groupId: string): bool {.discardable.} =
  ## Switch the focused group. Local-only state — no db involvement.
  if not vm.catalog.hasGroup(groupId):
    return false
  vm.activeGroupId.val = groupId
  true

proc setToggle*(vm: SettingsVM; itemId: string; value: bool): bool
              {.discardable.} =
  ## Write a toggle item asynchronously. Returns `false` (and does not
  ## enqueue) if the id is unknown or refers to a non-toggle item.
  ## Otherwise enqueues a `saveSetting` op, refreshes the snapshot on
  ## success, and updates `lastError` on failure.
  var item: SettingsItem
  if not vm.lookupItem(itemId, sikToggle, item):
    return false
  vm.beginOp()
  let vmRef = vm
  vm.db.saveSetting(itemId, %value).onCompleteVoid(
    onSuccess = proc() =
      vmRef.catalogResource.refresh()
      vmRef.endOpOk(),
    onError = proc(msg: string) =
      vmRef.endOpFail(msg))
  true

proc setNumber*(vm: SettingsVM; itemId: string; value: int): bool
              {.discardable.} =
  ## Write a number item. The value is clamped to the item's
  ## `[numberMin, numberMax]` range before being sent to the db.
  var item: SettingsItem
  if not vm.lookupItem(itemId, sikNumber, item):
    return false
  var clamped = value
  if clamped < item.numberMin: clamped = item.numberMin
  if clamped > item.numberMax: clamped = item.numberMax
  vm.beginOp()
  let vmRef = vm
  vm.db.saveSetting(itemId, %clamped).onCompleteVoid(
    onSuccess = proc() =
      vmRef.catalogResource.refresh()
      vmRef.endOpOk(),
    onError = proc(msg: string) =
      vmRef.endOpFail(msg))
  true

proc setChoice*(vm: SettingsVM; itemId: string; value: string): bool
              {.discardable.} =
  ## Write a choice item. Rejects values outside `choiceOptions` with
  ## `false` (no db op enqueued).
  var item: SettingsItem
  if not vm.lookupItem(itemId, sikChoice, item):
    return false
  var ok = false
  for opt in item.choiceOptions:
    if opt == value:
      ok = true
      break
  if not ok:
    return false
  vm.beginOp()
  let vmRef = vm
  vm.db.saveSetting(itemId, %value).onCompleteVoid(
    onSuccess = proc() =
      vmRef.catalogResource.refresh()
      vmRef.endOpOk(),
    onError = proc(msg: string) =
      vmRef.endOpFail(msg))
  true

proc resetDefaults*(vm: SettingsVM) =
  ## Restore every item's value to the catalog default. Implemented as
  ## a sequence of `setToggle` / `setNumber` / `setChoice` calls so the
  ## standard async path drives every write. Tests advancing the fake
  ## clock should advance enough simulated time to flush every op.
  for g in vm.catalog.groups:
    for it in g.items:
      case it.kind
      of sikToggle:
        discard vm.setToggle(it.id, it.toggleDefault)
      of sikNumber:
        discard vm.setNumber(it.id, it.numberDefault)
      of sikChoice:
        discard vm.setChoice(it.id, it.choiceDefault)

proc refreshSnapshot*(vm: SettingsVM) =
  ## Manually trigger a re-fetch of the settings snapshot.
  vm.catalogResource.refresh()

# ----------------------------------------------------------------------------
# Derived state (read-only views over the resource + activeGroup signal).
# ----------------------------------------------------------------------------

proc currentGroup*(vm: SettingsVM): SettingsGroup =
  let id = vm.activeGroupId.val
  vm.catalog.findGroup(id)

proc toggleValue*(vm: SettingsVM; itemId: string): bool =
  ## Read a toggle item's current value. Reads `vm.catalogResource.data` so
  ## callers inside a `createRenderEffect` re-run when the snapshot
  ## refreshes after a programmatic mutation.
  let snap = vm.catalogResource.data.val
  snap.toggles.getOrDefault(itemId)

proc numberValue*(vm: SettingsVM; itemId: string): int =
  let snap = vm.catalogResource.data.val
  snap.numbers.getOrDefault(itemId)

proc choiceValue*(vm: SettingsVM; itemId: string): string =
  let snap = vm.catalogResource.data.val
  snap.choices.getOrDefault(itemId)

proc itemValue*(vm: SettingsVM; itemId: string): JsonNode =
  ## Kind-erased accessor — useful for tests / snapshot helpers.
  let item = vm.catalog.findItem(itemId)
  case item.kind
  of sikToggle: newJBool(vm.toggleValue(itemId))
  of sikNumber: newJInt(vm.numberValue(itemId))
  of sikChoice: newJString(vm.choiceValue(itemId))

proc loading*(vm: SettingsVM): bool =
  vm.catalogResource.loading

# Legacy compatibility shims: a few tests still expect the old
# `vm.toggleValues.val[itemId]` shape. Provide read-only accessors
# that return whole tables, keyed off the loaded snapshot.

proc toggleValues*(vm: SettingsVM): Table[string, bool] =
  vm.catalogResource.data.val.toggles

proc numberValues*(vm: SettingsVM): Table[string, int] =
  vm.catalogResource.data.val.numbers

proc choiceValues*(vm: SettingsVM): Table[string, string] =
  vm.catalogResource.data.val.choices

# ----------------------------------------------------------------------------
# Snapshot — used by tests to assert the VM reached an expected
# state without depending on the rendered tree.
# ----------------------------------------------------------------------------

type
  SettingsVMSnapshot* = object
    activeGroupId*: string
    toggles*: seq[(string, bool)]
    numbers*: seq[(string, int)]
    choices*: seq[(string, string)]

proc sortedToggleEntries(t: Table[string, bool]): seq[(string, bool)] =
  var keys: seq[string] = @[]
  for k in t.keys: keys.add k
  keys.sort(system.cmp)
  for k in keys: result.add (k, t[k])

proc sortedNumberEntries(t: Table[string, int]): seq[(string, int)] =
  var keys: seq[string] = @[]
  for k in t.keys: keys.add k
  keys.sort(system.cmp)
  for k in keys: result.add (k, t[k])

proc sortedChoiceEntries(t: Table[string, string]): seq[(string, string)] =
  var keys: seq[string] = @[]
  for k in t.keys: keys.add k
  keys.sort(system.cmp)
  for k in keys: result.add (k, t[k])

proc snapshot*(vm: SettingsVM): SettingsVMSnapshot =
  let snap = vm.catalogResource.data.val
  SettingsVMSnapshot(
    activeGroupId: vm.activeGroupId.val,
    toggles: sortedToggleEntries(snap.toggles),
    numbers: sortedNumberEntries(snap.numbers),
    choices: sortedChoiceEntries(snap.choices))
