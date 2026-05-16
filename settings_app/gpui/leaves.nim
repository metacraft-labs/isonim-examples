## settings_app/gpui/leaves.nim — Layer-1 GPUI leaves for the settings demo.
##
## EX-M17: per-item subscriptions. Each value-bearing leaf now takes a
## `SettingsVM` reference + the item id and subscribes via
## `createRenderEffect`. Programmatic VM mutations propagate to the
## shim's element tree without a re-mount.

import std/strutils

import isonim/core/computation  # createRenderEffect
import isonim_gpui/renderer
import isonim_gpui/bindings
import isonim_render_serve/element_tree_attrs

import settings_app/core/vm
import settings_app/core/component_paths

# ----------------------------------------------------------------------------
# Layout containers
# ----------------------------------------------------------------------------

proc itemContainerLeaf*(r: GpuiRenderer): GpuiElement =
  let node = r.createElement("div")
  r.setAttribute(node, "class", "settings-item")
  # EX-M23b: component-path annotation. Mirrors what
  # ``settings_app/tui/leaves.itemContainerLeaf`` writes, keeping the
  # cross-renderer ``componentPath`` set identical.
  r.setAttribute(node, ComponentPathAttr, SettingsRowPath)
  r.setAttribute(node, ElementKindAttr, "row")
  # RS-M14 Phase 2 styling: the real headless renderer captures only
  # what the leaves explicitly request. See the matching note in
  # ``task_app/gpui/leaves.nim``. The shim's renderer maps CSS-like
  # names through ``apply_styles_to_div``; ``border`` / ``font-size`` /
  # ``font-weight`` are accepted but ignored by the renderer (no
  # corresponding GPUI method). Padding takes a single scalar.
  r.setStyle(node, "background", "#1d1d28")
  r.setStyle(node, "padding", "10")
  r.setStyle(node, "gap", "8")
  r.setStyle(node, "flex-direction", "row")
  r.setStyle(node, "align-items", "center")
  r.setStyle(node, "border-radius", "6")
  node

proc labelLeaf*(r: GpuiRenderer; text: string): GpuiElement =
  let node = r.createElement("label")
  r.setAttribute(node, "class", "settings-label")
  r.setTextContent(node, text)
  r.setStyle(node, "color", "#e8e9f0")
  r.setStyle(node, "padding", "2")
  node

proc descriptionLeaf*(r: GpuiRenderer; text: string): GpuiElement =
  let node = r.createElement("span")
  r.setAttribute(node, "class", "settings-description")
  r.setTextContent(node, text)
  r.setStyle(node, "color", "#a0a2b0")
  node

# ----------------------------------------------------------------------------
# Toggle leaf
# ----------------------------------------------------------------------------

proc toggleLeaf*(r: GpuiRenderer; vmRef: SettingsVM;
                 itemId: string): GpuiElement =
  let node = r.createElement("input")
  r.setAttribute(node, "type", "checkbox")
  # Round-3 review: against the dark card surface (#1d1d28) the toggle
  # was invisible because it inherited a near-identical background and
  # the GPUI shim drops borders. Pin pill geometry explicitly (the shim
  # honours width/height/border-radius) and use an off-state fill that
  # contrasts against the card so the control is visible even when the
  # underlying signal is false.
  r.setStyle(node, "width", "32")
  r.setStyle(node, "height", "18")
  r.setStyle(node, "border-radius", "9")
  r.setStyle(node, "cursor", "pointer")
  let captured = vmRef
  let id = itemId
  createRenderEffect proc() =
    let value = captured.toggleValue(id)
    r.setAttribute(node, "data-value", (if value: "true" else: "false"))
    if value:
      r.setAttribute(node, "checked", "checked")
      # Active accent fill mirrors the editor's accent token.
      r.setStyle(node, "background", "#7c7aed")
      r.setStyle(node, "color", "#ffffff")
    else:
      r.removeAttribute(node, "checked")
      # Off-state pill: lighter than the card so the control reads as a
      # tangible affordance rather than a hole in the surface.
      r.setStyle(node, "background", "#3a3a52")
      r.setStyle(node, "color", "#a0a2b0")
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

