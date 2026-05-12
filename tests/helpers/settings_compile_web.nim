## helpers/settings_compile_web.nim — minimal web leaf stubs that let
## the EX-M9 shared components compile + run against `MockRenderer`.
##
## EX-M17 update: the leaf surface now takes `vmRef, itemId` (no more
## one-shot `value` + `onChange`). The stubs below record the (vmRef,
## itemId) pair that each component template binds so the EX-M9
## driver test can assert the wiring round-trip by inspecting the
## post-construction state.

import std/strutils
import std/tables

import isonim/testing/mock_dom

import settings_app/core/types
import settings_app/core/vm
export types
export vm

# Capture buffers for the wired-up (vmRef, itemId) pairs. Tests fire
# `vm.setToggle(itemId, newValue)` directly to round-trip the wiring.

var capturedToggleItem*: string
var capturedNumberItem*: string
var capturedChoiceItem*: string
var capturedToggleVm*: SettingsVM
var capturedNumberVm*: SettingsVM
var capturedChoiceVm*: SettingsVM

proc clearCapturedHandlers*() =
  capturedToggleItem = ""
  capturedNumberItem = ""
  capturedChoiceItem = ""
  capturedToggleVm = nil
  capturedNumberVm = nil
  capturedChoiceVm = nil

# ----------------------------------------------------------------------------
# Stub leaves — match the EX-M17 web leaf signatures.
# ----------------------------------------------------------------------------

proc itemContainerLeaf*(r: MockRenderer): MockNode =
  let node = r.createElement("div")
  r.setAttribute(node, "class", "settings-row")
  node

proc labelLeaf*(r: MockRenderer; text: string): MockNode =
  let node = r.createElement("label")
  r.setAttribute(node, "class", "settings-label")
  r.setTextContent(node, text)
  node

proc descriptionLeaf*(r: MockRenderer; text: string): MockNode =
  let node = r.createElement("span")
  r.setAttribute(node, "class", "settings-description")
  r.setTextContent(node, text)
  node

proc toggleLeaf*(r: MockRenderer; vmRef: SettingsVM;
                 itemId: string): MockNode =
  capturedToggleItem = itemId
  capturedToggleVm = vmRef
  let node = r.createElement("input")
  r.setAttribute(node, "type", "checkbox")
  r.setAttribute(node, "data-item-id", itemId)
  if vmRef.toggleValue(itemId):
    r.setAttribute(node, "checked", "checked")
  node

proc numberLeaf*(r: MockRenderer; vmRef: SettingsVM; itemId: string;
                 minValue, maxValue, stepValue: int;
                 suffix: string): MockNode =
  capturedNumberItem = itemId
  capturedNumberVm = vmRef
  let node = r.createElement("input")
  r.setAttribute(node, "type", "number")
  r.setAttribute(node, "data-item-id", itemId)
  r.setAttribute(node, "value", $vmRef.numberValue(itemId))
  r.setAttribute(node, "min", $minValue)
  r.setAttribute(node, "max", $maxValue)
  r.setAttribute(node, "step", $stepValue)
  if suffix.len > 0:
    r.setAttribute(node, "data-suffix", suffix)
  node

proc choiceLeaf*(r: MockRenderer; vmRef: SettingsVM; itemId: string;
                 options: seq[string]): MockNode =
  capturedChoiceItem = itemId
  capturedChoiceVm = vmRef
  let node = r.createElement("select")
  r.setAttribute(node, "data-item-id", itemId)
  r.setAttribute(node, "value", vmRef.choiceValue(itemId))
  r.setAttribute(node, "data-options", options.join("|"))
  for opt in options:
    let optNode = r.createElement("option")
    r.setAttribute(optNode, "value", opt)
    r.setTextContent(optNode, opt)
    r.appendChild(node, optNode)
  node

proc groupContainerLeaf*(r: MockRenderer): MockNode =
  let node = r.createElement("section")
  r.setAttribute(node, "class", "settings-group")
  node

proc groupHeaderLeaf*(r: MockRenderer; label, description: string): MockNode =
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

proc buildToggleRow*(vm: SettingsVM; item: SettingsItem): MockNode =
  let r = MockRenderer()
  renderToggleItem(r, vm, item)

proc buildNumberRow*(vm: SettingsVM; item: SettingsItem): MockNode =
  let r = MockRenderer()
  renderNumberItem(r, vm, item)

proc buildChoiceRow*(vm: SettingsVM; item: SettingsItem): MockNode =
  let r = MockRenderer()
  renderChoiceItem(r, vm, item)

proc buildGroup*(vm: SettingsVM; group: SettingsGroup): MockNode =
  let r = MockRenderer()
  renderSettingsGroup(r, vm, group)
