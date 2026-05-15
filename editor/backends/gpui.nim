## editor/backends/gpui.nim — GPUI-backend launcher for the demo editor.
##
## Constructs a real `TaskAppVM` or `SettingsVM`, builds the headless
## GPUI tree via the demo's Layer-4 composition root, and streams the
## resulting element tree to the bridge through
## `isonim_render_serve/adapters/gpui_adapter`.
##
## EX-M23b. Wires an `ElementTreeProvider` into the bridge.
##
## RS-M12. The launcher wires a `StoryDispatchSink` so the editor's
## `select-story` / `apply-mutation` I packets reconfigure the live
## VM. The composition root stays mounted across selects — the
## reactive graph repaints the surface in response to VM state
## changes.

import std/json

import isonim_gpui/renderer as gpui_renderer
import isonim_gpui/bindings as gpui_bindings
import isonim/core/owner

import isonim_render_serve
import isonim_render_serve/adapters/gpui_tree_adapter

import task_app/core/vm as task_vm
import task_app/main_gpui as task_gpui
import settings_app/core/vm as settings_vm
import settings_app/core/demo_catalog
import settings_app/main_gpui as settings_gpui

import ./common
import ./story_dispatch_demo

const
  DefaultWidth = 800
  DefaultHeight = 600

proc runGpuiDemo(cfg: LauncherConfig) =
  let w = if cfg.width > 0: cfg.width else: DefaultWidth
  let h = if cfg.height > 0: cfg.height else: DefaultHeight

  createRoot proc(dispose: proc()) =
    let r = GpuiRenderer()
    var root: GpuiElement
    var taskAppVm: TaskAppVM
    var settingsAppVm: SettingsVM
    case cfg.demo
    of "settings":
      gpui_bindings.gpui_reset_tree()
      gpui_renderer.resetCallbacks()
      let catalog = buildDemoSettingsCatalog()
      settingsAppVm = newSettingsVM(catalog)
      root = settings_gpui.buildSettingsApp(r, settingsAppVm)
    else:
      gpui_bindings.gpui_reset_tree()
      gpui_renderer.resetCallbacks()
      taskAppVm = newTaskAppVM()
      seedTaskInboxDefaults(taskAppVm)
      root = task_gpui.buildTaskApp(r, taskAppVm)

    discard r
    let capturedRoot = root
    let providerState = GpuiRenderTreeProviderState(
      root: capturedRoot, width: w, height: h, frameSeq: 0)

    # RS-M13b: a no-op frame source supplies the dimensions reported
    # in hello.initialSize. The launcher advertises
    # `rendererSurface = "tree"` so the bridge never invokes
    # renderFrame on this source.
    let src = newNoopFrameSource(w, h)

    let elementTreeProvider = ElementTreeProvider(
      buildImpl: proc(): ElementTreeManifest {.gcsafe.} =
        {.cast(gcsafe).}:
          buildGpuiElementTreeManifest(capturedRoot,
            providerState.width, providerState.height))

    let renderTreeProvider = newGpuiRenderTreeProvider(providerState)

    let resizingSink = newAnyInputSink(
      proc(event: InputEvent) {.gcsafe.} =
        if event.kind != iekResize: return
        if event.width <= 0 or event.height <= 0: return
        if event.width == providerState.width and
           event.height == providerState.height: return
        {.cast(gcsafe).}:
          providerState.width = event.width
          providerState.height = event.height
          src.width = event.width
          src.height = event.height)

    let captTaskVm = taskAppVm
    let captSettingsVm = settingsAppVm
    let demoIsSettings = cfg.demo == "settings"
    let mountFn = proc(storyId: string; properties: JsonNode)
                  {.closure, gcsafe.} =
      {.cast(gcsafe).}:
        if demoIsSettings:
          applySettingsStory(captSettingsVm, storyId)
        else:
          applyTaskStory(captTaskVm, storyId)
    let applyFn = proc(target, key: string; value: JsonNode;
                       scope: MutationScope) {.closure, gcsafe.} =
      {.cast(gcsafe).}:
        if demoIsSettings:
          applySettingsMutation(captSettingsVm, target, key, value, scope)
        else:
          applyTaskMutation(captTaskVm, target, key, value, scope)
    let storySink = newStoryDispatchSink(mountFn, applyFn,
                                         inner = resizingSink)
    runDemoBridgeWith(cfg, src, elementTreeProvider,
                      storySink.toAnyInputSink(),
                      renderTree = renderTreeProvider,
                      rendererSurface = "tree")
    dispose()

proc runDemoBridge*(backend: string) =
  let cfg = parseLauncherArgs(backend)
  runGpuiDemo(cfg)

when isMainModule:
  runDemoBridge("gpui")
