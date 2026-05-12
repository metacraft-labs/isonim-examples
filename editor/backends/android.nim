## editor/backends/android.nim — Android-backend launcher for the demo
## editor.
##
## EX-M21. The Android launcher is a *host-side* binary (macOS or Linux)
## that talks to a connected Android device via `adb`. The on-device
## counterpart is the existing `nimexamples` flavor in `isonim-android`
## (the `MainActivity` plus `libtask_app.so` shipped by EX-M6 + EX-M22):
## the launcher's responsibility is to drive `adb` so the right Activity
## is showing, then capture frames from the device's framebuffer with
## `adb exec-out screencap` (RS-M6's documented `acmScreencap` fallback,
## promoted here to the primary host-side path because the alternative
## — `View.draw(Canvas)` via the RS-M6 `acmHeadless` recipe — requires
## the Nim code to be running *inside* the device's process, which the
## launcher is not).
##
## On macOS and Linux the launcher:
##   1. Parses the standard launcher CLI (`--port`, `--demo`, `--width`,
##      `--height`, `--fps`, `--static`) via the shared
##      `editor/backends/common.nim` helper.
##   2. Invokes `adb` to launch the `nimexamples` Activity with the
##      requested `--demo` (an intent extra dispatches between task_app
##      and settings_app — see `MainActivity.kt`).
##   3. Wraps a `AdbScreencapFrameSource` (this module — invokes `adb
##      exec-out screencap` per frame, parses the 16-byte header
##      `<u32 width, u32 height, u32 format, u32 colorspace>`, and
##      scales the raw RGBA8888 framebuffer down to the configured
##      `cfg.width x cfg.height` via nearest-neighbour sampling) and
##      hands the `AnyFrameSource` to `runDemoBridgeWith`.
##
## Gated `when defined(macosx) or defined(linux):` because `adb` is
## available on both POSIX host toolchains. On other hosts the file
## compiles as an empty shell.
##
## *Why no in-process Android renderer?* The launcher runs on the *host*
## (not the device). Replaying the EX-M6 / EX-M22 leaves through the
## `AndroidRenderer` host-side via `-d:mockJni` would let us build the
## demo trees in-process, but the renderer would still target the
## MockJNI shim — the resulting "view tree" lives entirely in Nim memory
## and has no associated raster surface. The honest answer for the
## EX-M21 acceptance test is therefore: drive the on-device tree via
## adb and capture the device's framebuffer.

when defined(macosx) or defined(linux):
  import std/[osproc, streams, strutils]

  import isonim_render_serve

  import editor/backends/common

  const
    DefaultWidth = 800
    DefaultHeight = 600
    AdbBin = "adb"
      ## Resolved against `PATH`. The dev-shell flake provides the
      ## Android platform-tools so this works out of the box; CI / non-
      ## dev-shell environments should ensure `adb` is on the path.

  type
    AdbScreencapFrameSource* = ref object
      ## Host-side frame source that drives the device's framebuffer.
      ## Mirrors the shape of `CocoaFrameSource` / `FreyaFrameSource` /
      ## `GpuiFrameSource` so the bridge consumes it identically.
      width*, height*: int
      deviceSerial*: string
        ## Optional `-s <serial>` selector for multi-device hosts.
        ## Empty string means "use adb's default device" (single device
        ## attached, or `ANDROID_SERIAL` env var).

  proc newAdbScreencapFrameSource*(width = DefaultWidth;
                                   height = DefaultHeight;
                                   deviceSerial = ""): AdbScreencapFrameSource =
    AdbScreencapFrameSource(width: width, height: height,
                            deviceSerial: deviceSerial)

  proc runAdb(args: openArray[string]; stdoutBin = true): tuple[output: string, code: int] =
    ## Spawn adb with the given args, capture stdout. `stdoutBin = true`
    ## reads stdout byte-for-byte (used for `exec-out screencap`); for
    ## non-binary use cases the return is the textual output.
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
    ## Invoke `adb exec-out screencap` against the connected device,
    ## parse the binary framebuffer, and scale it down to
    ## `src.width x src.height` via nearest-neighbour sampling.
    ##
    ## Header format (Android L+; 16 bytes):
    ##   u32 width (LE)
    ##   u32 height (LE)
    ##   u32 pixel-format (LE)  — typically 1 (HAL_PIXEL_FORMAT_RGBA_8888)
    ##   u32 colorspace (LE)    — typically 1 (sRGB)
    ##
    ## Older devices may emit a 12-byte header (no colorspace). We
    ## detect by checking the length: 12-byte header => total =
    ## 12 + w*h*4; 16-byte header => total = 16 + w*h*4.
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
      # 1 = HAL_PIXEL_FORMAT_RGBA_8888. Other formats would need a
      # per-format swizzle; surface a clear error rather than emit
      # corrupt RGBA bytes.
      raise newException(IOError,
        "EX-M21: unexpected pixel format " & $format & " from screencap " &
        "(expected 1 = RGBA_8888). The device may not be returning RGBA " &
        "frames; check `adb shell getprop ro.build.version.sdk` and the " &
        "device's display config.")
    # Nearest-neighbour downscale from (w0,h0) to (src.width, src.height).
    let outW = src.width
    let outH = src.height
    var pixels = newSeq[byte](outW * outH * 4)
    for y in 0 ..< outH:
      let srcY = (y * h0) div outH
      for x in 0 ..< outW:
        let srcX = (x * w0) div outW
        let srcOff = headerLen + (srcY * w0 + srcX) * 4
        let dstOff = (y * outW + x) * 4
        pixels[dstOff]     = byte(raw[srcOff].byte)
        pixels[dstOff + 1] = byte(raw[srcOff + 1].byte)
        pixels[dstOff + 2] = byte(raw[srcOff + 2].byte)
        pixels[dstOff + 3] = byte(raw[srcOff + 3].byte)
    Frame(kind: fkFull,
          flags: FrameFlags(isDiff: false, isVideo: false),
          width: outW, height: outH, pixels: pixels)

  proc toAny*(src: AdbScreencapFrameSource): AnyFrameSource =
    let captured = src
    newAnyFrameSource(src.width, src.height,
      renderFrameImpl = proc(): Frame {.gcsafe.} =
        {.cast(gcsafe).}: captured.captureFrame(),
      closeImpl = proc() {.gcsafe.} = discard)

  proc launchActivity(demo: string) =
    ## Bring the on-device `nimexamples` Activity to the foreground via
    ## `adb shell am start`, passing `--es demo <demo>` so the
    ## Activity's `onCreate` dispatches to the right Nim bridge.
    ## See `MainActivity.kt` for the receiver side.
    let pkg = "com.metacraft.isonim.android.nimexamples"
    let activity = "com.metacraft.isonim.examples.MainActivity"
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
    let src = newAdbScreencapFrameSource(width = w, height = h)
    runDemoBridgeWith(cfg, src.toAny())

  proc runDemoBridge*(backend: string) =
    let cfg = parseLauncherArgs(backend)
    runAndroidDemo(cfg)

  when isMainModule:
    runDemoBridge("android")
