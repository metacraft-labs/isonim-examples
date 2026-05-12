## test_settings_vm_round_trip — EX-M8 / EX-M17 mandatory integration test.
##
## Real-stack exercise of the canonical `SettingsVM` after the EX-M17
## restructure: every action is async (it enqueues a `saveSetting`
## through a `FakeDb` and refreshes the resource on completion). The
## test installs a `FakeAsyncContext`, drives the VM through the same
## scripted scenarios, and advances the simulated clock after each
## action so the assertions see the post-resolution state.

import std/json
import std/tables
import std/unittest

import isonim/core/signals

import settings_app/core/types
import settings_app/core/vm
import settings_app/core/demo_catalog
import ./helpers/async_drive

# Helper: build a fresh VM + driver with the demo catalog already
# seeded into the db. The defer-pattern keeps thread-local fake-context
# state clean across tests.
template withSettings(body: untyped) =
  let drv {.inject.} = newAsyncDriver()
  defer: drv.shutdown()
  drv.db.seedSettings(buildDemoSettingsCatalog())
  let vm {.inject.} = newSettingsVM(drv.db)
  drv.flush()  # initial load
  body

suite "EX-M17: SettingsVM async round-trip via fake_db":
  test "fresh VM seeds activeGroupId from first catalog group":
    withSettings:
      check vm.activeGroupId.val == "appearance"

  test "fresh VM seeds every item value from its catalog default":
    withSettings:
      check vm.toggleValue("appearance.dark_mode") == false
      check vm.toggleValue("editor.tabs_to_spaces") == true
      check vm.toggleValue("notifications.enable_sounds") == true
      check vm.toggleValue("notifications.show_badges") == false
      check vm.numberValue("appearance.font_size") == 14
      check vm.numberValue("editor.tab_width") == 4
      check vm.numberValue("notifications.poll_interval_ms") == 5000
      check vm.choiceValue("appearance.theme") == "Default"
      check vm.choiceValue("editor.line_endings") == "LF"

  test "setToggle writes through and the snapshot table updates":
    withSettings:
      check vm.setToggle("appearance.dark_mode", true) == true
      drv.flush()
      check vm.toggleValue("appearance.dark_mode") == true
      check vm.toggleValues["appearance.dark_mode"] == true
      check vm.toggleValue("editor.tabs_to_spaces") == true
      check vm.toggleValue("notifications.show_badges") == false
      check vm.setToggle("appearance.dark_mode", false) == true
      drv.flush()
      check vm.toggleValue("appearance.dark_mode") == false

  test "setNumber writes through inside the [min, max] range":
    withSettings:
      check vm.setNumber("appearance.font_size", 18) == true
      drv.flush()
      check vm.numberValue("appearance.font_size") == 18
      check vm.numberValues["appearance.font_size"] == 18

  test "setNumber clamps above-max writes to max":
    withSettings:
      check vm.setNumber("appearance.font_size", 999) == true
      drv.flush()
      check vm.numberValue("appearance.font_size") == 32
      check vm.setNumber("notifications.poll_interval_ms", 10_000_000) == true
      drv.flush()
      check vm.numberValue("notifications.poll_interval_ms") == 60_000

  test "setNumber clamps below-min writes to min":
    withSettings:
      check vm.setNumber("appearance.font_size", 0) == true
      drv.flush()
      check vm.numberValue("appearance.font_size") == 10
      check vm.setNumber("appearance.font_size", -50) == true
      drv.flush()
      check vm.numberValue("appearance.font_size") == 10
      check vm.setNumber("notifications.poll_interval_ms", 0) == true
      drv.flush()
      check vm.numberValue("notifications.poll_interval_ms") == 500

  test "setNumber accepts boundary values exactly":
    withSettings:
      check vm.setNumber("appearance.font_size", 10) == true
      drv.flush()
      check vm.numberValue("appearance.font_size") == 10
      check vm.setNumber("appearance.font_size", 32) == true
      drv.flush()
      check vm.numberValue("appearance.font_size") == 32

  test "setChoice writes through when value is in the options list":
    withSettings:
      check vm.setChoice("appearance.theme", "Solarized") == true
      drv.flush()
      check vm.choiceValue("appearance.theme") == "Solarized"
      check vm.setChoice("appearance.theme", "Dracula") == true
      drv.flush()
      check vm.choiceValue("appearance.theme") == "Dracula"
      check vm.setChoice("editor.line_endings", "CRLF") == true
      drv.flush()
      check vm.choiceValue("editor.line_endings") == "CRLF"

  test "setChoice rejects values outside the options list":
    withSettings:
      let snap = vm.snapshot
      check vm.setChoice("appearance.theme", "InvalidName") == false
      check vm.choiceValue("appearance.theme") == "Default"
      check vm.snapshot == snap
      check vm.setChoice("appearance.theme", "solarized") == false
      check vm.choiceValue("appearance.theme") == "Default"
      check vm.setChoice("appearance.theme", "") == false
      check vm.choiceValue("appearance.theme") == "Default"

  test "setActiveGroup updates the signal for known group ids":
    withSettings:
      check vm.activeGroupId.val == "appearance"
      check vm.setActiveGroup("editor") == true
      check vm.activeGroupId.val == "editor"
      check vm.setActiveGroup("notifications") == true
      check vm.activeGroupId.val == "notifications"
      check vm.setActiveGroup("appearance") == true
      check vm.activeGroupId.val == "appearance"

  test "setActiveGroup rejects unknown group ids without mutation":
    withSettings:
      check vm.setActiveGroup("does_not_exist") == false
      check vm.activeGroupId.val == "appearance"

  test "actions reject unknown item ids without mutation":
    withSettings:
      let snap = vm.snapshot
      check vm.setToggle("missing.id", true) == false
      check vm.setNumber("missing.id", 5) == false
      check vm.setChoice("missing.id", "x") == false
      check vm.snapshot == snap

  test "actions reject mismatched-kind writes without mutation":
    withSettings:
      let snap = vm.snapshot
      check vm.setToggle("appearance.font_size", true) == false
      check vm.setNumber("appearance.dark_mode", 1) == false
      check vm.setChoice("appearance.font_size", "x") == false
      check vm.setToggle("appearance.theme", true) == false
      check vm.snapshot == snap

  test "currentGroup tracks activeGroupId":
    withSettings:
      check vm.currentGroup.id == "appearance"
      check vm.currentGroup.label == "Appearance"
      check vm.currentGroup.items.len == 3
      discard vm.setActiveGroup("editor")
      check vm.currentGroup.id == "editor"
      check vm.currentGroup.items.len == 3
      discard vm.setActiveGroup("notifications")
      check vm.currentGroup.id == "notifications"

  test "itemValue returns kind-correct JSON for each item kind":
    withSettings:
      discard vm.setToggle("appearance.dark_mode", true); drv.flush()
      discard vm.setNumber("appearance.font_size", 22); drv.flush()
      discard vm.setChoice("appearance.theme", "Solarized"); drv.flush()
      let toggleNode = vm.itemValue("appearance.dark_mode")
      check toggleNode.kind == JBool
      check toggleNode.getBool == true
      let numberNode = vm.itemValue("appearance.font_size")
      check numberNode.kind == JInt
      check numberNode.getInt == 22
      let choiceNode = vm.itemValue("appearance.theme")
      check choiceNode.kind == JString
      check choiceNode.getStr == "Solarized"

  test "resetDefaults restores every item to its catalog default":
    # Build the pristine snapshot first, on a separate driver that we
    # tear down before installing the main driver. The fake context
    # is per-thread, so nesting contexts is fine but ops dispatch
    # against whichever is *currently* installed — we keep the test
    # simple by not nesting.
    let drvP = newAsyncDriver()
    drvP.db.seedSettings(buildDemoSettingsCatalog())
    let vmPristine = newSettingsVM(drvP.db)
    drvP.flush()
    let pristine = vmPristine.snapshot
    drvP.shutdown()

    let drv = newAsyncDriver()
    defer: drv.shutdown()
    drv.db.seedSettings(buildDemoSettingsCatalog())
    let vm = newSettingsVM(drv.db)
    drv.flush()
    discard vm.setToggle("appearance.dark_mode", true); drv.flush()
    discard vm.setNumber("appearance.font_size", 22); drv.flush()
    discard vm.setChoice("appearance.theme", "Solarized"); drv.flush()
    discard vm.setToggle("editor.tabs_to_spaces", false); drv.flush()
    let dirty = vm.snapshot
    check dirty != pristine
    vm.resetDefaults()
    # resetDefaults fires 9 saveSetting ops + cascaded refreshes.
    for _ in 0 ..< 12: drv.flush()
    check vm.snapshot == pristine

  test "snapshot captures a value-copy independent of the live VM":
    withSettings:
      discard vm.setToggle("appearance.dark_mode", true); drv.flush()
      let snap = vm.snapshot
      discard vm.setToggle("appearance.dark_mode", false); drv.flush()
      check vm.toggleValue("appearance.dark_mode") == false
      var found = false
      for (k, v) in snap.toggles:
        if k == "appearance.dark_mode":
          check v == true
          found = true
      check found

  test "two VMs driven by the same script produce equal snapshots":
    proc drive(vm: SettingsVM; drv: AsyncDriver) =
      discard vm.setToggle("appearance.dark_mode", true); drv.flush()
      discard vm.setChoice("appearance.theme", "Dracula"); drv.flush()
      discard vm.setNumber("appearance.font_size", 18); drv.flush()
      discard vm.setToggle("editor.tabs_to_spaces", false); drv.flush()
      discard vm.setNumber("editor.tab_width", 2); drv.flush()
      discard vm.setChoice("editor.line_endings", "CRLF"); drv.flush()
      discard vm.setNumber("notifications.poll_interval_ms", 1500); drv.flush()
      discard vm.setActiveGroup("editor")

    let drvA = newAsyncDriver(seed = 42)
    defer: drvA.shutdown()
    drvA.db.seedSettings(buildDemoSettingsCatalog())
    let vmA = newSettingsVM(drvA.db); drvA.flush()
    drive(vmA, drvA)
    let snapA = vmA.snapshot

    let drvB = newAsyncDriver(seed = 42)
    drvB.db.seedSettings(buildDemoSettingsCatalog())
    let vmB = newSettingsVM(drvB.db); drvB.flush()
    drive(vmB, drvB)
    let snapB = vmB.snapshot
    drvB.shutdown()

    check snapA == snapB

    # And differs from the pristine snapshot.
    let drvC = newAsyncDriver()
    drvC.db.seedSettings(buildDemoSettingsCatalog())
    let vmPristine = newSettingsVM(drvC.db); drvC.flush()
    check snapA != vmPristine.snapshot
    drvC.shutdown()

  test "demo catalog has the expected shape":
    let cat = buildDemoSettingsCatalog()
    check cat.groups.len == 3
    check cat.groups[0].id == "appearance"
    check cat.groups[1].id == "editor"
    check cat.groups[2].id == "notifications"
    for g in cat.groups:
      check g.items.len == 3
    let kinds = block:
      var s: seq[SettingsItemKind] = @[]
      for it in cat.groups[0].items:
        s.add it.kind
      s
    check sikToggle in kinds
    check sikNumber in kinds
    check sikChoice in kinds
