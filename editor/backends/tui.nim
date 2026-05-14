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
## EX-M23 (TUI slice). The launcher wires an `ElementTreeProvider`
## into the bridge so the editor's preview-canvas can hit-test
## pointer events back to component paths.
##
## RS-M12. The launcher wires a `StoryDispatchSink` on top of the
## existing resize sink so the editor's `select-story` /
## `apply-mutation` I packets reconfigure the live VM. The same
## composition root stays mounted across selects — re-seeding the VM
## drives the reactive graph to repaint the harness automatically.

import std/json

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
import ./story_dispatch_demo

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
    var taskAppVm: TaskAppVM
    var settingsAppVm: SettingsVM
    case cfg.demo
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
    let bufferGetter = proc(): ScreenBuffer {.closure, gcsafe.} =
      {.cast(gcsafe).}: capturedHarness.screenBuffer
    let src = newTuiFrameSource(bufferGetter, cols, rows,
                                DefaultCellW, DefaultCellH)

    var dynamicCols = cols
    var dynamicRows = rows
    let provider = ElementTreeProvider(
      buildImpl: proc(): ElementTreeManifest {.gcsafe.} =
        {.cast(gcsafe).}:
          capturedHarness.flush()
          buildTuiElementTreeManifest(capturedHarness,
            dynamicCols, dynamicRows, DefaultCellW, DefaultCellH))

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
        capturedHarness.flush()
    let applyFn = proc(target, key: string; value: JsonNode;
                       scope: MutationScope) {.closure, gcsafe.} =
      {.cast(gcsafe).}:
        if demoIsSettings:
          applySettingsMutation(captSettingsVm, target, key, value, scope)
        else:
          applyTaskMutation(captTaskVm, target, key, value, scope)
        capturedHarness.flush()
    let storySink = newStoryDispatchSink(mountFn, applyFn,
                                         inner = resizingSink)
    runDemoBridgeWith(cfg, src.toAny(), provider, storySink.toAnyInputSink())
    dispose()

proc runDemoBridge*(backend: string) =
  let cfg = parseLauncherArgs(backend)
  runTuiDemo(cfg)

when isMainModule:
  runDemoBridge("tui")
