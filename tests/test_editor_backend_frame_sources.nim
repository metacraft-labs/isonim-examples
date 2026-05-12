## test_editor_backend_frame_sources — EX-M14 Gap 1 acceptance test.
##
## Asserts that each Linux per-backend launcher's frame source produces
## *real demo content* rather than a stub gradient. The launcher
## binaries themselves are exercised by the Playwright spec; this
## headless test re-creates the same frame-source plumbing in-process
## so we can scrape the cell grid (TUI) and pixel buffers (GPUI / Freya
## / web) without spawning child processes.

import std/[strutils, unicode, unittest]

import isonim/core/owner
import isonim_tui
import isonim_gpui/renderer as gpui_renderer
import isonim_gpui/bindings as gpui_bindings
import isonim_freya/renderer as freya_renderer
import isonim_freya/bindings as freya_bindings

import isonim_render_serve/adapters/tui_adapter
import isonim_render_serve/adapters/gpui_adapter
import isonim_render_serve/adapters/freya_adapter
import isonim_render_serve/packet

import task_app/core/vm as task_vm
import task_app/main_tui as task_tui
import task_app/main_gpui as task_gpui
import task_app/main_freya as task_freya

import settings_app/core/vm as settings_vm
import settings_app/core/demo_catalog
import settings_app/main_tui as settings_tui
import settings_app/main_freya as settings_freya

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc bufferContainsString(buf: ScreenBuffer; needle: string): bool =
  ## Walk the harness's cell grid and return true iff `needle` appears
  ## on some row (left-to-right) as a substring formed by the cell
  ## runes.
  for r in 0 ..< buf.rowsCount:
    var row = ""
    for c in 0 ..< buf.cols:
      let cell = buf[r, c]
      if cell.width > 0:
        row.add toUTF8(cell.rune)
      else:
        row.add ' '
    if needle in row:
      return true
  return false

proc framesByteEqual(a, b: packet.Frame): bool =
  a.width == b.width and a.height == b.height and a.pixels == b.pixels

proc countNonBackgroundPixels(f: packet.Frame; bgR, bgG, bgB: uint8): int =
  ## Count the pixels that are not the adapter's initial background.
  var i = 0
  let stride = 4
  while i < f.pixels.len:
    if f.pixels[i] != bgR or f.pixels[i + 1] != bgG or f.pixels[i + 2] != bgB:
      inc result
    i += stride

# ---------------------------------------------------------------------------
# TUI: the rasterized frame must carry sample task / settings text.
# ---------------------------------------------------------------------------

suite "EX-M14 Gap 1 — TUI adapter streams real demo content":

  test "task_app: rasterized frame includes a sample task name from vm.tasks":
    createRoot do (dispose: proc()):
      let h = newTerminalTestHarness(80, 24)
      let vm = newTaskAppVM()
      vm.addTask("Buy groceries")
      vm.addTask("Walk the dog")
      vm.addTask("Ship EX-M14")
      discard task_tui.runTaskApp(h, vm)
      h.flush()

      # The harness's screen buffer must contain at least one of the
      # seeded task names: this is the "scrape produces real demo
      # text" assertion the EX-M14 acceptance demands.
      let buf = h.screenBuffer
      check bufferContainsString(buf, "Buy groceries") or
            bufferContainsString(buf, "Walk the dog") or
            bufferContainsString(buf, "Ship EX-M14")

      # Now wrap in the TUI frame source and confirm rasterization
      # produces a non-empty pixel buffer.
      let capturedH = h
      let src = newTuiFrameSource(
        proc(): ScreenBuffer {.gcsafe.} =
          {.cast(gcsafe).}: capturedH.screenBuffer,
        80, 24)
      let frame = src.renderFrame()
      check frame.width == 80 * 8
      check frame.height == 24 * 12
      check countNonBackgroundPixels(frame, 0x0Au8, 0x10u8, 0x1Eu8) > 0
      dispose()

  test "settings_app: rasterized TUI frame includes a catalog group label":
    createRoot do (dispose: proc()):
      let h = newTerminalTestHarness(80, 24)
      let catalog = buildDemoSettingsCatalog()
      let vm = newSettingsVM(catalog)
      discard settings_tui.runSettingsApp(h, vm)
      h.flush()

      let buf = h.screenBuffer
      # The demo catalog ships an "Appearance" group; the TUI shell
      # renders the group list as cells.
      check bufferContainsString(buf, "Appearance") or
            bufferContainsString(buf, "Editor") or
            bufferContainsString(buf, "Notifications")

      let capturedH = h
      let src = newTuiFrameSource(
        proc(): ScreenBuffer {.gcsafe.} =
          {.cast(gcsafe).}: capturedH.screenBuffer,
        80, 24)
      let frame = src.renderFrame()
      check countNonBackgroundPixels(frame, 0x0Au8, 0x10u8, 0x1Eu8) > 0
      dispose()

