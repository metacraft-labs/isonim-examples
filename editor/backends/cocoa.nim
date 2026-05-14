## editor/backends/cocoa.nim — Cocoa-backend launcher for the demo editor.
##
## EX-M19. Constructs a real `TaskAppVM` or `SettingsVM`, builds the
## demo tree via the Cocoa Layer-4 composition root, and streams via
## `isonim_render_serve/adapters/cocoa_adapter`.
##
## EX-M23c. Wires an `ElementTreeProvider` into the bridge.
##
## RS-M12. Wires a `StoryDispatchSink` so the editor's `select-story` /
## `apply-mutation` I packets reconfigure the live VM.
##
## Gated entirely `when defined(macosx):`.

when defined(macosx):
  import std/json

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
  import ./story_dispatch_demo

  const
    DefaultWidth = 800
    DefaultHeight = 600

  proc runCocoaDemo(cfg: LauncherConfig) =
    let w = if cfg.width > 0: cfg.width else: DefaultWidth
    let h = if cfg.height > 0: cfg.height else: DefaultHeight

    createRoot proc(dispose: proc()) =
      let r = CocoaRenderer()
      var root: CocoaElement
      var taskAppVm: TaskAppVM
      var settingsAppVm: SettingsVM
      case cfg.demo
      of "settings":
        let catalog = buildDemoSettingsCatalog()
        settingsAppVm = newSettingsVM(catalog)
        root = settings_cocoa.buildSettingsApp(r, settingsAppVm)
      else:
        taskAppVm = newTaskAppVM()
        seedTaskInboxDefaults(taskAppVm)
        root = task_cocoa.buildTaskApp(r, taskAppVm)

      var dynamicW = w
      var dynamicH = h

      let src = newCocoaFrameSource(r, root, dynamicW, dynamicH)
      let capturedRoot = root

      let provider = ElementTreeProvider(
        buildImpl: proc(): ElementTreeManifest {.gcsafe.} =
          {.cast(gcsafe).}:
            buildCocoaElementTreeManifest(capturedRoot,
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
      runDemoBridgeWith(cfg, src.toAny(), provider,
                        storySink.toAnyInputSink())
      dispose()

  proc runDemoBridge*(backend: string) =
    let cfg = parseLauncherArgs(backend)
    runCocoaDemo(cfg)

  when isMainModule:
    runDemoBridge("cocoa")
