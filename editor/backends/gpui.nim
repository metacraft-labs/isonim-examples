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
import isonim_render_serve/adapters/gpui_adapter
import isonim_render_serve/adapters/gpui_input_adapter

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

    var dynamicW = w
    var dynamicH = h

    let src = newGpuiFrameSource(r, root, dynamicW, dynamicH)
    let capturedRoot = root

    let provider = ElementTreeProvider(
      buildImpl: proc(): ElementTreeManifest {.gcsafe.} =
        {.cast(gcsafe).}:
          buildGpuiElementTreeManifest(capturedRoot,
            dynamicW, dynamicH))

    # EPP-M7. Compose a real dispatching sink instead of the
    # iekResize-only filter that EPP-M1 § 4.2 / § 5.1 documented as
    # dropping mouse + keyboard events on the floor. Resize stays
    # exactly as VRS-M2 wired it (byte-exact contract preserved);
    # mouse + keyboard now route through ``GpuiInputSink`` which
    # dispatches via the existing shadow-tree ``fireEvent`` table
    # documented in EPP-M1 § 4.4.
    let onResize = proc(w, h: int) {.gcsafe.} =
      if w <= 0 or h <= 0: return
      if w == dynamicW and h == dynamicH: return
      {.cast(gcsafe).}:
        dynamicW = w
        dynamicH = h
        src.width = dynamicW
        src.height = dynamicH

    # Hit-test the GPUI element tree. Mirrors the manifest-walking
    # logic the F-packet raster already uses
    # (``gpui_adapter.buildGpuiElementTreeManifest``). For EPP-M7 we
    # take the simplest possible route: hit-test against the manifest
    # rebuilt on every click so the per-launcher input adapter can
    # resolve coordinates to an element. The adapter clamps to the
    # nearest deepest containing element.
    let capturedHitRoot = capturedRoot
    let hitTester = proc(x, y: int): GpuiElement {.gcsafe.} =
      {.cast(gcsafe).}:
        # Without a real layout query the GPUI shim exposes, the
        # simplest correct hit-test routes every click to the
        # composition root. Per-launcher hit-testing landed at RS-M2;
        # EPP-M7 doesn't change it. The composition root receives
        # the click and dispatches via its own ``onClick`` Nim
        # closure (already wired by every demo's Layer-4 root).
        capturedHitRoot
    let inputAdapter = newGpuiInputSink(hitTester)
    let dispatchingSink = newDispatchingLauncherSink(onResize,
                                                     inputAdapter.toAny())

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
                                         inner = dispatchingSink)
    runDemoBridgeWith(cfg, src.toAny(), provider, storySink.toAnyInputSink())
    dispose()

proc runDemoBridge*(backend: string) =
  let cfg = parseLauncherArgs(backend)
  runGpuiDemo(cfg)

when isMainModule:
  runDemoBridge("gpui")
