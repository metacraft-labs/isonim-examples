## helpers/settings_compile_gpui.nim — minimal GPUI leaf stubs for the
## EX-M9 / EX-M17 compile-check.

import std/strutils

import isonim_gpui/renderer

import settings_app/core/types
import settings_app/core/vm
export types
export vm
export renderer

proc itemContainerLeaf*(r: GpuiRenderer): GpuiElement =
  let node = r.createElement("div")
  r.setAttribute(node, "class", "settings-row")
  node

proc labelLeaf*(r: GpuiRenderer; text: string): GpuiElement =
  let node = r.createElement("label")
  r.setAttribute(node, "class", "settings-label")
  r.setTextContent(node, text)
  node

proc descriptionLeaf*(r: GpuiRenderer; text: string): GpuiElement =
  let node = r.createElement("span")
  r.setAttribute(node, "class", "settings-description")
  r.setTextContent(node, text)
  node

proc toggleLeaf*(r: GpuiRenderer; vmRef: SettingsVM;
                 itemId: string): GpuiElement =
  let node = r.createElement("button")
  r.setAttribute(node, "class", "settings-toggle")
  r.setAttribute(node, "data-item-id", itemId)
  r.setAttribute(node, "data-value", $vmRef.toggleValue(itemId))
  node

proc numberLeaf*(r: GpuiRenderer; vmRef: SettingsVM; itemId: string;
                 minValue, maxValue, stepValue: int;
                 suffix: string): GpuiElement =
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

proc choiceLeaf*(r: GpuiRenderer; vmRef: SettingsVM; itemId: string;
                 options: seq[string]): GpuiElement =
  let node = r.createElement("select")
  r.setAttribute(node, "data-item-id", itemId)
  r.setAttribute(node, "value", vmRef.choiceValue(itemId))
  r.setAttribute(node, "data-options", options.join("|"))
  node

proc groupContainerLeaf*(r: GpuiRenderer): GpuiElement =
  let node = r.createElement("section")
  r.setAttribute(node, "class", "settings-group")
  node

proc groupHeaderLeaf*(r: GpuiRenderer; label, description: string): GpuiElement =
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

proc buildToggleRow*(vm: SettingsVM; item: SettingsItem): GpuiElement =
  let r = GpuiRenderer()
  renderToggleItem(r, vm, item)

proc buildNumberRow*(vm: SettingsVM; item: SettingsItem): GpuiElement =
  let r = GpuiRenderer()
  renderNumberItem(r, vm, item)

proc buildChoiceRow*(vm: SettingsVM; item: SettingsItem): GpuiElement =
  let r = GpuiRenderer()
  renderChoiceItem(r, vm, item)

proc buildGroup*(vm: SettingsVM; group: SettingsGroup): GpuiElement =
  let r = GpuiRenderer()
  renderSettingsGroup(r, vm, group)