proc numberLeaf*(r: GpuiRenderer; vmRef: SettingsVM; itemId: string;
                 minValue, maxValue, stepValue: int;
                 suffix: string): GpuiElement =
  let host = r.createElement("div")
  r.setAttribute(host, "class", "settings-number")
  r.setAttribute(host, "data-min", $minValue)
  r.setAttribute(host, "data-max", $maxValue)
  r.setAttribute(host, "data-step", $stepValue)
  if suffix.len > 0:
    r.setAttribute(host, "data-suffix", suffix)
  r.setStyle(host, "flex-direction", "row")
  r.setStyle(host, "align-items", "center")
  r.setStyle(host, "gap", "6")

  # Round-2 review: the headless renderer renders ``textContent`` from
  # the element tree, not ``value`` attributes. So we emit the numeric
  # value as the input's text content and reactively rewrite it on
  # ``numberValue`` changes — this surfaces ``14 pt`` as a legible
  # boxed field adjacent to the ``pt`` suffix span.
  let inputNode = r.createElement("input")
  r.setAttribute(inputNode, "type", "number")
  r.setAttribute(inputNode, "data-min", $minValue)
  r.setAttribute(inputNode, "data-max", $maxValue)
  r.setAttribute(inputNode, "data-step", $stepValue)
  r.setStyle(inputNode, "background", "#22232e")
  r.setStyle(inputNode, "color", "#e8e9f0")
  r.setStyle(inputNode, "padding", "6")
  r.setStyle(inputNode, "border-radius", "4")

  let captured = vmRef
  let id = itemId
  createRenderEffect proc() =
    let value = captured.numberValue(id)
    r.setAttribute(host, "data-value", $value)
    r.setAttribute(inputNode, "data-value", $value)
    r.setTextContent(inputNode, $value)

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
    r.setStyle(suffixNode, "color", "#a0a2b0")
    r.appendChild(host, suffixNode)

  host

# ----------------------------------------------------------------------------
# Choice leaf
# ----------------------------------------------------------------------------

proc choiceLeaf*(r: GpuiRenderer; vmRef: SettingsVM; itemId: string;
                 options: seq[string]): GpuiElement =
  let host = r.createElement("div")
  r.setAttribute(host, "class", "settings-choice")
  r.setAttribute(host, "data-options", options.join("|"))
  r.setStyle(host, "flex-direction", "row")
  r.setStyle(host, "align-items", "center")
  r.setStyle(host, "gap", "6")

  let selectNode = r.createElement("select")
  r.setStyle(selectNode, "background", "#22232e")
  r.setStyle(selectNode, "color", "#e8e9f0")
  r.setStyle(selectNode, "padding", "6")
  r.setStyle(selectNode, "border-radius", "4")
  r.setStyle(selectNode, "cursor", "pointer")
  let captured = vmRef
  let id = itemId
  let capturedOptions = options

  for opt in options:
    let optionNode = r.createElement("option")
    r.setAttribute(optionNode, "data-value", opt)
    r.setTextContent(optionNode, opt)
    r.setStyle(optionNode, "color", "#a0a2b0")
    r.setStyle(optionNode, "background", "#22232e")
    r.setStyle(optionNode, "padding", "6")
    r.setStyle(optionNode, "border-radius", "4")
    r.appendChild(selectNode, optionNode)

  createRenderEffect proc() =
    let value = captured.choiceValue(id)
    r.setAttribute(host, "data-value", value)
    r.setAttribute(selectNode, "data-value", value)
    for i in 0 ..< childCount(selectNode):
      let optionNode = nthChild(selectNode, i)
      if getAttribute(optionNode, "data-value") == value:
        r.setAttribute(optionNode, "selected", "selected")
        # Selected option carries the indigo accent fill so the
        # active choice is visually distinct from siblings.
        r.setStyle(optionNode, "background", "#7c7aed")
        r.setStyle(optionNode, "color", "#ffffff")
      else:
        r.removeAttribute(optionNode, "selected")
        r.setStyle(optionNode, "background", "#22232e")
        r.setStyle(optionNode, "color", "#a0a2b0")

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

proc groupContainerLeaf*(r: GpuiRenderer): GpuiElement =
  let node = r.createElement("section")
  r.setAttribute(node, "class", "settings-group")
  r.setAttribute(node, ComponentPathAttr, SettingsGroupPath)
  r.setAttribute(node, ElementKindAttr, "group")
  # Pane card containing one group's header + items.
  r.setStyle(node, "background", "#15151c")
  r.setStyle(node, "padding", "12")
  r.setStyle(node, "gap", "8")
  r.setStyle(node, "flex-direction", "column")
  r.setStyle(node, "border-radius", "8")
  node

proc groupHeaderLeaf*(r: GpuiRenderer; label, description: string):
                     GpuiElement =
  let host = r.createElement("header")
  r.setAttribute(host, "class", "settings-group-header")
  r.setAttribute(host, "data-label", label)
  r.setAttribute(host, ComponentPathAttr, SettingsGroupHeaderPath)
  r.setAttribute(host, ElementKindAttr, "group-header")
  if description.len > 0:
    r.setAttribute(host, "data-description", description)
  r.setStyle(host, "padding", "8")
  r.setStyle(host, "gap", "4")
  r.setStyle(host, "flex-direction", "column")

  let h2 = r.createElement("h2")
  r.setAttribute(h2, "class", "settings-group-header-label")
  r.setTextContent(h2, label)
  r.setStyle(h2, "color", "#e8e9f0")
  r.appendChild(host, h2)

  if description.len > 0:
    let p = r.createElement("p")
    r.setAttribute(p, "class", "settings-group-header-description")
    r.setTextContent(p, description)
    r.setStyle(p, "color", "#a0a2b0")
    r.appendChild(host, p)

  host
