## editor/backends/freya.nim — Freya-backend launcher for the demo editor.
##
## Constructs a real `TaskAppVM` or `SettingsVM`, builds the headless
## Freya tree via the demo's Layer-4 composition root, and streams via
## `isonim_render_serve/adapters/freya_adapter`.
##
## EX-M23b: wires an `ElementTreeProvider` into the bridge.
##
## RS-M12. Wires a `StoryDispatchSink` so the editor's `select-story` /
## `apply-mutation` I packets reconfigure the live VM.

import std/json

import isonim_freya/renderer as freya_renderer
import isonim_freya/bindings as freya_bindings
import isonim/core/owner

import isonim_render_serve
import isonim_render_serve/adapters/freya_adapter
import isonim_render_serve/adapters/freya_input_adapter

import task_app/core/vm as task_vm
import task_app/main_freya as task_freya
import settings_app/core/vm as settings_vm
import settings_app/core/demo_catalog
import settings_app/main_freya as settings_freya

import ./common
import ./story_dispatch_demo

const
  DefaultWidth = 800
  DefaultHeight = 600

proc runFreyaDemo(cfg: LauncherConfig) =
  let w = if cfg.width > 0: cfg.width else: DefaultWidth
  let h = if cfg.height > 0: cfg.height else: DefaultHeight

  createRoot proc(dispose: proc()) =
    let r = FreyaRenderer()
    var root: FreyaElement
    var taskAppVm: TaskAppVM
    var settingsAppVm: SettingsVM
    case cfg.demo
    of "settings":
      freya_bindings.freya_reset_tree()
      freya_renderer.resetCallbacks()
      let catalog = buildDemoSettingsCatalog()
      settingsAppVm = newSettingsVM(catalog)
      root = settings_freya.buildSettingsApp(r, settingsAppVm)
    else:
      freya_bindings.freya_reset_tree()
      freya_renderer.resetCallbacks()
      taskAppVm = newTaskAppVM()
      seedTaskInboxDefaults(taskAppVm)
      root = task_freya.buildTaskApp(r, taskAppVm)

    var dynamicW = w
    var dynamicH = h

    let src = newFreyaFrameSource(r, root, dynamicW, dynamicH)
    let capturedRoot = root

    let provider = ElementTreeProvider(
      buildImpl: proc(): ElementTreeManifest {.gcsafe.} =
        {.cast(gcsafe).}:
          buildFreyaElementTreeManifest(capturedRoot,
            dynamicW, dynamicH))

    # EPP-M7. See ``backends/gpui.nim`` for the rationale; this
    # mirrors that shape exactly so mouse + keyboard reach the Freya
    # leaves via the shadow-tree ``fireEvent`` table.
    let onResize = proc(w, h: int) {.gcsafe.} =
      if w <= 0 or h <= 0: return
      if w == dynamicW and h == dynamicH: return
      {.cast(gcsafe).}:
        dynamicW = w
        dynamicH = h
        src.width = dynamicW
        src.height = dynamicH

    # EPP-M12. See ``backends/gpui.nim`` for the rationale. The
    # ``hitChain`` callback returns every shadow-tree node whose
    # synthetic-layout rect contains the click coordinate (deepest
    # first); the input adapter fires ``"click"`` on each so the
    # ancestor that owns the Nim handler runs and mutates the VM.
    let capturedHitRoot = capturedRoot
    let hitTester = proc(x, y: int): FreyaElement {.gcsafe.} =
      {.cast(gcsafe).}:
        capturedHitRoot
    let hitChain = proc(x, y: int): seq[FreyaElement] {.gcsafe.} =
      {.cast(gcsafe).}:
        hitTestPath(capturedHitRoot, dynamicW, dynamicH, x, y)
    let inputAdapter = newFreyaInputSink(hitTester, hitChain)
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
    # ETS-M3 Part B: see ``backends/gpui.nim`` for the gate rationale.
    var streamElementTreeDelta = false
    when defined(withElementTreeDelta):
      streamElementTreeDelta = true
    runDemoBridgeWith(cfg, src.toAny(), provider, storySink.toAnyInputSink(),
                      streamElementTreeDelta = streamElementTreeDelta)
    dispose()

proc runDemoBridge*(backend: string) =
  let cfg = parseLauncherArgs(backend)
  runFreyaDemo(cfg)

when isMainModule:
  runDemoBridge("freya")
