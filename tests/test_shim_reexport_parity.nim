## test_shim_reexport_parity — EX-M1 mandatory integration test.
##
## EX-M1 chose Option A: the canonical task-app core lives here in
## `isonim-examples`, and the previous `isonim-tui/examples/task_app/
## core/vm.nim` was rewritten as a thin re-export shim that pulls the
## canonical types via `import task_app/core/vm; export vm`.
##
## This test proves the shim approach has zero behavioral divergence:
##
##   1. `static:` block asserts the shim's `TaskAppVM` and `FilterMode`
##      types are byte-identical with the canonical types (i.e. the
##      shim re-exports them rather than redefining them).
##
##   2. The same M22-style scenario runs through the shim path; the
##      live signals + derived projections must match the canonical
##      run line-for-line.
##
##   3. A VM constructed via the canonical path can be operated on by
##      a proc imported via the shim path (and vice-versa) — there's
##      genuinely one type, not two interconvertible ones.
##
## No mocks: both `import` paths point at real Nim modules backed by
## the same on-disk `task_app/core/vm.nim`.

import std/unittest

import isonim/core/signals
import task_app/core/vm as canonicalVm
# The shim file `isonim-tui/examples/task_app/core/vm.nim` lives at
# `../isonim-tui/examples/task_app/core/vm.nim` from this repo root.
# We rely on the absolute-style path (relative path from the *test*
# file's directory).
import "../../isonim-tui/examples/task_app/core/vm" as shimVm

suite "EX-M1: re-export shim has zero behavioral divergence":
  test "shim re-exports the canonical types byte-identically":
    static:
      doAssert shimVm.TaskAppVM is canonicalVm.TaskAppVM
      doAssert shimVm.FilterMode is canonicalVm.FilterMode
      doAssert shimVm.Task is canonicalVm.Task
      doAssert shimVm.VMSnapshot is canonicalVm.VMSnapshot

  test "shim's newTaskAppVM produces a usable canonical VM":
    let vm = shimVm.newTaskAppVM()
    # Operate on it via the canonical proc set.
    canonicalVm.addTask(vm, "from canonical")
    # And via the shim proc set.
    shimVm.addTask(vm, "from shim")
    check vm.totalCount == 2
    check vm.tasks.val[0].name == "from canonical"
    check vm.tasks.val[1].name == "from shim"

  test "shim path runs the M22 script with byte-identical results":
    # Run the same script as test_vm_round_trip's "full M22 scenario"
    # but through the shim import. Resulting snapshot must be equal.
    let vmShim = shimVm.newTaskAppVM()
    shimVm.addTask(vmShim, "Buy milk")
    shimVm.addTask(vmShim, "Write specs")
    shimVm.toggleTask(vmShim, vmShim.tasks.val[1].id)
    shimVm.setFilter(vmShim, shimVm.FilterMode.fmActive)
    let snapShim = shimVm.snapshot(vmShim)

    let vmCanon = canonicalVm.newTaskAppVM()
    canonicalVm.addTask(vmCanon, "Buy milk")
    canonicalVm.addTask(vmCanon, "Write specs")
    canonicalVm.toggleTask(vmCanon, vmCanon.tasks.val[1].id)
    canonicalVm.setFilter(vmCanon, canonicalVm.FilterMode.fmActive)
    let snapCanon = canonicalVm.snapshot(vmCanon)

    check snapShim == snapCanon
    check shimVm.visibleTasks(vmShim) == canonicalVm.visibleTasks(vmCanon)
    check shimVm.activeCount(vmShim) == canonicalVm.activeCount(vmCanon)
    check shimVm.completedCount(vmShim) == canonicalVm.completedCount(vmCanon)
    check shimVm.totalCount(vmShim) == canonicalVm.totalCount(vmCanon)

  test "FilterMode enum values are byte-identical between shim and canonical":
    check ord(shimVm.FilterMode.fmAll) == ord(canonicalVm.FilterMode.fmAll)
    check ord(shimVm.FilterMode.fmActive) == ord(canonicalVm.FilterMode.fmActive)
    check ord(shimVm.FilterMode.fmCompleted) ==
      ord(canonicalVm.FilterMode.fmCompleted)
    check $shimVm.FilterMode.fmAll == $canonicalVm.FilterMode.fmAll
    check $shimVm.FilterMode.fmActive == $canonicalVm.FilterMode.fmActive
    check $shimVm.FilterMode.fmCompleted == $canonicalVm.FilterMode.fmCompleted
