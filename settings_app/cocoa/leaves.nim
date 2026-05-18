## settings_app/cocoa/leaves.nim — Layer-1 Cocoa leaves for the settings demo.
##
## EX-M20: Cocoa port of the settings_app leaves, mirroring
## `settings_app/freya/leaves.nim`. The whole module body is gated
## `when defined(macosx):` because `isonim_cocoa/renderer` transitively
## imports `isonim_cocoa/objc_runtime` and the AppKit FFI wrappers, none
## of which link on a Linux host. On Linux the module collapses to an
## empty shell so `just test` keeps passing while the cross-compile gate
## drives the macOS-target check.
##
## Per-item subscriptions follow the EX-M17 pattern (already in place
## for the Freya/GPUI/TUI/web leaves): each value-bearing leaf takes a
## `SettingsVM` reference + the item id and subscribes via
## `createRenderEffect`. Programmatic VM mutations propagate to the
## materialised Cocoa view tree without a re-mount.
##
## Renderer-method-call discipline: unlike Freya/GPUI which export
## bare `getAttribute(node, name)` / `childCount(node)` / `nthChild(...)`
## procs, the Cocoa renderer's helpers are methods on the renderer
## (`r.getAttribute(node, name)`, `r.childCount(node)`, ...). The leaves
## use the renderer-method style throughout so the surface stays uniform
## with `task_app/cocoa/leaves.nim` (which already uses `r.childCount`,
## `r.nthChild`).

