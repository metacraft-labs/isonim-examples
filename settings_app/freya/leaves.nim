## settings_app/freya/leaves.nim — Layer-1 Freya leaves for the settings demo.
##
## EX-M17: per-item subscriptions. Each value-bearing leaf takes a
## `SettingsVM` reference + the item id and subscribes via
## `createRenderEffect`. Programmatic VM mutations propagate to the
## shim's element tree without a re-mount.

import std/strutils

import isonim/core/computation  # createRenderEffect
import isonim_freya/renderer
import isonim_freya/bindings
import isonim_render_serve/element_tree_attrs

import settings_app/core/vm
import settings_app/core/component_paths

# ----------------------------------------------------------------------------
# Layout containers
# ----------------------------------------------------------------------------

proc itemContainerLeaf*(r: FreyaRenderer): FreyaElement =
  let node = r.createElement("div")
  r.setAttribute(node, "class", "settings-item")
  # EX-M23b: component-path annotation; identical string to GPUI + TUI.
  r.setAttribute(node, ComponentPathAttr, SettingsRowPath)
  r.setAttribute(node, ElementKindAttr, "row")
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

# ----------------------------------------------------------------------------
# Toggle leaf
# ----------------------------------------------------------------------------

proc toggleLeaf*(r: FreyaRenderer; vmRef: SettingsVM;
                 itemId: string): FreyaElement =
  let node = r.createElement("input")
  r.setAttribute(node, "type", "checkbox")
  let captured = vmRef
  let id = itemId
  createRenderEffect proc() =
    let value = captured.toggleValue(id)
    r.setAttribute(node, "data-value", (if value: "true" else: "false"))
    if value:
      r.setAttribute(node, "checked", "checked")
    else:
      r.removeAttribute(node, "checked")
  r.addEventListener(node, "click", proc() =
    let current = getAttribute(node, "data-value") == "true"
    discard captured.setToggle(id, not current))
  node

# ----------------------------------------------------------------------------
# Number leaf
# ----------------------------------------------------------------------------

proc isIntegerString(s: string): bool =
  if s.len == 0: return false
  var i = 0
  if s[0] == '-' or s[0] == '+':
    if s.len == 1: return false
    i = 1
  while i < s.len:
    if s[i] notin {'0' .. '9'}: return false
    inc i
  true

proc numberLeaf*(r: FreyaRenderer; vmRef: SettingsVM; itemId: string;
                 minValue, maxValue, stepValue: int;
                 suffix: string): FreyaElement =
  let host = r.createElement("div")
  r.setAttribute(host, "class", "settings-number")
  r.setAttribute(host, "data-min", $minValue)
  r.setAttribute(host, "data-max", $maxValue)
  r.setAttribute(host, "data-step", $stepValue)
  if suffix.len > 0:
    r.setAttribute(host, "data-suffix", suffix)

  let inputNode = r.createElement("input")
  r.setAttribute(inputNode, "type", "number")
  r.setAttribute(inputNode, "data-min", $minValue)
  r.setAttribute(inputNode, "data-max", $maxValue)
  r.setAttribute(inputNode, "data-step", $stepValue)

  let captured = vmRef
  let id = itemId
  createRenderEffect proc() =
    let value = captured.numberValue(id)
    r.setAttribute(host, "data-value", $value)
    r.setAttribute(inputNode, "data-value", $value)

  let lo = minValue
  let hi = maxValue
  r.addEventListener(inputNode, "click", proc() =
    let raw = getAttribute(inputNode, "data-value").strip()
    if not isIntegerString(raw):
      return
    var parsed: int
    try:
      parsed = parseInt(raw)
    except ValueError:
      return
    var clamped = parsed
    if clamped < lo: clamped = lo
    if clamped > hi: clamped = hi
    discard captured.setNumber(id, clamped))
  r.appendChild(host, inputNode)

  if suffix.len > 0:
    let suffixNode = r.createElement("span")
    r.setAttribute(suffixNode, "class", "settings-number-suffix")
    r.setTextContent(suffixNode, suffix)
    r.appendChild(host, suffixNode)

  host

# ----------------------------------------------------------------------------
# Choice leaf
# ----------------------------------------------------------------------------

proc choiceLeaf*(r: FreyaRenderer; vmRef: SettingsVM; itemId: string;
                 options: seq[string]): FreyaElement =
  let host = r.createElement("div")
  r.setAttribute(host, "class", "settings-choice")
  r.setAttribute(host, "data-options", options.join("|"))

  let selectNode = r.createElement("select")
  let captured = vmRef
  let id = itemId
  let capturedOptions = options

  for opt in options:
    let optionNode = r.createElement("option")
    r.setAttribute(optionNode, "data-value", opt)
    r.setTextContent(optionNode, opt)
    r.appendChild(selectNode, optionNode)

  createRenderEffect proc() =
    let value = captured.choiceValue(id)
    r.setAttribute(host, "data-value", value)
    r.setAttribute(selectNode, "data-value", value)
    for i in 0 ..< childCount(selectNode):
      let optionNode = nthChild(selectNode, i)
      if getAttribute(optionNode, "data-value") == value:
        r.setAttribute(optionNode, "selected", "selected")
      else:
        r.removeAttribute(optionNode, "selected")

  r.addEventListener(selectNode, "click", proc() =
    let picked = getAttribute(selectNode, "data-value")
    var valid = false
    for opt in capturedOptions:
      if opt == picked:
        valid = true
        break
    if valid:
      discard captured.setChoice(id, picked))

  r.appendChild(host, selectNode)
  host

# ----------------------------------------------------------------------------
# Group container + header
# ----------------------------------------------------------------------------

proc groupContainerLeaf*(r: FreyaRenderer): FreyaElement =
  let node = r.createElement("section")
  r.setAttribute(node, "class", "settings-group")
  r.setAttribute(node, ComponentPathAttr, SettingsGroupPath)
  r.setAttribute(node, ElementKindAttr, "group")
  node

proc groupHeaderLeaf*(r: FreyaRenderer; label, description: string):
                     FreyaElement =
  let host = r.createElement("header")
  r.setAttribute(host, "class", "settings-group-header")
  r.setAttribute(host, "data-label", label)
  r.setAttribute(host, ComponentPathAttr, SettingsGroupHeaderPath)
  r.setAttribute(host, ElementKindAttr, "group-header")
  if description.len > 0:
    r.setAttribute(host, "data-description", description)

  let h2 = r.createElement("h2")
  r.setAttribute(h2, "class", "settings-group-header-label")
  r.setTextContent(h2, label)
  r.appendChild(host, h2)

  if description.len > 0:
    let p = r.createElement("p")
    r.setAttribute(p, "class", "settings-group-header-description")
    r.setTextContent(p, description)
    r.appendChild(host, p)

  host
