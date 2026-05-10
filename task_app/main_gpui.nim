## task_app/main_gpui.nim — Layer-4 composition root for the GPUI target.
##
## Order matters: the leaves module exports the leaf names (`appShell`,
## `taskInput`, ...) used by `core/views.nim`; the `include` of
## `core/views.nim` resolves those names against the imported leaves
## here.
##
## EX-M3: this composition root replaces the stand-alone GPUI port
## previously hosted at `isonim-gpui/demos/task-manager/src/main.nim`.
## The GPUI flavour now consumes the canonical Layer-3 ViewModel +
## Layer-2 view template alongside the TUI/web flavours, mirroring the
## EX-M2 pattern.
##
## Two modes are supported (matching the existing GPUI port):
##   - Headless (default): builds the tree against `GpuiRenderer` for
##     programmatic interaction. Suitable for automated testing — no
##     display server required, only the Rust shim's `cdylib`.
##   - Window mode (`-d:gpuiGui`): creates an actual GPUI window via
##     `isonim_gpui/window`. Currently a placeholder (the existing port
##     also leaves the window event loop unimplemented; the bridge in
##     RS-M2 will provide the production rendering surface).
##
## To run the headless demo from the workspace root:
##
##   LD_LIBRARY_PATH=isonim-gpui/rust/target/debug \
##     nim c -r isonim-examples/task_app/main_gpui.nim

import isonim_gpui/renderer
import isonim_gpui/bindings

import task_app/core/vm
import task_app/gpui/leaves

export renderer, bindings, vm, leaves

include task_app/core/views

proc buildTaskApp*(r: GpuiRenderer; vm: TaskAppVM): GpuiElement =
  ## Convenience wrapper exported for tests. Mirrors what `runApp`
  ## would do in a production driver: build the tree, return the root.
  renderTaskApp(r, vm)

proc runTaskApp*(vm: TaskAppVM): GpuiElement =
  ## Build the task app against a fresh `GpuiRenderer` and return the
  ## root node. Resets the per-thread leaves table + the GPUI shim's
  ## tree + the callback registry so successive test cases don't leak
  ## state into each other.
  resetGpuiLeaves()
  gpui_reset_tree()
  resetCallbacks()
  let r = GpuiRenderer()
  buildTaskApp(r, vm)

when isMainModule:
  import isonim/core/owner
  when defined(gpuiGui):
    import isonim_gpui/window
    createRoot proc(dispose: proc()) =
      let appVm = newTaskAppVM()
      let root = runTaskApp(appVm)
      discard root
      var win = createWindow("Task Manager - IsoNim GPUI", 800.0, 600.0)
      discard win.show()
      echo "Window mode placeholder (event loop not yet wired; ",
           "see RS-M2 for the streaming bridge)."
      dispose()
  else:
    createRoot proc(dispose: proc()) =
      let appVm = newTaskAppVM()
      let root = runTaskApp(appVm)
      echo "Task app GPUI mounted; root.childCount=", childCount(root)
      appVm.setInputText("first")
      let s = leavesFor(appVm)
      fireEvent(s.addBtn, "click")
      appVm.setInputText("second")
      fireEvent(s.addBtn, "click")
      echo "After adds, tasks: ", totalCount(appVm)
      dispose()
