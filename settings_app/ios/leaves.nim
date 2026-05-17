## settings_app/ios/leaves.nim — Layer-1 iOS leaves for the settings demo.
##
## Mirrors `settings_app/cocoa/leaves.nim` (AppKit / NSView) but targets
## the `UIKitRenderer` from `isonim_cocoa/uikit_renderer.nim` so the
## Stream app can paint the demo into a live `UIView` hierarchy. Per-
## item subscriptions follow the EX-M17 pattern: each value-bearing
## leaf takes a `SettingsVM` reference + the item id and subscribes via
## `createRenderEffect`. Programmatic VM mutations propagate without
## a re-mount.
##
## Visual palette + topology kept symmetric with the Android leaves so
## the editor's side-by-side comparison reads as the same demo across
## both mobile renderers.
##
## Gating: `when defined(macosx)` — the whole module body is empty on
## Linux. The Cocoa-target leaves' cross-compile gate is the umbrella
## check for both AppKit + UIKit paths.

when defined(macosx):
  import std/strutils

  import isonim/core/computation  # createRenderEffect
  import isonim_cocoa/uikit_renderer
  import isonim_cocoa/objc_runtime
  import isonim_render_serve/element_tree_attrs

  import settings_app/core/vm
  import settings_app/core/component_paths

  # Visual palette — mirrors the Android leaves so the two mobile
  # renderers paint the demo as siblings on capture.
  const
    accentIndigo  = "#7c7aed"
    onTrackIndigo = "#7c7aed"
    offTrackGrey  = "#3a3a52"
    surfaceCard   = "#1d1d28"
    surfaceMuted  = "#2a2a3a"
    onSurface     = "#e6e6f0"
    mutedText     = "#a0a0b8"

  # ----------------------------------------------------------------------------
  # Layout containers
  # ----------------------------------------------------------------------------

  proc itemContainerLeaf*(r: UIKitRenderer): UIKitElement =
    let node = r.createElement("div")
    r.setAttribute(node, "class", "settings-item")
    r.setAttribute(node, ComponentPathAttr, SettingsRowPath)
    r.setAttribute(node, ElementKindAttr, "row")
    r.setStyle(node, "background-color", surfaceCard)
    r.setStyle(node, "border-radius", "8")
    r.setStyle(node, "padding", "12")
    r.setStyle(node, "gap", "4")
    node

  proc labelLeaf*(r: UIKitRenderer; text: string): UIKitElement =
    let node = r.createElement("label")
    r.setAttribute(node, "class", "settings-label")
    r.setTextContent(node, text)
    r.setStyle(node, "font-size", "16")
    r.setStyle(node, "font-weight", "500")
    r.setStyle(node, "color", onSurface)
    node

  proc descriptionLeaf*(r: UIKitRenderer; text: string): UIKitElement =
    let node = r.createElement("span")
    r.setAttribute(node, "class", "settings-description")
    r.setTextContent(node, text)
    r.setStyle(node, "font-size", "14")
    r.setStyle(node, "color", mutedText)
    node

  # ----------------------------------------------------------------------------
  # Toggle leaf — UISwitch-style native control
  # ----------------------------------------------------------------------------

  proc toggleLeaf*(r: UIKitRenderer; vmRef: SettingsVM;
                   itemId: string): UIKitElement =
    ## Renders as a UIKit-native `UISwitch` (the renderer maps the
    ## `switch` tag to `uiSwitchNew()`). The cross-renderer parity
    ## driver still walks the row's last child and matches on
    ## `data-value` so the contract is preserved.
    let node = r.createElement("switch")
    r.setAttribute(node, "type", "checkbox")
    r.setStyle(node, "width", "52")
    r.setStyle(node, "height", "32")
    let captured = vmRef
    let id = itemId
    let rCaptured = r
    createRenderEffect proc() =
      let value = captured.toggleValue(id)
      rCaptured.setAttribute(node, "data-value",
                             (if value: "true" else: "false"))
      if value:
        rCaptured.setAttribute(node, "checked", "true")
        rCaptured.setStyle(node, "background-color", onTrackIndigo)
      else:
        rCaptured.removeAttribute(node, "checked")
        rCaptured.setStyle(node, "background-color", offTrackGrey)
    r.addEventListener(node, "click", proc() =
      let current = rCaptured.getAttribute(node, "data-value") == "true"
      discard captured.setToggle(id, not current))
    node

  # ----------------------------------------------------------------------------
  # Number leaf — `[-] value [+]` stepper composed of UIButtons + UILabel
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

  proc numberLeaf*(r: UIKitRenderer; vmRef: SettingsVM; itemId: string;
                   minValue, maxValue, stepValue: int;
                   suffix: string): UIKitElement =
    let host = r.createElement("div")
    r.setAttribute(host, "class", "settings-number")
    r.setAttribute(host, "data-min", $minValue)
    r.setAttribute(host, "data-max", $maxValue)
    r.setAttribute(host, "data-step", $stepValue)
    if suffix.len > 0:
      r.setAttribute(host, "data-suffix", suffix)
    r.setStyle(host, "flex-direction", "row")
    r.setStyle(host, "gap", "6")
    r.setStyle(host, "height", "40")

    # Hidden input — preserves the parity test contract. Sized to 0
    # so it doesn't occupy visible space on the device.
    let inputNode = r.createElement("input")
    r.setAttribute(inputNode, "type", "number")
    r.setAttribute(inputNode, "data-min", $minValue)
    r.setAttribute(inputNode, "data-max", $maxValue)
    r.setAttribute(inputNode, "data-step", $stepValue)
    r.setStyle(inputNode, "width", "0")
    r.setStyle(inputNode, "height", "0")

    let captured = vmRef
    let id = itemId
    let rCaptured = r
    let lo = minValue
    let hi = maxValue
    let step = stepValue

    let decBtn = r.createElement("button")
    r.setTextContent(decBtn, "-")
    r.setAttribute(decBtn, "class", "settings-number-dec")
    r.setStyle(decBtn, "width", "40")
    r.setStyle(decBtn, "height", "40")
    r.setStyle(decBtn, "border-radius", "20")
    r.setStyle(decBtn, "background-color", surfaceMuted)
    r.setStyle(decBtn, "color", accentIndigo)
    r.setStyle(decBtn, "font-size", "20")

    let valueLabel = r.createElement("span")
    r.setAttribute(valueLabel, "class", "settings-number-value")
    r.setStyle(valueLabel, "font-size", "16")
    r.setStyle(valueLabel, "color", onSurface)
    r.setStyle(valueLabel, "padding", "8")

    let incBtn = r.createElement("button")
    r.setTextContent(incBtn, "+")
    r.setAttribute(incBtn, "class", "settings-number-inc")
    r.setStyle(incBtn, "width", "40")
    r.setStyle(incBtn, "height", "40")
    r.setStyle(incBtn, "border-radius", "20")
    r.setStyle(incBtn, "background-color", surfaceMuted)
    r.setStyle(incBtn, "color", accentIndigo)
    r.setStyle(incBtn, "font-size", "20")

    createRenderEffect proc() =
      let value = captured.numberValue(id)
      rCaptured.setAttribute(host, "data-value", $value)
      rCaptured.setAttribute(inputNode, "data-value", $value)
      rCaptured.setTextContent(valueLabel, $value)

    r.addEventListener(inputNode, "click", proc() =
      let raw = rCaptured.getAttribute(inputNode, "data-value").strip()
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

    r.addEventListener(decBtn, "click", proc() =
      let cur = captured.numberValue(id)
      var nv = cur - step
      if nv < lo: nv = lo
      if nv > hi: nv = hi
      discard captured.setNumber(id, nv))
    r.addEventListener(incBtn, "click", proc() =
      let cur = captured.numberValue(id)
      var nv = cur + step
      if nv < lo: nv = lo
      if nv > hi: nv = hi
      discard captured.setNumber(id, nv))

    r.appendChild(host, inputNode)
    r.appendChild(host, decBtn)
    r.appendChild(host, valueLabel)
    r.appendChild(host, incBtn)

    if suffix.len > 0:
      let suffixNode = r.createElement("span")
      r.setAttribute(suffixNode, "class", "settings-number-suffix")
      r.setTextContent(suffixNode, suffix)
      r.setStyle(suffixNode, "font-size", "14")
      r.setStyle(suffixNode, "color", mutedText)
      r.setStyle(suffixNode, "padding", "8")
      r.appendChild(host, suffixNode)

    host

  # ----------------------------------------------------------------------------
  # Choice leaf — segmented chip row with hidden `<select>` for parity
  # ----------------------------------------------------------------------------

  proc choiceLeaf*(r: UIKitRenderer; vmRef: SettingsVM; itemId: string;
                   options: seq[string]): UIKitElement =
    let host = r.createElement("div")
    r.setAttribute(host, "class", "settings-choice")
    r.setAttribute(host, "data-options", options.join("|"))
    r.setStyle(host, "flex-direction", "row")
    r.setStyle(host, "gap", "6")
    r.setStyle(host, "height", "40")

    let selectNode = r.createElement("select")
    let captured = vmRef
    let id = itemId
    let capturedOptions = options
    let rCaptured = r

    for opt in options:
      let optionNode = r.createElement("option")
      r.setAttribute(optionNode, "data-value", opt)
      r.setTextContent(optionNode, opt)
      r.appendChild(selectNode, optionNode)

    r.setStyle(selectNode, "width", "0")
    r.setStyle(selectNode, "height", "0")

    createRenderEffect proc() =
      let value = captured.choiceValue(id)
      rCaptured.setAttribute(host, "data-value", value)
      rCaptured.setAttribute(selectNode, "data-value", value)
      for i in 0 ..< rCaptured.childCount(selectNode):
        let optionNode = rCaptured.nthChild(selectNode, i)
        if rCaptured.getAttribute(optionNode, "data-value") == value:
          rCaptured.setAttribute(optionNode, "selected", "selected")
        else:
          rCaptured.removeAttribute(optionNode, "selected")

    r.addEventListener(selectNode, "click", proc() =
      let picked = rCaptured.getAttribute(selectNode, "data-value")
      var valid = false
      for opt in capturedOptions:
        if opt == picked:
          valid = true
          break
      if valid:
        discard captured.setChoice(id, picked))

    r.appendChild(host, selectNode)

    proc makeChipHandler(opt: string): proc() =
      result = proc() = discard captured.setChoice(id, opt)

    proc makeChipEffect(chipNode: UIKitElement; opt: string) =
      createRenderEffect proc() =
        if captured.choiceValue(id) == opt:
          rCaptured.setStyle(chipNode, "background-color", accentIndigo)
          rCaptured.setStyle(chipNode, "color", "#ffffff")
        else:
          rCaptured.setStyle(chipNode, "background-color", surfaceMuted)
          rCaptured.setStyle(chipNode, "color", accentIndigo)

    for opt in options:
      let chip = r.createElement("button")
      r.setAttribute(chip, "class", "settings-choice-chip")
      r.setAttribute(chip, "data-chip", opt)
      r.setTextContent(chip, opt)
      r.setStyle(chip, "height", "36")
      r.setStyle(chip, "border-radius", "18")
      r.setStyle(chip, "padding", "8")
      r.setStyle(chip, "font-size", "14")
      r.addEventListener(chip, "click", makeChipHandler(opt))
      makeChipEffect(chip, opt)
      r.appendChild(host, chip)

    host

  # ----------------------------------------------------------------------------
  # Group container + header
  # ----------------------------------------------------------------------------

  proc groupContainerLeaf*(r: UIKitRenderer): UIKitElement =
    let node = r.createElement("section")
    r.setAttribute(node, "class", "settings-group")
    r.setAttribute(node, ComponentPathAttr, SettingsGroupPath)
    r.setAttribute(node, ElementKindAttr, "group")
    r.setStyle(node, "background-color", surfaceCard)
    r.setStyle(node, "border-radius", "12")
    r.setStyle(node, "padding", "12")
    r.setStyle(node, "gap", "8")
    node

  proc groupHeaderLeaf*(r: UIKitRenderer; label, description: string):
                       UIKitElement =
    let host = r.createElement("header")
    r.setAttribute(host, "class", "settings-group-header")
    r.setAttribute(host, "data-label", label)
    r.setAttribute(host, ComponentPathAttr, SettingsGroupHeaderPath)
    r.setAttribute(host, ElementKindAttr, "group-header")
    if description.len > 0:
      r.setAttribute(host, "data-description", description)
    r.setStyle(host, "padding", "4")
    r.setStyle(host, "gap", "2")

    let h2 = r.createElement("h2")
    r.setAttribute(h2, "class", "settings-group-header-label")
    r.setTextContent(h2, label)
    r.setStyle(h2, "font-size", "18")
    r.setStyle(h2, "font-weight", "600")
    r.setStyle(h2, "color", onSurface)
    r.appendChild(host, h2)

    if description.len > 0:
      let p = r.createElement("p")
      r.setAttribute(p, "class", "settings-group-header-description")
      r.setTextContent(p, description)
      r.setStyle(p, "font-size", "12")
      r.setStyle(p, "color", mutedText)
      r.appendChild(host, p)

    host

else:
  ## Linux/non-macOS hosts: the leaf surface is intentionally empty.
  discard
