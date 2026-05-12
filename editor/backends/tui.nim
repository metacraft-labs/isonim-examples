## editor/backends/tui.nim — TUI-backend launcher for the demo editor.
##
## Constructs a real `TaskAppVM` or `SettingsVM`, mounts it inside an
## `isonim-tui` `TerminalTestHarness` via the demo's Layer-4
## composition root, and streams the harness's screen buffer to the
## bridge through `isonim_render_serve/adapters/tui_adapter`.
##
## Each emitted frame carries real demo content: task names from
## `task_app/core/vm`'s sample data (when `--demo=task`) or settings
## group/item labels from `settings_app/core/demo_catalog` (when
## `--demo=settings`).

import isonim_tui
import isonim/core/owner

import isonim_render_serve/adapters/tui_adapter

import task_app/core/vm as task_vm
import task_app/main_tui as task_tui
import settings_app/core/vm as settings_vm
import settings_app/core/demo_catalog
import settings_app/main_tui as settings_tui

import ./common

const
  DefaultCols = 80
  DefaultRows = 24
  DefaultCellW = 8
  DefaultCellH = 12

proc runTuiDemo(cfg: LauncherConfig) =
  let cols =
    if cfg.width > 0 and cfg.width >= DefaultCellW * 10:
      cfg.width div DefaultCellW
    else:
      DefaultCols
  let rows =
    if cfg.height > 0 and cfg.height >= DefaultCellH * 8:
      cfg.height div DefaultCellH
    else:
      DefaultRows

  createRoot proc(dispose: proc()) =
    let harness = newTerminalTestHarness(cols, rows)
    case cfg.demo
    of "settings":
      let catalog = buildDemoSettingsCatalog()
      let vm = newSettingsVM(catalog)
      discard settings_tui.runSettingsApp(harness, vm)
    else:
      # Task app: seed a few sample tasks so the rasterized frame
      # actually shows demo strings.
      let vm = newTaskAppVM()
      vm.addTask("Buy groceries")
      vm.addTask("Walk the dog")
      vm.addTask("Ship EX-M14")
      discard task_tui.runTaskApp(harness, vm)
    harness.flush()

    let capturedHarness = harness
    let bufferGetter = proc(): ScreenBuffer {.closure, gcsafe.} =
      {.cast(gcsafe).}: capturedHarness.screenBuffer
    let src = newTuiFrameSource(bufferGetter, cols, rows,
                                DefaultCellW, DefaultCellH)
    runDemoBridgeWith(cfg, src.toAny())
    dispose()

proc runDemoBridge*(backend: string) =
  let cfg = parseLauncherArgs(backend)
  runTuiDemo(cfg)

when isMainModule:
  runDemoBridge("tui")
