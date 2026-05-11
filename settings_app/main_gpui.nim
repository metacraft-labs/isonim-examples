## settings_app/main_gpui.nim — Layer-4 composition root for the
## settings-app GPUI target.
##
## EX-M12. Mirrors `settings_app/main_tui.nim` and `main_web.nim` in
## shape: the composition root imports the platform leaves first, then
## includes the shared components and the shell in dependency order so
## the unqualified leaf calls inside the components / shell bind to
## the GPUI procs in `settings_app/gpui/leaves.nim`.
##
## Include order (load-bearing):
##
##   1. ``import isonim_gpui/{renderer, bindings}`` — provides
##      `GpuiRenderer`, `GpuiElement`, callback registry + shim
##      bindings (`gpui_reset_tree`, `fireEvent`, ...).
##   2. ``import settings_app/core/{vm, demo_catalog}`` — VM type +
##      actions + the canonical demo catalog.
##   3. ``import settings_app/gpui/leaves`` — the 8-leaf surface.
##   4. ``include settings_app/components/{toggle,number,choice}_item``
##      then ``include settings_app/components/group`` — the shared
##      Layer-2 component templates.
##   5. ``include settings_app/gpui/shell`` — the Layer-3 grid shell.
##
## Public surface:
##
##   * ``buildSettingsApp(r, vm)`` — returns the root node. Tests
##     call this directly when they already own a renderer.
##   * ``rebuildSettingsApp(r, vm)`` — builds a fresh tree from the
##     current VM state. Like EX-M3's GPUI task_app + EX-M11's web
##     settings_app, the GPUI flavour uses a manual rebuild path after
##     every mutation; this matches the imperative rerender pattern
##     documented in `task_app/gpui/leaves.nim` (the shim's reactive
##     memo observer notification is still limited).
##   * ``runSettingsApp(vm)`` — convenience wrapper that builds against
##     a fresh `GpuiRenderer` after resetting the shim's tree +
##     callback registry. Symmetric with `task_app/main_gpui.nim`'s
##     `runTaskApp`.

import std/tables

import isonim/core/signals
import isonim_gpui/renderer
import isonim_gpui/bindings

import settings_app/core/vm
import settings_app/core/demo_catalog
import settings_app/gpui/leaves

export tables, signals, renderer, bindings, vm, demo_catalog, leaves

include settings_app/components/toggle_item
include settings_app/components/number_item
include settings_app/components/choice_item
include settings_app/components/group
include settings_app/gpui/shell

proc buildSettingsApp*(r: GpuiRenderer; vm: SettingsVM): GpuiElement =
  ## Convenience wrapper exported for tests. Builds the full
  ## settings-app GPUI tree (Layer 3 → Layer 2 → Layer 1) and returns
  ## the root node.
  renderSettingsShell(r, vm)

proc rebuildSettingsApp*(r: GpuiRenderer; vm: SettingsVM): GpuiElement =
  ## Build a fresh tree from the current VM state. The shell reads
  ## `vm.activeGroupId` + the per-item value tables on every build, so
  ## calling this after a VM mutation paints the new state. The GPUI
  ## shim's tree + callback registry are *not* reset here — call
  ## `runSettingsApp` for the full-reset path used between independent
  ## scripted scenarios.
  buildSettingsApp(r, vm)

proc runSettingsApp*(vm: SettingsVM): GpuiElement =
  ## Build the settings app against a fresh `GpuiRenderer` and return
  ## the root node. Resets the GPUI shim's tree + the callback
  ## registry so successive test cases don't leak state into each
  ## other (mirrors `task_app/main_gpui.nim`'s `runTaskApp`).
  gpui_reset_tree()
  resetCallbacks()
  let r = GpuiRenderer()
  buildSettingsApp(r, vm)

when isMainModule:
  import isonim/core/owner
  when defined(gpuiGui):
    import isonim_gpui/window
    createRoot proc(dispose: proc()) =
      let catalog = buildDemoSettingsCatalog()
      let settingsVm = newSettingsVM(catalog)
      let root = runSettingsApp(settingsVm)
      discard root
      var win = createWindow("Settings - IsoNim GPUI", 800.0, 600.0)
      discard win.show()
      echo "Window mode placeholder (event loop not yet wired; ",
           "see RS-M2 for the streaming bridge)."
      dispose()
  else:
    createRoot proc(dispose: proc()) =
      let catalog = buildDemoSettingsCatalog()
      let settingsVm = newSettingsVM(catalog)
      let root = runSettingsApp(settingsVm)
      echo "Settings app GPUI mounted; root.childCount=", childCount(root)
      echo "Groups: ", catalog.groups.len
      echo "Active: ", settingsVm.activeGroupId.val
      dispose()
