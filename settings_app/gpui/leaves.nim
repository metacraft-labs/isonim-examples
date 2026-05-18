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
  # Wave S-2: bumped to a 36x20 pill hosting a 16x16 thumb. The
  # round-10 28x16 host + 12x12 thumb read as too small at the editor's
  # preview scale — the thumb disappeared into the pill chrome when
  # the cell was downscaled to a thumbnail. The pill is now visibly
  # larger than the surrounding text baseline; the thumb's diameter
  # leaves a 2px breathing strip on each side so the OFF / ON glyph
  # reads as a tangible affordance.
  #
  # Round-10 review history: the original `<input>` element collapsed
  # visually because the shim's renderer paints `<input>` tags as a
  # plain div with no decorative chrome. R-B rewrote the toggle as an
  # explicit pill + thumb div pair, which lifted visibility from "none"
  # to "small dot" — this S-wave pass takes it the rest of the way to
  # "clearly readable switch" at preview scale.
  let node = r.createElement("div")
  r.setAttribute(node, "data-toggle", "true")
  # Round-10: keep the `type=checkbox` data hook so existing tests
  # (test_settings_gpui_end_to_end ``toggleNodeOf``) still resolve the
  # leaf via the same attribute lookup. The visible chrome is now an
  # explicit div pill + thumb instead of a `<input type=checkbox>`.
  r.setAttribute(node, "type", "checkbox")
  r.setStyle(node, "width", "36")
  r.setStyle(node, "height", "20")
  r.setStyle(node, "border-radius", "10")
  r.setStyle(node, "padding", "2")
  r.setStyle(node, "flex-direction", "row")
  r.setStyle(node, "align-items", "center")
  r.setStyle(node, "cursor", "pointer")

  # Inner thumb — a circle that visibly anchors the on/off state on
  # top of the track background. 16x16 leaves a 2px gutter on each
  # axis inside the 20-tall pill so the circle reads as a discrete
  # element rather than spanning the full pill height. A 1px white
  # border on the OFF state lifts the thumb off the muted-grey pill
  # background even when the cell is rendered at preview scale.
  let thumb = r.createElement("div")
  r.setStyle(thumb, "width", "16")
  r.setStyle(thumb, "height", "16")
  r.setStyle(thumb, "border-radius", "8")
  r.setStyle(thumb, "background", "#ffffff")
  r.setStyle(thumb, "border", "1")
  r.setStyle(thumb, "border-color", "#15151c")
  r.appendChild(node, thumb)

  let captured = vmRef
  let id = itemId
  createRenderEffect proc() =
    let value = captured.toggleValue(id)
    r.setAttribute(node, "data-value", (if value: "true" else: "false"))
    if value:
      r.setAttribute(node, "checked", "checked")
      # Active accent fill mirrors the editor's accent token; thumb
      # stays white so the contrast vs the indigo track is maximal.
      r.setStyle(node, "background", "#7c7aed")
      r.setStyle(node, "justify-content", "end")
      r.setStyle(thumb, "background", "#ffffff")
      r.setStyle(thumb, "border-color", "#7c7aed")
    else:
      r.removeAttribute(node, "checked")
      # Off-state pill: a darker pill (#2a2a3a) with a slightly raised
      # thumb tinted #d8d9e0 (off-white) — the colour delta vs the pill
      # is bigger than pure white-on-#3a3a52 was, which is what the
      # reviewer reported as "thumb not visible at preview scale".
      r.setStyle(node, "background", "#2a2a3a")
      r.setStyle(node, "justify-content", "start")
      r.setStyle(thumb, "background", "#d8d9e0")
      r.setStyle(thumb, "border-color", "#15151c")
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

proc makeNumberStepHandler(vmRef: SettingsVM; itemId: string;
                           delta, lo, hi: int): proc() =
  let captured = vmRef
  let id = itemId
  let d = delta
  let mn = lo
  let mx = hi
  result = proc() =
    var next = captured.numberValue(id) + d
    if next < mn: next = mn
    if next > mx: next = mx
    discard captured.setNumber(id, next)

