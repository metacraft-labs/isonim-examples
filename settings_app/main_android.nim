## settings_app/main_android.nim — Layer-4 composition root for the
## settings-app Android target.
##
## EX-M22. Mirrors `settings_app/main_cocoa.nim` /
## `settings_app/main_freya.nim` / `main_gpui.nim` in shape: import the
## platform leaves first, then `include` the shared components and the
## shell in dependency order so unqualified leaf calls inside the
## components / shell bind to the Android procs in
## `settings_app/android/leaves.nim`.
##
## The whole module body is gated `when defined(android):` because
## `isonim_android/renderer` transitively imports
## `isonim_android/jni_callbacks`, which raises a hard `{.error.}`
## unless either `-d:mockJni` (host-side test shim) or
## `-d:commandBuffer` (real Android JNI bridge) is set. On Linux this
## module collapses to an empty shell so `isonim-examples`'s default
## `just test` keeps working unchanged while the cross-compile gate
## drives the Android-target check from the same Linux host.
##
## Public surface (on Android):
##
##   * `buildSettingsApp(r, vm)` — returns the root node. Tests call
##     this directly when they already own a renderer.
##   * `runSettingsApp(vm)` — convenience wrapper that builds against
##     a fresh `AndroidRenderer` after resetting per-thread leaves +
##     the callback registry.
##
## Window-mode (`-d:androidGui`) note: unlike `task_app/main_android.nim`,
## which exports its own JNI entry points for the legacy task_app demo,
## the settings_app exports are co-hosted in `task_app/main_android.nim`
## under the `SettingsAppBridge_*` JNI namespace. That keeps the
## `nimexamples` flavor's single `libtask_app.so` carrying both demos
## (EX-M22 architectural decision A — see the milestone notes). The
## `buildSettingsApp` / `runSettingsApp` procs below are imported by
## `task_app/main_android.nim`'s `-d:androidGui` block for that purpose.

when defined(android) or defined(mockJni):
  import std/tables

  import isonim/core/signals
  import isonim/core/computation  # createRenderEffect
  import isonim_android/renderer

  import settings_app/core/vm
  import settings_app/core/demo_catalog
  import settings_app/android/leaves

  export tables, signals, renderer, vm, demo_catalog, leaves

  include settings_app/components/toggle_item
  include settings_app/components/number_item
  include settings_app/components/choice_item
  include settings_app/components/group
  include settings_app/android/shell

  proc buildSettingsApp*(r: AndroidRenderer; vm: SettingsVM): AndroidElement =
    ## Convenience wrapper exported for tests. Builds the full
    ## settings-app Android tree (Layer 3 → Layer 2 → Layer 1) and
    ## returns the root node.
    renderSettingsShell(r, vm)

  proc runSettingsApp*(vm: SettingsVM): AndroidElement =
    ## Build the settings app against a fresh `AndroidRenderer` and
    ## return the root node. Resets the Android renderer's element
    ## tracking + the callback registry so successive test cases don't
    ## leak state into each other (mirrors `task_app/main_android.nim`'s
    ## `runTaskApp`).
    resetRenderer()
    let r = AndroidRenderer()
    buildSettingsApp(r, vm)

  when isMainModule:
    import isonim/core/owner

    createRoot proc(dispose: proc()) =
      let catalog = buildDemoSettingsCatalog()
      let settingsVm = newSettingsVM(catalog)
      let root = runSettingsApp(settingsVm)
      let r = AndroidRenderer()
      echo "Settings app Android mounted; root.childCount=",
        r.childCount(root)
      echo "Groups: ", catalog.groups.len
      echo "Active: ", settingsVm.activeGroupId.val
      dispose()

else:
  ## Linux/non-android hosts: the composition root surface is
  ## intentionally empty. The cross-compile gate
  ## (`tests/test_android_leaves_compile.nim` for the task_app — the
  ## settings_app does not yet have a dedicated cross-compile gate test)
  ## validates the Android renderer surface from this host.
  discard
