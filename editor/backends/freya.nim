## editor/backends/freya.nim — Freya-backend launcher for the demo editor.
##
## Constructs a real `TaskAppVM`, builds the headless Freya tree via
## the demo's Layer-4 composition root, and streams the resulting
## element tree to the bridge through
## `isonim_render_serve/adapters/freya_adapter`. The Freya port for the
## settings app has not yet landed (`settings_app` ships only TUI / web
## / GPUI roots), so `--demo=settings` falls back to task_app on Freya
## until EX-M*+ adds it; this matches the per-renderer scope tracked in
## `codetracer-specs/Front-Ends/IsoNim/isonim-render-stream.status.org`.

import isonim_freya/renderer as freya_renderer
import isonim_freya/bindings as freya_bindings
import isonim/core/owner

import isonim_render_serve/adapters/freya_adapter

import task_app/core/vm as task_vm
import task_app/main_freya as task_freya

import ./common

const
  DefaultWidth = 800
  DefaultHeight = 600

proc runFreyaDemo(cfg: LauncherConfig) =
  let w = if cfg.width > 0: cfg.width else: DefaultWidth
  let h = if cfg.height > 0: cfg.height else: DefaultHeight

  createRoot proc(dispose: proc()) =
    freya_bindings.freya_reset_tree()
    freya_renderer.resetCallbacks()
    let r = FreyaRenderer()
    let vm = newTaskAppVM()
    vm.addTask("Buy groceries")
    vm.addTask("Walk the dog")
    vm.addTask("Ship EX-M14")
    let root = task_freya.buildTaskApp(r, vm)
    let src = newFreyaFrameSource(r, root, w, h)
    runDemoBridgeWith(cfg, src.toAny())
    dispose()

proc runDemoBridge*(backend: string) =
  let cfg = parseLauncherArgs(backend)
  runFreyaDemo(cfg)

when isMainModule:
  runDemoBridge("freya")
