## test_settings_vm_round_trip — EX-M8 mandatory integration test.
##
## Real-stack exercise of the canonical `SettingsVM` (Layer-3.5
## ViewModel for the settings demo). The test instantiates a real
## `SettingsVM` bound to the real `buildDemoSettingsCatalog()` and
## drives it through the full action surface (`setActiveGroup`,
## `setToggle`, `setNumber`, `setChoice`, `resetDefaults`), asserting
## both the live signal values and the derived projections reflect
## every operation byte-for-byte.
##
## Validation invariants explicitly covered:
##   * number writes clamp to [min, max] (in-range, above max, below
##     min, exactly at boundaries).
##   * choice writes reject values outside the declared options
##     (signal stays put, action returns false).
##   * unknown ids on every action return false with no mutation.
##   * the kind-erased `itemValue` accessor returns the right JSON
##     payload for each kind.
##   * snapshots are deep-equal across two VMs driven by the same
##     scripted action sequence (the parity invariant EX-M9+ shells
##     will rely on for cross-renderer parity).
##
## No mocks: the `SettingsVM` is the real type from
## `settings_app/core/vm.nim`, the signals are the real `Signal[T]`
## primitives from `isonim/core/signals`, and every assertion reads
## the live signal `.val` (no recorded snapshot indirection except
## for the parity check at the end which compares two real VMs).

import std/json
import std/tables
import std/unittest

import isonim/core/signals

import settings_app/core/types
import settings_app/core/vm
import settings_app/core/demo_catalog

