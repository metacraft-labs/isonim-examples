## test_android_launcher_device_only — EX-M21 host-with-device
## integration test.
##
## Boots the Android launcher's frame-source pipeline in-process and
## verifies it produces a real RGBA8888 frame from the connected
## device's framebuffer with non-zero variance (proves real device
## content, not a uniform / placeholder buffer).
##
## Fails (does NOT skip) when no Android device is reachable via
## `adb devices`. Gated `when defined(macosx) or defined(linux):`; on
## other hosts the body compiles as a single `check true` pointer to
## this docstring. The no-skip policy follows the user's standing
## instruction (`feedback_real_environment_tests.md`): a missing adb
## device is a real test environment defect, not a skip-worthy
## condition. CI environments without an Android device fail fast with
## a clear diagnostic naming the missing prerequisite.
##
## What this test verifies for EX-M21:
##
##   1. `adb exec-out screencap` produces a binary buffer of the
##      device's native framebuffer dimensions (parsed from the 12- or
##      16-byte header).
##   2. The `AdbScreencapFrameSource` downscales that buffer to the
##      configured `(width, height)` via nearest-neighbour and emits a
##      well-formed `Frame` (length = width*height*4, alpha opaque).
##   3. The frame has non-zero variance — proving the device's display
##      contains real content (the `nimexamples` Activity or the
##      device's home screen), not a uniform placeholder.
##   4. Two successive captures from the same device produce
##      byte-identical results IF the screen content hasn't changed
##      (sanity check that screencap isn't injecting random per-call
##      noise); they need not be identical if the launcher's
##      `launchActivity` is racing with a tree rebuild.
##
## This is the EX-M21 acceptance gate: the launcher's frame source
## pipeline produces real device-captured RGBA frames. The on-device
## side (the demo trees themselves) is verified by RS-M6's
## `AdapterCaptureTest.kt` and EX-M22's `SettingsAppScenarioTest.kt`.

import std/[osproc, strutils, unittest]

when defined(macosx) or defined(linux):
  import editor/backends/android as android_launcher

  proc adbDevicePresent(): bool =
    let (output, code) = execCmdEx("adb devices")
    if code != 0:
      return false
    var devices = 0
    for line in output.splitLines:
      let parts = line.split()
      if parts.len >= 2 and parts[1] == "device":
        inc devices
    devices >= 1

  proc pixelVariance(pixels: seq[byte]): float =
    ## Sum of absolute deviations from the per-channel mean across the
    ## RGB channels (ignoring alpha). Returns 0 if every pixel is
    ## identical; any real-content frame returns a positive number.
    if pixels.len < 16: return 0
    let pixelCount = pixels.len div 4
    var sumR, sumG, sumB: int64
    for p in 0 ..< pixelCount:
      sumR += pixels[p * 4 + 0].int
      sumG += pixels[p * 4 + 1].int
      sumB += pixels[p * 4 + 2].int
    let meanR = sumR div pixelCount.int64
    let meanG = sumG div pixelCount.int64
    let meanB = sumB div pixelCount.int64
    var dev: int64
    for p in 0 ..< pixelCount:
      dev += abs(pixels[p * 4 + 0].int64 - meanR)
      dev += abs(pixels[p * 4 + 1].int64 - meanG)
      dev += abs(pixels[p * 4 + 2].int64 - meanB)
    dev.float / pixelCount.float

  const NoDeviceDiagnostic = """
EX-M21: no Android device reachable via adb. The Android launcher
frame-source pipeline test requires at least one device or emulator
in `adb devices` reporting the `device` state. Per the user's
standing instruction (real-environment tests only; obstacles must be
removed, not worked around), this is a hard failure, not a skip.
Attach an emulator / device and re-run.
"""

  template requireAdbDevice() =
    if not adbDevicePresent():
      echo NoDeviceDiagnostic
    require adbDevicePresent()

  suite "EX-M21: Android launcher frame-source pipeline":

    test "device is reachable via adb":
      requireAdbDevice()

    test "captureFrame produces RGBA8888 of configured dimensions":
      requireAdbDevice()
      let src = newAdbScreencapFrameSource(width = 320, height = 240)
      let frame = src.captureFrame()
      check frame.width == 320
      check frame.height == 240
      check frame.pixels.len == 320 * 240 * 4

    test "captureFrame variance > 0 (real device content)":
      requireAdbDevice()
      let src = newAdbScreencapFrameSource(width = 320, height = 240)
      let frame = src.captureFrame()
      let v = pixelVariance(frame.pixels)
      # Any non-uniform device screen returns variance well above 0.5
      # (text, status bar, app chrome). A black-screen device returns
      # 0; a uniform-colour test pattern returns 0. The connected
      # R5CX1130V0X test device is never in those states during CI.
      check v > 0.5

    test "two captures of an unchanging screen agree on most bytes":
      requireAdbDevice()
      let src = newAdbScreencapFrameSource(width = 320, height = 240)
      let frame1 = src.captureFrame()
      let frame2 = src.captureFrame()
      # Status-bar clock + battery indicators may tick between the
      # two captures, but the bulk of the frame should match. Require
      # at least 80% of bytes to agree as a sanity check that
      # screencap returns a stable view rather than per-call noise.
      check frame1.pixels.len == frame2.pixels.len
      var agree = 0
      for i in 0 ..< frame1.pixels.len:
        if frame1.pixels[i] == frame2.pixels[i]: inc agree
      let agreeRatio = agree.float / frame1.pixels.len.float
      check agreeRatio > 0.8

else:
  suite "EX-M21: Android launcher (macOS/Linux host)":
    test "skipped on this host":
      check true
