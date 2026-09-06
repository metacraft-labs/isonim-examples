## editor/backends/common.nim — shared launcher plumbing for the
## isonim-examples demo bridges.
##
## EX-M14: each per-renderer launcher binary under
## `editor/backends/{tui,web,gpui,freya}.nim` is a thin shim that
## (1) parses the launcher CLI (`--port`, `--demo`, ...), (2) builds
## a real demo composition (TaskAppVM / SettingsVM mounted in the
## per-renderer Layer-4 root), (3) wraps the resulting tree in the
## matching `isonim-render-serve` adapter, and (4) hands the resulting
## `AnyFrameSource` to the bridge so the editor's streaming-preview
## widget can subscribe.
##
## Each renderer launcher provides its own `runDemoBridge(demo)` proc
## because the frame source type, demo build proc, and required
## globals (callback registry, shim trees) differ per renderer. This
## module owns only the CLI parsing + the bridge boot.

import std/[asyncdispatch, options, os, strutils]

import isonim_render_serve

type
  LauncherConfig* = object
    backend*: string  ## Backend identifier — overrides the CLI default.
    port*: int
    width*: int
    height*: int
    fps*: int
    staticDir*: string
    demo*: string     ## "task" | "settings" — selects which demo to mount.
    encoder*: string  ## EPP-M5 + ELT-M8: encoder selection.
                       ## "" / "raw_rgba" → F-packet baseline (EPP-M4).
                       ## "h264" / "h264_videotoolbox" → V-packet path
                       ## (EPP-M5; VideoToolbox H.264).
                       ## "webp" / "webp_lossless" → W-packet path
                       ## (ELT-M8; libwebp lossless via ffmpeg) with
                       ## per-frame transport selection (W for static
                       ## UI, V for animation, F for the seed).
                       ## "auto" → prefer WebP, degrade to H.264, then
                       ## raw RGBA per host capability.
                       ## The launcher composition validates against
                       ## host capability via ``selectEncoderKind`` and
                       ## degrades silently when the preferred path is
                       ## unavailable.
    bitrate*: int     ## EPP-M5: H.264 ``AverageBitRate`` target in
                       ## bits/sec. Defaults to 2_000_000 (2 Mbps)
                       ## matching the EPP-M5 brief. Ignored when
                       ## the launcher resolves to ``ekRawRgba`` or
                       ## ``ekWebP``.
    webpCompressionLevel*: int
                       ## ELT-M8: libwebp ``-compression_level`` knob
                       ## (1..6). 0 leaves the default
                       ## (``DefaultWebPCompressionLevel`` = 3 per the
                       ## ELT-M7 recommendation). Ignored when the
                       ## launcher resolves to anything other than
                       ## ``ekWebP``.

