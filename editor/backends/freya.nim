## editor/backends/freya.nim — Freya-backend launcher for the demo editor.
##
## Constructs a real `TaskAppVM` or `SettingsVM`, builds the headless
## Freya tree via the demo's Layer-4 composition root, and streams the
## resulting element tree to the bridge through
## `isonim_render_serve/adapters/freya_adapter`. The frame source
## rasterises the tree as colored rectangles whose tag / text content
## comes from the real demo VM, so each emitted frame is visibly
## distinct from the other backends' renders.
##
## EX-M15: the `--demo=settings` branch now drives the real Freya
## settings composition (`settings_app/main_freya.buildSettingsApp`)
## rather than falling back to `task_app`. This matches the GPUI
## launcher's pre-existing dispatch shape (`editor/backends/gpui.nim`).
##
## EX-M23b. The launcher additionally wires an
## ``ElementTreeProvider`` into the bridge so the editor's preview
## canvas can hit-test pointer events back to component paths. Mirror
## of the GPUI launcher; the manifest builder is
## ``freya_adapter.buildFreyaElementTreeManifest`` against the
## Freya tree.

import isonim_freya/renderer as freya_renderer
import isonim_freya/bindings as freya_bindings
import isonim/core/owner

import isonim_render_serve
import isonim_render_serve/adapters/freya_adapter

import task_app/core/vm as task_vm
import task_app/main_freya as task_freya
import settings_app/core/vm as settings_vm
import settings_app/core/demo_catalog
import settings_app/main_freya as settings_freya

import ./common

const
  DefaultWidth = 800
  DefaultHeight = 600

proc runFreyaDemo(cfg: LauncherConfig) =
  let w = if cfg.width > 0: cfg.width else: DefaultWidth
  let h = if cfg.height > 0: cfg.height else: DefaultHeight

  createRoot proc(dispose: proc()) =
    let r = FreyaRenderer()
    var root: FreyaElement
    case cfg.demo
    of "settings":
      freya_bindings.freya_reset_tree()
      freya_renderer.resetCallbacks()
      let catalog = buildDemoSettingsCatalog()
      let vm = newSettingsVM(catalog)
      root = settings_freya.buildSettingsApp(r, vm)
    else:
      freya_bindings.freya_reset_tree()
      freya_renderer.resetCallbacks()
      let vm = newTaskAppVM()
      vm.addTask("Buy groceries")
      vm.addTask("Walk the dog")
      vm.addTask("Ship EX-M14")
      root = task_freya.buildTaskApp(r, vm)

    var dynamicW = w
    var dynamicH = h

    let src = newFreyaFrameSource(r, root, dynamicW, dynamicH)
    let capturedRoot = root

    let provider = ElementTreeProvider(
      buildImpl: proc(): ElementTreeManifest {.gcsafe.} =
        {.cast(gcsafe).}:
          buildFreyaElementTreeManifest(capturedRoot,
            dynamicW, dynamicH))

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
  runFreyaDemo(cfg)

when isMainModule:
  runDemoBridge("freya")
