## editor/backends/web.nim — Web-backend launcher for the demo editor.
##
## The Web backend renders the demo in the editor's in-iframe `MockRenderer`
## path; no bridge frames are pulled for it in practice. We still register
## a launcher binary so the M57 left-edge strip's "spawn on click" UX has
## a consistent shape across every backend (and so anyone running
## `isonim-render-serve --backend web` against this binary gets a real
## process, not the stub gradient).
##
## The launcher constructs the web composition root against a
## `MockRenderer`, then paints a deterministic header band + per-task
## row stripe so the streamed frame is *visibly distinct* from the
## stub gradient even though the editor itself shows the iframe.

import isonim/core/owner
import isonim/testing/mock_dom

import isonim_render_serve

import task_app/core/vm as task_vm
import task_app/main_web as task_web
import settings_app/core/vm as settings_vm
import settings_app/core/demo_catalog
import settings_app/main_web as settings_web

import ./common

const
  DefaultWidth = 800
  DefaultHeight = 600

type
  WebFrameSource = ref object
    width, height: int
    summary: string  ## Demo-specific status string (e.g. "task_app: 3 tasks").

proc fontBand(pixels: var seq[byte]; w, h: int; row: int; r, g, b: uint8) =
  if row < 0 or row >= h: return
  var off = row * w * 4
  for _ in 0 ..< w:
    pixels[off] = r
    pixels[off + 1] = g
    pixels[off + 2] = b
    pixels[off + 3] = 0xFF'u8
    off += 4

proc renderWebFrame(src: WebFrameSource): Frame =
  ## Paint a deterministic colour layout: dark navy background +
  ## per-task horizontal accent stripes. The hash of the summary
  ## seeds the colours so settings-app vs task-app produce different
  ## visuals; the resulting frame is plain enough that the canvas
  ## ImageData hash differs from every other backend's frame.
  let w = src.width
  let h = src.height
  var pixels = newSeq[byte](w * h * 4)
  for i in 0 ..< (w * h):
    let off = i * 4
    pixels[off] = 0x18'u8
    pixels[off + 1] = 0x1F'u8
    pixels[off + 2] = 0x3A'u8
    pixels[off + 3] = 0xFF'u8
  # Header band — distinct accent so the web frame doesn't blend with
  # the TUI / GPUI / Freya outputs.
  for y in 0 ..< min(h, 24):
    fontBand(pixels, w, h, y, 0x3Bu8, 0x82u8, 0xF6u8)
  # Per-summary accent stripes (rough text-content fingerprint).
  for i in 0 ..< src.summary.len:
    let baseY = 32 + i * 6
    if baseY >= h: break
    let c = src.summary[i].uint8
    fontBand(pixels, w, h, baseY,
             ((c shl 1) and 0xFEu8) xor 0x80u8,
             ((c shl 2) and 0xFEu8) xor 0x40u8,
             ((c xor 0x5Au8) and 0xFEu8) xor 0xC0u8)
  Frame(kind: fkFull,
        flags: FrameFlags(isDiff: false, isVideo: false),
        width: w, height: h, pixels: pixels)

proc toAny(src: WebFrameSource): AnyFrameSource =
  let captured = src
  newAnyFrameSource(src.width, src.height,
    renderFrameImpl = proc(): Frame {.gcsafe.} =
      {.cast(gcsafe).}: renderWebFrame(captured),
    closeImpl = proc() {.gcsafe.} = discard)

proc runWebDemo(cfg: LauncherConfig) =
  let w = if cfg.width > 0: cfg.width else: DefaultWidth
  let h = if cfg.height > 0: cfg.height else: DefaultHeight

  createRoot proc(dispose: proc()) =
    let r = MockRenderer()
    var summary = ""
    case cfg.demo
    of "settings":
      let catalog = buildDemoSettingsCatalog()
      let vm = newSettingsVM(catalog)
      discard settings_web.buildSettingsApp(r, vm)
      summary = "settings_app: " & $catalog.groups.len & " groups"
    else:
      let vm = newTaskAppVM()
      vm.addTask("Buy groceries")
      vm.addTask("Walk the dog")
      vm.addTask("Ship EX-M14")
      discard task_web.buildTaskApp(r, vm)
      summary = "task_app: " & $vm.tasks.val.len & " tasks"
    let src = WebFrameSource(width: w, height: h, summary: summary)
    runDemoBridgeWith(cfg, src.toAny())
    dispose()

proc runDemoBridge*(backend: string) =
  let cfg = parseLauncherArgs(backend)
  runWebDemo(cfg)

when isMainModule:
  runDemoBridge("web")
