## settings_app/android/leaves.nim — Layer-1 Android leaves for the settings demo.
##
## EX-M22: Android port of the settings_app leaves, mirroring
## `settings_app/cocoa/leaves.nim` and `settings_app/freya/leaves.nim`.
## The whole module body is gated `when defined(android):` because
## `isonim_android/renderer` transitively imports
## `isonim_android/jni_callbacks`, which raises a hard `{.error.}`
## unless either `-d:mockJni` (host-side test shim) or
## `-d:commandBuffer` (real Android JNI bridge) is set. On Linux the
## module collapses to an empty shell so `just test` keeps passing
## unchanged.
##
## Per-item subscriptions follow the EX-M17 pattern (already in place
## for the TUI/web/GPUI/Freya/Cocoa leaves): each value-bearing leaf
## takes a `SettingsVM` reference + the item id and subscribes via
## `createRenderEffect`. Programmatic VM mutations propagate to the
## materialised Android view tree through the reactive graph without a
## re-mount.
##
## Renderer-method-call discipline: the Android renderer's helpers are
## methods on the renderer (`r.getAttribute(node, name)`,
## `r.childCount(node)`, ...). The leaves use the renderer-method style
## throughout so the surface stays uniform with
## `task_app/android/leaves.nim` and `settings_app/cocoa/leaves.nim`.
##
## Null-check idiom: `AndroidElement = ViewHandle = int64`, so the
## empty-element sentinel is `c == 0` (not `c.isNil` as for the
## Cocoa/GPUI/Freya `distinct pointer` aliases). The shell + parity
## driver follow the same idiom.
##
## Round-3 visual fix: the value-bearing leaves now materialise as
## Material 3-style widgets on the device (a coloured "switch" track
## for `toggleLeaf`, a horizontal segmented chip row for `choiceLeaf`,
## and a `[-] value [+]` stepper for `numberLeaf`) instead of plain
## `<input>` text widgets. The cross-renderer parity test
## (`tests/test_settings_parity_across_renderers.nim`) still drives the
## hidden `<select>` / `<input type="number">` / host element by
## attribute, so the on-screen widgets are *additional* visual
## scaffolding — the parity contract is preserved.

