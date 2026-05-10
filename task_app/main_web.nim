## task_app/main_web.nim — Layer-4 composition root for the web target.
##
## The web demo defaults to `MockRenderer` so the same composition
## works under native `nim c` (for headless tests) and under the JS
## backend with `WebRenderer` swapped in. The leaf set is the shared
## one in `web/leaves.nim`; `core/views.nim` is the byte-identical
## Layer-2 view.
##
## This module lives in the `isonim-examples` repository — the single
## canonical home for IsoNim showcase apps. A future `isonim-website/`
## adapter swaps `MockRenderer` for `WebRenderer` without touching the
## leaf code.
##
## Migration history: the entire `task_app/` tree (Layer-1 leaves +
## Layer-4 composition root) was previously hosted at
## `isonim-tui/examples/task_app/`; EX-M2 (see
## `codetracer-specs/Front-Ends/IsoNim/isonim-render-stream.status.org`)
## promoted it to its canonical location here. Layer-3 VM and Layer-2
## view template (consumed via `task_app/core/...`) shipped in EX-M1.

import isonim/testing/mock_dom

import task_app/core/vm
import task_app/web/leaves

export mock_dom, vm, leaves

include task_app/core/views

proc buildTaskApp*(r: MockRenderer; vm: TaskAppVM): MockNode =
  ## Build the task-app tree against a MockRenderer. Returns the root.
  ## A real browser deploy swaps in `WebRenderer` — the leaf-and-view
  ## code is unchanged.
  renderTaskApp(r, vm)

when isMainModule:
  let appVm = newTaskAppVM()
  let r = MockRenderer()
  let root = buildTaskApp(r, appVm)
  echo "Task app web mounted; root.tag=", root.tag
  echo "Children: ", root.children.len
  appVm.addTask("first")
  appVm.addTask("second")
  rerender(appVm)
  echo "After adds, tasks: ", totalCount(appVm)
