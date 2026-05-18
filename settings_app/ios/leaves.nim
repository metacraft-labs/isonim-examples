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
    ## Round-7: lay out as a horizontal row (label/description column
    ## on the left, control on the right) so the UISwitch / stepper /
    ## segmented control sits at the trailing edge — the canonical
    ## iOS settings-cell idiom. Round-6 left the default vertical
    ## stack which pushed controls below the label and clipped the
    ## UISwitch off the bottom of the 54-pt row.
    let node = r.createElement("div")
    r.setAttribute(node, "class", "settings-item")
    r.setAttribute(node, ComponentPathAttr, SettingsRowPath)
    r.setAttribute(node, ElementKindAttr, "row")
    r.setStyle(node, "background-color", surfaceCard)
    r.setStyle(node, "border-radius", "8")
    r.setStyle(node, "padding", "6")
    r.setStyle(node, "gap", "8")
    r.setStyle(node, "flex-direction", "row")
    r.setStyle(node, "align-items", "center")
    # Wave U-5: bump from 30 → 48 pt so a label + description column
    # fits vertically inside the row. Round-7 pinned 30 pt when the
    # iOS rows omitted descriptions; round-13 reviewer flagged the
    # missing description tier as a content-equivalence gap. The
    # extra 18 pt accommodates a 14-pt label baseline + 10-pt
    # description baseline + 6 + 6 padding (descenders included).
    r.setStyle(node, "height", "48")
    node

  proc rowTextColumnLeaf*(r: UIKitRenderer): UIKitElement =
    ## Vertical text column inside a settings row that holds the
    ## primary label + optional description and pushes the control
    ## to the trailing edge via `flex-grow: 1`.
    let node = r.createElement("div")
    r.setAttribute(node, "class", "settings-row-text")
    r.setStyle(node, "flex-direction", "column")
    r.setStyle(node, "flex-grow", "1")
    r.setStyle(node, "gap", "0")
    node

  proc labelLeaf*(r: UIKitRenderer; text: string): UIKitElement =
    ## Primary label — the row's headline. Must visually dominate the
    ## description (round-5 inverted this; reviewer flagged that the
    ## description "Use the dark colour palette." was the largest line
    ## on screen).
    let node = r.createElement("label")
    r.setAttribute(node, "class", "settings-label")
    r.setTextContent(node, text)
    r.setStyle(node, "font-size", "14")
    r.setStyle(node, "font-weight", "600")
    r.setStyle(node, "color", onSurface)
    node

  proc descriptionLeaf*(r: UIKitRenderer; text: string): UIKitElement =
    ## Secondary description — smaller and muted so the label wins.
    let node = r.createElement("span")
    r.setAttribute(node, "class", "settings-description")
    r.setTextContent(node, text)
    r.setStyle(node, "font-size", "10")
    r.setStyle(node, "color", mutedText)
    node

  # ----------------------------------------------------------------------------
  # Toggle leaf — UISwitch-style native control
  # ----------------------------------------------------------------------------

  proc toggleLeaf*(r: UIKitRenderer; vmRef: SettingsVM;
                   itemId: string): UIKitElement =
    ## Renders as a UIKit-native `UISwitch` (the renderer maps the
    ## `switch` tag to `uiSwitchNew()`). Round-5 styled it as a custom
    ## white pill via ``background-color``; round-6 drops the
    ## background-color override so the real UISwitch chrome (track,
    ## thumb, on/off colours) paints unaltered. The cross-renderer
    ## parity driver still walks the row's last child and matches on
    ## ``data-value`` so the contract is preserved.
    let node = r.createElement("switch")
    r.setAttribute(node, "type", "checkbox")
    # The intrinsic UISwitch frame is 51 x 31 pt — pin to that so
    # Yoga reserves the natural-control footprint instead of stretching
    # the switch across the row.
    r.setStyle(node, "width", "51")
    r.setStyle(node, "height", "31")
    let captured = vmRef
    let id = itemId
    let rCaptured = r
    createRenderEffect proc() =
      let value = captured.toggleValue(id)
      rCaptured.setAttribute(node, "data-value",
                             (if value: "true" else: "false"))
      if value:
        rCaptured.setAttribute(node, "checked", "true")
      else:
        rCaptured.removeAttribute(node, "checked")
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
    ## Round-7 stepper: ``[−] value (suffix) [+]`` with explicit
    ## widths for the value+suffix block so the value text isn't
    ## clipped to a single character (round-6 capture truncated the
    ## "14" for Font size to "1" because the value `<span>` got no
    ## width allocation from Yoga and the surrounding row dominated
    ## the layout). The host pins to a `48 + 12 + 56 + 12 + 48 = ~176`
    ## pt-wide block so the stepper hugs the trailing edge of the
    ## settings cell without consuming the full width.
    let host = r.createElement("div")
    r.setAttribute(host, "class", "settings-number")
    r.setAttribute(host, "data-min", $minValue)
    r.setAttribute(host, "data-max", $maxValue)
    r.setAttribute(host, "data-step", $stepValue)
    if suffix.len > 0:
      r.setAttribute(host, "data-suffix", suffix)
    r.setStyle(host, "flex-direction", "row")
    r.setStyle(host, "align-items", "center")
    r.setStyle(host, "gap", "4")
    r.setStyle(host, "height", "28")

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
    r.setStyle(decBtn, "width", "28")
    r.setStyle(decBtn, "height", "28")
    r.setStyle(decBtn, "border-radius", "14")
    r.setStyle(decBtn, "background-color", surfaceMuted)
    r.setStyle(decBtn, "color", accentIndigo)
    r.setStyle(decBtn, "font-size", "16")
    r.setStyle(decBtn, "font-weight", "600")

    # Value + suffix block. Pin a wide enough fixed width so the
    # value text never truncates to one digit. 64 pt comfortably
    # holds five characters at 14 pt ("60000" + "ms" suffix is the
    # widest catalog entry — Notifications poll interval).
    let valueBlock = r.createElement("div")
    r.setStyle(valueBlock, "flex-direction", "row")
    r.setStyle(valueBlock, "align-items", "center")
    r.setStyle(valueBlock, "justify-content", "center")
    r.setStyle(valueBlock, "gap", "3")
    r.setStyle(valueBlock, "width", "68")
    r.setStyle(valueBlock, "height", "28")

    let valueLabel = r.createElement("span")
    r.setAttribute(valueLabel, "class", "settings-number-value")
    r.setStyle(valueLabel, "font-size", "15")
    r.setStyle(valueLabel, "font-weight", "600")
    r.setStyle(valueLabel, "color", onSurface)
    r.setStyle(valueLabel, "text-align", "center")
    # Pin an explicit width so the label's frame is wide enough for
    # up-to-five-digit values (the demo catalog tops out at "60000").
    # Without this, the text-intrinsic measure runs against the empty
    # initial label (width 0) and the post-set frame inherited the
    # zero, causing UIKit to truncate the value to its ellipsis glyph.
    r.setStyle(valueLabel, "width", "40")
    r.setStyle(valueLabel, "height", "20")
    r.appendChild(valueBlock, valueLabel)

    if suffix.len > 0:
      let suffixNode = r.createElement("span")
      r.setAttribute(suffixNode, "class", "settings-number-suffix")
      r.setTextContent(suffixNode, suffix)
      r.setStyle(suffixNode, "font-size", "12")
      r.setStyle(suffixNode, "color", mutedText)
      r.setStyle(suffixNode, "width", "20")
      r.setStyle(suffixNode, "height", "16")
      r.appendChild(valueBlock, suffixNode)

    let incBtn = r.createElement("button")
    r.setTextContent(incBtn, "+")
    r.setAttribute(incBtn, "class", "settings-number-inc")
    r.setStyle(incBtn, "width", "28")
    r.setStyle(incBtn, "height", "28")
    r.setStyle(incBtn, "border-radius", "14")
    r.setStyle(incBtn, "background-color", surfaceMuted)
    r.setStyle(incBtn, "color", accentIndigo)
    r.setStyle(incBtn, "font-size", "16")
    r.setStyle(incBtn, "font-weight", "600")

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
    r.appendChild(host, valueBlock)
    r.appendChild(host, incBtn)

    host

  # ----------------------------------------------------------------------------
  # Choice leaf — segmented chip row with hidden `<select>` for parity
  # ----------------------------------------------------------------------------

  proc choiceLeaf*(r: UIKitRenderer; vmRef: SettingsVM; itemId: string;
                   options: seq[string]): UIKitElement =
    ## Render a choice as a native ``UISegmentedControl``. Round-5
    ## composed chips from raw ``UIButton`` instances which the
    ## reviewer flagged as malformed (no unified pill background, an
    ## indigo blob overlapping the active text). Switching to the
    ## ``<segmented>`` element gives us the real iOS segmented pill
    ## with proper segment dividers and an animated selection indicator
    ## that UIKit owns.
    ##
    ## Parity contract preserved: we still emit a hidden ``<select>``
    ## with one ``<option>`` per choice (sized 0x0 so it never paints
    ## on the device), and one zero-sized ``<button data-chip="…">``
    ## per option so cross-renderer probes still see the choice option
    ## set.
    let host = r.createElement("div")
    r.setAttribute(host, "class", "settings-choice")
    r.setAttribute(host, "data-options", options.join("|"))
    r.setStyle(host, "flex-direction", "row")
    r.setStyle(host, "gap", "0")
    r.setStyle(host, "height", "28")
    r.setStyle(host, "width", "200")
    r.setStyle(host, "flex-shrink", "0")

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
    # Truly hide the parity ``<select>`` stub so its child option
    # labels don't paint over the visible segmented control. Round-6
    # reviewer (intermediate capture) saw the three options' titles
    # ("DefaultSolarizedDracula") rendered as a single concatenated
    # blob next to the segmented pill — the zero frame clipped the
    # bounds but UIKit kept painting the inner UILabel text overflow.
    r.setStyle(selectNode, "display", "none")

    # Find the initial selected index so we can seed the segmented
    # control before the first reactive pass.
    var initialIdx = 0
    let initialValue = vmRef.choiceValue(itemId)
    for i, opt in options:
      if opt == initialValue:
        initialIdx = i
        break

    let seg = r.createElement("segmented")
    r.setAttribute(seg, "segments", options.join(","))
    r.setAttribute(seg, "selectedIndex", $initialIdx)
    r.setStyle(seg, "height", "28")
    # Round-7: pin a fixed width sized for three short labels (the
    # demo catalog tops out at "Solarized" / "Default" / "Dracula" or
    # "LF" / "CRLF" / "CR"). 190 pt gives ~63 pt per segment which
    # fits "Solarized" (~58 pt at the default segmented font size)
    # without truncation, while still keeping the selection pill
    # cleanly aligned to a single segment's bounds rather than the
    # near-row-wide capsule round-6 produced with `flex-grow: 1`.
    ## Also keeps the row total width (text-column + 190 + gap) under
    ## the 366-pt content width (390 - 12*2 outer padding), so the
    ## trailing segment doesn't get squeezed off-row.
    r.setStyle(seg, "width", "200")
    # Wave K2 round-10: darken the selected segment fill so it lifts
    # off the system-white track in light mode and reads cleanly on
    # the demo's dark surface in dark mode. `background-color` is
    # mapped to `-setSelectedSegmentTintColor:` for `uekSegmented`
    # in the renderer.
    r.setStyle(seg, "background-color", offTrackGrey)

    let segNode = seg
    let segOptions = options
    r.addEventListener(seg, "click", proc() =
      let raw = rCaptured.getAttribute(segNode, "selectedIndex")
      let idx = try: parseInt(raw) except: 0
      if idx >= 0 and idx < segOptions.len:
        discard captured.setChoice(id, segOptions[idx]))

    createRenderEffect proc() =
      let value = captured.choiceValue(id)
      rCaptured.setAttribute(host, "data-value", value)
      rCaptured.setAttribute(selectNode, "data-value", value)
      var idx = 0
      for i, opt in capturedOptions:
        if opt == value:
          idx = i
        let optionNode = rCaptured.nthChild(selectNode, i)
        if opt == value:
          rCaptured.setAttribute(optionNode, "selected", "selected")
        else:
          rCaptured.removeAttribute(optionNode, "selected")
      rCaptured.setAttribute(segNode, "selectedIndex", $idx)

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
    r.appendChild(host, seg)

    # Parity contract: keep zero-sized ``<button data-chip>`` siblings
    # so cross-renderer probes still see one entry per choice option.
    proc makeChipHandler(opt: string): proc() =
      result = proc() = discard captured.setChoice(id, opt)

    for opt in options:
      let chip = r.createElement("button")
      r.setAttribute(chip, "class", "settings-choice-chip")
      r.setAttribute(chip, "data-chip", opt)
      r.setTextContent(chip, opt)
      r.setStyle(chip, "width", "0")
      r.setStyle(chip, "height", "0")
      # Hide the parity-only chip so its title doesn't overflow into
      # the visible segmented control next to it.
      r.setStyle(chip, "display", "none")
      r.addEventListener(chip, "click", makeChipHandler(opt))
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
    r.setStyle(node, "border-radius", "10")
    # Round-7: very tight outer padding so three group cards x three
    # items each + headers fit inside the editor preview's ~500-pt
    # crop of the iPhone-14 safe area. Round-6 capture had Editor
    # only partly visible and Notifications off-screen even on the
    # device's full safe area because of the preview's crop window.
    r.setStyle(node, "padding", "3")
    r.setStyle(node, "gap", "1")
    node

  proc groupHeaderLeaf*(r: UIKitRenderer; label, description: string):
                       UIKitElement =
    ## Group header. Typography hierarchy: ``header >> label >>
    ## description`` so the group title visually dominates. Round-5
    ## inverted this (description was the largest line on screen) and
    ## the reviewer flagged it as the most jarring failure on the
    ## Settings iOS cell.
    let host = r.createElement("header")
    r.setAttribute(host, "class", "settings-group-header")
    r.setAttribute(host, "data-label", label)
    r.setAttribute(host, ComponentPathAttr, SettingsGroupHeaderPath)
    r.setAttribute(host, ElementKindAttr, "group-header")
    if description.len > 0:
      r.setAttribute(host, "data-description", description)
    r.setStyle(host, "padding", "2")
    r.setStyle(host, "gap", "0")
    # Round-7: trim header to 18 pt (label-only). Round-6 used 28 pt
    # when a description was present, but we drop the per-group
    # subtitle on iOS to keep all three groups in-frame.
    r.setStyle(host, "height", "18")

    let h2 = r.createElement("h2")
    r.setAttribute(h2, "class", "settings-group-header-label")
    # Wave K2 round-10: iOS Settings-app grouped-table caption style —
    # uppercased, ~13 pt, muted secondary-label colour. The previous
    # bold black "Appearance" / "Editor" / "Notifications" read as a
    # generic page heading; UIKit's grouped UITableView convention is
    # an uppercase muted caption that frames the cells below it.
    r.setTextContent(h2, label.toUpperAscii())
    r.setStyle(h2, "font-size", "13")
    r.setStyle(h2, "font-weight", "500")
    r.setStyle(h2, "color", "#a0a2b0")
    r.setStyle(h2, "letter-spacing", "0.5")
    r.appendChild(host, h2)

    # Round-6: drop the per-group descriptive subtitle when stacking
    # all three groups; the visual rhythm reads better without it and
    # the description text is not load-bearing for the brief.
    discard description

    host

else:
  ## Linux/non-macOS hosts: the leaf surface is intentionally empty.
  discard