when defined(android) or defined(mockJni):
  import std/strutils

  import isonim/core/computation  # createRenderEffect
  import isonim_android/renderer
  import isonim_render_serve/element_tree_attrs

  import settings_app/core/vm
  import settings_app/core/component_paths

  # Visual palette. Mirrors the indigo / neutral surface tokens used by
  # the task_app leaves so the two demos look like siblings on the
  # device.
  const
    accentIndigo   = "#7c7aed"
    onTrackIndigo  = "#7c7aed"
    offTrackGrey   = "#3a3a52"
    surfaceCard    = "#1d1d28"
    surfaceMuted   = "#2a2a3a"
    onSurface      = "#e6e6f0"
    mutedText      = "#a0a0b8"

  # ----------------------------------------------------------------------------
  # Layout containers
  # ----------------------------------------------------------------------------

  proc itemContainerLeaf*(r: AndroidRenderer): AndroidElement =
    let node = r.createElement("div")
    r.setAttribute(node, "class", "settings-item")
    # EX-M23c: component-path annotation; identical to other renderers.
    # On the launcher the in-process `-d:mockJni` tree carries the
    # annotation; on the device the same Nim composition root paints
    # the real `View` tree, so structural parity is by-construction.
    r.setAttribute(node, ComponentPathAttr, SettingsRowPath)
    r.setAttribute(node, ElementKindAttr, "row")
    # Round-3 fix: the row now renders as a Material 3 surface card
    # (neutral background + 8 dp rounded corners + 12 dp padding) so
    # the catalogue items read as discrete tappable rows instead of a
    # wall of unstyled text.
    r.setStyle(node, "background-color", surfaceCard)
    r.setStyle(node, "border-radius", "8")
    r.setStyle(node, "padding", "12")
    node

  proc labelLeaf*(r: AndroidRenderer; text: string): AndroidElement =
    let node = r.createElement("label")
    r.setAttribute(node, "class", "settings-label")
    r.setTextContent(node, text)
    # M3 bodyLarge for the primary label; tinted to the on-surface
    # neutral so it pops against the dark card background.  Round-5:
    # add an explicit medium-weight hint so the label reads as the
    # row's title relative to the description below.  The Android
    # NimBridge currently drops ``font-weight`` (no
    # ``Paint.setTypeface(Typeface.create(_, MEDIUM))`` wiring on the
    # TextView side yet), but the leaf carries forward-compatible
    # intent.
    r.setStyle(node, "font-size", "16")
    r.setStyle(node, "font-weight", "500")
    r.setStyle(node, "color", onSurface)
    node

  proc descriptionLeaf*(r: AndroidRenderer; text: string): AndroidElement =
    let node = r.createElement("span")
    r.setAttribute(node, "class", "settings-description")
    r.setTextContent(node, text)
    # Round-5 review: M3 spec says summary text is ``bodyMedium`` (14 sp,
    # regular weight) on ``colorOnSurfaceVariant``.  The round-4 size of
    # 12 sp ran the description too thin against the 16 sp label; the
    # M3-correct treatment is 14 sp + ``onSurfaceVariant`` (the muted-
    # text token) at regular weight (``font-weight: 400``).  Explicitly
    # setting ``font-weight: 400`` is forward-compatible: the Android
    # NimBridge currently drops it, but the leaf documents the M3
    # bodyMedium intent so the description never inherits the label's
    # medium weight if the upstream wiring lands.
    r.setStyle(node, "font-size", "14")
    r.setStyle(node, "font-weight", "400")
    r.setStyle(node, "color", mutedText)
    node

  # ----------------------------------------------------------------------------
  # Toggle leaf
  # ----------------------------------------------------------------------------

  proc toggleLeaf*(r: AndroidRenderer; vmRef: SettingsVM;
                   itemId: string): AndroidElement =
    ## Round-4 fix: drop the flat-pill "OFF"/"ON" label rectangle the
    ## round-3 leaf rendered (the reviewer flagged it as not reading
    ## like an M3 switch) and build a real M3 switch shape: an outer
    ## pill *track* (52 x 32 dp, 16 dp radius) plus an inner round
    ## *thumb* (24 dp circle) that lives at the leading edge when off
    ## and the trailing edge when on.  No more inline text; the thumb
    ## position is the affordance.
    ##
    ## The element switches from `<button>` to `<div>` (mapped to
    ## `LinearLayout`) so it can host the thumb child.  The
    ## `type="checkbox"` attribute moves with it — the cross-renderer
    ## parity driver (`tests/test_settings_parity_across_renderers.nim`'s
    ## `androidToggleOf`) walks the row's last child and matches on
    ## `getAttribute(last, "type") == "checkbox"`, so the contract is
    ## preserved.  `setOnClickListener` works on any `View`, so the
    ## click handler keeps firing into the same code path.
    let node = r.createElement("div")
    r.setAttribute(node, "type", "checkbox")
    r.setAttribute(node, "class", "settings-toggle")
    # M3 switch track metric — 52 x 32 dp pill.
    # Round-10: 56x32 dp switch + sync off-track grey.
    r.setStyle(node, "width", "56")
    r.setStyle(node, "height", "32")
    r.setStyle(node, "border-radius", "16")
    r.setStyle(node, "background-color", offTrackGrey)
    r.setStyle(node, "flex-direction", "row")

    # Two spacers + a thumb.  When OFF, the trailing spacer takes all
    # the slack and the thumb sits at the leading edge; when ON, the
    # leading spacer takes the slack and the thumb sits at the
    # trailing edge.  We toggle the spacer widths by toggling their
    # `flex-grow` weights inside the render effect below.
    let leadSpacer = r.createElement("div")
    r.appendChild(node, leadSpacer)

    let thumb = r.createElement("div")
    # M3 thumb metric — 24 dp circle, indigo when on / muted when off.
    r.setStyle(thumb, "width", "24")
    r.setStyle(thumb, "height", "24")
    r.setStyle(thumb, "border-radius", "12")
    r.setStyle(thumb, "background-color", "#ffffff")
    r.appendChild(node, thumb)

    let trailSpacer = r.createElement("div")
    r.appendChild(node, trailSpacer)

    let captured = vmRef
    let id = itemId
    let rCaptured = r
    createRenderEffect proc() =
      let value = captured.toggleValue(id)
      rCaptured.setAttribute(node, "data-value",
                             (if value: "true" else: "false"))
      if value:
        rCaptured.setAttribute(node, "checked", "checked")
        rCaptured.setStyle(node, "background-color", onTrackIndigo)
        # Thumb to the trailing edge.
        rCaptured.setStyle(leadSpacer, "flex-grow", "1")
        rCaptured.setStyle(trailSpacer, "flex-grow", "0")
      else:
        rCaptured.removeAttribute(node, "checked")
        rCaptured.setStyle(node, "background-color", offTrackGrey)
        # Thumb to the leading edge.
        rCaptured.setStyle(leadSpacer, "flex-grow", "0")
        rCaptured.setStyle(trailSpacer, "flex-grow", "1")
    r.addEventListener(node, "click", proc() =
      let current = rCaptured.getAttribute(node, "data-value") == "true"
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

  proc numberLeaf*(r: AndroidRenderer; vmRef: SettingsVM; itemId: string;
                   minValue, maxValue, stepValue: int;
                   suffix: string): AndroidElement =
    ## Round-3 fix: render the number leaf as a horizontal `[-] value
    ## [+]` stepper.
    ##
    ## Tree shape::
    ##
    ##   <div class="settings-number" type="" data-min ... data-step ...>
    ##     <input type="number" data-value=...> (HIDDEN — kept as the
    ##                                            parity-test click target)
    ##     <button class="settings-number-dec">-</button>
    ##     <span  class="settings-number-value">42</span>
    ##     <button class="settings-number-inc">+</button>
    ##     <span  class="settings-number-suffix">px</span>  (optional)
    ##
    ## The hidden `<input type="number">` retains its existing click
    ## handler so the parity driver's
    ## `r.setAttribute(input, "data-value", "18"); r.fireEvent(input,
    ## "click")` flow still drives the VM. On the device the input is
    ## sized to 0 dp and the visible chrome is the stepper buttons.
    let host = r.createElement("div")
    r.setAttribute(host, "class", "settings-number")
    r.setAttribute(host, "data-min", $minValue)
    r.setAttribute(host, "data-max", $maxValue)
    r.setAttribute(host, "data-step", $stepValue)
    if suffix.len > 0:
      r.setAttribute(host, "data-suffix", suffix)
    # Horizontal layout for the stepper.
    r.setStyle(host, "flex-direction", "row")
    r.setStyle(host, "gap", "6")

    # Hidden input — preserves the parity test contract.
    let inputNode = r.createElement("input")
    r.setAttribute(inputNode, "type", "number")
    r.setAttribute(inputNode, "data-min", $minValue)
    r.setAttribute(inputNode, "data-max", $maxValue)
    r.setAttribute(inputNode, "data-step", $stepValue)
    # Collapse the hidden input so it doesn't take any visible space.
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
    r.setStyle(decBtn, "font-size", "18")

    let valueLabel = r.createElement("span")
    r.setAttribute(valueLabel, "class", "settings-number-value")
    r.setStyle(valueLabel, "font-size", "16")
    r.setStyle(valueLabel, "color", onSurface)
    r.setStyle(valueLabel, "padding", "6")

    let incBtn = r.createElement("button")
    r.setTextContent(incBtn, "+")
    r.setAttribute(incBtn, "class", "settings-number-inc")
    r.setStyle(incBtn, "width", "40")
    r.setStyle(incBtn, "height", "40")
    r.setStyle(incBtn, "border-radius", "20")
    r.setStyle(incBtn, "background-color", surfaceMuted)
    r.setStyle(incBtn, "color", accentIndigo)
    r.setStyle(incBtn, "font-size", "18")

    createRenderEffect proc() =
      let value = captured.numberValue(id)
      rCaptured.setAttribute(host, "data-value", $value)
      rCaptured.setAttribute(inputNode, "data-value", $value)
      rCaptured.setTextContent(valueLabel, $value)

    # Existing click handler on the hidden input — preserves the
    # parity-driver flow (`setAttribute data-value` then fireEvent
    # "click").
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

    # Visible stepper buttons drive the VM directly. The handlers
    # clamp against the same bounds the parity driver uses.
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
      r.setStyle(suffixNode, "padding", "6")
      r.appendChild(host, suffixNode)

    host

  # ----------------------------------------------------------------------------
  # Choice leaf
  # ----------------------------------------------------------------------------

  proc choiceLeaf*(r: AndroidRenderer; vmRef: SettingsVM; itemId: string;
                   options: seq[string]): AndroidElement =
    ## Round-3 fix: render the choice leaf as a horizontal Material 3
    ## segmented row of FilterChip-like buttons (active = filled
    ## indigo, inactive = outlined indigo on the card surface).
    ##
    ## Tree shape::
    ##
    ##   <div class="settings-choice" data-options="A|B|C">
    ##     <select class="">             (HIDDEN — parity-test click target)
    ##       <option data-value="A">A</option>
    ##       <option data-value="B">B</option>
    ##       …
    ##     </select>
    ##     <button class="settings-choice-chip" data-chip="A">A</button>
    ##     <button class="settings-choice-chip" data-chip="B">B</button>
    ##     …
    ##
    ## The hidden `<select>` has its `class` left empty so the parity
    ## driver's `androidChoiceSelectOf` still finds it (it scans for
    ## the first child with empty class). Visible chip buttons drive
    ## the VM directly via per-button click handlers.
    let host = r.createElement("div")
    r.setAttribute(host, "class", "settings-choice")
    r.setAttribute(host, "data-options", options.join("|"))
    # Horizontal segmented layout.
    r.setStyle(host, "flex-direction", "row")
    r.setStyle(host, "gap", "6")

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

    # Collapse the hidden select on the device.
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

    # Visible chip row.
    proc makeChipHandler(opt: string): proc() =
      result = proc() = discard captured.setChoice(id, opt)

    proc makeChipEffect(chipNode: AndroidElement; opt: string) =
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
      r.setStyle(chip, "height", "32")
      r.setStyle(chip, "border-radius", "16")
      r.setStyle(chip, "padding", "8")
      r.setStyle(chip, "font-size", "13")
      r.addEventListener(chip, "click", makeChipHandler(opt))
      makeChipEffect(chip, opt)
      r.appendChild(host, chip)

    host

  # ----------------------------------------------------------------------------
  # Group container + header
  # ----------------------------------------------------------------------------

  proc groupContainerLeaf*(r: AndroidRenderer): AndroidElement =
    ## Round-4 fix: wrap the group in its own M3 *surface card* so the
    ## catalogue reads as a stack of discrete cards rather than a flat
    ## run of headers.  Each group now gets the same neutral surface
    ## fill, 12 dp rounded corners, 4 dp elevation, and 12 dp interior
    ## padding the task_app rows already use.  The leaves only emit
    ## the styling; the MainActivity `applyStyle` handler interprets
    ## `elevation` via `View.elevation` (a real M3 shadow), with the
    ## GradientDrawable corner radius drawing the rounded surface.
    let node = r.createElement("section")
    r.setAttribute(node, "class", "settings-group")
    r.setAttribute(node, ComponentPathAttr, SettingsGroupPath)
    r.setAttribute(node, ElementKindAttr, "group")
    r.setStyle(node, "background-color", surfaceCard)
    r.setStyle(node, "border-radius", "12")
    r.setStyle(node, "padding", "12")
    # Round-10: drop elevation; M3 dark theme overlay tinted indigo.
    r.setStyle(node, "flex-direction", "column")
    r.setStyle(node, "gap", "8")
    node

  proc groupHeaderLeaf*(r: AndroidRenderer; label, description: string):
                       AndroidElement =
    ## Round-4 fix: the round-3 review still flagged the header
    ## typography as eating ~30 % of the preview before any item was
    ## visible. The h2 tag maps to TextView with no default font-size,
    ## but Android's TextView default sp (~14) plus the `<h2>` semantic
    ## hint at large defaults — the leaf now sets `font-size` to a
    ## tight M3 `titleMedium` (16 sp) explicitly and drops the
    ## description size to 11 sp (M3 `labelSmall`).  The header host's
    ## vertical padding shrinks from 8 dp to 4 dp so the row no longer
    ## squats over the group's items.
    let host = r.createElement("header")
    r.setAttribute(host, "class", "settings-group-header")
    r.setAttribute(host, "data-label", label)
    r.setAttribute(host, ComponentPathAttr, SettingsGroupHeaderPath)
    r.setAttribute(host, ElementKindAttr, "group-header")
    if description.len > 0:
      r.setAttribute(host, "data-description", description)
    r.setStyle(host, "padding", "4")

    let h2 = r.createElement("h2")
    r.setAttribute(h2, "class", "settings-group-header-label")
    r.setTextContent(h2, label)
    # M3 titleMedium = 16 sp.
    r.setStyle(h2, "font-size", "16")
    r.setStyle(h2, "color", onSurface)
    r.appendChild(host, h2)

    if description.len > 0:
      let p = r.createElement("p")
      r.setAttribute(p, "class", "settings-group-header-description")
      r.setTextContent(p, description)
      # M3 labelSmall = 11 sp — keeps the secondary line subordinate
      # to the title.
      r.setStyle(p, "font-size", "11")
      r.setStyle(p, "color", mutedText)
      r.appendChild(host, p)

    host

else:
  ## Linux/non-android hosts: the leaf surface is intentionally empty.
  ## See `task_app/android/leaves.nim` for the same gating rationale.
  ## The cross-compile gate (`tests/test_android_leaves_compile.nim`)
  ## validates the Android renderer surface from this host.
  discard
