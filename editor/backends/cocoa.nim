## editor/backends/cocoa.nim — Cocoa-backend launcher for the demo editor.
##
## EX-M19. Constructs a real `TaskAppVM` or `SettingsVM`, builds the
## demo tree via the Cocoa Layer-4 composition root (EX-M5 +
## EX-M20), and streams via `isonim_render_serve/adapters/cocoa_adapter`
## (RS-M5's real `bitmapImageRepForCachingDisplayInRect` capture path).
## The frame source produces real-AppKit-rendered pixels so each emitted
## frame is visibly distinct from the other backends' renders.
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
        root = task_cocoa.buildTaskApp(r, vm)

      let src = newCocoaFrameSource(r, root, w, h)
      runDemoBridgeWith(cfg, src.toAny())
      dispose()

  proc runDemoBridge*(backend: string) =
    let cfg = parseLauncherArgs(backend)
    runCocoaDemo(cfg)

  when isMainModule:
    runDemoBridge("cocoa")
