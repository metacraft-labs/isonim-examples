## task_app/main_cocoa.nim — Layer-4 composition root for the Cocoa target.
##
## Order matters: the leaves module exports the leaf names (`appShell`,
## `taskInput`, ...) used by `core/views.nim`; the `include` of
## `core/views.nim` resolves those names against the imported leaves
## here.
##
## The whole composition root body is gated with `when defined(macosx)`
## because `isonim_cocoa/renderer` (and the AppKit wrappers it
## transitively imports) cannot be compiled on a Linux host (see
## `task_app/cocoa/leaves.nim` docstring for the full rationale). On
## Linux this module compiles as an empty shell so that
## `isonim-examples`'s default `just test` keeps working unchanged
## while the cross-compile gate (`tests/test_cocoa_leaves_compile.nim`)
## drives the macOS-target check from the same Linux host.
##
## On macOS the composition root mirrors EX-M3 (`main_gpui.nim`) and
## EX-M4 (`main_freya.nim`):
##   - Headless (default): builds the tree against `CocoaRenderer` for
##     programmatic interaction. Suitable for automated testing — no
##     window server required.
##   - Window mode (`-d:cocoaGui`): wires an `NSWindow` via
##     `isonim_cocoa/appkit/window` and starts the AppKit event loop
##     with `nsAppRun`. RS-M5 supplies the streaming/screencap surface
##     for headless display use.
##
## To run the headless demo on a macOS host (from the workspace root):
##
##   nim c -r isonim-examples/task_app/main_cocoa.nim

when defined(macosx):
  import isonim_cocoa/renderer

  import task_app/core/vm
  import task_app/cocoa/leaves

  export renderer, vm, leaves

  include task_app/core/views

  proc buildTaskApp*(r: CocoaRenderer; vm: TaskAppVM): CocoaElement =
    ## Convenience wrapper exported for tests. Mirrors what `runApp`
    ## would do in a production driver: build the tree, return the root.
    renderTaskApp(r, vm)

  proc runTaskApp*(vm: TaskAppVM): CocoaElement =
    ## Build the task app against a fresh `CocoaRenderer` and return the
    ## root node. Resets the per-thread leaves table + the Cocoa
    ## renderer's element tracking + the callback registry so successive
    ## test cases don't leak state into each other.
    resetCocoaLeaves()
    resetTree()
    resetCallbacks()
    let r = CocoaRenderer()
    buildTaskApp(r, vm)

  when isMainModule:
    import isonim/core/owner
    when defined(cocoaGui):
      import isonim_cocoa/appkit/window as cocoa_window
      createRoot proc(dispose: proc()) =
        let appVm = newTaskAppVM()
        let root = runTaskApp(appVm)
        discard cocoa_window.sharedApplication()
        let win = cocoa_window.newNSWindow(100.0, 100.0, 800.0, 600.0)
        cocoa_window.setWindowTitle(win, "Task Manager — IsoNim Cocoa")
        cocoa_window.setContentView(win, root)
        cocoa_window.makeKeyAndOrderFront(win)
        echo "Cocoa window mounted; entering NSApplication run loop."
        echo "(Close the window to terminate. RS-M5 supplies the ",
             "streaming/headless capture path.)"
        cocoa_window.nsAppRun()
        dispose()
    else:
      createRoot proc(dispose: proc()) =
        let appVm = newTaskAppVM()
        let root = runTaskApp(appVm)
        let r = CocoaRenderer()
        echo "Task app Cocoa mounted; root.childCount=", r.childCount(root)
        appVm.setInputText("first")
        let s = leavesFor(appVm)
        r.fireEvent(s.addBtn, "click")
        appVm.setInputText("second")
        r.fireEvent(s.addBtn, "click")
        echo "After adds, tasks: ", totalCount(appVm)
        dispose()

else:
  ## Linux/non-macOS hosts: the composition root surface is
  ## intentionally empty. See the module docstring for the EX-M5
  ## partial-linux rationale and the macOS hand-off checklist.
  discard
