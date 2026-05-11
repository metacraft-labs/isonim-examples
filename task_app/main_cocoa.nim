## task_app/main_cocoa.nim — Layer-4 composition root for the Cocoa target.
##
## Order matters: the leaves module exports the leaf names (`appShell`,
## `taskInput`, ...) used by `core/views.nim`; the `include` of
## `core/views.nim` resolves those names against the imported leaves
## here.
##
## EX-M5 status: **partial-linux**. The whole composition root body is
## gated with `when defined(macosx)` because `isonim_cocoa/renderer`
## (and the AppKit wrappers it transitively imports) cannot be compiled
## on a Linux host (see `task_app/cocoa/leaves.nim` docstring for the
## full rationale and the macOS engineer's hand-off checklist). On
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
##   - Window mode (`-d:cocoaGui`): TODO for the macOS engineer —
##     `isonim-cocoa` already ships `app_entry_native.nim` /
##     `app_entry.nim` which the macOS host can wire here in the same
##     shape as EX-M3's `gpuiGui` / EX-M4's `freyaGui` blocks. RS-M5
##     will provide the production rendering surface.
##
## To run the headless demo on a macOS host once the macOS portion of
## EX-M5 is complete (from the workspace root):
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
      # Window-mode placeholder: the macOS engineer should wire
      # `isonim_cocoa/app_entry_native` here (see EX-M5 status notes).
      createRoot proc(dispose: proc()) =
        let appVm = newTaskAppVM()
        let root = runTaskApp(appVm)
        discard root
        echo "Cocoa window mode placeholder (event loop not yet wired; ",
             "see RS-M5 for the streaming bridge)."
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
