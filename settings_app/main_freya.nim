## settings_app/main_freya.nim — Layer-4 composition root for the
## settings-app Freya target.
##
## EX-M15. Mirrors `settings_app/main_tui.nim`, `main_web.nim`, and
## `main_gpui.nim` in shape: the composition root imports the platform
## leaves first, then includes the shared components and the shell in
## dependency order so the unqualified leaf calls inside the components
## / shell bind to the Freya procs in `settings_app/freya/leaves.nim`.
##
## Include order (load-bearing):
##
##   1. ``import isonim_freya/{renderer, bindings}`` — provides
##      `FreyaRenderer`, `FreyaElement`, callback registry + shim
##      bindings (`freya_reset_tree`, `fireEvent`, ...).
##   2. ``import settings_app/core/{vm, demo_catalog}`` — VM type +
##      actions + the canonical demo catalog.
##   3. ``import settings_app/freya/leaves`` — the 8-leaf surface.
##   4. ``include settings_app/components/{toggle,number,choice}_item``
##      then ``include settings_app/components/group`` — the shared
##      Layer-2 component templates.
##   5. ``include settings_app/freya/shell`` — the Layer-3 card-stack
##      shell.
##
## Public surface:
##
##   * ``buildSettingsApp(r, vm)`` — returns the root node. Tests
##     call this directly when they already own a renderer.
##   * ``rebuildSettingsApp(r, vm)`` — builds a fresh tree from the
##     current VM state. Like the GPUI flavour, Freya uses a manual
##     rebuild path after every mutation (the shim's reactive memo
##     observer notification is still limited; this matches the
##     imperative rerender pattern documented in
##     `task_app/freya/leaves.nim`).
##   * ``runSettingsApp(vm)`` — convenience wrapper that builds against
##     a fresh `FreyaRenderer` after resetting the shim's tree +
##     callback registry. Symmetric with `task_app/main_freya.nim`'s
##     `runTaskApp` and `settings_app/main_gpui.nim`'s `runSettingsApp`.

import std/tables

import isonim/core/signals
import isonim_freya/renderer
import isonim_freya/bindings

import settings_app/core/vm
import settings_app/core/demo_catalog
import settings_app/freya/leaves

export tables, signals, renderer, bindings, vm, demo_catalog, leaves

include settings_app/components/toggle_item
include settings_app/components/number_item
include settings_app/components/choice_item
include settings_app/components/group
include settings_app/freya/shell

proc buildSettingsApp*(r: FreyaRenderer; vm: SettingsVM): FreyaElement =
  ## Convenience wrapper exported for tests. Builds the full
  ## settings-app Freya tree (Layer 3 → Layer 2 → Layer 1) and returns
  ## the root node.
  renderSettingsShell(r, vm)

proc rebuildSettingsApp*(r: FreyaRenderer; vm: SettingsVM): FreyaElement =
  ## Build a fresh tree from the current VM state. The shell reads
  ## `vm.activeGroupId` + the per-item value tables on every build, so
  ## calling this after a VM mutation paints the new state. The Freya
  ## shim's tree + callback registry are *not* reset here — call
  ## `runSettingsApp` for the full-reset path used between independent
  ## scripted scenarios.
  buildSettingsApp(r, vm)

proc runSettingsApp*(vm: SettingsVM): FreyaElement =
  ## Build the settings app against a fresh `FreyaRenderer` and return
  ## the root node. Resets the Freya shim's tree + the callback
  ## registry so successive test cases don't leak state into each
  ## other (mirrors `settings_app/main_gpui.nim`'s `runSettingsApp` and
  ## `task_app/main_freya.nim`'s `runTaskApp`).
  freya_reset_tree()
  resetCallbacks()
  let r = FreyaRenderer()
  buildSettingsApp(r, vm)

when isMainModule:
  import isonim/core/owner
  when defined(freyaGui):
    import isonim_freya/window
    createRoot proc(dispose: proc()) =
      let catalog = buildDemoSettingsCatalog()
      let settingsVm = newSettingsVM(catalog)
      let root = runSettingsApp(settingsVm)
      discard root
      var win = createWindow("Settings - IsoNim Freya", 800.0, 600.0)
      discard win.show()
      echo "Window mode placeholder (event loop not yet wired; ",
           "see RS-M4 for the streaming bridge)."
      dispose()
  else:
    createRoot proc(dispose: proc()) =
      let catalog = buildDemoSettingsCatalog()
      let settingsVm = newSettingsVM(catalog)
      let root = runSettingsApp(settingsVm)
      echo "Settings app Freya mounted; root.childCount=", childCount(root)
      echo "Groups: ", catalog.groups.len
      echo "Active: ", settingsVm.activeGroupId.val
      dispose()
