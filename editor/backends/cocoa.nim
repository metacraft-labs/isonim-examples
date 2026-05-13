## editor/backends/cocoa.nim — Cocoa-backend launcher for the demo editor.
##
## EX-M19. Constructs a real `TaskAppVM` or `SettingsVM`, builds the
## demo tree via the Cocoa Layer-4 composition root (EX-M5 +
## EX-M20), and streams via `isonim_render_serve/adapters/cocoa_adapter`
## (RS-M5's real `bitmapImageRepForCachingDisplayInRect` capture path).
## The frame source produces real-AppKit-rendered pixels so each emitted
## frame is visibly distinct from the other backends' renders.
##
## EX-M23c. The launcher additionally wires an
## ``ElementTreeProvider`` into the bridge so the editor's preview
## canvas can hit-test pointer events back to component paths. Mirror
## of the EX-M23b GPUI / Freya launchers; the manifest builder is
## ``cocoa_adapter.buildCocoaElementTreeManifest`` against the
## headless `CocoaElement` tree. The provider closure captures the
## tree root + the launcher's (width, height) so resize-driven
## changes propagate through the manifestKey hash and force the
## bridge to re-emit per the RS-M11 cadence rule.
##
## EX-M23c follow-up. The leaves were refactored to a
## `createRenderEffect + forEachKeyed` reactive pattern (matching the
## GPUI / Freya leaves) so the leaves track VM signal changes on their
## own. The launcher no longer needs a reactive bridge that calls
## `rerender(vm)` after the seed tasks land; the leaves' own effects
## subscribe to `vm.tasks.data` / `vm.visibleTasks` / `vm.filter` /
## etc. directly.
##
## Gated entirely `when defined(macosx):`. On Linux the file compiles as
## an empty shell (no `runDemoBridge` symbol) so that the launcher binary
## simply doesn't exist on Linux hosts — the editor's
## `BackendBinaryRegistry` already leaves `pbCocoa` unregistered on
## Linux (per EX-M14's spec), so the M57 backend strip continues to
## surface Cocoa as aria-disabled there. On macOS the launcher
## registers as `isonim-examples-cocoa` (see
## `editor/workspace.nim:43`).

when defined(macosx):
  import isonim_cocoa/renderer as cocoa_renderer
  import isonim/core/owner

  import isonim_render_serve
  import isonim_render_serve/adapters/cocoa_adapter

  import task_app/core/vm as task_vm
  import task_app/main_cocoa as task_cocoa
  import settings_app/core/vm as settings_vm
  import settings_app/core/demo_catalog
  import settings_app/main_cocoa as settings_cocoa

  import ./common

  const
    DefaultWidth = 800
    DefaultHeight = 600

  proc runCocoaDemo(cfg: LauncherConfig) =
    let w = if cfg.width > 0: cfg.width else: DefaultWidth
    let h = if cfg.height > 0: cfg.height else: DefaultHeight

    createRoot proc(dispose: proc()) =
      let r = CocoaRenderer()
      var root: CocoaElement
      case cfg.demo
      of "settings":
        let catalog = buildDemoSettingsCatalog()
        let vm = newSettingsVM(catalog)
        root = settings_cocoa.buildSettingsApp(r, vm)
      else:
        let vm = newTaskAppVM()
        vm.addTask("Buy groceries")
        vm.addTask("Walk the dog")
        vm.addTask("Ship EX-M19")
        # EX-M23c follow-up: the Cocoa task_app leaves are now
        # reactive (`createRenderEffect + forEachKeyed`), so the
        # leaves' own effects pick up the seeded tasks as they land
        # on `vm.tasks.data`. No launcher-side `rerender(vm)` bridge
        # is needed.
        root = task_cocoa.buildTaskApp(r, vm)

      # EX-M23c: dimensions are mutable so a future resize I packet can
      # update them in lock-step with the manifest emission. The captured
      # closures below read these on every bridge tick.
      var dynamicW = w
      var dynamicH = h

      let src = newCocoaFrameSource(r, root, dynamicW, dynamicH)
      let capturedRoot = root

      # EX-M23c: the manifest provider. The closure captures the Cocoa
      # tree root + the dynamic (width, height) so resize-driven
      # bound changes propagate through the manifestKey hash and force
      # the bridge to re-emit per the RS-M11 cadence rule.
      let provider = ElementTreeProvider(
        buildImpl: proc(): ElementTreeManifest {.gcsafe.} =
          {.cast(gcsafe).}:
            buildCocoaElementTreeManifest(capturedRoot,
              dynamicW, dynamicH))

      # EX-M23c: minimal real input dispatch — resize events from the
      # editor surface update the captured surface dimensions so a
      # resize-driven state change re-emits the manifest. Click / key
      # dispatch is out of scope for this milestone (mirror of GPUI /
      # Freya launchers).
      let resizingSink = newAnyInputSink(
        proc(event: InputEvent) {.gcsafe.} =
          if event.kind != iekResize: return
          if event.width <= 0 or event.height <= 0: return
          if event.width == dynamicW and event.height == dynamicH: return
          {.cast(gcsafe).}:
            dynamicW = event.width
            dynamicH = event.height
            src.width = dynamicW
            src.height = dynamicH)

      runDemoBridgeWith(cfg, src.toAny(), provider, resizingSink)
      dispose()

  proc runDemoBridge*(backend: string) =
    let cfg = parseLauncherArgs(backend)
    runCocoaDemo(cfg)

  when isMainModule:
    runDemoBridge("cocoa")
