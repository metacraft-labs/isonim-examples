## settings_app/main_ios_entry.nim — Layer-4 C-ABI library entry for the
## settings-app iOS target.
##
## Mirrors `settings_app/main_android_entry.nim`: the entry library is
## a *separate* compile-unit so the task_app's `libtask_app_ios.a`
## stays byte-untouched. Both libraries can be linked into the same
## Swift host; their C-ABI symbols are namespaced
## (`isonim_task_start` vs `isonim_settings_start`) so they never
## collide.
##
## The whole module body is gated `when defined(macosx)` because
## `isonim_cocoa/uikit_renderer` requires the iOS / macOS SDKs. On
## Linux this module compiles as an empty shell.
##
## Cross-compile (iPhone arm64) — see `build-nim-ios-settings.sh` for
## the canonical invocation.

when defined(macosx):
  import isonim_cocoa/objc_runtime
  import isonim_cocoa/uikit_renderer
  import isonim_cocoa/uikit/views
  import isonim/layout/layout_engine
  import isonim/core/[owner, signals, computation]

  import settings_app/core/vm
  import settings_app/core/demo_catalog
  import settings_app/main_ios as settings_app

  export uikit_renderer, vm, demo_catalog, settings_app

  var iosSettingsRootView {.global.}: Id
  var iosSettingsRenderedRoot {.global.}: Id
  var iosSettingsScreenWidth {.global.}: float = 390.0
  var iosSettingsScreenHeight {.global.}: float = 844.0
  var iosSettingsSafeAreaTop {.global.}: float = 59.0
  var iosSettingsSafeAreaBottom {.global.}: float = 34.0

  # As in `task_app/main_ios.nim`: hoist the long-lived state out of
  # the per-call closure into module-level globals. The Stream app
  # keeps the rendered tree alive for the entire session and any user
  # interaction re-enters the VM long after `isonim_settings_start`
  # has returned, so the engine + VM + layout closure must outlive
  # the C-ABI call.
  var iosSettingsEngine {.global.}: LayoutEngine
  var iosSettingsVm {.global.}: SettingsVM
  var iosSettingsApplyLayout {.global.}: proc() {.closure.}

  proc isonim_settings_start(rootView: pointer;
                             width, height, saTop, saBottom: cdouble)
      {.exportc, cdecl, dynlib.} =
    ## Stream-app entry point for the settings demo. The Swift host
    ## passes the `FrameStreamingViewController.view` as `rootView`
    ## plus the device's logical bounds + safe-area insets. We
    ## construct `SettingsVM` from the demo catalog, mount the
    ## settings shell against the `UIKitRenderer`, and attach the
    ## resulting `UIView` subtree to the host view.
    iosSettingsRootView = Id(rootView)
    iosSettingsScreenWidth = width
    iosSettingsScreenHeight = height
    iosSettingsSafeAreaTop = saTop
    iosSettingsSafeAreaBottom = saBottom

    createRoot proc(dispose: proc()) =
      # `dispose` is intentionally not invoked: subscriptions inside
      # this block must outlive this call so the Stream app continues
      # to re-render when SettingsVM signals change.
      discard repr(dispose)
      iosSettingsEngine = newLayoutEngine()
      let catalog = buildDemoSettingsCatalog()
      iosSettingsVm = newSettingsVM(catalog)
      let rendered =
        settings_app.runSettingsApp(iosSettingsVm, iosSettingsEngine)
      iosSettingsRenderedRoot = Id(rendered)

      let safeWidth = iosSettingsScreenWidth
      let safeHeight =
        iosSettingsScreenHeight - iosSettingsSafeAreaTop - iosSettingsSafeAreaBottom
      let setFrameSel = sel("setFrame:")
      let rootHandle = cast[int64](cast[pointer](rendered))
      let engine = iosSettingsEngine

      iosSettingsApplyLayout = proc() =
        engine.calculateLayout(safeWidth, safeHeight)
        for (handle, layout) in engine.allLayouts():
          if layout.width > 0 and layout.height > 0 and handle != rootHandle:
            let view = Id(cast[pointer](handle))
            let rect = CGRect(
              origin: CGPoint(x: CGFloat(layout.x), y: CGFloat(layout.y)),
              size: CGSize(width: CGFloat(layout.width),
                           height: CGFloat(layout.height)))
            msgSendVoidCGRect(view, setFrameSel, rect)

      iosSettingsApplyLayout()

      # Reactive layout: re-run when the active group flips or any
      # of the per-group items' values change. The createRenderEffect
      # inside the shell handles structural rebuilds; this effect
      # re-flushes layout after the structural change so the device
      # sees the new geometry.
      let settingsVm = iosSettingsVm
      let applyLayout = iosSettingsApplyLayout
      createRenderEffect proc() =
        discard settingsVm.activeGroupId.val
        applyLayout()

      msgSendVoidCGRect(iosSettingsRenderedRoot, setFrameSel,
        CGRect(origin: CGPoint(x: 0, y: iosSettingsSafeAreaTop),
               size: CGSize(width: iosSettingsScreenWidth,
                            height: safeHeight)))
      uiAddSubview(iosSettingsRootView, iosSettingsRenderedRoot)
      # Force an immediate UIKit layout pass on the host view so the
      # very first `drawHierarchy(in:afterScreenUpdates:false)` capture
      # in `FrameStreamingViewController.tick` already includes the
      # just-attached settings subtree instead of the bare background
      # colour the host UIView paints by default.
      uiSetNeedsLayout(iosSettingsRootView)
      uiLayoutIfNeeded(iosSettingsRootView)

  when isMainModule:
    createRoot proc(dispose: proc()) =
      let catalog = buildDemoSettingsCatalog()
      let settingsVm = newSettingsVM(catalog)
      let root = settings_app.runSettingsApp(settingsVm)
      let r = UIKitRenderer()
      echo "Settings app iOS entry mounted; root.childCount=",
        r.childCount(root)
      dispose()

else:
  ## Linux/non-macOS hosts: the C-ABI entry surface is intentionally
  ## empty.
  discard
