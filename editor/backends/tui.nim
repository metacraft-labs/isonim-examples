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
##
## EX-M23 (TUI slice). The launcher additionally wires an
## `ElementTreeProvider` into the bridge so the editor's
## preview-canvas can hit-test pointer events back to component
## paths. The provider walks the harness's compositor on every
## bridge tick and emits a manifest via `tui_adapter.buildTui-
## ElementTreeManifest`; the bridge handles cadence (emit on
## change, never on idle frames). The Layer-1 leaves under
## `task_app/tui/leaves.nim` and `settings_app/tui/leaves.nim`
## annotate every visible node with `data-component-path`.

import isonim_tui
import isonim/core/owner

import isonim_render_serve
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

    # EX-M23: the manifest provider. The closure captures `harness`
    # by reference; on every call we flush the compositor (cheap when
    # nothing has changed — the harness's flush is idempotent against
    # the reactive graph's fixpoint) and read the latest layout.
    var dynamicCols = cols
    var dynamicRows = rows
    let provider = ElementTreeProvider(
      buildImpl: proc(): ElementTreeManifest {.gcsafe.} =
        {.cast(gcsafe).}:
          capturedHarness.flush()
          buildTuiElementTreeManifest(capturedHarness,
            dynamicCols, dynamicRows, DefaultCellW, DefaultCellH))

    # EX-M23: minimal real input dispatch — resize events from the
    # editor surface flow through to the harness so a resize-driven
    # state change actually mutates the manifest. (Click / key
    # dispatch follows the same shape but isn't required to land
    # this milestone; the editor's hit-test path uses the manifest
    # to decide what to select before any click I packets fly.)
    let resizingSink = newAnyInputSink(
      proc(event: InputEvent) {.gcsafe.} =
        if event.kind != iekResize: return
        let newCols = max(10, event.width div DefaultCellW)
        let newRows = max(8, event.height div DefaultCellH)
        if newCols == dynamicCols and newRows == dynamicRows: return
        {.cast(gcsafe).}:
          capturedHarness.resize(newCols, newRows)
          dynamicCols = newCols
          dynamicRows = newRows
          capturedHarness.flush())
    runDemoBridgeWith(cfg, src.toAny(), provider, resizingSink)
    dispose()

proc runDemoBridge*(backend: string) =
  let cfg = parseLauncherArgs(backend)
  runTuiDemo(cfg)

when isMainModule:
  runDemoBridge("tui")
