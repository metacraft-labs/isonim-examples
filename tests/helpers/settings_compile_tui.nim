## helpers/settings_compile_tui.nim — minimal TUI leaf stubs for the
## EX-M9 / EX-M17 compile-check.

import std/strutils
import std/tables

import isonim_tui/renderer

import settings_app/core/types
import settings_app/core/vm
export types
export vm

proc itemContainerLeaf*(r: TerminalRenderer): TerminalNode =
  let node = r.createElement("div")
  node.attributes["class"] = "settings-row"
  node

proc labelLeaf*(r: TerminalRenderer; text: string): TerminalNode =
  let node = r.createElement("span")
  node.attributes["class"] = "settings-label"
  node.text = text
  node

proc descriptionLeaf*(r: TerminalRenderer; text: string): TerminalNode =
  let node = r.createElement("span")
  node.attributes["class"] = "settings-description"
  node.text = text
  node

proc toggleLeaf*(r: TerminalRenderer; vmRef: SettingsVM;
                 itemId: string): TerminalNode =
  let node = r.createElement("button")
  node.attributes["role"] = "switch"
  node.attributes["data-item-id"] = itemId
  node.attributes["aria-checked"] = $vmRef.toggleValue(itemId)
  node

proc numberLeaf*(r: TerminalRenderer; vmRef: SettingsVM; itemId: string;
                 minValue, maxValue, stepValue: int;
                 suffix: string): TerminalNode =
  let node = r.createElement("input")
  node.attributes["type"] = "number"
  node.attributes["data-item-id"] = itemId
  node.attributes["value"] = $vmRef.numberValue(itemId)
  node.attributes["min"] = $minValue
  node.attributes["max"] = $maxValue
  node.attributes["step"] = $stepValue
  if suffix.len > 0:
    node.attributes["data-suffix"] = suffix
  node

proc choiceLeaf*(r: TerminalRenderer; vmRef: SettingsVM; itemId: string;
                 options: seq[string]): TerminalNode =
  let node = r.createElement("select")
  node.attributes["data-item-id"] = itemId
  node.attributes["value"] = vmRef.choiceValue(itemId)
  node.attributes["data-options"] = options.join("|")
  node

proc groupContainerLeaf*(r: TerminalRenderer): TerminalNode =
  let node = r.createElement("section")
  node.attributes["class"] = "settings-group"
  node

proc groupHeaderLeaf*(r: TerminalRenderer; label, description: string):
                    TerminalNode =
  let node = r.createElement("header")
  node.attributes["class"] = "settings-group-header"
  node.attributes["data-label"] = label
  if description.len > 0:
    node.attributes["data-description"] = description
  node

include settings_app/components/toggle_item
include settings_app/components/number_item
include settings_app/components/choice_item
include settings_app/components/group

proc buildToggleRow*(vm: SettingsVM; item: SettingsItem): TerminalNode =
  let r = TerminalRenderer()
  renderToggleItem(r, vm, item)

proc buildNumberRow*(vm: SettingsVM; item: SettingsItem): TerminalNode =
  let r = TerminalRenderer()
  renderNumberItem(r, vm, item)

proc buildChoiceRow*(vm: SettingsVM; item: SettingsItem): TerminalNode =
  let r = TerminalRenderer()
  renderChoiceItem(r, vm, item)

proc buildGroup*(vm: SettingsVM; group: SettingsGroup): TerminalNode =
  let r = TerminalRenderer()
  renderSettingsGroup(r, vm, group)
