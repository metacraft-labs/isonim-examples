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

## NH-M1. The mount no longer builds the tree imperatively under a bare
## `createRoot`: it goes through `isonim_tui`'s `renderTui`, i.e. through
## `isonim/renderers/native.renderNative`, so the insertion site is a
## `createRenderEffect` inside the reactive root. That is the seam NH-M2's
## hot-component proxy needs in order to replace the root component without
## disposing the root (and with it every signal, resource and cleanup the
## running demo owns).
##
## The accessor is wrapped in `staticNativeRoot` — the direct analogue of web
## `render()`'s `untrack(proc(): Node = code())`. This is not decoration:
## MEASURED with a tracked accessor against this exact composition root, the
## outer effect picks up build-time signal reads and `vm.setInputText` /
## `vm.setFilter` each rebuild and re-mount the WHOLE tree (render count
## 1 → 2 → 3), which would invalidate the root handle the frame source, the
## element-tree provider and the hit-tester all captured. Untracked, the
## render count stays 1 across the same mutations and every update flows
## through the leaves' own fine-grained effects, exactly as before NH-M1.
## `tests/test_render_native_launcher_entry.nim` keeps both halves measured.

import std/json

import isonim_tui

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

  block:
    let harness = newTerminalTestHarness(cols, rows)
    var taskAppVm: TaskAppVM
    var settingsAppVm: SettingsVM
    let mountSettings = cfg.demo == "settings"
    if mountSettings:
      let catalog = buildDemoSettingsCatalog()
      settingsAppVm = newSettingsVM(catalog)
    else:
      taskAppVm = newTaskAppVM()
      seedTaskInboxDefaults(taskAppVm)

    # NH-M1 reactive mount. The two resets reproduce, per branch, exactly what
    # the previous `runSettingsApp` / `runTaskApp` + `TerminalTestHarness.mount`
    # pair did: `mount` reset the node-id counter for both demos, and only
    # `runTaskApp` reset the per-VM task leaves table. They live inside the
    # accessor so a later re-run (NH-M2) repeats them as the first build did.
    let capturedTaskVm = taskAppVm
    let capturedSettingsVm = settingsAppVm
    let rootHandle = renderTui(harness,
      staticNativeRoot(proc(): TerminalNode =
        resetNodeIds()
        if mountSettings:
          settings_tui.buildSettingsApp(harness.renderer, capturedSettingsVm)
        else:
          resetTuiLeaves()
          task_tui.buildTaskApp(harness.renderer, capturedTaskVm)))

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
    rootHandle.dispose()

proc runDemoBridge*(backend: string) =
  let cfg = parseLauncherArgs(backend)
  runTuiDemo(cfg)

when isMainModule:
  runDemoBridge("tui")