proc parseLauncherArgs*(backendOverride: string;
                        defaultDemo = "task"): LauncherConfig =
  ## Parse argv against the flags every launcher accepts. The
  ## `--backend` flag is accepted so the same binary can be re-purposed
  ## as a generic bridge in tests, but each launcher hard-codes a
  ## sensible default in `backendOverride`.
  result = LauncherConfig(
    backend: backendOverride,
    port: 0,
    width: 0,
    height: 0,
    fps: 12,
    staticDir: "static",
    demo: defaultDemo,
    encoder: "",
    bitrate: 2_000_000,
    webpCompressionLevel: 0)
  var i = 1
  while i <= paramCount():
    let arg = paramStr(i)
    case arg
    of "--port":
      inc i; result.port = parseInt(paramStr(i))
    of "--backend":
      inc i; result.backend = paramStr(i)
    of "--width":
      inc i; result.width = parseInt(paramStr(i))
    of "--height":
      inc i; result.height = parseInt(paramStr(i))
    of "--fps":
      inc i; result.fps = parseInt(paramStr(i))
    of "--static":
      inc i; result.staticDir = paramStr(i)
    of "--component":
      # Accepted for forward compat with `launchBridge` argv shaping.
      inc i; discard
    of "--encoder":
      # EPP-M5: ``--encoder h264`` opts into the VideoToolbox path;
      # ``--encoder raw_rgba`` keeps the F-packet baseline (default).
      # ELT-M8: ``--encoder webp`` opts into the W-packet path with
      # per-frame transport selection; ``--encoder auto`` picks WebP
      # if libwebp is reachable, falling back to H.264 then raw RGBA.
      inc i; result.encoder = paramStr(i)
    of "--bitrate":
      inc i; result.bitrate = parseInt(paramStr(i))
    of "--webp-compression-level":
      # ELT-M8: ffmpeg libwebp ``-compression_level`` knob. Honoured
      # only when the launcher resolves to ekWebP. Default (0) =
      # the facade-side default = ELT-M7's recommended 3.
      inc i; result.webpCompressionLevel = parseInt(paramStr(i))
    else:
      # Accept both `--demo=task` and `--demo task`.
      if arg.startsWith("--demo="):
        result.demo = arg.substr(len("--demo="))
      elif arg == "--demo":
        inc i; result.demo = paramStr(i)
      elif arg.startsWith("--encoder="):
        result.encoder = arg.substr(len("--encoder="))
      elif arg.startsWith("--bitrate="):
        result.bitrate = parseInt(arg.substr(len("--bitrate=")))
      elif arg.startsWith("--webp-compression-level="):
        result.webpCompressionLevel = parseInt(
          arg.substr(len("--webp-compression-level=")))
      else:
        # Tolerate unknown flags so adapter authors can extend the CLI
        # per-renderer without forcing a global recompile.
        discard
    inc i

proc resolveStaticDir*(cfgStatic: string): string =
  ## Pick a usable directory to serve the canvas client. Prefer the
  ## launcher's `--static` flag, otherwise fall back to the
  ## `isonim-render-serve` repo's `static/` directory next door.
  if cfgStatic.len > 0 and dirExists(cfgStatic):
    return cfgStatic
  const fallback = currentSourcePath().parentDir.parentDir.parentDir /
    ".." / "isonim-render-serve" / "static"
  if dirExists(fallback):
    return fallback
  cfgStatic # last resort — bridge will 404 the canvas page

proc resolveEncoderKind*(cfg: LauncherConfig): EncoderKind =
  ## Map the CLI string to an ``EncoderKind`` and degrade to
  ## ``ekRawRgba`` (or ``ekH264`` when the host supports it) for
  ## codecs that aren't available on this build.
  ##
  ## ELT-M8 extends the recognised values:
  ##   "webp", "webp_lossless" → ekWebP (per-frame W/V/F selector;
  ##     SHIP tier per the ELT-M7 synthesis report).
  ##   "auto" → prefer ekWebP; ``selectEncoderKind`` degrades to
  ##     ekH264 or ekRawRgba based on host capability.
  let prefer =
    case cfg.encoder
    of "h264", "h264_videotoolbox", "vt":
      ekH264
    of "webp", "webp_lossless":
      ekWebP
    of "auto":
      # ELT-M8 auto-mode: WebP is the SHIP tier per the ELT-M7
      # synthesis. ``selectEncoderKind(ekWebP)`` degrades via the
      # facade's standard chain (ekWebP → ekH264 → ekRawRgba).
      ekWebP
    else:
      ekRawRgba
  selectEncoderKind(prefer)

proc effectiveEncoderKind*(cfg: LauncherConfig;
                          explicit: Option[EncoderKind]): EncoderKind =
  ## Which encoder the bridge should actually run.
  ##
  ## An ``explicit`` value from the launcher wins — cocoa and gpui
  ## post-process ``resolveEncoderKind``'s answer against an H.264
  ## handle they may or may not have been able to construct, so they
  ## must be able to override.  Everyone else passes ``none`` and gets
  ## the user's ``--encoder`` flag honoured.
  ##
  ## The ``Option`` is load-bearing.  ``runDemoBridgeWith`` used to
  ## declare ``encoder: EncoderKind = ekRawRgba``, so a launcher that
  ## simply did not mention the argument — freya, web, tui, tui_term,
  ## ios, android: six of the eight — silently forced raw RGBA and
  ## discarded the flag the CLI had already parsed.  Omission now means
  ## "ask the CLI", which is the behaviour a launcher author expects
  ## when they say nothing at all.
  if explicit.isSome: explicit.get
  else: resolveEncoderKind(cfg)

