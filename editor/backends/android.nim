## editor/backends/android.nim — Android-backend launcher for the demo
## editor.
##
## EX-M21. Host-side binary that talks to a connected Android device
## via `adb`. The on-device counterpart is `isonim-android`'s
## `nimexamples` flavor.
##
## EX-M23c. Wires an `ElementTreeProvider` into the bridge when built
## with `-d:mockJni`.
##
## RS-M12. Wires a `StoryDispatchSink` so the editor's `select-story` /
## `apply-mutation` I packets reconfigure the live VM. With
## `-d:mockJni` enabled, the parallel in-process Android renderer
## tree's VM is the dispatch target. Without `-d:mockJni`, the
## dispatch sink is still wired so the bridge can advertise the
## packets are accepted; the device's VM is unaffected (the on-
## device runtime owns its own VM lifecycle, and the launcher has
## no FFI / IPC channel to it today — this is the same constraint
## as EX-M21's pre-RS-M12 design).
##
## Gated `when defined(macosx) or defined(linux):` because `adb` is
## available on both POSIX host toolchains.

when defined(macosx) or defined(linux):
  import std/[json, osproc, streams, strutils]

  import isonim_render_serve
  import isonim_render_serve/adapters/android_adapter

  import editor/backends/common

  when defined(mockJni):
    import isonim/core/owner

    import isonim_render_serve/adapters/android_input_adapter

    import task_app/core/vm as task_vm
    import task_app/main_android as task_android
    import settings_app/core/vm as settings_vm
    import settings_app/core/demo_catalog
    import settings_app/main_android as settings_android

    import editor/backends/story_dispatch_demo

  const
    DefaultWidth = 800
    DefaultHeight = 600
    AdbBin = "adb"

  type
    AdbScreencapFrameSource* = ref object
      width*, height*: int
      deviceSerial*: string

  proc newAdbScreencapFrameSource*(width = DefaultWidth;
                                   height = DefaultHeight;
                                   deviceSerial = ""): AdbScreencapFrameSource =
    AdbScreencapFrameSource(width: width, height: height,
                            deviceSerial: deviceSerial)

  proc runAdb(args: openArray[string]; stdoutBin = true): tuple[output: string, code: int] =
    var argv = newSeq[string]()
    for a in args: argv.add(a)
    let p = startProcess(AdbBin, args = argv,
                         options = {poUsePath, poStdErrToStdOut})
    defer: p.close()
    let s = p.outputStream()
    var buf = newStringOfCap(8 * 1024 * 1024)
    var chunk = newString(64 * 1024)
    while true:
      let n = s.readData(addr chunk[0], chunk.len)
      if n <= 0: break
      buf.add(chunk[0 ..< n])
    discard p.waitForExit()
    (buf, p.peekExitCode())

  proc parseLEUInt32(s: string; offset: int): uint32 =
    uint32(s[offset].byte) or
      (uint32(s[offset + 1].byte) shl 8) or
      (uint32(s[offset + 2].byte) shl 16) or
      (uint32(s[offset + 3].byte) shl 24)

  proc captureFrame*(src: AdbScreencapFrameSource): Frame =
    var args: seq[string] = @[]
    if src.deviceSerial.len > 0:
      args.add "-s"
      args.add src.deviceSerial
    args.add "exec-out"
    args.add "screencap"
    let (raw, code) = runAdb(args, stdoutBin = true)
    if code != 0 or raw.len < 12:
      raise newException(IOError,
        "EX-M21: `adb exec-out screencap` failed (exit=" & $code &
        "; payload=" & $raw.len & " bytes). Ensure a device is " &
        "attached and the nimexamples Activity is foregrounded.")
    let w0 = int(parseLEUInt32(raw, 0))
    let h0 = int(parseLEUInt32(raw, 4))
    let format = int(parseLEUInt32(raw, 8))
    let withColorspace = raw.len == 16 + w0 * h0 * 4
    let headerLen = if withColorspace: 16 else: 12
    if raw.len != headerLen + w0 * h0 * 4:
      raise newException(IOError,
        "EX-M21: screencap payload length mismatch (got " &
        $raw.len & " bytes; expected " & $(headerLen + w0 * h0 * 4) &
        " for " & $w0 & "x" & $h0 & " header).")
    if format != 1:
      raise newException(IOError,
        "EX-M21: unexpected pixel format " & $format & " from screencap " &
        "(expected 1 = RGBA_8888). The device may not be returning RGBA " &
        "frames; check `adb shell getprop ro.build.version.sdk` and the " &
        "device's display config.")
    # M-EVP-14 NO-STRETCH FIX (Wave AB): emit the device's native
    # framebuffer dimensions verbatim. The previous loop here did a
    # nearest-neighbor resize from (w0, h0) to (src.width, src.height) —
    # but `src.width / height` come from the launcher's `--width/--height`
    # CLI args (default 800x600; the editor-screenshot tool passes
    # 1080x720 per Wave Q-A). A portrait device framebuffer (e.g.
    # 1080x2340) thus got aspect-distorted to landscape (1080x720),
    # producing the ~3:1 horizontal-squash that the user flagged after
    # round 20.
    #
    # The user's original "no image stretching" rule (saved as
    # feedback_no_image_stretching.md in memory) explicitly mandates
    # that real-device backends display their native framebuffer at 1:1
    # and the preview pane letterboxes (the canvas-mount CSS already
    # does this — `width: auto; height: auto; max-width/height: 100%`).
    # Honor that contract here: pass through the device's native
    # dimensions and pixels with no resampling.
    #
    # Mirror the source's recorded width/height so downstream
    # consumers (the `toAny` wrapper, the resizing sink) see the
    # actual framebuffer dimensions, not the stale CLI defaults.
    src.width = w0
    src.height = h0
    var pixels = newSeq[byte](w0 * h0 * 4)
    let payloadStart = headerLen
    for i in 0 ..< w0 * h0 * 4:
      pixels[i] = byte(raw[payloadStart + i].byte)
    Frame(kind: fkFull,
          flags: FrameFlags(isDiff: false, isVideo: false),
          width: w0, height: h0, pixels: pixels)

  proc toAny*(src: AdbScreencapFrameSource): AnyFrameSource =
    let captured = src
    newAnyFrameSource(src.width, src.height,
      renderFrameImpl = proc(): Frame {.gcsafe.} =
        {.cast(gcsafe).}: captured.captureFrame(),
      closeImpl = proc() {.gcsafe.} = discard)

  proc launchActivity(demo: string) =
    let pkg = "com.metacraft.isonim.android.nimexamples"
    let activity = "com.metacraft.isonim.examples.MainActivity"
    # M-EVP-14 round-2 fix: when the activity is already running from a
    # prior launch (e.g. `--demo=task` followed by `--demo=settings` in
    # the screenshot tool's sweep), Android's intent system does not
    # re-route the new intent extra to the existing instance. The
    # activity keeps rendering whatever demo it was initialised with.
    # Force-stop the package first so the next `am start` creates a
    # fresh process that picks up the new `--es demo` extra at onCreate.
    let (stopOutput, stopCode) = runAdb(@[
      "shell", "am", "force-stop", pkg,
    ], stdoutBin = false)
    if stopCode != 0:
      echo "Warning: `adb shell am force-stop` exited ", stopCode, " — output:"
      echo stopOutput
    let (output, code) = runAdb(@[
      "shell", "am", "start",
      "-n", pkg & "/" & activity,
      "--es", "demo", demo,
    ], stdoutBin = false)
    if code != 0:
      echo "Warning: `adb shell am start` exited ", code, " — output:"
      echo output

  proc runAndroidDemo(cfg: LauncherConfig) =
    let w = if cfg.width > 0: cfg.width else: DefaultWidth
    let h = if cfg.height > 0: cfg.height else: DefaultHeight
    launchActivity(cfg.demo)
    when defined(mockJni):
      createRoot proc(dispose: proc()) =
        let mockR = AndroidRenderer()
        var mockRoot: AndroidElement
        var taskAppVm: TaskAppVM
        var settingsAppVm: SettingsVM
        case cfg.demo
        of "settings":
          let catalog = buildDemoSettingsCatalog()
          settingsAppVm = newSettingsVM(catalog)
          mockRoot = settings_android.buildSettingsApp(mockR, settingsAppVm)
        else:
          taskAppVm = newTaskAppVM()
          seedTaskInboxDefaults(taskAppVm)
          mockRoot = task_android.buildTaskApp(mockR, taskAppVm)

        var dynamicW = w
        var dynamicH = h

        let src = newAdbScreencapFrameSource(width = w, height = h)
        let capturedRoot = mockRoot

        let provider = ElementTreeProvider(
          buildImpl: proc(): ElementTreeManifest {.gcsafe.} =
            {.cast(gcsafe).}:
              buildAndroidElementTreeManifest(capturedRoot,
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

        # FUH-M2. Mirror the GPUI / Freya / Cocoa hitChain wiring per
        # the FUH-M1 audit § 1.1: the legacy ``hitTester`` routes
        # every click to the composition root (no handler), so the
        # adapter falls back to the chain walk-up. ``hitChain``
        # delegates to ``android_adapter.hitTestPath`` which mirrors
        # the EPP-M12 contract — every shadow-tree node whose rect
        # contains ``(x, y)`` is returned deepest-first.
        let capturedHitRoot = capturedRoot
        let capturedRenderer = mockR
        let hitTester = proc(x, y: int): AndroidElement {.gcsafe.} =
          {.cast(gcsafe).}:
            capturedHitRoot
        let hitChain = proc(x, y: int): seq[AndroidElement] {.gcsafe.} =
          {.cast(gcsafe).}:
            hitTestPath(capturedRenderer, capturedHitRoot,
                        dynamicW, dynamicH, x, y)
        let inputAdapter = newAndroidInputSink(mockR, hitTester, hitChain)
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
        runDemoBridgeWith(cfg, src.toAny(), provider,
                          storySink.toAnyInputSink(),
                          streamElementTreeDelta = streamElementTreeDelta)
        dispose()
    else:
      # ETS-M3 Part B: no in-process element-tree provider on the
      # non-mockJni Android path (the on-device runtime owns its own
      # tree). The delta gate is still honoured at hello time so the
      # browser-side accept advertises a stable shape across
      # configurations.
      var streamElementTreeDelta = false
      when defined(withElementTreeDelta):
        streamElementTreeDelta = true
      let src = newAdbScreencapFrameSource(width = w, height = h)
      runDemoBridgeWith(cfg, src.toAny(),
                        streamElementTreeDelta = streamElementTreeDelta)

  proc runDemoBridge*(backend: string) =
    let cfg = parseLauncherArgs(backend)
    runAndroidDemo(cfg)

  when isMainModule:
    runDemoBridge("android")