suite "EX-M8: SettingsVM round-trip":
  test "fresh VM seeds activeGroupId from first catalog group":
    let cat = buildDemoSettingsCatalog()
    let vm = newSettingsVM(cat)
    check vm.activeGroupId.val == "appearance"

  test "fresh VM seeds every item value from its catalog default":
    let cat = buildDemoSettingsCatalog()
    let vm = newSettingsVM(cat)
    # Toggles
    check vm.toggleValue("appearance.dark_mode") == false
    check vm.toggleValue("editor.tabs_to_spaces") == true
    check vm.toggleValue("notifications.enable_sounds") == true
    check vm.toggleValue("notifications.show_badges") == false
    # Numbers
    check vm.numberValue("appearance.font_size") == 14
    check vm.numberValue("editor.tab_width") == 4
    check vm.numberValue("notifications.poll_interval_ms") == 5000
    # Choices
    check vm.choiceValue("appearance.theme") == "Default"
    check vm.choiceValue("editor.line_endings") == "LF"

  test "setToggle writes through and the signal table updates":
    let cat = buildDemoSettingsCatalog()
    let vm = newSettingsVM(cat)
    check vm.setToggle("appearance.dark_mode", true) == true
    check vm.toggleValue("appearance.dark_mode") == true
    check vm.toggleValues.val["appearance.dark_mode"] == true
    # Other toggles untouched.
    check vm.toggleValue("editor.tabs_to_spaces") == true
    check vm.toggleValue("notifications.show_badges") == false
    # Toggle back.
    check vm.setToggle("appearance.dark_mode", false) == true
    check vm.toggleValue("appearance.dark_mode") == false

  test "setNumber writes through inside the [min, max] range":
    let cat = buildDemoSettingsCatalog()
    let vm = newSettingsVM(cat)
    check vm.setNumber("appearance.font_size", 18) == true
    check vm.numberValue("appearance.font_size") == 18
    check vm.numberValues.val["appearance.font_size"] == 18

  test "setNumber clamps above-max writes to max":
    let cat = buildDemoSettingsCatalog()
    let vm = newSettingsVM(cat)
    check vm.setNumber("appearance.font_size", 999) == true
    check vm.numberValue("appearance.font_size") == 32  # max
    check vm.setNumber("notifications.poll_interval_ms", 10_000_000) == true
    check vm.numberValue("notifications.poll_interval_ms") == 60_000

  test "setNumber clamps below-min writes to min":
    let cat = buildDemoSettingsCatalog()
    let vm = newSettingsVM(cat)
    check vm.setNumber("appearance.font_size", 0) == true
    check vm.numberValue("appearance.font_size") == 10  # min
    check vm.setNumber("appearance.font_size", -50) == true
    check vm.numberValue("appearance.font_size") == 10
    check vm.setNumber("notifications.poll_interval_ms", 0) == true
    check vm.numberValue("notifications.poll_interval_ms") == 500

  test "setNumber accepts boundary values exactly":
    let cat = buildDemoSettingsCatalog()
    let vm = newSettingsVM(cat)
    check vm.setNumber("appearance.font_size", 10) == true
    check vm.numberValue("appearance.font_size") == 10
    check vm.setNumber("appearance.font_size", 32) == true
    check vm.numberValue("appearance.font_size") == 32

  test "setChoice writes through when value is in the options list":
    let cat = buildDemoSettingsCatalog()
    let vm = newSettingsVM(cat)
    check vm.setChoice("appearance.theme", "Solarized") == true
    check vm.choiceValue("appearance.theme") == "Solarized"
    check vm.setChoice("appearance.theme", "Dracula") == true
    check vm.choiceValue("appearance.theme") == "Dracula"
    check vm.setChoice("editor.line_endings", "CRLF") == true
    check vm.choiceValue("editor.line_endings") == "CRLF"

  test "setChoice rejects values outside the options list":
    let cat = buildDemoSettingsCatalog()
    let vm = newSettingsVM(cat)
    let snap = vm.snapshot
    check vm.setChoice("appearance.theme", "InvalidName") == false
    check vm.choiceValue("appearance.theme") == "Default"  # unchanged
    check vm.snapshot == snap
    # Case-sensitive: lowercase doesn't match.
    check vm.setChoice("appearance.theme", "solarized") == false
    check vm.choiceValue("appearance.theme") == "Default"
    # Empty string rejected.
    check vm.setChoice("appearance.theme", "") == false
    check vm.choiceValue("appearance.theme") == "Default"

  test "setActiveGroup updates the signal for known group ids":
    let cat = buildDemoSettingsCatalog()
    let vm = newSettingsVM(cat)
    check vm.activeGroupId.val == "appearance"
    check vm.setActiveGroup("editor") == true
    check vm.activeGroupId.val == "editor"
    check vm.setActiveGroup("notifications") == true
    check vm.activeGroupId.val == "notifications"
    check vm.setActiveGroup("appearance") == true
    check vm.activeGroupId.val == "appearance"

  test "setActiveGroup rejects unknown group ids without mutation":
    let cat = buildDemoSettingsCatalog()
    let vm = newSettingsVM(cat)
    check vm.setActiveGroup("does_not_exist") == false
    check vm.activeGroupId.val == "appearance"

  test "actions reject unknown item ids without mutation":
    let cat = buildDemoSettingsCatalog()
    let vm = newSettingsVM(cat)
    let snap = vm.snapshot
    check vm.setToggle("missing.id", true) == false
    check vm.setNumber("missing.id", 5) == false
    check vm.setChoice("missing.id", "x") == false
    check vm.snapshot == snap

  test "actions reject mismatched-kind writes without mutation":
    ## Writing a toggle to a number id, etc., is a category error.
    let cat = buildDemoSettingsCatalog()
    let vm = newSettingsVM(cat)
    let snap = vm.snapshot
    check vm.setToggle("appearance.font_size", true) == false  # number
    check vm.setNumber("appearance.dark_mode", 1) == false      # toggle
    check vm.setChoice("appearance.font_size", "x") == false    # number
    check vm.setToggle("appearance.theme", true) == false       # choice
    check vm.snapshot == snap

  test "currentGroup tracks activeGroupId":
    let cat = buildDemoSettingsCatalog()
    let vm = newSettingsVM(cat)
    check vm.currentGroup.id == "appearance"
    check vm.currentGroup.label == "Appearance"
    check vm.currentGroup.items.len == 3
    discard vm.setActiveGroup("editor")
    check vm.currentGroup.id == "editor"
    check vm.currentGroup.items.len == 3
    discard vm.setActiveGroup("notifications")
    check vm.currentGroup.id == "notifications"

  test "itemValue returns kind-correct JSON for each item kind":
    let cat = buildDemoSettingsCatalog()
    let vm = newSettingsVM(cat)
    discard vm.setToggle("appearance.dark_mode", true)
    discard vm.setNumber("appearance.font_size", 22)
    discard vm.setChoice("appearance.theme", "Solarized")
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
    let cat = buildDemoSettingsCatalog()
    let vm = newSettingsVM(cat)
    discard vm.setToggle("appearance.dark_mode", true)
    discard vm.setNumber("appearance.font_size", 22)
    discard vm.setChoice("appearance.theme", "Solarized")
    discard vm.setToggle("editor.tabs_to_spaces", false)
    let dirty = vm.snapshot
    let pristine = newSettingsVM(buildDemoSettingsCatalog()).snapshot
    check dirty != pristine  # sanity: we changed something
    vm.resetDefaults()
    check vm.snapshot == pristine

  test "snapshot captures a value-copy independent of the live VM":
    let cat = buildDemoSettingsCatalog()
    let vm = newSettingsVM(cat)
    discard vm.setToggle("appearance.dark_mode", true)
    let snap = vm.snapshot
    # Mutating the VM after snapshot doesn't change the snapshot.
    discard vm.setToggle("appearance.dark_mode", false)
    check vm.toggleValue("appearance.dark_mode") == false
    # The snapshot still records the post-true state.
    var found = false
    for (k, v) in snap.toggles:
      if k == "appearance.dark_mode":
        check v == true
        found = true
    check found

  test "two VMs driven by the same script produce equal snapshots":
    ## Parity invariant — the same scripted scenario must yield a
    ## byte-identical snapshot regardless of which catalog instance
    ## (or which platform shell, in EX-M9+) drove it. EX-M9's cross-
    ## renderer parity test will reuse this invariant.
    proc drive(vm: SettingsVM) =
      discard vm.setToggle("appearance.dark_mode", true)
      discard vm.setChoice("appearance.theme", "Dracula")
      discard vm.setNumber("appearance.font_size", 18)
      discard vm.setToggle("editor.tabs_to_spaces", false)
      discard vm.setNumber("editor.tab_width", 2)
      discard vm.setChoice("editor.line_endings", "CRLF")
      discard vm.setNumber("notifications.poll_interval_ms", 1500)
      discard vm.setActiveGroup("editor")

    let vmA = newSettingsVM(buildDemoSettingsCatalog())
    let vmB = newSettingsVM(buildDemoSettingsCatalog())
    drive(vmA)
    drive(vmB)
    check vmA.snapshot == vmB.snapshot
    # And differs from the pristine snapshot.
    check vmA.snapshot != newSettingsVM(buildDemoSettingsCatalog()).snapshot

  test "demo catalog has the expected shape":
    ## Spec-locking test for the catalog itself — anything that
    ## changes the catalog structure here forces a deliberate update
    ## of the cross-renderer parity tests in EX-M9+.
    let cat = buildDemoSettingsCatalog()
    check cat.groups.len == 3
    check cat.groups[0].id == "appearance"
    check cat.groups[1].id == "editor"
    check cat.groups[2].id == "notifications"
    for g in cat.groups:
      check g.items.len == 3
    # One item of every kind in the appearance group.
    let kinds = block:
      var s: seq[SettingsItemKind] = @[]
      for it in cat.groups[0].items:
        s.add it.kind
      s
    check sikToggle in kinds
    check sikNumber in kinds
    check sikChoice in kinds
