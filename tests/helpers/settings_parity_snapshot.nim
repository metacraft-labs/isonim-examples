## helpers/settings_parity_snapshot.nim — shared snapshot helper for the
## EX-M13 cross-renderer SettingsVM-parity test.
##
## Mirrors `helpers/parity_snapshot.nim` (the EX-M7 task_app helper) for
## the settings_app demo. The canonical Layer-3 ViewModel
## (`settings_app/core/vm.nim`) already exposes a
## `snapshot(vm: SettingsVM): SettingsVMSnapshot` proc returning a plain-
## value object with sorted `toggles` / `numbers` / `choices` seqs +
## `activeGroupId`. That value supports structural `==` and is the
## *real* source of truth for byte-identical parity assertions.
##
## This helper adds a JSON projection on top of `SettingsVMSnapshot` so
## test failures surface as readable diffs (the JSON `pretty` output is
## much friendlier than the auto-generated `$SettingsVMSnapshot` dump
## when a single field diverges between renderers).
##
## Both `settingsVmSnapshot` and `settingsVmSnapshotJson` are exported.
## EX-M13 prefers the object form for the actual `==` check (zero
## allocation, deterministic field order via the snapshot proc's sorted
## seqs); the JSON form is used to produce the failure messages.

import std/json

import settings_app/core/vm
export vm

proc settingsVmSnapshot*(vm: SettingsVM): SettingsVMSnapshot =
  ## Renderer-agnostic snapshot of the live VM. Identical across every
  ## renderer for the same scripted scenario — that invariant is what
  ## EX-M13 asserts.
  vm.snapshot

proc settingsVmSnapshotJson*(vm: SettingsVM): JsonNode =
  ## JSON projection of `settingsVmSnapshot`. Stable field order
  ## (activeGroupId, toggles, numbers, choices) so cross-renderer diffs
  ## read cleanly. Each (key, value) pair is encoded as a two-element
  ## JSON array so the snapshot's sorted-seq layout (not the underlying
  ## Table) is what surfaces in failure messages.
  let snap = vm.snapshot
  let togglesNode = newJArray()
  for (k, v) in snap.toggles:
    let pair = newJArray()
    pair.add newJString(k)
    pair.add newJBool(v)
    togglesNode.add pair
  let numbersNode = newJArray()
  for (k, v) in snap.numbers:
    let pair = newJArray()
    pair.add newJString(k)
    pair.add newJInt(v)
    numbersNode.add pair
  let choicesNode = newJArray()
  for (k, v) in snap.choices:
    let pair = newJArray()
    pair.add newJString(k)
    pair.add newJString(v)
    choicesNode.add pair
  let root = newJObject()
  root["activeGroupId"] = newJString(snap.activeGroupId)
  root["toggles"] = togglesNode
  root["numbers"] = numbersNode
  root["choices"] = choicesNode
  root
