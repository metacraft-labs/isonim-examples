## settings_app/main_ios.nim — Layer-4 composition root for the
## settings-app iOS target.
##
## Mirrors `settings_app/main_cocoa.nim` and
## `settings_app/main_android.nim` in shape: import the platform
## leaves first, then `include` the shared components and the shell in
## dependency order so unqualified leaf calls inside the components /
## shell bind to the iOS procs in `settings_app/ios/leaves.nim`.
##
## The whole module body is gated `when defined(macosx)` because
## `isonim_cocoa/uikit_renderer` transitively imports UIKit FFI that
## doesn't link on Linux. On Linux this module collapses to an empty
## shell so `isonim-examples`'s default `just test` keeps working.
##
## Public surface (on macOS):
##
##   * `buildSettingsApp(r, vm)` — returns the root node.
##   * `runSettingsApp(vm)` — convenience wrapper that builds against
##     a fresh `UIKitRenderer` after resetting per-thread state.

when defined(macosx):
  import std/tables

  import isonim/core/signals
  import isonim/core/computation  # createRenderEffect
  import isonim/layout/layout_engine
  import isonim_cocoa/uikit_renderer
  import isonim_cocoa/objc_runtime

  import settings_app/core/vm
  import settings_app/core/demo_catalog
  import settings_app/ios/leaves

  export tables, signals, uikit_renderer, vm, demo_catalog, leaves

  include settings_app/components/toggle_item
  include settings_app/components/number_item
  include settings_app/components/choice_item
  include settings_app/components/group
  include settings_app/ios/shell

  proc buildSettingsApp*(r: UIKitRenderer; vm: SettingsVM): UIKitElement =
    renderSettingsShell(r, vm)

  proc runSettingsApp*(vm: SettingsVM;
                       engine: LayoutEngine = nil): UIKitElement =
    resetUITree()
    let r = UIKitRenderer(engine: engine)
    buildSettingsApp(r, vm)

  when isMainModule:
    import isonim/core/owner

    createRoot proc(dispose: proc()) =
      let catalog = buildDemoSettingsCatalog()
      let settingsVm = newSettingsVM(catalog)
      let root = runSettingsApp(settingsVm)
      let r = UIKitRenderer()
      echo "Settings app iOS mounted; root.childCount=",
        r.childCount(root)
      echo "Groups: ", catalog.groups.len
      echo "Active: ", settingsVm.activeGroupId.val
      dispose()

else:
  ## Linux/non-macOS hosts: the composition root surface is
  ## intentionally empty.
  discard
