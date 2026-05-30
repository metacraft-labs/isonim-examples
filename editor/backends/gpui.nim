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

proc runGpuiDemo(cfgIn: LauncherConfig) =
  # EMC-M2 (Option A): when no ``--encoder`` is on the CLI, default
  # to ``ekWebP`` for the GPUI launcher. The EMC-M1 audit
  # (``isonim/docs/gpui-serialisation-audit-EMC-M1.md``) recommends
  # this as the FUH-M5-effort-scale mitigation that closes the 50 ms
  # frame-latency gate + the 3 click-response cells the FUH-M8 matrix
  # surfaced. ``resolveEncoderKind`` below maps ``"auto"`` to ``ekWebP``
  # whenever the host has libwebp reachable; degrades to ``ekRawRgba``
  # otherwise (so the launcher is safe to invoke on a host without
  # libwebp). Pass ``--encoder raw_rgba`` to opt back into the legacy
  # F-packet baseline for A/B comparison.
  var cfg = cfgIn
  when defined(withCodecWebP):
    if cfg.encoder.len == 0:
      cfg.encoder = "auto"
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
    # (``gpui_adapter.buildGpuiElementTreeManifest``).
    #
    # EPP-M12: the legacy ``hitTester`` routed every click to the
    # composition root, which has no registered ``"click"`` handler —
    # so the click was silently dropped and no VM mutation followed.
    # The new ``hitChain`` callback walks the same ``buildLayoutRects``
    # the rasteriser paints from and returns every shadow-tree node
    # whose rect contains the click coordinate (deepest first). The
    # input adapter then fires ``"click"`` on each candidate; the
    # one with a registered Nim closure (filter pill, task row,
    # add button) handles the click, mutates the VM, and the
    # reactive graph repaints on the next frame.
    let capturedHitRoot = capturedRoot
    let hitTester = proc(x, y: int): GpuiElement {.gcsafe.} =
      {.cast(gcsafe).}:
        capturedHitRoot
    let hitChain = proc(x, y: int): seq[GpuiElement] {.gcsafe.} =
      {.cast(gcsafe).}:
        hitTestPath(capturedHitRoot, dynamicW, dynamicH, x, y)
    let inputAdapter = newGpuiInputSink(hitTester, hitChain)
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

    # EMC-M2 (Option A from the EMC-M1 audit). Resolve the encoder
    # preference against host capability, mirroring the cocoa launcher
    # at ``backends/cocoa.nim:136``. The FUH-M8 matrix observed 55-59 ms
    # frame latency on the GPUI raw-RGBA path (over the 50 ms gate);
    # the EMC-M1 audit at ``isonim/docs/gpui-serialisation-audit-EMC-M1.md``
    # showed the shim FFI dominates (~42-44 ms median) but the
    # post-shim wire-encode + browser ``putImageData`` accounts for
    # the remaining ~9-13 ms. Switching the GPUI launcher's default
    # encoder to ``ekWebP`` (FUH-M5 in-process libwebp, ~5-7 ms encode
    # + ~50-100 KB wire payload vs ~4-5 MiB raw RGBA) trims that
    # tail and is the FUH-M5-effort-scale mitigation the audit
    # recommends.
    #
    # With ``-d:withCodecWebP`` on (default per
    # ``isonim-examples/config.nims``), unspecified ``--encoder``
    # resolves through the same ``resolveEncoderKind`` table the
    # cocoa launcher uses. ``--encoder webp`` (and ``--encoder auto``)
    # both end up at ``ekWebP``; ``--encoder raw_rgba`` keeps the
    # legacy F-packet baseline for direct A/B comparison.
    let encoderKind = resolveEncoderKind(cfg)
    # GPUI never runs the VideoToolbox H.264 encoder (the audit's
    # measurement scope is Metal-headless render + libwebp encode);
    # the H264 handle stays nil and the bridge degrades to raw RGBA
    # if the launcher is ever invoked with ``--encoder h264``.
    var encoderHandle: H264EncoderHandle = nil
    let resolvedEncoder =
      case encoderKind
      of ekWebP: ekWebP
      of ekH264: ekRawRgba
      of ekRawRgba: ekRawRgba

    # ETS-M3 Part B: gate the ``element-tree-delta`` wire path on
    # at launcher boot when the ``-d:withElementTreeDelta`` define is
    # set (default-on per config.nims, dormant-code-on-loss pattern
    # mirrors ELT-M8's ``-d:withCodecWebP`` gate). With the gate on,
    # the bridge advertises ``e/element-tree`` in the hello capability
    # bag; the browser-side shim opt-in lands at ETS-M4. Until then,
    # gate-on-no-accept keeps the legacy full-manifest wire shape.
    var streamElementTreeDelta = false
    when defined(withElementTreeDelta):
      streamElementTreeDelta = true
    runDemoBridgeWith(cfg, src.toAny(), provider, storySink.toAnyInputSink(),
                      encoder = resolvedEncoder,
                      encoderHandle = encoderHandle,
                      streamElementTreeDelta = streamElementTreeDelta)
    dispose()

proc runDemoBridge*(backend: string) =
  let cfg = parseLauncherArgs(backend)
  runGpuiDemo(cfg)

when isMainModule:
  runDemoBridge("gpui")
