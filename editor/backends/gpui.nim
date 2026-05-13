## editor/backends/gpui.nim — GPUI-backend launcher for the demo editor.
##
## Constructs a real `TaskAppVM` or `SettingsVM`, builds the headless
## GPUI tree via the demo's Layer-4 composition root, and streams the
## resulting element tree to the bridge through
## `isonim_render_serve/adapters/gpui_adapter`. The frame source
## rasterises the tree as colored rectangles whose tag / text content
## comes from the real demo VM, so each emitted frame is visibly
## distinct from the other backends' renders.
##
## EX-M23b. The launcher additionally wires an
## ``ElementTreeProvider`` into the bridge so the editor's preview
## canvas can hit-test pointer events back to component paths. The
## provider walks the same ``buildLayoutRects`` pass the rasteriser
## uses and emits a manifest via ``gpui_adapter.buildGpuiElementTreeManifest``;
## the bridge handles cadence (emit on change, never on idle frames).
## The Layer-1 leaves under ``task_app/gpui/leaves.nim`` and
## ``settings_app/gpui/leaves.nim`` annotate every visible node with
## ``ComponentPathAttr`` so the manifest entries carry the
## ``task_app/views/*`` / ``settings_app/views/*`` taxonomy shared
## with the TUI + Freya producers.

import isonim_gpui/renderer as gpui_renderer
import isonim_gpui/bindings as gpui_bindings
import isonim/core/owner

import isonim_render_serve
import isonim_render_serve/adapters/gpui_adapter

import task_app/core/vm as task_vm
import task_app/main_gpui as task_gpui
import settings_app/core/vm as settings_vm
import settings_app/core/demo_catalog
import settings_app/main_gpui as settings_gpui

import ./common

const
  DefaultWidth = 800
  DefaultHeight = 600

proc runGpuiDemo(cfg: LauncherConfig) =
  let w = if cfg.width > 0: cfg.width else: DefaultWidth
  let h = if cfg.height > 0: cfg.height else: DefaultHeight

  createRoot proc(dispose: proc()) =
    let r = GpuiRenderer()
    var root: GpuiElement
    case cfg.demo
    of "settings":
      gpui_bindings.gpui_reset_tree()
      gpui_renderer.resetCallbacks()
      let catalog = buildDemoSettingsCatalog()
      let vm = newSettingsVM(catalog)
      root = settings_gpui.buildSettingsApp(r, vm)
    else:
      gpui_bindings.gpui_reset_tree()
      gpui_renderer.resetCallbacks()
      let vm = newTaskAppVM()
      vm.addTask("Buy groceries")
      vm.addTask("Walk the dog")
      vm.addTask("Ship EX-M14")
      root = task_gpui.buildTaskApp(r, vm)

    # EX-M23b: dimensions are mutable so a future resize I packet can
    # update them in lock-step with the manifest emission. The captured
    # closures below read these on every bridge tick.
    var dynamicW = w
    var dynamicH = h

    let src = newGpuiFrameSource(r, root, dynamicW, dynamicH)
    let capturedRoot = root

    # EX-M23b: the manifest provider. The closure captures the GPUI
    # tree root + the dynamic (width, height) so resize-driven
    # bound changes propagate through the manifestKey hash and force
    # the bridge to re-emit per the RS-M11 cadence rule.
    let provider = ElementTreeProvider(
      buildImpl: proc(): ElementTreeManifest {.gcsafe.} =
        {.cast(gcsafe).}:
          buildGpuiElementTreeManifest(capturedRoot,
            dynamicW, dynamicH))

    # EX-M23b: minimal real input dispatch — resize events from the
    # editor surface update the captured surface dimensions so a
    # resize-driven state change re-emits the manifest. (Click / key
    # dispatch follows the same shape but isn't required to land this
    # milestone; the editor's hit-test path uses the manifest to
    # decide what to select before any click I packets fly.)
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
  runGpuiDemo(cfg)

when isMainModule:
  runDemoBridge("gpui")