proc numberLeaf*(r: GpuiRenderer; vmRef: SettingsVM; itemId: string;
                 minValue, maxValue, stepValue: int;
                 suffix: string): GpuiElement =
  ## Round-10 review: the previous numberLeaf surfaced only static
  ## ``14 pt`` text with no spinner affordance. Wrap the value in a
  ## host row with explicit ``−`` and ``+`` step buttons flanking the
  ## value display so the control reads as a numeric stepper.
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

  let lo = minValue
  let hi = maxValue
  let step = stepValue

  # Decrement button — quiet square with a muted '−' glyph. Honours
  # the only styles the GPUI shim maps (bg/color/width/height/border
  # -radius/cursor/flex centring).
  let decBtn = r.createElement("button")
  r.setAttribute(decBtn, "class", "settings-number-dec")
  r.setTextContent(decBtn, "−")
  r.setStyle(decBtn, "background", "#22232e")
  r.setStyle(decBtn, "color", "#c8cad6")
  r.setStyle(decBtn, "width", "20")
  r.setStyle(decBtn, "height", "20")
  r.setStyle(decBtn, "padding", "2")
  r.setStyle(decBtn, "border-radius", "4")
  r.setStyle(decBtn, "align-items", "center")
  r.setStyle(decBtn, "justify-content", "center")
  r.setStyle(decBtn, "cursor", "pointer")
  r.addEventListener(decBtn, "click",
    makeNumberStepHandler(vmRef, itemId, -step, lo, hi))
  r.appendChild(host, decBtn)

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
  r.setStyle(inputNode, "width", "40")
  r.setStyle(inputNode, "border-radius", "4")
  r.setStyle(inputNode, "align-items", "center")
  r.setStyle(inputNode, "justify-content", "center")

  let captured = vmRef
  let id = itemId
  createRenderEffect proc() =
    let value = captured.numberValue(id)
    r.setAttribute(host, "data-value", $value)
    r.setAttribute(inputNode, "data-value", $value)
    r.setTextContent(inputNode, $value)

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

  # Increment button — symmetric with the decrement above. Uses the
  # ASCII '+' glyph; the shim doesn't measure-and-centre text the way
  # CSS would, so flex centring on the surrounding div is the way to
  # anchor the single character cleanly.
  let incBtn = r.createElement("button")
  r.setAttribute(incBtn, "class", "settings-number-inc")
  r.setTextContent(incBtn, "+")
  r.setStyle(incBtn, "background", "#22232e")
  r.setStyle(incBtn, "color", "#c8cad6")
  r.setStyle(incBtn, "width", "20")
  r.setStyle(incBtn, "height", "20")
  r.setStyle(incBtn, "padding", "2")
  r.setStyle(incBtn, "border-radius", "4")
  r.setStyle(incBtn, "align-items", "center")
  r.setStyle(incBtn, "justify-content", "center")
  r.setStyle(incBtn, "cursor", "pointer")
  r.addEventListener(incBtn, "click",
    makeNumberStepHandler(vmRef, itemId, step, lo, hi))
  r.appendChild(host, incBtn)

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

proc makeChoiceSelectionEffect(r: GpuiRenderer; vmRef: SettingsVM;
                               itemId: string; optBtn: GpuiElement;
                               optValue: string) =
  ## Factory hoisted to top level so the per-option closure can't alias
  ## the loop variable in ``choiceLeaf``.
  let captured = vmRef
  let id = itemId
  let value = optValue
  let btn = optBtn
  createRenderEffect proc() =
    let active = captured.choiceValue(id) == value
    if active:
      # Active segment carries the indigo accent fill + white text so
      # the selected option is visually distinct from siblings (the
      # round-9 review reported a non-functional accent on the segmented
      # control — segments all rendered as identical dark pills).
      r.setAttribute(btn, "data-active", "true")
      r.setStyle(btn, "background", "#7c7aed")
      r.setStyle(btn, "color", "#ffffff")
    else:
      r.removeAttribute(btn, "data-active")
      # Inactive segments sit transparent on the row surface (#1d1d28)
      # with muted text so they read as siblings rather than competing
      # band-fills.
      r.setStyle(btn, "background", "#22232e")
      r.setStyle(btn, "color", "#a0a2b0")

