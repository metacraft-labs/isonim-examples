## editor/backends/tui_term.nim — RS-M13 native-terminal TUI launcher.
##
## Replaces the pixel TUI launcher (``editor/backends/tui.nim``) for
## editor-preview use. The launcher mounts the demo's TUI composition
## root inside a ``TerminalTestHarness``, streams the harness's ANSI
## escape-sequence bytes over the D/M/P transport (per
## ``isonim-tui-serve``'s packet framing), and emits element-tree M
## packets whose ``bounds`` are in cell coordinates with an explicit
## ``boundsUnit: "cells"`` tag.
##
## The editor's TUI-mount path consumes D bytes through an xterm.js
## ``Terminal`` instance and routes ``select-story`` /
## ``apply-mutation`` P packets through the same launcher StoryDispatch
## callbacks the pixel TUI launcher used at RS-M12. Field order on the
## P body is byte-identical to RS-M12's I body so the editor's
## existing encoders stay shared.
##
## CLI surface mirrors the pixel TUI launcher:
##
##   --port <int>     bind 127.0.0.1:<port> (required; default 8112)
##   --demo task|settings  pick which demo composition mounts
##   --cols <int>     terminal columns (default 80)
##   --rows <int>     terminal rows (default 24)
##   --fps <int>      frame tick rate in Hz (default 12)
##   --backend <id>   accepted for forward-compat (default "tui-term")

import std/[asyncdispatch, json, os, strutils, tables]

import isonim_tui
import isonim_tui/compositor
import isonim_tui/testing/harness
import isonim_tui/renderer
import isonim/core/owner

# Force a full ANSI repaint from the harness. Setting
# ``compositor.initialPainted = false`` puts the next ``paint()`` back
# on the full-paint branch (``driver.paintBuffer(buf)``), which emits
# ``cursorTo(0, 0)`` + one positioned-strip per row covering the
# entire screen. Clearing the driver's byte log first means
# ``bytesEmitted`` after the flush carries exactly that snapshot.
proc fullRepaintBytes(h: TerminalTestHarness): string =
  h.compositor.initialPainted = false
  h.clearBytesEmitted()
  h.flush()
  h.bytesEmitted

import isonim_render_serve
import isonim_render_serve/element_tree_attrs
import isonim_tui_serve

import task_app/core/vm as task_vm
import task_app/main_tui as task_tui
import settings_app/core/vm as settings_vm
import settings_app/core/demo_catalog
import settings_app/main_tui as settings_tui

import ./story_dispatch_demo
import ./tui_term_bridge

const
  # M-EVP-14 Wave R: bumped 80x24 → 100x30 to match the editor's
  # xterm.js host (isonim@4b2b5eb increased the cell grid so the TUI
  # demo fills the preview pane instead of clustering top-left).
  DefaultCols = 100
  DefaultRows = 30
  DefaultFps = 12
  DefaultPort = 8112
  DefaultBackend = "tui-term"

type
  LauncherArgs = object
    port: int
    cols: int
    rows: int
    fps: int
    demo: string
    backend: string

proc parseArgs(): LauncherArgs =
  result = LauncherArgs(
    port: DefaultPort,
    cols: DefaultCols,
    rows: DefaultRows,
    fps: DefaultFps,
    demo: "task",
    backend: DefaultBackend)
  var i = 1
  while i <= paramCount():
    let arg = paramStr(i)
    case arg
    of "--port":
      inc i; result.port = parseInt(paramStr(i))
    of "--cols":
      inc i; result.cols = parseInt(paramStr(i))
    of "--rows":
      inc i; result.rows = parseInt(paramStr(i))
    of "--fps":
      inc i; result.fps = parseInt(paramStr(i))
    of "--backend":
      inc i; result.backend = paramStr(i)
    else:
      if arg.startsWith("--demo="):
        result.demo = arg.substr(len("--demo="))
      elif arg == "--demo":
        inc i; result.demo = paramStr(i)
      else:
        # Tolerate forward-compat flags from the editor's
        # `launchBridge` path (e.g. `--width`, `--height`,
        # `--component`, `--static`) without affecting behaviour.
        if arg.startsWith("--") and i + 1 <= paramCount():
          inc i
    inc i

# ---------------------------------------------------------------------------
# Manifest walker — cell-space variant of the pixel adapter's walker.
# ---------------------------------------------------------------------------

proc walkCellManifest(node: TerminalNode; c: Compositor;
                      root: TerminalNode;
                      acc: var seq[TuiElementEntry]) =
  if node == nil: return
  if ComponentPathAttr in node.attributes:
    let path = node.attributes[ComponentPathAttr]
    if path.len > 0:
      let region = layoutRegionFor(c, root, node.id)
      if region.width > 0 and region.height > 0:
        let kind =
          if ElementKindAttr in node.attributes:
            node.attributes[ElementKindAttr]
          else:
            ""
        acc.add TuiElementEntry(
          id: path,
          componentPath: path,
          kind: kind,
          bounds: TuiElementBounds(
            x: region.col, y: region.row,
            w: region.width, h: region.height))
  for child in node.children:
    walkCellManifest(child, c, root, acc)

