## helpers/settings_compile_freya.nim — minimal Freya leaf stubs for the
## EX-M9 / EX-M17 compile-check.

import std/strutils

import isonim_freya/renderer

import settings_app/core/types
import settings_app/core/vm
export types
export vm
export renderer

proc itemContainerLeaf*(r: FreyaRenderer): FreyaElement =
  let node = r.createElement("div")
  r.setAttribute(node, "class", "settings-row")
  node

proc labelLeaf*(r: FreyaRenderer; text: string): FreyaElement =
  let node = r.createElement("label")
  r.setAttribute(node, "class", "settings-label")
  r.setTextContent(node, text)
  node

proc descriptionLeaf*(r: FreyaRenderer; text: string): FreyaElement =
  let node = r.createElement("span")
  r.setAttribute(node, "class", "settings-description")
  r.setTextContent(node, text)
  node

proc toggleLeaf*(r: FreyaRenderer; vmRef: SettingsVM;
                 itemId: string): FreyaElement =
  let node = r.createElement("button")
  r.setAttribute(node, "class", "settings-toggle")
  r.setAttribute(node, "data-item-id", itemId)
  r.setAttribute(node, "data-value", $vmRef.toggleValue(itemId))
  node

proc numberLeaf*(r: FreyaRenderer; vmRef: SettingsVM; itemId: string;
                 minValue, maxValue, stepValue: int;
                 suffix: string): FreyaElement =
  let node = r.createElement("input")
  r.setAttribute(node, "type", "number")
  r.setAttribute(node, "data-item-id", itemId)
  r.setAttribute(node, "value", $vmRef.numberValue(itemId))
  r.setAttribute(node, "data-min", $minValue)
  r.setAttribute(node, "data-max", $maxValue)
  r.setAttribute(node, "data-step", $stepValue)
  if suffix.len > 0:
    r.setAttribute(node, "data-suffix", suffix)
  node

proc choiceLeaf*(r: FreyaRenderer; vmRef: SettingsVM; itemId: string;
                 options: seq[string]): FreyaElement =
  let node = r.createElement("select")
  r.setAttribute(node, "data-item-id", itemId)
  r.setAttribute(node, "value", vmRef.choiceValue(itemId))
  r.setAttribute(node, "data-options", options.join("|"))
  node

proc groupContainerLeaf*(r: FreyaRenderer): FreyaElement =
  let node = r.createElement("section")
  r.setAttribute(node, "class", "settings-group")
  node

proc groupHeaderLeaf*(r: FreyaRenderer; label, description: string): FreyaElement =
  let node = r.createElement("header")
  r.setAttribute(node, "class", "settings-group-header")
  r.setAttribute(node, "data-label", label)
  if description.len > 0:
    r.setAttribute(node, "data-description", description)
  node

include settings_app/components/toggle_item
include settings_app/components/number_item
include settings_app/components/choice_item
include settings_app/components/group

proc buildToggleRow*(vm: SettingsVM; item: SettingsItem): FreyaElement =
  let r = FreyaRenderer()
  renderToggleItem(r, vm, item)

proc buildNumberRow*(vm: SettingsVM; item: SettingsItem): FreyaElement =
  let r = FreyaRenderer()
  renderNumberItem(r, vm, item)

proc buildChoiceRow*(vm: SettingsVM; item: SettingsItem): FreyaElement =
  let r = FreyaRenderer()
  renderChoiceItem(r, vm, item)

proc buildGroup*(vm: SettingsVM; group: SettingsGroup): FreyaElement =
  let r = FreyaRenderer()
  renderSettingsGroup(r, vm, group)
