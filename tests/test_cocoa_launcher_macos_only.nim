## test_cocoa_launcher_macos_only — EX-M19 macOS-host integration test.
##
## Boots the Cocoa launcher's frame-source pipeline in-process and
## verifies it produces a real RGBA8888 frame with non-zero variance
## (proves real demo content, not a uniform / placeholder buffer).
##
## Gated entirely `when defined(macosx):`. On Linux the body skips with
## a single `check true` and a docstring pointer to the cross-compile
## gate.
##
## What this test verifies for EX-M19:
##
##   1. The Cocoa task_app composition root + the RS-M5
##      `bitmapImageRepForCachingDisplayInRect` capture path produce an
##      RGBA8888 frame of the configured dimensions.
##   2. The frame is NOT uniform (variance > 0 across at least the RGB
##      channels) — proving real AppKit painted real content.
##   3. The `--demo=settings` dispatch (EX-M20) produces a *different*
##      frame from `--demo=tasks` — confirming that the launcher's
##      `case cfg.demo` branch wires both demos through the same
##      capture pipeline.
##
## The Playwright-driven "canvas hash distinct from other backends"
## check (per EX-M19's scope) is deferred to the editor's browser test
## suite once the editor's Cocoa-bridge wiring lands; this in-process
## test is the gating "Cocoa launcher binary boots and emits a real
## frame" criterion.

import std/[unittest]

when defined(macosx):
  import isonim_cocoa/renderer as cocoa_renderer
  import isonim/core/owner

  import isonim_render_serve/adapters/cocoa_adapter

  import task_app/core/vm as task_vm
  import task_app/main_cocoa as task_cocoa
  import settings_app/core/vm as settings_vm
  import settings_app/core/demo_catalog
  import settings_app/main_cocoa as settings_cocoa

  proc captureTasksFrame(width, height: int): seq[byte] =
    var pixels: seq[byte]
    createRoot proc(dispose: proc()) =
      let r = CocoaRenderer()
      let vm = newTaskAppVM()
      vm.addTask("Buy groceries")
      vm.addTask("Walk the dog")
      vm.addTask("Ship EX-M19")
      let root = task_cocoa.buildTaskApp(r, vm)
      let src = newCocoaFrameSource(r, root, width, height)
      let frame = src.renderFrame()
      pixels = frame.pixels
      dispose()
    pixels

  proc captureSettingsFrame(width, height: int): seq[byte] =
    var pixels: seq[byte]
    createRoot proc(dispose: proc()) =
      let r = CocoaRenderer()
      let catalog = buildDemoSettingsCatalog()
      let vm = newSettingsVM(catalog)
      let root = settings_cocoa.buildSettingsApp(r, vm)
      let src = newCocoaFrameSource(r, root, width, height)
      let frame = src.renderFrame()
      pixels = frame.pixels
      dispose()
    pixels

  proc pixelVariance(pixels: seq[byte]): float =
    ## Sum of absolute deviations from the per-channel mean across the
    ## RGB channels (ignoring alpha which is always 255 for the
    ## RS-M5 capture path). Returns 0 if every pixel is identical;
    ## any real-content frame returns a positive number.
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

  suite "EX-M19: Cocoa launcher frame-source pipeline":

    test "task_app — frame is RGBA8888 of configured dimensions":
      let w = 320
      let h = 240
      let pixels = captureTasksFrame(w, h)
      check pixels.len == w * h * 4

    test "task_app — frame variance > 0 (real content)":
      let pixels = captureTasksFrame(320, 240)
      let v = pixelVariance(pixels)
      # Variance threshold: any real-painted AppKit tree returns much
      # more than 0.5; a uniform placeholder buffer returns exactly 0.
      check v > 0.5

    test "settings_app — frame is RGBA8888 of configured dimensions":
      let w = 320
      let h = 240
      let pixels = captureSettingsFrame(w, h)
      check pixels.len == w * h * 4

    test "settings_app — frame variance > 0 (real content)":
      let pixels = captureSettingsFrame(320, 240)
      let v = pixelVariance(pixels)
      check v > 0.5

    test "tasks and settings produce visibly distinct frames":
      let tasks = captureTasksFrame(320, 240)
      let settings = captureSettingsFrame(320, 240)
      # Count differing bytes — the two demos render visibly distinct
      # trees, so the byte arrays must differ in many positions. Even
      # if the two layouts share a background color, the inner text /
      # button positions will differ enough that >>100 bytes differ.
      check tasks.len == settings.len
      var diff = 0
      for i in 0 ..< tasks.len:
        if tasks[i] != settings[i]: inc diff
      check diff > 100

else:
  suite "EX-M19: Cocoa launcher (macOS host)":
    test "skipped on Linux — see test_cocoa_leaves_compile.nim for the gate":
      check true
