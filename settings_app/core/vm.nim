## settings_app/core/vm.nim — Layer-3.5 ViewModel (pure logic).
##
## Single source of truth for the settings demo. This module is the
## byte-identical core of every renderer target — the platform shells
## (Layer 3) read/write through this VM, the shared components (Layer
## 2) wire reactive observers to its signals, and the Layer-1 leaves
## drop into the wiring without any platform-specific business logic.
##
## The VM is parameterised over a `SettingsCatalog` (see `types.nim`)
## so the same VM can host arbitrary settings UIs; the demo catalog
## that EX-M9+ renders ships in `demo_catalog.nim`.
##
## Reactive surface:
##   * `activeGroupId`  — id of the currently-focused group (drives
##                        the right-hand pane / expanded section).
##   * `toggleValues`   — itemId -> bool, for every `sikToggle` item.
##   * `numberValues`   — itemId -> int, for every `sikNumber` item.
##   * `choiceValues`   — itemId -> string, for every `sikChoice` item.
##
## All four are real `Signal[T]` instances; observers `createRenderEffect`
## against them exactly as task_app's components do against `vm.tasks`.
##
## Action surface (every mutation goes through one of these — never
## poke the signals directly from outside the VM module):
##   * `setActiveGroup(vm, groupId)`         — switch focused group.
##   * `setToggle(vm, itemId, value)`        — write a toggle item.
##   * `setNumber(vm, itemId, value)`        — clamps to [min, max].
##   * `setChoice(vm, itemId, value)`        — rejects values not in
##                                             `choiceOptions`.
##
## Validation policy:
##   * Number writes are *clamped* (min/max). The VM commits a
##     within-range value, never rejects.
##   * Choice writes are *rejected* when the value is not in the
##     declared options. The signal does not change; the action
##     returns `false`. Toggle/number actions return `bool` too so
##     consumers have a uniform success channel.
##   * Unknown item ids and unknown group ids cause the action to
##     return `false` with no signal mutation (defensive — a stale
##     write from a removed row should not crash).
##
## EX-M8 milestone reference:
## `codetracer-specs/Front-Ends/IsoNim/isonim-render-stream.status.org`.

import std/algorithm
import std/json
import std/tables

import isonim/core/signals
import ./types
export types

type
  SettingsVM* = ref object
    ## Reactive ViewModel for the settings demo. The `catalog`
    ## reference is shared across the lifetime of the VM and is
    ## treated as immutable (the VM never mutates it; calling code
    ## should treat it as read-only after construction). The four
    ## signals carry the live state.
    catalog*: SettingsCatalog
    activeGroupId*: Signal[string]
    toggleValues*: Signal[Table[string, bool]]
    numberValues*: Signal[Table[string, int]]
    choiceValues*: Signal[Table[string, string]]

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc seedDefaults(catalog: SettingsCatalog;
                  toggles: var Table[string, bool];
                  numbers: var Table[string, int];
                  choices: var Table[string, string]) =
  ## Populate the three value tables from the catalog's per-item
  ## `*Default` fields. Pulled out so `resetDefaults` can reuse it.
  for g in catalog.groups:
    for it in g.items:
      case it.kind
      of sikToggle:
        toggles[it.id] = it.toggleDefault
      of sikNumber:
        numbers[it.id] = it.numberDefault
      of sikChoice:
        choices[it.id] = it.choiceDefault

proc newSettingsVM*(catalog: SettingsCatalog): SettingsVM =
  ## Construct a fresh VM bound to the given catalog. Every item's
  ## value signal is seeded from its `*Default`. `activeGroupId` is
  ## seeded to the first group's id (or empty string if the catalog
  ## has no groups).
  var toggles: Table[string, bool]
  var numbers: Table[string, int]
  var choices: Table[string, string]
  seedDefaults(catalog, toggles, numbers, choices)
  SettingsVM(
    catalog: catalog,
    activeGroupId: createSignal[string](catalog.firstGroupId),
    toggleValues: createSignal[Table[string, bool]](toggles),
    numberValues: createSignal[Table[string, int]](numbers),
    choiceValues: createSignal[Table[string, string]](choices))

# ----------------------------------------------------------------------------
# Internal helpers — find the catalog item for a given id and confirm
# it is of the expected kind. Returns a tuple instead of raising so
# the action procs can return `false` cleanly.
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
  ## Switch the focused group. Returns `false` (and leaves the signal
  ## unchanged) if `groupId` is not in the catalog. Returns `true`
  ## otherwise — even if the new value equals the old one.
  if not vm.catalog.hasGroup(groupId):
    return false
  vm.activeGroupId.val = groupId
  true