proc makeChoiceClickHandler(vmRef: SettingsVM; itemId: string;
                            value: string): proc() =
  let captured = vmRef
  let id = itemId
  let v = value
  result = proc() =
    discard captured.setChoice(id, v)

proc choiceLeaf*(r: GpuiRenderer; vmRef: SettingsVM; itemId: string;
                 options: seq[string]): GpuiElement =
  ## Round-10 review: render the choice as an explicit segmented pill
  ## row — one fixed-width button per option, with the active option
  ## painted in the indigo accent. The previous ``<select>``-with-
  ## ``<option>`` approach collapsed into a stacked column of dark
  ## divs (no flex-direction on the select) and the active option's
  ## indigo styling never read as a segmented control.
  ##
  ## Tree shape preserved for existing tests:
  ##   <div class="settings-choice" data-value=… data-options=…>
  ##     <div class="" data-value=…>                ← "select" host
  ##       <div class="settings-choice-option" data-value="LF">LF</div>
  ##       <div class="settings-choice-option" data-value="CRLF">CRLF</div>
  ##       …
  ##     </div>
  ##   </div>
  let host = r.createElement("div")
  r.setAttribute(host, "class", "settings-choice")
  r.setAttribute(host, "data-options", options.join("|"))
  r.setStyle(host, "flex-direction", "row")
  r.setStyle(host, "align-items", "center")
  r.setStyle(host, "gap", "4")

  # Inner "select" container — exposed to e2e tests via
  # ``choiceSelectOf``. The container holds the segmented option
  # buttons in a horizontal row; the host's click handler reads its
  # ``data-value`` and commits to the VM (mirrors the round-1 contract).
  let selectNode = r.createElement("div")
  r.setStyle(selectNode, "background", "#15151c")
  r.setStyle(selectNode, "padding", "2")
  r.setStyle(selectNode, "border-radius", "6")
  r.setStyle(selectNode, "flex-direction", "row")
  r.setStyle(selectNode, "gap", "4")
  r.setStyle(selectNode, "align-items", "center")
  r.setStyle(selectNode, "cursor", "pointer")
  let capturedOptions = options
  let captured = vmRef
  let id = itemId

  for opt in options:
    let optBtn = r.createElement("div")
    r.setAttribute(optBtn, "class", "settings-choice-option")
    r.setAttribute(optBtn, "data-value", opt)
    r.setTextContent(optBtn, opt)
    # Pin a content-hugging width so the segments are pills, not
    # stretched bands.
    r.setStyle(optBtn, "width", "72")
    r.setStyle(optBtn, "height", "22")
    r.setStyle(optBtn, "padding", "4")
    r.setStyle(optBtn, "border-radius", "4")
    r.setStyle(optBtn, "align-items", "center")
    r.setStyle(optBtn, "justify-content", "center")
    r.setStyle(optBtn, "cursor", "pointer")
    r.addEventListener(optBtn, "click",
      makeChoiceClickHandler(vmRef, itemId, opt))
    makeChoiceSelectionEffect(r, vmRef, itemId, optBtn, opt)
    r.appendChild(selectNode, optBtn)

  # Programmatic-write contract: tests / driver scripts set
  # ``data-value`` on the inner select then click. The handler reads
  # that value back and routes through ``setChoice`` so the VM-rejects-
  # unknown-options path stays intact.
  r.addEventListener(selectNode, "click", proc() =
    let picked = getAttribute(selectNode, "data-value")
    var valid = false
    for o in capturedOptions:
      if o == picked:
        valid = true
        break
    if valid:
      discard captured.setChoice(id, picked))

  createRenderEffect proc() =
    let value = captured.choiceValue(id)
    r.setAttribute(host, "data-value", value)
    r.setAttribute(selectNode, "data-value", value)

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
