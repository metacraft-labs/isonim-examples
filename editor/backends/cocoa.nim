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
  import isonim_render_serve/adapters/cocoa_input_adapter

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
      # EPP-M4: ``newCocoaFrameSource`` resolves a ``ccpMetal``
      # preference to ``ccpAppKit`` automatically when the host has
      # no Metal device. ``src.capturePath`` is the path the launcher
      # will actually use this session; forward the human-readable
      # label to the bridge so the hello capability bag advertises
      # ``cocoaCapturePath`` to the browser-side e2e harness.
      let captureLabel = capturePathName(src.capturePath)
      let capturedRoot = root

      let provider = ElementTreeProvider(
        buildImpl: proc(): ElementTreeManifest {.gcsafe.} =
          {.cast(gcsafe).}:
            buildCocoaElementTreeManifest(capturedRoot,
              dynamicW, dynamicH))

      # EPP-M7. See ``backends/gpui.nim`` for the rationale.
      let onResize = proc(w, h: int) {.gcsafe.} =
        if w <= 0 or h <= 0: return
        if w == dynamicW and h == dynamicH: return
        {.cast(gcsafe).}:
          dynamicW = w
          dynamicH = h
          src.width = dynamicW
          src.height = dynamicH

      let capturedHitRoot = capturedRoot
      let hitTester = proc(x, y: int): CocoaElement {.gcsafe.} =
        {.cast(gcsafe).}:
          capturedHitRoot
      let inputAdapter = newCocoaInputSink(r, hitTester)
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

      # EPP-M5. Resolve the encoder preference against the host's
      # capability. The launcher's CLI flag ``--encoder h264`` opts in;
      # without it the launcher stays on the EPP-M4 raw-RGBA F-packet
      # path. ``selectEncoderKind`` degrades automatically when
      # VideoToolbox is unreachable so the launcher never has to gate
      # on ``when defined(macosx)``.
      let encoderKind = resolveEncoderKind(cfg)
      var encoderHandle: H264EncoderHandle = nil
      if encoderKind == ekH264:
        encoderHandle = newH264EncoderHandle(dynamicW, dynamicH,
                                              cfg.bitrate)
        if encoderHandle == nil:
          # Hardware encoder construction failed at the last mile
          # (rare — selectEncoderKind already probed the host). Surface
          # the degradation so the launcher transcript shows the
          # fallback.
          echo "[cocoa launcher] VideoToolbox encoder init failed; ",
               "falling back to raw RGBA F-packet path."
      let resolvedEncoder =
        if encoderHandle != nil: ekH264 else: ekRawRgba

      runDemoBridgeWith(cfg, src.toAny(), provider,
                        storySink.toAnyInputSink(),
                        capturePath = captureLabel,
                        encoder = resolvedEncoder,
                        encoderHandle = encoderHandle)
      dispose()

  proc runDemoBridge*(backend: string) =
    let cfg = parseLauncherArgs(backend)
    runCocoaDemo(cfg)

  when isMainModule:
    runDemoBridge("cocoa")