proc runDemoBridgeWith*(cfg: LauncherConfig; source: AnyFrameSource;
                       elementTree: ElementTreeProvider = nil;
                       inputSink: AnyInputSink = nil;
                       capturePath: string = "";
                       encoder: Option[EncoderKind] = none(EncoderKind);
                       encoderHandle: H264EncoderHandle = nil;
                       streamElementTreeDelta: bool = false) =
  ## Boot the WebSocket bridge against an already-constructed frame
  ## source. Launchers call this after they've assembled a real demo
  ## frame source (TUI rasterizer / GPUI adapter / Freya adapter / web
  ## stub bridge).
  ##
  ## EX-M23: launchers that advertise the `elementTree` capability
  ## pass a non-nil `ElementTreeProvider` so the bridge emits one
  ## manifest per connect + one per (id, bounds)-change. Launchers
  ## that need to react to inbound I packets pass a non-nil
  ## `inputSink` (e.g. the TUI launcher's resize-aware sink that
  ## forwards `iekResize` events to the harness).
  ##
  ## EPP-M4: ``capturePath`` is the optional self-describing
  ## identifier the Cocoa launcher passes (``"metal"`` /
  ## ``"appkit"``) so the browser-side e2e test can verify which
  ## capture helper produced the streamed frames. Other launchers
  ## leave it empty.
  ##
  ## ETS-M3 Part B: ``streamElementTreeDelta`` enables the
  ## ``element-tree-delta`` M-subtype wire path. Each per-backend
  ## launcher passes ``true`` under the ``-d:withElementTreeDelta``
  ## gate (default-on per config.nims) so the bridge advertises the
  ## ``e/element-tree`` transport in its hello capability bag. Until
  ## the browser-side shim echoes the token back in its hello-accept
  ## reply (ETS-M4), the bridge stays on the legacy full-manifest
  ## path — gate-on-but-no-accept is bit-for-bit identical to the
  ## pre-ETS-M2 wire shape, preserving backward compatibility.
  ##
  ## ``encoder`` is an ``Option`` on purpose. Passing ``none`` (which
  ## is what a launcher that never mentions the argument does) means
  ## "honour the CLI's ``--encoder``", not "force raw RGBA". The old
  ## ``EncoderKind = ekRawRgba`` default made six of the eight
  ## launchers silently discard a flag the CLI had already parsed —
  ## ``isonim-examples-web --encoder webp`` reported
  ## ``encoder=raw_rgba`` with no diagnostic. Launchers that must
  ## override the CLI (cocoa and gpui post-process the resolved kind
  ## against an H.264 handle) pass ``some(...)`` explicitly.
  let resolvedEncoder = effectiveEncoderKind(cfg, encoder)
  let sink =
    if inputSink != nil: inputSink
    else: newBufferedInputSink().toAny()
  let bridgeCfg = BridgeConfig(
    port: Port(cfg.port),
    staticDir: resolveStaticDir(cfg.staticDir),
    backend: cfg.backend,
    frameIntervalMs: max(1, 1000 div cfg.fps),
    maxFrames: 0,
    inputSink: sink,
    frameSource: source,
    elementTree: elementTree,
    streamElementTreeDelta: streamElementTreeDelta,
    capturePath: capturePath,
    encoder: resolvedEncoder,
    encoderHandle: encoderHandle,
    encoderWebpCompressionLevel: cfg.webpCompressionLevel)
  let s = newServer(bridgeCfg)
  echo "isonim-examples-", cfg.backend, " demo=", cfg.demo,
    " listening on http://127.0.0.1:", cfg.port,
    " (", source.width, "x", source.height, " @ ", cfg.fps, " fps",
    ", encoder=", encoderKindName(resolvedEncoder), ")"
  waitFor s.serve()
