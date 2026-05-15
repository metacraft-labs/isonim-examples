## settings_app/freya/leaves.nim — Layer-1 Freya leaves for the settings demo.
##
## EX-M17: per-item subscriptions. Each value-bearing leaf takes a
## `SettingsVM` reference + the item id and subscribes via
## `createRenderEffect`. Programmatic VM mutations propagate to the
## shim's element tree without a re-mount.
##
## M-EVP-14 round-2: text on a Freya `rect` is not rendered by the
## Skia raster — only `label`/`paragraph` kinds paint glyphs. Every
## value-bearing leaf below puts its display text inside a child
## `span` (→ Freya `label`) so the headless render actually shows
## the values. A second pass adds card spacing, hairline borders on
## the group cards, and an indigo accent on the selected choice
## option so the "Default" theme chip is visually distinguished.

import std/strutils

import isonim/core/computation  # createRenderEffect
import isonim_freya/renderer
import isonim_freya/bindings
import isonim_render_serve/element_tree_attrs

import settings_app/core/vm
import settings_app/core/component_paths

const
  cTextPrimary = "rgb(232, 233, 240)"
  cTextSecondary = "rgb(160, 162, 176)"
  cAccent = "rgb(124, 122, 237)"
  cAccentText = "rgb(255, 255, 255)"
  cChipBg = "rgb(34, 35, 46)"
  cCardBg = "rgb(29, 29, 40)"
  cCardBorder = "1 solid rgb(60, 61, 75)"
  cCardGap = "12"
  cCardPad = "16"

# ----------------------------------------------------------------------------
# Layout containers
# ----------------------------------------------------------------------------

proc itemContainerLeaf*(r: FreyaRenderer): FreyaElement =
  let node = r.createElement("div")
  r.setAttribute(node, "class", "settings-item")
  # EX-M23b: component-path annotation; identical string to GPUI + TUI.
  r.setAttribute(node, ComponentPathAttr, SettingsRowPath)
  r.setAttribute(node, ElementKindAttr, "row")
  r.setStyle(node, "flex-direction", "column")
  r.setStyle(node, "gap", "4")
  r.setStyle(node, "padding", "8")
  node

proc labelLeaf*(r: FreyaRenderer; text: string): FreyaElement =
  let node = r.createElement("label")
  r.setAttribute(node, "class", "settings-label")
  r.setTextContent(node, text)
  r.setStyle(node, "color", cTextPrimary)
  r.setStyle(node, "font-size", "14")
  r.setStyle(node, "font-weight", "bold")
  node

proc descriptionLeaf*(r: FreyaRenderer; text: string): FreyaElement =
  let node = r.createElement("span")
  r.setAttribute(node, "class", "settings-description")
  r.setTextContent(node, text)
  r.setStyle(node, "color", cTextSecondary)
  r.setStyle(node, "font-size", "12")
  node

# ----------------------------------------------------------------------------
# Toggle leaf
# ----------------------------------------------------------------------------

