## test_settings_app_async_vm — EX-M17 strong integration test for the
## SettingsVM async lifecycle, including the load-bearing per-item leaf
## subscription assertion.
##
## The "per_item_leaf_subscription_reflects_programmatic_mutation" case
## here is the explicit verification of the EX-M16 review's
## architectural note: after a programmatic VM mutation (e.g. fake_db's
## refresh path firing after a save success), the leaf's DOM attribute
## must reflect the new value WITHOUT a re-mount. We use the web
## leaves' `MockRenderer` for the assertion because they are the
## simplest to introspect.

import std/[options, tables, unittest]

import nim_everywhere

import isonim/core/signals
import isonim/core/resource
import isonim/core/owner
import isonim/testing/mock_dom

import settings_app/core/vm
import settings_app/core/demo_catalog
import settings_app/web/leaves as web_leaves
import ./helpers/async_drive

# ---------------------------------------------------------------------------
# Local helper — drive the SettingsVM through the same flush() pattern.
# ---------------------------------------------------------------------------

proc seedDriver(drv: AsyncDriver) =
  drv.db.seedSettings(buildDemoSettingsCatalog())

suite "EX-M17: SettingsVM with fake_db":

  test "initial load transitions rsPending to rsReady":
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    drv.seedDriver()
    let vm = newSettingsVM(drv.db)
    check vm.catalogResource.state.val == rsPending
    drv.flush()
    check vm.catalogResource.state.val == rsReady
    check vm.toggleValue("appearance.dark_mode") == false
    check vm.numberValue("appearance.font_size") == 14
    check vm.choiceValue("appearance.theme") == "Default"

  test "setToggle marks pending and resolves":
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    drv.seedDriver()
    let vm = newSettingsVM(drv.db)
    drv.flush()
    check vm.pendingOps.val == 0
    discard vm.setToggle("appearance.dark_mode", true)
    check vm.pendingOps.val == 1
    drv.flush()
    check vm.pendingOps.val == 0
    check vm.toggleValue("appearance.dark_mode") == true
    check vm.lastError.val.isNone

  test "setNumber clamps before writing":
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    drv.seedDriver()
    let vm = newSettingsVM(drv.db)
    drv.flush()
    discard vm.setNumber("appearance.font_size", 5)  # below min=10
    drv.flush()
    check vm.numberValue("appearance.font_size") == 10
    discard vm.setNumber("appearance.font_size", 999)  # above max=32
    drv.flush()
    check vm.numberValue("appearance.font_size") == 32

  test "setChoice rejects invalid options without enqueueing":
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    drv.seedDriver()
    let vm = newSettingsVM(drv.db)
    drv.flush()
    let before = vm.pendingOps.val
    let ok = vm.setChoice("appearance.theme", "Invalid")
    check not ok
    check vm.pendingOps.val == before
    check vm.choiceValue("appearance.theme") == "Default"  # unchanged

  test "setToggle failure surfaces in lastError":
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    drv.seedDriver()
    let vm = newSettingsVM(drv.db)
    drv.flush()
    drv.db.scriptFailure("saveSetting", times = 1)
    discard vm.setToggle("appearance.dark_mode", true)
    drv.flush()
    check vm.lastError.val.isSome
    check vm.toggleValue("appearance.dark_mode") == false  # unchanged

  test "per_item_leaf_subscription_reflects_programmatic_mutation":
    ## EX-M17 load-bearing assertion. Mount a single toggleLeaf wired
    ## to a SettingsVM toggle item, then programmatically call
    ## vm.setToggle(id, true) and drive the resulting async path
    ## through fake_db. After the resource refresh resolves, the
    ## leaf's `data-value` attribute MUST read "true" — without
    ## re-mounting the node.
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    drv.seedDriver()
    createRoot do (dispose: proc()):
      let vm = newSettingsVM(drv.db)
      drv.flush()
      let r = MockRenderer()
      let leaf = web_leaves.toggleLeaf(r, vm, "appearance.dark_mode")
      # After initial mount + flush, the leaf shows the seeded false.
      check leaf.attributes.getOrDefault("data-value") == "false"

      # Programmatic mutation — not driven by the leaf's click handler.
      discard vm.setToggle("appearance.dark_mode", true)
      # The async path: vm.setToggle -> db.saveSetting -> refresh ->
      # db.loadSettings -> snapshot data update -> the createRenderEffect
      # over vm.toggleValue() fires -> the leaf's data-value flips.
      drv.flush()

      check vm.toggleValue("appearance.dark_mode") == true
      # THE load-bearing assertion: the leaf reflects the new value
      # without re-mounting. If this fails, the per-item subscription
      # is broken and the EX-M16 review's architectural note has
      # regressed.
      check leaf.attributes.getOrDefault("data-value") == "true"
      check leaf.attributes.getOrDefault("checked") == "checked"
      dispose()

  test "per_item_number_leaf_subscription_reflects_programmatic_mutation":
    ## Same shape as the toggle test, but for the number leaf.
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    drv.seedDriver()
    createRoot do (dispose: proc()):
      let vm = newSettingsVM(drv.db)
      drv.flush()
      let r = MockRenderer()
      let leaf = web_leaves.numberLeaf(r, vm, "appearance.font_size",
        minValue = 10, maxValue = 32, stepValue = 1, suffix = "pt")
      check leaf.attributes.getOrDefault("data-value") == "14"
      discard vm.setNumber("appearance.font_size", 22)
      drv.flush()
      check vm.numberValue("appearance.font_size") == 22
      check leaf.attributes.getOrDefault("data-value") == "22"
      dispose()

  test "per_item_choice_leaf_subscription_reflects_programmatic_mutation":
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    drv.seedDriver()
    createRoot do (dispose: proc()):
      let vm = newSettingsVM(drv.db)
      drv.flush()
      let r = MockRenderer()
      let leaf = web_leaves.choiceLeaf(r, vm, "appearance.theme",
        @["Default", "Solarized", "Dracula"])
      check leaf.attributes.getOrDefault("data-value") == "Default"
      discard vm.setChoice("appearance.theme", "Solarized")
      drv.flush()
      check vm.choiceValue("appearance.theme") == "Solarized"
      check leaf.attributes.getOrDefault("data-value") == "Solarized"
      dispose()

  test "resetDefaults restores every item via the async path":
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    drv.seedDriver()
    let vm = newSettingsVM(drv.db)
    drv.flush()
    # Mutate everything.
    discard vm.setToggle("appearance.dark_mode", true); drv.flush()
    discard vm.setNumber("appearance.font_size", 22); drv.flush()
    discard vm.setChoice("appearance.theme", "Solarized"); drv.flush()
    check vm.toggleValue("appearance.dark_mode") == true
    # Reset everything.
    vm.resetDefaults()
    # resetDefaults fires many ops; flush a few times to drain them all.
    for _ in 0 ..< 4: drv.flush()
    check vm.toggleValue("appearance.dark_mode") == false
    check vm.numberValue("appearance.font_size") == 14
    check vm.choiceValue("appearance.theme") == "Default"

  test "activeGroupId is local-only — no async involvement":
    let drv = newAsyncDriver()
    defer: drv.shutdown()
    drv.seedDriver()
    let vm = newSettingsVM(drv.db)
    drv.flush()
    let before = vm.pendingOps.val
    discard vm.setActiveGroup("editor")
    # Local — no pendingOps bump.
    check vm.pendingOps.val == before
    check vm.activeGroupId.val == "editor"