# ---------------------------------------------------------------------------
# GPUI / Freya: the adapter must produce a non-empty pixel buffer drawn
# from the actual demo tree, not a stub gradient.
# ---------------------------------------------------------------------------

suite "EX-M14 Gap 1 — graphical adapters stream real demo trees":

  test "GPUI adapter rasterizes the headless task_app tree to RGBA":
    createRoot do (dispose: proc()):
      gpui_bindings.gpui_reset_tree()
      gpui_renderer.resetCallbacks()
      let r = GpuiRenderer()
      let vm = newTaskAppVM()
      vm.addTask("Buy groceries")
      vm.addTask("Walk the dog")
      let root = task_gpui.buildTaskApp(r, vm)
      check root != nil

      let src = newGpuiFrameSource(r, root, 320, 200)
      let frame = src.renderFrame()
      check frame.width == 320
      check frame.height == 200
      # The GPUI adapter initialises the canvas to dark-grey (0x18) and
      # paints coloured rects per element; with two tasks the tree has
      # > 1 element, so the rasterized frame must have at least one
      # non-background pixel.
      check countNonBackgroundPixels(frame, 0x18u8, 0x18u8, 0x18u8) > 0
      dispose()

  test "Freya adapter rasterizes the headless task_app tree to RGBA":
    createRoot do (dispose: proc()):
      freya_bindings.freya_reset_tree()
      freya_renderer.resetCallbacks()
      let r = FreyaRenderer()
      let vm = newTaskAppVM()
      vm.addTask("Buy groceries")
      vm.addTask("Walk the dog")
      let root = task_freya.buildTaskApp(r, vm)
      check root != nil

      let src = newFreyaFrameSource(r, root, 320, 200)
      let frame = src.renderFrame()
      check frame.width == 320
      check frame.height == 200
      check countNonBackgroundPixels(frame, 0x18u8, 0x18u8, 0x18u8) > 0
      dispose()

  test "Freya adapter rasterizes the headless settings_app tree to RGBA":
    ## EX-M15: proves the Freya settings composition root mounts
    ## successfully and yields a non-empty rasterised frame. Pre-EX-M15
    ## the Freya launcher silently fell back to task_app for the
    ## settings demo; the dispatch wiring tested by the bridge spec
    ## relies on this composition returning a real tree.
    createRoot do (dispose: proc()):
      freya_bindings.freya_reset_tree()
      freya_renderer.resetCallbacks()
      let r = FreyaRenderer()
      let catalog = buildDemoSettingsCatalog()
      let vm = newSettingsVM(catalog)
      let root = settings_freya.buildSettingsApp(r, vm)
      check root != nil

      let src = newFreyaFrameSource(r, root, 320, 200)
      let frame = src.renderFrame()
      check frame.width == 320
      check frame.height == 200
      check countNonBackgroundPixels(frame, 0x18u8, 0x18u8, 0x18u8) > 0
      dispose()