proc toggleLeaf*(r: FreyaRenderer; vmRef: SettingsVM;
                 itemId: string): FreyaElement =
  let node = r.createElement("input")
  r.setAttribute(node, "type", "checkbox")
  r.setStyle(node, "background", cChipBg)
  r.setStyle(node, "padding", "4")
  r.setStyle(node, "border-radius", "4")
  r.setStyle(node, "flex-direction", "row")
  r.setStyle(node, "cross_align", "center")
  # Visible marker as a child span (→ Freya `label`): "[x]" or "[ ]".
  let marker = r.createElement("span")
  r.setStyle(marker, "color", cTextPrimary)
  r.setStyle(marker, "font-size", "13")
  r.setStyle(marker, "font-weight", "bold")
  r.appendChild(node, marker)
  let captured = vmRef
  let id = itemId
  let markerRef = marker
  createRenderEffect proc() =
    let value = captured.toggleValue(id)
    r.setAttribute(node, "data-value", (if value: "true" else: "false"))
    if value:
      r.setAttribute(node, "checked", "checked")
      r.setStyle(node, "background", cAccent)
      r.setTextContent(markerRef, "[x]")
      r.setStyle(markerRef, "color", cAccentText)
    else:
      r.removeAttribute(node, "checked")
      r.setStyle(node, "background", cChipBg)
      r.setTextContent(markerRef, "[ ]")
      r.setStyle(markerRef, "color", cTextSecondary)
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
  r.setStyle(host, "flex-direction", "row")
  r.setStyle(host, "cross_align", "center")
  r.setStyle(host, "gap", "6")

  let inputNode = r.createElement("input")
  r.setAttribute(inputNode, "type", "number")
  r.setAttribute(inputNode, "data-min", $minValue)
  r.setAttribute(inputNode, "data-max", $maxValue)
  r.setAttribute(inputNode, "data-step", $stepValue)
  r.setStyle(inputNode, "background", cChipBg)
  r.setStyle(inputNode, "padding", "6")
  r.setStyle(inputNode, "border-radius", "4")
  r.setStyle(inputNode, "flex-direction", "row")
  r.setStyle(inputNode, "cross_align", "center")
  # Visible value as a child span (→ Freya `label`).
  let valueSpan = r.createElement("span")
  r.setStyle(valueSpan, "color", cTextPrimary)
  r.setStyle(valueSpan, "font-size", "14")
  r.setStyle(valueSpan, "font-weight", "bold")
  r.appendChild(inputNode, valueSpan)

  let captured = vmRef
  let id = itemId
  let valueRef = valueSpan
  createRenderEffect proc() =
    let value = captured.numberValue(id)
    r.setAttribute(host, "data-value", $value)
    r.setAttribute(inputNode, "data-value", $value)
    r.setTextContent(valueRef, $value)

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
    r.setStyle(suffixNode, "color", cTextSecondary)
    r.setStyle(suffixNode, "font-size", "12")
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
  r.setStyle(host, "flex-direction", "row")
  r.setStyle(host, "gap", "6")
  r.setStyle(host, "padding", "4")
  r.setStyle(host, "cross_align", "center")

  let selectNode = r.createElement("select")
  r.setStyle(selectNode, "flex-direction", "row")
  r.setStyle(selectNode, "gap", "6")
  r.setStyle(selectNode, "cross_align", "center")
  let captured = vmRef
  let id = itemId
  let capturedOptions = options

  # Per-option chip. Each chip is a `<span>` (→ Freya `label`) wrapped
  # in an `<option>` (→ `rect`) so the headless render shows the text
  # while the wrapping option still carries the `data-value` attribute
  # the click router reads. The currently-selected option flips to an
  # indigo background through the createRenderEffect below.
  var chipBgs: seq[FreyaElement] = @[]
  for opt in options:
    let optionNode = r.createElement("option")
    r.setAttribute(optionNode, "data-value", opt)
    r.setTextContent(optionNode, opt)
    r.setStyle(optionNode, "background", cChipBg)
    r.setStyle(optionNode, "padding", "6")
    r.setStyle(optionNode, "border-radius", "4")
    r.setStyle(optionNode, "flex-direction", "row")
    r.setStyle(optionNode, "cross_align", "center")
    let chipSpan = r.createElement("span")
    r.setTextContent(chipSpan, opt)
    r.setStyle(chipSpan, "color", cTextPrimary)
    r.setStyle(chipSpan, "font-size", "13")
    r.appendChild(optionNode, chipSpan)
    r.appendChild(selectNode, optionNode)
    chipBgs.add optionNode

  createRenderEffect proc() =
    let value = captured.choiceValue(id)
    r.setAttribute(host, "data-value", value)
    r.setAttribute(selectNode, "data-value", value)
    for i in 0 ..< childCount(selectNode):
      let optionNode = nthChild(selectNode, i)
      if getAttribute(optionNode, "data-value") == value:
        r.setAttribute(optionNode, "selected", "selected")
        r.setStyle(optionNode, "background", cAccent)
      else:
        r.removeAttribute(optionNode, "selected")
        r.setStyle(optionNode, "background", cChipBg)

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
  # Card-style group: dark surface + hairline border + outer gap. The
  # outer gap pushes the group cards apart so they no longer touch
  # their inner padding (M-EVP-14 round-2 settings cell finding).
  r.setStyle(node, "background", cCardBg)
  r.setStyle(node, "padding", cCardPad)
  r.setStyle(node, "margin", "6")
  r.setStyle(node, "border", cCardBorder)
  r.setStyle(node, "border-radius", "8")
  r.setStyle(node, "flex-direction", "column")
  r.setStyle(node, "gap", cCardGap)
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
  r.setStyle(host, "flex-direction", "column")
  r.setStyle(host, "gap", "4")
  r.setStyle(host, "padding", "4")

  let h2 = r.createElement("h2")
  r.setAttribute(h2, "class", "settings-group-header-label")
  r.setTextContent(h2, label)
  # Visibly heavier + larger than item labels: 18 px / bold against
  # primary text colour, while items use 14 px bold.
  r.setStyle(h2, "color", cTextPrimary)
  r.setStyle(h2, "font-size", "18")
  r.setStyle(h2, "font-weight", "bold")
  r.appendChild(host, h2)

  if description.len > 0:
    let p = r.createElement("p")
    r.setAttribute(p, "class", "settings-group-header-description")
    r.setTextContent(p, description)
    r.setStyle(p, "color", cTextSecondary)
    r.setStyle(p, "font-size", "12")
    r.appendChild(host, p)

  host