proc buildCellManifest(harness: TerminalTestHarness;
                       cols, rows: int): TuiElementTreeManifest =
  result = TuiElementTreeManifest(
    frameSeq: 0,
    surfaceCols: cols,
    surfaceRows: rows,
    elements: @[])
  if harness == nil or harness.root == nil: return
  walkCellManifest(harness.root, harness.compositor, harness.root,
                   result.elements)

# ---------------------------------------------------------------------------
# Composition root.
# ---------------------------------------------------------------------------

proc runTuiTerm(args: LauncherArgs) =
  createRoot proc(dispose: proc()) =
    let harness = newTerminalTestHarness(args.cols, args.rows)
    var taskAppVm: TaskAppVM
    var settingsAppVm: SettingsVM
    case args.demo
    of "settings":
      let catalog = buildDemoSettingsCatalog()
      settingsAppVm = newSettingsVM(catalog)
      discard settings_tui.runSettingsApp(harness, settingsAppVm)
    else:
      taskAppVm = newTaskAppVM()
      seedTaskInboxDefaults(taskAppVm)
      discard task_tui.runTaskApp(harness, taskAppVm)
    harness.flush()

    let capturedHarness = harness
    var dynamicCols = args.cols
    var dynamicRows = args.rows

    # Display source: drain the harness's accumulated ANSI bytes. The
    # harness records every write to its headless driver into
    # ``bytesEmitted``; clearing after each pull means the next tick
    # only ships the delta. The very first emission of the *first*
    # connection carries the full initial-paint sequence (from
    # `harness.flush()` above); for the second + Nth connections the
    # bridge invokes ``initialDisplayProc`` below instead, which
    # forces a fresh full repaint.
    let displayProc: DisplaySource = proc(): string {.closure, gcsafe.} =
      {.cast(gcsafe).}:
        capturedHarness.flush()
        let bytes = capturedHarness.bytesEmitted
        capturedHarness.clearBytesEmitted()
        bytes

    # RS-M13 fix-cycle 1: per-connection full-repaint source. The
    # bridge calls this once at the start of every new WS connection
    # in lieu of ``displayProc`` so a freshly opened xterm.js consumer
    # sees the entire current screen state rather than just deltas
    # accumulated since the previous connection's last drain. The
    # mechanism: invalidate ``compositor.initialPainted`` so the next
    # ``flush()`` re-emits a full ANSI repaint (cursorTo(0,0) +
    # row-by-row positioned strips covering the entire surface), then
    # drain ``bytesEmitted``.
    let initialDisplayProc: InitialDisplaySource =
      proc(): string {.closure, gcsafe.} =
        {.cast(gcsafe).}:
          fullRepaintBytes(capturedHarness)

    let manifestProc: ManifestSource =
      proc(): TuiElementTreeManifest {.closure, gcsafe.} =
        {.cast(gcsafe).}:
          capturedHarness.flush()
          buildCellManifest(capturedHarness, dynamicCols, dynamicRows)

    let captTaskVm = taskAppVm
    let captSettingsVm = settingsAppVm
    let demoIsSettings = args.demo == "settings"
    let mountFn: TuiStoryMountFn =
      proc(storyId: string; properties: JsonNode) {.closure, gcsafe.} =
        {.cast(gcsafe).}:
          if demoIsSettings:
            applySettingsStory(captSettingsVm, storyId)
          else:
            applyTaskStory(captTaskVm, storyId)
          capturedHarness.flush()
    let applyFn: TuiApplyMutationFn =
      proc(target, key: string; value: JsonNode;
           scope: TuiMutationScope) {.closure, gcsafe.} =
        {.cast(gcsafe).}:
          # Translate to render-serve's MutationScope so the existing
          # demo dispatch can be re-used.
          let s = case scope
                  of tmsLocal: msLocal
                  of tmsShared: msShared
          if demoIsSettings:
            applySettingsMutation(captSettingsVm, target, key, value, s)
          else:
            applyTaskMutation(captTaskVm, target, key, value, s)
          capturedHarness.flush()

    let dispatch = newTuiStoryDispatchSink(mountFn, applyFn)
    let cfg = TerminalBridgeConfig(
      port: Port(args.port),
      frameIntervalMs: max(1, 1000 div max(1, args.fps)),
      displaySource: displayProc,
      initialDisplaySource: initialDisplayProc,
      manifestSource: manifestProc,
      storyDispatch: dispatch)
    let server = newTerminalBridgeServer(cfg)
    echo "isonim-examples-tui-term backend=", args.backend,
      " demo=", args.demo,
      " listening on http://127.0.0.1:", args.port,
      " (", args.cols, "x", args.rows, " cells @ ", args.fps, " fps)"
    waitFor server.serve()
    dispose()

proc runDemoBridge*(backend: string) =
  ## Compatibility shim for the editor's `BackendBinaryRegistry`
  ## launcher contract — the editor invokes the binary directly.
  let args = parseArgs()
  var a = args
  if backend.len > 0:
    a.backend = backend
  runTuiTerm(a)

when isMainModule:
  let args = parseArgs()
  runTuiTerm(args)