proc setToggle*(vm: SettingsVM; itemId: string; value: bool): bool
              {.discardable.} =
  ## Write a toggle item. Returns `false` if the id is unknown or
  ## refers to a non-toggle item; `true` on success. The full table
  ## is reassigned so the signal fires (Nim `Table` is a value type).
  var item: SettingsItem
  if not vm.lookupItem(itemId, sikToggle, item):
    return false
  var t = vm.toggleValues.val
  t[itemId] = value
  vm.toggleValues.val = t
  true

proc setNumber*(vm: SettingsVM; itemId: string; value: int): bool
              {.discardable.} =
  ## Write a number item. The value is clamped to the item's
  ## `[numberMin, numberMax]` range before being stored. Returns
  ## `false` if the id is unknown or refers to a non-number item.
  var item: SettingsItem
  if not vm.lookupItem(itemId, sikNumber, item):
    return false
  var clamped = value
  if clamped < item.numberMin: clamped = item.numberMin
  if clamped > item.numberMax: clamped = item.numberMax
  var t = vm.numberValues.val
  t[itemId] = clamped
  vm.numberValues.val = t
  true

proc setChoice*(vm: SettingsVM; itemId: string; value: string): bool
              {.discardable.} =
  ## Write a choice item. Returns `false` if the id is unknown,
  ## refers to a non-choice item, or `value` is not in the item's
  ## `choiceOptions`. The signal is left unchanged on rejection.
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
  var t = vm.choiceValues.val
  t[itemId] = value
  vm.choiceValues.val = t
  true

proc resetDefaults*(vm: SettingsVM) =
  ## Restore every item's value to the catalog default. Used by the
  ## "Reset" leaf in higher-level shells (and by tests that want to
  ## start from a clean state without rebuilding the VM).
  var toggles: Table[string, bool]
  var numbers: Table[string, int]
  var choices: Table[string, string]
  seedDefaults(vm.catalog, toggles, numbers, choices)
  vm.toggleValues.val = toggles
  vm.numberValues.val = numbers
  vm.choiceValues.val = choices

# ----------------------------------------------------------------------------
# Derived state (read-only views over signals).
# ----------------------------------------------------------------------------

proc currentGroup*(vm: SettingsVM): SettingsGroup =
  ## The group currently focused by the shell. Reads `activeGroupId`
  ## so callers inside a `createRenderEffect` re-run when the focused
  ## group changes. Raises `KeyError` if the active id is unknown
  ## (which can only happen if the catalog was mutated behind the
  ## VM's back — the VM itself never lets `activeGroupId` drift).
  let id = vm.activeGroupId.val
  vm.catalog.findGroup(id)

proc toggleValue*(vm: SettingsVM; itemId: string): bool =
  ## Read a toggle item's current value. Reads `toggleValues` so
  ## callers re-run when the item changes. Raises `KeyError` if the
  ## id is unknown.
  vm.toggleValues.val[itemId]

proc numberValue*(vm: SettingsVM; itemId: string): int =
  ## Read a number item's current value.
  vm.numberValues.val[itemId]

proc choiceValue*(vm: SettingsVM; itemId: string): string =
  ## Read a choice item's current value.
  vm.choiceValues.val[itemId]

proc itemValue*(vm: SettingsVM; itemId: string): JsonNode =
  ## Kind-erased accessor returning a JSON node. Useful for tests and
  ## the `vmSnapshot` parity helper that needs to compare values
  ## without static knowledge of the item kind. Raises `KeyError` if
  ## the id is unknown.
  let item = vm.catalog.findItem(itemId)
  case item.kind
  of sikToggle: newJBool(vm.toggleValues.val[itemId])
  of sikNumber: newJInt(vm.numberValues.val[itemId])
  of sikChoice: newJString(vm.choiceValues.val[itemId])

# ----------------------------------------------------------------------------
# Snapshot — used by tests to assert the VM reached an expected
# state without depending on the rendered tree, and by the parity
# snapshot helper to feed the cross-renderer parity test.
# ----------------------------------------------------------------------------

type
  SettingsVMSnapshot* = object
    ## Plain-value snapshot of the VM for golden comparisons.
    ## `tables` is omitted in favour of three sorted seqs so the
    ## structural `==` is deterministic across Nim's hash-table
    ## insertion orders.
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
  SettingsVMSnapshot(
    activeGroupId: vm.activeGroupId.val,
    toggles: sortedToggleEntries(vm.toggleValues.val),
    numbers: sortedNumberEntries(vm.numberValues.val),
    choices: sortedChoiceEntries(vm.choiceValues.val))
