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

import std/[asyncdispatch, os, strutils]

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
    demo: defaultDemo)
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
    else:
      # Accept both `--demo=task` and `--demo task`.
      if arg.startsWith("--demo="):
        result.demo = arg.substr(len("--demo="))
      elif arg == "--demo":
        inc i; result.demo = paramStr(i)
      else:
        # Tolerate unknown flags so adapter authors can extend the CLI
        # per-renderer without forcing a global recompile.
        discard
    inc i

proc newNoopFrameSource*(width, height: int): AnyFrameSource =
  ## RS-M13b: render-tree launchers don't emit F packets but the
  ## bridge config still requires a frame source so it can read
  ## `(width, height)` for the hello packet. This helper returns an
  ## `AnyFrameSource` whose `renderFrameImpl` returns an empty 1×1
  ## RGBA frame; with `rendererSurface == "tree"` the bridge never
  ## calls it, so the empty frame is unreachable on the wire.
  let w = max(1, width)
  let h = max(1, height)
  newAnyFrameSource(w, h,
    renderFrameImpl = proc(): Frame {.gcsafe.} =
      {.cast(gcsafe).}:
        Frame(kind: fkFull,
              flags: FrameFlags(isDiff: false, isVideo: false),
              width: 1, height: 1, pixels: @[0u8, 0, 0, 0xFF]),
    closeImpl = proc() {.gcsafe.} = discard)

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

proc runDemoBridgeWith*(cfg: LauncherConfig; source: AnyFrameSource;
                       elementTree: ElementTreeProvider = nil;
                       inputSink: AnyInputSink = nil;
                       renderTree: RenderTreeProvider = nil;
                       rendererSurface: string = "") =
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
  ## RS-M13b: launchers that ship a `RenderTreeProvider` pass it as
  ## the `renderTree` argument and set `rendererSurface = "tree"` so
  ## the bridge advertises both capability flags in `hello` and skips
  ## the F-packet stream entirely. The `source` arg still supplies
  ## the surface dimensions reported in `hello.initialSize` — the
  ## GPUI / Freya launchers wrap a no-op `AnyFrameSource` for that.
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
    renderTree: renderTree,
    rendererSurface: rendererSurface)
  let s = newServer(bridgeCfg)
  let surfaceLabel =
    if rendererSurface == "tree": "render-tree DOM"
    else: "pixels"
  echo "isonim-examples-", cfg.backend, " demo=", cfg.demo,
    " listening on http://127.0.0.1:", cfg.port,
    " (", source.width, "x", source.height, " @ ", cfg.fps, " fps, ",
    surfaceLabel, ")"
  waitFor s.serve()
