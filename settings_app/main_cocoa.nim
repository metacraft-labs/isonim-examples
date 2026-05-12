## settings_app/main_cocoa.nim — Layer-4 composition root for the
## settings-app Cocoa target.
##
## EX-M20. Mirrors `settings_app/main_freya.nim` / `main_gpui.nim` /
## `main_tui.nim` / `main_web.nim` in shape: import the platform leaves
## first, then `include` the shared components and the shell in
## dependency order so unqualified leaf calls inside the components /
## shell bind to the Cocoa procs in `settings_app/cocoa/leaves.nim`.
##
## The whole module body is gated `when defined(macosx):` because
## `isonim_cocoa/renderer` transitively imports AppKit FFI that won't
## link on Linux. On Linux this module collapses to an empty shell so
## that `isonim-examples`'s default `just test` keeps working unchanged
## while the cross-compile gate drives the macOS-target check from the
## Linux host.
##
## Public surface (on macOS):
##
##   * `buildSettingsApp(r, vm)` — returns the root node. Tests call
##     this directly when they already own a renderer.
##   * `runSettingsApp(vm)` — convenience wrapper that builds against
##     a fresh `CocoaRenderer` after resetting per-thread leaves +
##     the callback registry. Symmetric with the other renderers'
##     `runSettingsApp`.

when defined(macosx):
  import std/tables

  import isonim/core/signals
  import isonim/core/computation  # createRenderEffect
  import isonim_cocoa/renderer

  import settings_app/core/vm
  import settings_app/core/demo_catalog
  import settings_app/cocoa/leaves

  export tables, signals, renderer, vm, demo_catalog, leaves

  include settings_app/components/toggle_item
  include settings_app/components/number_item
  include settings_app/components/choice_item
  include settings_app/components/group
  include settings_app/cocoa/shell

  proc buildSettingsApp*(r: CocoaRenderer; vm: SettingsVM): CocoaElement =
    ## Convenience wrapper exported for tests. Builds the full
    ## settings-app Cocoa tree (Layer 3 → Layer 2 → Layer 1) and returns
    ## the root node.
    renderSettingsShell(r, vm)

  proc runSettingsApp*(vm: SettingsVM): CocoaElement =
    ## Build the settings app against a fresh `CocoaRenderer` and return
    ## the root node. The Cocoa renderer carries its own per-instance
    ## state so each `runSettingsApp` invocation starts clean.
    let r = CocoaRenderer()
    buildSettingsApp(r, vm)

  when isMainModule:
    import isonim/core/owner

    createRoot proc(dispose: proc()) =
      let catalog = buildDemoSettingsCatalog()
      let settingsVm = newSettingsVM(catalog)
      let root = runSettingsApp(settingsVm)
      let r = CocoaRenderer()
      echo "Settings app Cocoa mounted; root.childCount=",
        r.childCount(root)
      echo "Groups: ", catalog.groups.len
      echo "Active: ", settingsVm.activeGroupId.val
      dispose()
