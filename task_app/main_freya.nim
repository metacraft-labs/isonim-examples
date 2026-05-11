## task_app/main_freya.nim — Layer-4 composition root for the Freya target.
##
## Order matters: the leaves module exports the leaf names (`appShell`,
## `taskInput`, ...) used by `core/views.nim`; the `include` of
## `core/views.nim` resolves those names against the imported leaves
## here.
##
## EX-M4: this composition root replaces the stand-alone Freya port
## previously hosted at `isonim-freya/demos/task-manager/src/main.nim`.
## The Freya flavour now consumes the canonical Layer-3 ViewModel +
## Layer-2 view template alongside the TUI/web/GPUI flavours, mirroring
## the EX-M2/EX-M3 pattern.
##
## Two modes are supported (matching the existing Freya port):
##   - Headless (default): builds the tree against `FreyaRenderer` for
##     programmatic interaction. Suitable for automated testing — no
##     display server required, only the Rust shim's `cdylib`.
##   - Window mode (`-d:freyaGui`): creates an actual Freya window via
##     `isonim_freya/window`. Currently a placeholder (the existing port
##     also leaves the window event loop unimplemented; the bridge in
##     RS-M4 will provide the production rendering surface).
##
## To run the headless demo from the workspace root:
##
##   LD_LIBRARY_PATH=isonim-freya/rust/target/debug \
##     nim c -r isonim-examples/task_app/main_freya.nim

import isonim_freya/renderer
import isonim_freya/bindings

import task_app/core/vm
import task_app/freya/leaves

export renderer, bindings, vm, leaves

include task_app/core/views

proc buildTaskApp*(r: FreyaRenderer; vm: TaskAppVM): FreyaElement =
  ## Convenience wrapper exported for tests. Mirrors what `runApp`
  ## would do in a production driver: build the tree, return the root.
  renderTaskApp(r, vm)

proc runTaskApp*(vm: TaskAppVM): FreyaElement =
  ## Build the task app against a fresh `FreyaRenderer` and return the
  ## root node. Resets the per-thread leaves table + the Freya shim's
  ## tree + the callback registry so successive test cases don't leak
  ## state into each other.
  resetFreyaLeaves()
  freya_reset_tree()
  resetCallbacks()
  let r = FreyaRenderer()
  buildTaskApp(r, vm)

when isMainModule:
  import isonim/core/owner
  when defined(freyaGui):
    import isonim_freya/window
    createRoot proc(dispose: proc()) =
      let appVm = newTaskAppVM()
      let root = runTaskApp(appVm)
      discard root
      var win = createWindow("Task Manager - IsoNim Freya", 800.0, 600.0)
      discard win.show()
      echo "Window mode placeholder (event loop not yet wired; ",
           "see RS-M4 for the streaming bridge)."
      dispose()
  else:
    createRoot proc(dispose: proc()) =
      let appVm = newTaskAppVM()
      let root = runTaskApp(appVm)
      echo "Task app Freya mounted; root.childCount=", childCount(root)
      appVm.setInputText("first")
      let s = leavesFor(appVm)
      fireEvent(s.addBtn, "click")
      appVm.setInputText("second")
      fireEvent(s.addBtn, "click")
      echo "After adds, tasks: ", totalCount(appVm)
      dispose()
