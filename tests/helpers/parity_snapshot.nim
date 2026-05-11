## helpers/parity_snapshot.nim — shared snapshot helper for the
## EX-M7 cross-renderer VM-parity test (and any future test that
## needs a renderer-agnostic VM digest).
##
## The canonical Layer-3 ViewModel (`task_app/core/vm.nim`) already
## exposes a `snapshot(vm: TaskAppVM): VMSnapshot` proc returning a
## plain-value object with `tasks`, `filter`, `inputText`. That value
## supports structural `==` and is the *real* source of truth for
## byte-identical parity assertions.
##
## This helper adds a JSON projection on top of `VMSnapshot` so test
## failures surface as readable diffs (the JSON `pretty` output is
## much friendlier than the auto-generated `$VMSnapshot` tuple dump
## when a single field diverges between renderers).
##
## Both `vmSnapshot` and `vmSnapshotJson` are exported. EX-M7 prefers
## the object form for the actual `==` check (zero allocation, no
## ordering ambiguity); the JSON form is used to produce the failure
## messages.

import std/json

import task_app/core/vm
export vm

proc vmSnapshot*(vm: TaskAppVM): VMSnapshot =
  ## Renderer-agnostic snapshot of the live VM. Identical across every
  ## renderer for the same scripted scenario — that invariant is what
  ## EX-M7 asserts.
  vm.snapshot

proc vmSnapshotJson*(vm: TaskAppVM): JsonNode =
  ## JSON projection of `vmSnapshot`. Stable field order
  ## (tasks, filter, inputText) so cross-renderer diffs read cleanly.
  ## The task records are encoded as objects with `id`, `name`,
  ## `completed`. `filter` is encoded as its enum string name.
  let snap = vm.snapshot
  let tasksNode = newJArray()
  for t in snap.tasks:
    let row = newJObject()
    row["id"] = newJInt(t.id)
    row["name"] = newJString(t.name)
    row["completed"] = newJBool(t.completed)
    tasksNode.add row
  let root = newJObject()
  root["tasks"] = tasksNode
  root["filter"] = newJString($snap.filter)
  root["inputText"] = newJString(snap.inputText)
  root