# ---------------------------------------------------------------------------
# Cross-backend distinctness — every backend's frame must be byte-distinct
# from every other so the Playwright spec's "four distinct preview hashes"
# claim is grounded.
# ---------------------------------------------------------------------------

suite "EX-M14 Gap 1 — backends produce byte-distinct frames":

  test "TUI vs GPUI vs Freya frames are pairwise byte-distinct":
    var tuiFrame, gpuiFrame, freyaFrame: packet.Frame

    createRoot do (dispose: proc()):
      let h = newTerminalTestHarness(80, 24)
      let vm = newTaskAppVM()
      vm.addTask("Buy groceries")
      vm.addTask("Walk the dog")
      discard task_tui.runTaskApp(h, vm)
      h.flush()
      let capturedH = h
      let src = newTuiFrameSource(
        proc(): ScreenBuffer {.gcsafe.} =
          {.cast(gcsafe).}: capturedH.screenBuffer,
        80, 24)
      tuiFrame = src.renderFrame()
      dispose()

    createRoot do (dispose: proc()):
      gpui_bindings.gpui_reset_tree()
      gpui_renderer.resetCallbacks()
      let r = GpuiRenderer()
      let vm = newTaskAppVM()
      vm.addTask("Buy groceries")
      vm.addTask("Walk the dog")
      let root = task_gpui.buildTaskApp(r, vm)
      let src = newGpuiFrameSource(r, root, tuiFrame.width, tuiFrame.height)
      gpuiFrame = src.renderFrame()
      dispose()

    createRoot do (dispose: proc()):
      freya_bindings.freya_reset_tree()
      freya_renderer.resetCallbacks()
      let r = FreyaRenderer()
      let vm = newTaskAppVM()
      vm.addTask("Buy groceries")
      vm.addTask("Walk the dog")
      let root = task_freya.buildTaskApp(r, vm)
      let src = newFreyaFrameSource(r, root, tuiFrame.width, tuiFrame.height)
      freyaFrame = src.renderFrame()
      dispose()

    check not framesByteEqual(tuiFrame, gpuiFrame)
    check not framesByteEqual(tuiFrame, freyaFrame)
    check not framesByteEqual(gpuiFrame, freyaFrame)

  test "EX-M15: Freya task_app vs Freya settings_app frames are byte-distinct":
    ## Pre-EX-M15, the Freya launcher's `--demo=settings` branch fell
    ## back to task_app and produced byte-identical pixels to the task
    ## demo. The launcher's settings branch now wires the
    ## `settings_app/main_freya` composition root, which builds a
    ## visibly distinct card-stack tree. Rasterising both trees through
    ## the same adapter at the same dimensions must therefore yield
    ## byte-distinct frame buffers.
    var freyaTaskFrame, freyaSettingsFrame: packet.Frame

    createRoot do (dispose: proc()):
      freya_bindings.freya_reset_tree()
      freya_renderer.resetCallbacks()
      let r = FreyaRenderer()
      let vm = newTaskAppVM()
      vm.addTask("Buy groceries")
      vm.addTask("Walk the dog")
      let root = task_freya.buildTaskApp(r, vm)
      let src = newFreyaFrameSource(r, root, 320, 200)
      freyaTaskFrame = src.renderFrame()
      dispose()

    createRoot do (dispose: proc()):
      freya_bindings.freya_reset_tree()
      freya_renderer.resetCallbacks()
      let r = FreyaRenderer()
      let catalog = buildDemoSettingsCatalog()
      let vm = newSettingsVM(catalog)
      let root = settings_freya.buildSettingsApp(r, vm)
      let src = newFreyaFrameSource(r, root, 320, 200)
      freyaSettingsFrame = src.renderFrame()
      dispose()

    check not framesByteEqual(freyaTaskFrame, freyaSettingsFrame)
