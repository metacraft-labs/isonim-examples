## task_app/main_ios.nim — Layer-4 composition root for the iOS target.
##
## Mirrors `task_app/main_android.nim` (Android JNI bridge entry) and
## `task_app/main_cocoa.nim` (AppKit composition root) but exposes a
## C-ABI entry point callable from the Stream app's
## `FrameStreamingViewController.swift`. The Swift side hands a
## `UIView` pointer plus the on-device safe-area metrics; the Nim side
## constructs the demo's `TaskAppVM`, seeds it with the brief's three
## sample tasks, mounts the view template against the `UIKitRenderer`,
## and attaches the resulting `UIView` subtree to the host view.
##
## Order matters: the leaves module exports the leaf names
## (`appShell`, `taskInput`, ...) used by `core/views.nim`; the
## `include` of `core/views.nim` resolves those names against the
## imported leaves here.
##
## The whole composition root body is gated `when defined(macosx)`
## because `isonim_cocoa/uikit_renderer` requires the Objective-C
## runtime FFI + UIKit shims. On Linux this module compiles as an
## empty shell so `isonim-examples`'s default `just test` keeps
## working unchanged.

when defined(macosx):
  import isonim_cocoa/objc_runtime
  import isonim_cocoa/uikit_renderer
  import isonim_cocoa/uikit/views
  import isonim/layout/layout_engine
  import isonim/core/[owner, signals, computation]
  import nim_everywhere/async_compat

  import task_app/core/vm
  import task_app/ios/leaves

  export uikit_renderer, vm, leaves

  include task_app/core/views

  proc buildTaskApp*(r: UIKitRenderer; vm: TaskAppVM): UIKitElement =
    ## Convenience wrapper exported for tests. Mirrors what `runApp`
    ## would do in a production driver: build the tree, return the root.
    renderTaskApp(r, vm)

  proc runTaskApp*(vm: TaskAppVM; engine: LayoutEngine = nil): UIKitElement =
    ## Build the task app against a fresh `UIKitRenderer` and return
    ## the root node. Resets the per-thread leaves table + the UIKit
    ## renderer's element tracking + the callback registry so
    ## successive test cases don't leak state into each other.
    resetIosLeaves()
    resetUITree()
    let r = UIKitRenderer(engine: engine)
    buildTaskApp(r, vm)

  proc seedAppVmDefaults*(vm: TaskAppVM) =
    ## Plant the three sample tasks the brief mandates so the on-device
    ## demo opens with a populated inbox instead of the "(no tasks
    ## yet)" placeholder. Mirrors the Android composition root's
    ## seeder in `task_app/main_android.nim` so the cross-mobile
    ## comparison reads as the same demo.
    vm.addTask("Buy groceries")
    for _ in 0 ..< 10: drainPlatformCallbacks()
    vm.addTask("Walk the dog")
    for _ in 0 ..< 10: drainPlatformCallbacks()
    vm.addTask("Ship EX-M14")
    for _ in 0 ..< 10: drainPlatformCallbacks()

  # ----------------------------------------------------------------------------
  # C-ABI entry point — called from
  # `ios-app/StreamSources/FrameStreamingViewController.swift`.
  # ----------------------------------------------------------------------------

  var iosRootView {.global.}: Id
  var iosRenderedRoot {.global.}: Id
  var iosScreenWidth {.global.}: float = 390.0
  var iosScreenHeight {.global.}: float = 844.0
  var iosSafeAreaTop {.global.}: float = 59.0
  var iosSafeAreaBottom {.global.}: float = 34.0

  proc isonim_task_start(rootView: pointer;
                         width, height, saTop, saBottom: cdouble)
      {.exportc, cdecl, dynlib.} =
    ## Stream-app entry point. The Swift host passes the
    ## `FrameStreamingViewController.view` as `rootView` plus the
    ## device's logical bounds + safe-area insets. We construct the
    ## demo's reactive tree once; createRenderEffect handles signal
    ## propagation. Layout is driven by the Yoga `LayoutEngine` and
    ## flushed to AppKit/UIKit views via `setFrame:`.
    iosRootView = Id(rootView)
    iosScreenWidth = width
    iosScreenHeight = height
    iosSafeAreaTop = saTop
    iosSafeAreaBottom = saBottom

    createRoot proc(dispose: proc()) =
      # `dispose` is intentionally not invoked: the reactive
      # subscriptions registered inside this block (layout updates +
      # leaf-side createRenderEffects) must outlive this call so the
      # Stream app keeps re-rendering when VM signals change.
      discard repr(dispose)
      let engine = newLayoutEngine()
      let appVm = newTaskAppVM()
      seedAppVmDefaults(appVm)
      let rendered = runTaskApp(appVm, engine)
      iosRenderedRoot = Id(rendered)

      let safeWidth = iosScreenWidth
      let safeHeight = iosScreenHeight - iosSafeAreaTop - iosSafeAreaBottom
      let setFrameSel = sel("setFrame:")
      let rootHandle = cast[int64](cast[pointer](rendered))

      proc applyLayout() =
        engine.calculateLayout(safeWidth, safeHeight)
        for (handle, layout) in engine.allLayouts():
          if layout.width > 0 and layout.height > 0 and handle != rootHandle:
            let view = Id(cast[pointer](handle))
            let rect = CGRect(
              origin: CGPoint(x: CGFloat(layout.x), y: CGFloat(layout.y)),
              size: CGSize(width: CGFloat(layout.width),
                           height: CGFloat(layout.height)))
            msgSendVoidCGRect(view, setFrameSel, rect)

      # Initial layout pass.
      applyLayout()

      # Reactive layout — re-run when tasks or filter change. We read
      # `tasks.data.val` (the underlying signal the resource hangs off)
      # rather than `tasks.val` so the effect re-runs even when the
      # snapshot rebuild lands without a full resource state change.
      createRenderEffect proc() =
        discard appVm.tasks.data.val
        discard appVm.filter.val
        applyLayout()

      # Position the root in the safe area and attach to the host view.
      msgSendVoidCGRect(iosRenderedRoot, setFrameSel,
        CGRect(origin: CGPoint(x: 0, y: iosSafeAreaTop),
               size: CGSize(width: iosScreenWidth,
                            height: safeHeight)))
      uiAddSubview(iosRootView, iosRenderedRoot)

  when isMainModule:
    # Headless smoke-build used by the cross-compile gate. The Stream
    # app calls `isonim_task_start` directly; this `isMainModule`
    # block exists so `nim c -r` on macOS exercises the leaves +
    # composition root chain without touching a live UIView.
    createRoot proc(dispose: proc()) =
      let appVm = newTaskAppVM()
      seedAppVmDefaults(appVm)
      let root = runTaskApp(appVm)
      let r = UIKitRenderer()
      echo "Task app iOS mounted; root.childCount=", r.childCount(root)
      echo "Seeded tasks: ", totalCount(appVm)
      dispose()

else:
  ## Linux/non-macOS hosts: the composition root surface is
  ## intentionally empty.
  discard
