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
  import services/fake_db as task_fake_db

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
    ##
    ## On iOS we bypass the async `addTask` + `tasks.refresh()` pipeline
    ## and write the seeded inbox straight into both the FakeDb backing
    ## store AND the resource's `data` signal. Reason: under the
    ## production asyncdispatch backend a 0-ms `sleepAsync` is still
    ## enqueued through the event-loop's timer wheel, and on the first
    ## invocation of `poll(0)` the timer hasn't yet elapsed (kqueue
    ## resolution + `epochTime` rounding). The result was the on-device
    ## "(no tasks yet)" placeholder rendering on the first captured
    ## frame even though the tasks eventually landed a few hundred ms
    ## later. Writing into `vm.tasks.data.val` directly bypasses the
    ## async fetcher chain; the reactive subscriptions inside the
    ## leaves' `forEachKeyed` (already mounted by the time we run) fire
    ## immediately and the very first display-link capture sees the
    ## populated inbox.
    ##
    ## We drain the asyncdispatch event loop FIRST so the
    ## `createResource` initial load completes (it captures the
    ## current — empty — db state). Only then do we seed: the
    ## subsequent direct write to `data.val` is the last value to
    ## land on the signal and the leaves render the populated inbox.
    for _ in 0 ..< 20: drainPlatformCallbacks()
    var seeded: seq[Task] = @[]
    for name in ["Buy groceries", "Walk the dog", "Ship EX-M14"]:
      let t = Task(id: vm.db.allocTaskId(), name: name, completed: false)
      vm.db.tasks.add(t)
      seeded.add t
    vm.tasks.data.val = seeded

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

  # The reactive ViewModel, the Yoga layout engine and the per-mount
  # `applyLayout` closure must outlive `isonim_task_start`'s stack
  # frame — the Stream app keeps the Nim-built UIView tree alive on
  # the device and the user's interactions (taps, etc.) re-enter the
  # VM's actions long after the C-ABI call has returned. Parking them
  # in module-level globals (rather than letting them die with the
  # `createRoot` closure environment that owns them) makes the
  # lifetime explicit and shields the reactive graph from any ORC
  # tear-down racing the first `drawHierarchy(in:)` capture in
  # `FrameStreamingViewController.tick`.
  var iosEngine {.global.}: LayoutEngine
  var iosAppVm {.global.}: TaskAppVM
  var iosApplyLayout {.global.}: proc() {.closure.}

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
      iosEngine = newLayoutEngine()
      iosAppVm = newTaskAppVM()
      # Seed BEFORE building the tree. The leaves' initial
      # `createRenderEffect` / `forEachKeyed` runs then see the
      # populated `vm.visibleTasks` directly and the very first
      # captured frame paints the seeded inbox instead of the empty
      # placeholder. Order matters because the leaves' placeholder
      # effect appends a "(no tasks yet)" label on its initial run
      # when `visible.len == 0`; running the seed first dodges that
      # transient state.
      seedAppVmDefaults(iosAppVm)
      let rendered = runTaskApp(iosAppVm, iosEngine)
      iosRenderedRoot = Id(rendered)

      let safeWidth = iosScreenWidth
      let safeHeight = iosScreenHeight - iosSafeAreaTop - iosSafeAreaBottom
      let setFrameSel = sel("setFrame:")
      let rootHandle = cast[int64](cast[pointer](rendered))
      let engine = iosEngine

      iosApplyLayout = proc() =
        engine.calculateLayout(safeWidth, safeHeight)
        for (handle, layout) in engine.allLayouts():
          if layout.width > 0 and layout.height > 0 and handle != rootHandle:
            let view = Id(cast[pointer](handle))
            let rect = CGRect(
              origin: CGPoint(x: CGFloat(layout.x), y: CGFloat(layout.y)),
              size: CGSize(width: CGFloat(layout.width),
                           height: CGFloat(layout.height)))
            msgSendVoidCGRect(view, setFrameSel, rect)

      # Initial layout pass after the seed so Yoga sees the populated
      # task rows in its child list.
      iosApplyLayout()

      # Reactive layout — re-run when tasks or filter change. We read
      # `tasks.data.val` (the underlying signal the resource hangs off)
      # rather than `tasks.val` so the effect re-runs even when the
      # snapshot rebuild lands without a full resource state change.
      let appVm = iosAppVm
      let applyLayout = iosApplyLayout
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
      # Belt-and-braces: UIKit's `drawHierarchy(in:afterScreenUpdates:false)`
      # in `FrameStreamingViewController.tick` skips the implicit layout
      # pass that would otherwise materialise our just-attached subtree.
      # Force the layout pass now so the very first captured frame already
      # reflects the seeded task rows + chrome instead of the bare
      # background colour the host UIView paints by default.
      uiSetNeedsLayout(iosRootView)
      uiLayoutIfNeeded(iosRootView)

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
