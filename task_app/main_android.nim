## task_app/main_android.nim — Layer-4 composition root for the Android target.
##
## Order matters: the leaves module exports the leaf names (`appShell`,
## `taskInput`, ...) used by `core/views.nim`; the `include` of
## `core/views.nim` resolves those names against the imported leaves
## here.
##
## EX-M6 status: **partial-linux**. The whole composition root body is
## gated with `when defined(android)` because `isonim_android/renderer`
## requires either `-d:mockJni` (host-side test shim) or
## `-d:commandBuffer` (real Android JNI bridge) to be set, and driving
## the leaves end-to-end requires either an Android emulator (the
## macOS-host responsibility per EX-M6) or the host-side MockJNI shim.
## The Linux dev shell does not ship the Android emulator (Android
## Studio's emulator runs natively on Apple Silicon — see EX-M6 status
## notes' hand-off checklist). On Linux this module compiles as an
## empty shell so that `isonim-examples`'s default `just test` keeps
## working unchanged while the cross-compile gate
## (`tests/test_android_leaves_compile.nim`) drives the Android-target
## check from the same Linux host.
##
## On Android the composition root mirrors EX-M3 (`main_gpui.nim`),
## EX-M4 (`main_freya.nim`), and EX-M5 (`main_cocoa.nim`):
##   - Headless (default): builds the tree against `AndroidRenderer`
##     for programmatic interaction. Suitable for automated testing —
##     the MockJNI shim records the view tree in-process with no
##     emulator required.
##   - Window mode (`-d:androidGui`): TODO for the macOS engineer —
##     `isonim-android` already ships `android_entry_native.nim` /
##     `android_entry.nim` which the macOS host can wire here in the
##     same shape as EX-M3's `gpuiGui` / EX-M4's `freyaGui` /
##     EX-M5's `cocoaGui` blocks. RS-M6 will provide the production
##     rendering surface.
##
## To run the headless demo on a host with the MockJNI shim available
## once the macOS portion of EX-M6 is complete (from the workspace
## root):
##
##   nim c -r -d:android -d:mockJni isonim-examples/task_app/main_android.nim
##
## On a real Android target (emulator on Apple Silicon):
##
##   nim c -r -d:android -d:commandBuffer isonim-examples/task_app/main_android.nim

when defined(android):
  import isonim_android/renderer

  import task_app/core/vm
  import task_app/android/leaves

  export renderer, vm, leaves

  include task_app/core/views

  proc buildTaskApp*(r: AndroidRenderer; vm: TaskAppVM): AndroidElement =
    ## Convenience wrapper exported for tests. Mirrors what `runApp`
    ## would do in a production driver: build the tree, return the root.
    renderTaskApp(r, vm)

  proc runTaskApp*(vm: TaskAppVM): AndroidElement =
    ## Build the task app against a fresh `AndroidRenderer` and return
    ## the root node. Resets the per-thread leaves table + the Android
    ## renderer's element tracking + the callback registry so successive
    ## test cases don't leak state into each other.
    resetAndroidLeaves()
    resetRenderer()
    let r = AndroidRenderer()
    buildTaskApp(r, vm)

  when isMainModule:
    import isonim/core/owner
    when defined(androidGui):
      # Window-mode placeholder: the macOS engineer should wire
      # `isonim_android/android_entry_native` here (see EX-M6 status
      # notes).
      createRoot proc(dispose: proc()) =
        let appVm = newTaskAppVM()
        let root = runTaskApp(appVm)
        discard root
        echo "Android window mode placeholder (event loop not yet wired; ",
             "see RS-M6 for the streaming bridge)."
        dispose()
    else:
      createRoot proc(dispose: proc()) =
        let appVm = newTaskAppVM()
        let root = runTaskApp(appVm)
        let r = AndroidRenderer()
        echo "Task app Android mounted; root.childCount=", r.childCount(root)
        appVm.setInputText("first")
        let s = leavesFor(appVm)
        r.fireEvent(s.addBtn, "click")
        appVm.setInputText("second")
        r.fireEvent(s.addBtn, "click")
        echo "After adds, tasks: ", totalCount(appVm)
        dispose()

else:
  ## Linux/non-android hosts: the composition root surface is
  ## intentionally empty. See the module docstring for the EX-M6
  ## partial-linux rationale and the macOS hand-off checklist.
  discard
