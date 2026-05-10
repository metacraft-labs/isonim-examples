## task_app/main_tui.nim — Layer-4 composition root for the TUI target.
##
## Order matters: the leaves module exports the leaf names (`appShell`,
## `taskInput`, …) used by `core/views.nim`; the `include` of
## `core/views.nim` resolves those names against the imported leaves
## here.
##
## This module lives in the `isonim-examples` repository — the single
## canonical home for IsoNim showcase apps. The `isonim-tui` repo
## supplies only the renderer + widget runtime via path-based dep
## (wired by `isonim-examples/config.nims:--path:../isonim-tui/src`).
##
## Migration history: the entire `task_app/` tree (Layer-1 leaves +
## Layer-4 composition root) was previously hosted at
## `isonim-tui/examples/task_app/`; EX-M2 (see
## `codetracer-specs/Front-Ends/IsoNim/isonim-render-stream.status.org`)
## promoted it to its canonical location here. Layer-3 VM and Layer-2
## view template (consumed via `task_app/core/...`) shipped in EX-M1.

import isonim_tui

import task_app/core/vm
import task_app/tui/leaves

export vm, leaves

include task_app/core/views

proc buildTaskApp*(r: TerminalRenderer; vm: TaskAppVM): TerminalNode =
  ## Convenience wrapper exported for tests. Mirrors what `runApp`
  ## would do in a production driver: build the tree, return the root.
  renderTaskApp(r, vm)

proc runTaskApp*(h: TerminalTestHarness; vm: TaskAppVM): TerminalNode =
  ## Mount the task app into a `TerminalTestHarness` and return the
  ## root node. Used by tests + by an interactive entry point.
  resetTuiLeaves()
  var rootRef: TerminalNode
  h.mount(proc(r: TerminalRenderer): TerminalNode =
    rootRef = buildTaskApp(r, vm)
    rootRef)
  rootRef

when isMainModule:
  let appVm = newTaskAppVM()
  let h = newTerminalTestHarness(60, 12)
  discard runTaskApp(h, appVm)
  echo "Task app TUI mounted (", h.cols, "x", h.rows, ")."
  echo "Tasks: ", totalCount(appVm)
  h.dispose()