when defined(macosx):
  import std/strutils

  import isonim/core/computation # createRenderEffect
  import isonim_cocoa/renderer
  import isonim_render_serve/element_tree_attrs

  import settings_app/core/vm
  import settings_app/core/component_paths

  # ----------------------------------------------------------------------------
  # Layout containers
  # ----------------------------------------------------------------------------

  proc itemContainerLeaf*(r: CocoaRenderer): CocoaElement =
    let node = r.createElement("div")
    r.setAttribute(node, "class", "settings-item")
    # EX-M23c: component-path annotation; identical strings to TUI /
    # GPUI / Freya / Android counterparts (the cross-renderer
    # set-equality invariant). The RS-M5 AppKit capture path does
    # read a small set of layout-driving ``data-*`` attributes
    # (``data-layout``, ``data-fixed-height``, ``data-fixed-width``)
    # to hint per-row geometry; everything else still collapses to
    # the default vertical-stack heuristic, so cross-renderer
    # F-packet shape stays comparable.
    r.setAttribute(node, ComponentPathAttr, SettingsRowPath)
    r.setAttribute(node, ElementKindAttr, "row")
    # M-EVP-14 round-4: bump the row's fixed slice to ~64 px so the
    # label / description / widget triplet inside each row can each
    # claim a real vertical band (round-3 sized the row at 52 px and
    # the equal-flex split left ~17 px per child, so the AppKit
    # widgets ended up as full-width single-pixel strips). Round-4
    # also adds explicit ``data-fixed-height`` hints on each child
    # leaf below so the row's three slices line up as
    # ``[label 20 px] [description flex] [widget 24 px]``.
    r.setAttribute(node, "data-fixed-height", "64")
    node

  proc labelLeaf*(r: CocoaRenderer; text: string): CocoaElement =
    let node = r.createElement("label")
    r.setAttribute(node, "class", "settings-label")
    r.setTextContent(node, text)
    # M-EVP-14 round-4: pin the primary label to a fixed vertical
    # band so it doesn't soak up the row's height share and squeeze
    # the widget below to a sliver.
    r.setAttribute(node, "data-fixed-height", "20")
    # M-EVP-14 round-8: NSTextField's default ``controlTextColor`` is
    # near-black, and the cocoa adapter's ``neutralTint`` paints
    # every container in the #18..#3A dark-grey band. Without an
    # explicit foreground, the label text disappears entirely
    # (round-7's bezel-less fix only painted button titles white;
    # ``<label>`` / ``<span>`` / ``<p>`` still inherit the default).
    # The renderer's ``applyStyle "color"`` branch wires
    # ``setTextColor:`` for ``ekLabel`` (see
    # ``isonim-cocoa/src/isonim_cocoa/renderer.nim`` lines 433-442).
    r.setStyle(node, "color", "#ecedf3")
    node

  proc descriptionLeaf*(r: CocoaRenderer; text: string): CocoaElement =
    let node = r.createElement("span")
    r.setAttribute(node, "class", "settings-description")
    r.setTextContent(node, text)
    # M-EVP-14 round-4: the description is the row's flex child;
    # leaving it unsized so it absorbs any leftover vertical slack
    # without starving the widget below.
    # M-EVP-14 round-8: pick a dimmer grey foreground so the
    # description reads as a secondary helper line below the primary
    # label (same #a3a4ad muted grey the placeholder rows in
    # ``task_app/cocoa/leaves.nim`` use). Without this, NSTextField
    # paints the body in black on the adapter's dark surface and
    # the row collapses to label + invisible-strip + widget.
    r.setStyle(node, "color", "#a3a4ad")
    node

  # ----------------------------------------------------------------------------
  # Toggle leaf
  # ----------------------------------------------------------------------------

  proc toggleLeaf*(r: CocoaRenderer; vmRef: SettingsVM;
                   itemId: string): CocoaElement =
    ## P-B fix: emit a real ``<switch>`` element so the cocoa renderer
    ## maps it to ``ekSwitch`` → ``NSSwitch``. NSSwitch ships its own
    ## pill-shaped on/off chrome (track + knob, animated) so the row's
    ## right band paints a recognisable toggle widget in the captured
    ## PNG instead of a coloured ``[OFF]`` / ``[ON]`` text strip in an
    ## NSTextField (the previous ``<input type="checkbox">`` mapping).
    let node = r.createElement("switch")
    # NSSwitch's natural height is ~22 px on macOS; round up to 24
    # so the row reserves a comfortable band.
    r.setAttribute(node, "data-fixed-height", "24")
    # Pin a fixed width too so the headless layout pass doesn't
    # stretch the switch across the full row.
    r.setAttribute(node, "data-fixed-width", "44")
    # M-EVP-14 Wave T (T-8 fix): tint the on-state in the IsoNim brand
    # indigo instead of the macOS system accent (teal / system-blue
    # on Sonoma). The cocoa renderer's ``color`` style branch now
    # routes to ``-[NSSwitch setOnTintColor:]`` for ekSwitch elements
    # (probed via ``respondsToSelector:`` for graceful pre-10.15
    # fallback).
    r.setStyle(node, "color", "#7c7aed")
    let captured = vmRef
    let id = itemId
    let rCaptured = r
    createRenderEffect proc() =
      let value = captured.toggleValue(id)
      # ``setAttribute("checked", "true"|"false")`` lands on
      # ``setSwitchState:`` via ``applyAttribute`` (see
      # ``isonim_cocoa/renderer.nim`` ekSwitch branch).
      rCaptured.setAttribute(node, "data-value",
                             (if value: "true" else: "false"))
      if value:
        rCaptured.setAttribute(node, "checked", "true")
      else:
        rCaptured.setAttribute(node, "checked", "false")
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

  proc numberLeaf*(r: CocoaRenderer; vmRef: SettingsVM; itemId: string;
                   minValue, maxValue, stepValue: int;
                   suffix: string): CocoaElement =
    ## P-B fix: render a real NSStepper next to an NSTextField that
    ## shows the current numeric value. Previously the leaf only
    ## emitted an ``<input type="number">`` (NSTextField) so the cell
    ## had digits but no visible up/down arrows — the strict reviewer
    ## flagged the absence of stepper chrome. The cocoa renderer maps
    ## ``<stepper>`` → ``ekStepper`` → ``newNSStepper(...)`` which
    ## paints the canonical two-button arrow control.
    let host = r.createElement("div")
    r.setAttribute(host, "class", "settings-number")
    r.setAttribute(host, "data-min", $minValue)
    r.setAttribute(host, "data-max", $maxValue)
    r.setAttribute(host, "data-step", $stepValue)
    if suffix.len > 0:
      r.setAttribute(host, "data-suffix", suffix)
    r.setAttribute(host, "data-layout", "horizontal")
    # Wave S-3: bump the host band from 28 → 32 px. Round-10's 28 px
    # left only 24 px of usable child height (the adapter reserves a
    # 4-px vertical inset, 2 px top + 2 px bottom). NSTextField's
    # default rendering centred the digits in those 24 px but the
    # NSStepper's two-arrow chrome is canonically 27 px tall, so the
    # widget got clipped at the bottom — reading as the "stepper
    # arrows look stacked / cramped" defect the reviewer flagged. At
    # 32 px the child slot is 28 px, which gives the stepper a full
    # band and the digit cell a comfortable vertically-centred baseline.
    r.setAttribute(host, "data-fixed-height", "32")

    # NSTextField for the displayed digit value.
    let inputNode = r.createElement("input")
    r.setAttribute(inputNode, "type", "number")
    r.setAttribute(inputNode, "data-min", $minValue)
    r.setAttribute(inputNode, "data-max", $maxValue)
    r.setAttribute(inputNode, "data-step", $stepValue)
    # Round-10 fix: widen the digit slot from 40→60 px so a 1-3
    # digit value sits centred in a comfortable text field rather
    # than crowded against the stepper arrows.
    r.setAttribute(inputNode, "data-fixed-width", "60")
    r.setStyle(inputNode, "background-color", "#15161f")
    r.setStyle(inputNode, "color", "#ecedf3")

    let captured = vmRef
    let id = itemId
    let rCaptured = r
    createRenderEffect proc() =
      let value = captured.numberValue(id)
      rCaptured.setAttribute(host, "data-value", $value)
      rCaptured.setAttribute(inputNode, "data-value", $value)
      rCaptured.setTextContent(inputNode, $value)

    let lo = minValue
    let hi = maxValue
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
    r.appendChild(host, inputNode)

    # Round-10 fix: insert an 8-px breathing spacer between the
    # digit field and the stepper arrows. The horizontal layout
    # heuristic doesn't honour CSS ``gap`` on plain ``<div>``
    # containers (it only applies to ekStack), so we add an empty
    # ``<div>`` with ``data-fixed-width: 8`` to claim that band.
    let spacer = r.createElement("div")
    r.setAttribute(spacer, "data-fixed-width", "8")
    r.appendChild(host, spacer)

    # NSStepper sibling — the actual up/down arrow widget. Maps to
    # ``ekStepper`` → ``newNSStepper(min, max, value, increment)``.
    # The renderer's ``applyAttribute`` wires ``min`` / ``max`` /
    # ``value`` directly to NSStepper's ``setMinValue:`` /
    # ``setMaxValue:`` / ``setDoubleValue:`` (see
    # ``isonim-cocoa/src/isonim_cocoa/renderer.nim``).
    let stepperNode = r.createElement("stepper")
    r.setAttribute(stepperNode, "min", $minValue)
    r.setAttribute(stepperNode, "max", $maxValue)
    r.setAttribute(stepperNode, "data-fixed-width", "19")
    r.setAttribute(stepperNode, "data-fixed-height", "27")
    createRenderEffect proc() =
      rCaptured.setAttribute(stepperNode, "value",
                             $captured.numberValue(id))
    r.addEventListener(stepperNode, "change", proc() =
      # NSStepper -change fires when the user clicks an arrow; we
      # don't read the post-click value back from the control because
      # the headless capture path never dispatches real user clicks,
      # but wiring the callback keeps the on-device target-action
      # surface in place.
      discard)
    r.appendChild(host, stepperNode)

    if suffix.len > 0:
      let suffixNode = r.createElement("span")
      r.setAttribute(suffixNode, "class", "settings-number-suffix")
      r.setTextContent(suffixNode, suffix)
      r.setAttribute(suffixNode, "data-fixed-width", "32")
      r.setStyle(suffixNode, "color", "#a3a4ad")
      r.appendChild(host, suffixNode)

    host

  # ----------------------------------------------------------------------------
  # Choice leaf
  # ----------------------------------------------------------------------------

  proc choiceLeaf*(r: CocoaRenderer; vmRef: SettingsVM; itemId: string;
                   options: seq[string]): CocoaElement =
    let host = r.createElement("div")
    r.setAttribute(host, "class", "settings-choice")
    r.setAttribute(host, "data-options", options.join("|"))
    # M-EVP-14 round-4: pin the choice (NSPopUpButton) widget to its
    # natural AppKit height so the layout pass doesn't compress it
    # into a single-pixel strip. The host itself is a thin wrapper
    # around the live <select>; the inner select view consumes the
    # full slice via the default vertical-stack split (single child
    # → flex eats everything).
    r.setAttribute(host, "data-fixed-height", "24")

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

    # Wave S-3: the previous round-8 workaround appended a sibling
    # ``<span>`` mirroring ``vm.choiceValue(id)`` because the
    # ``<option>`` children weren't reaching NSPopUpButton's menu.
    # That mirror is no longer needed: ``isonim-cocoa@e6b2e7d4``
    # added ``<option>`` → ``popUpAddItem`` forwarding inside
    # ``appendChild``, so the NSPopUpButton now paints its real
    # current-selection title in its own chrome. With both surfaces
    # painting, the row showed "Default | Default" — the strict
    # reviewer flagged the duplication as the most visible cocoa
    # defect in the M-EVP-14 round-10 sweep. Drop the sibling span
    # and keep only the popup; ``selected`` attribute syncing on
    # the option nodes still routes to ``selectItemAtIndex:`` via
    # the renderer's ``applyAttribute`` branch for ekSelect children.

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
    host

  # ----------------------------------------------------------------------------
  # Group container + header
  # ----------------------------------------------------------------------------

  proc groupContainerLeaf*(r: CocoaRenderer): CocoaElement =
    let node = r.createElement("section")
    r.setAttribute(node, "class", "settings-group")
    r.setAttribute(node, ComponentPathAttr, SettingsGroupPath)
    r.setAttribute(node, ElementKindAttr, "group")
    node

  proc groupHeaderLeaf*(r: CocoaRenderer; label, description: string;
                        isFirst: bool = true;
                        isActive: bool = false): CocoaElement =
    ## Round-5 review: group headers previously rendered at the same
    ## visible weight as item labels (system NSTextField default ~13 px
    ## regular), so the eye had to count rows to find a group boundary.
    ## Three changes:
    ##
    ##   1. Set ``font-weight: 600`` on the header label. The current
    ##      Cocoa adapter silently drops this style key, but the leaf
    ##      now carries forward-compatible intent; once
    ##      ``isonim-cocoa/src/.../renderer.nim`` honours it (a
    ##      one-line ``boldSystemFontOfSize:`` wiring on top of the
    ##      existing ``setFontSize`` AppKit helper), the label will
    ##      render in a semibold weight on the device.
    ##   2. Bump the label's ``font-size`` so the header reads visibly
    ##      heavier than the item labels even *before* the font-weight
    ##      wiring lands — font-size is already plumbed end-to-end
    ##      through ``setFontSize`` (uses ``NSFont systemFontOfSize:``).
    ##      A header at 15 px reads as a "title" band relative to the
    ##      ~13 px body labels below.
    ##   3. For every non-first group header, bump the header's fixed
    ##      band from 44 px → 52 px. The adapter reserves the extra
    ##      8 px as effective top-of-section spacing (the header itself
    ##      keeps its visual content centred via its own padding) so
    ##      the group boundary reads as a deliberate gap rather than a
    ##      seamless row run.
    let host = r.createElement("header")
    r.setAttribute(host, "class", "settings-group-header")
    r.setAttribute(host, "data-label", label)
    r.setAttribute(host, ComponentPathAttr, SettingsGroupHeaderPath)
    r.setAttribute(host, ElementKindAttr, "group-header")
    # M-EVP-14 round-3: pin the header to a fixed height so the
    # group-container layout reserves its slice up front and lets
    # the per-item rows below claim the remaining vertical space.
    # Round-5: non-first headers get ~8 px extra band as inter-group
    # spacing.
    if isFirst:
      r.setAttribute(host, "data-fixed-height", "44")
    else:
      r.setAttribute(host, "data-fixed-height", "52")
    if description.len > 0:
      r.setAttribute(host, "data-description", description)

    let h2 = r.createElement("h2")
    r.setAttribute(h2, "class", "settings-group-header-label")
    r.setTextContent(h2, label)
    # Round-5 visual hierarchy: semibold + slightly larger so the
    # header label is unambiguously heavier than the body item labels.
    r.setStyle(h2, "font-weight", "600")
    r.setStyle(h2, "font-size", "15")
    # M-EVP-14 round-8 + round-10: paint the group title in the
    # indigo accent for the active group, in a lighter primary
    # foreground for the others. Both colours are legible against
    # the adapter's ``neutralTint`` palette (#28-#3A grey); the
    # active accent gives the user an unambiguous "this is the
    # currently-selected section" signal — the M-EVP-14 round-10
    # reviewer flagged the prior all-indigo headers as masking the
    # active/inactive distinction.
    r.setStyle(h2, "color",
               (if isActive: "#9d9bff" else: "#ecedf3"))
    r.appendChild(host, h2)

    if description.len > 0:
      let p = r.createElement("p")
      r.setAttribute(p, "class", "settings-group-header-description")
      r.setTextContent(p, description)
      # M-EVP-14 round-8: the header description sits directly below
      # the title on the same dark band; without an explicit
      # foreground it collapses to black-on-black.
      r.setStyle(p, "color", "#a3a4ad")
      r.appendChild(host, p)

    host
