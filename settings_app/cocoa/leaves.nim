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

  import isonim/core/computation  # createRenderEffect
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
    # M-EVP-14 round-3: each item row gets a real fixed slice inside
    # the group container (~52 px). Without this, the prior heuristic
    # split the group's body height equally among header + N items,
    # squeezing each item down to single-digit pixels and losing all
    # of the toggle / stepper / popup widgets in the captured raster.
    # The label sits above the widget vertically; the wrapper itself
    # stacks vertically by default.
    r.setAttribute(node, "data-fixed-height", "52")
    node

  proc labelLeaf*(r: CocoaRenderer; text: string): CocoaElement =
    let node = r.createElement("label")
    r.setAttribute(node, "class", "settings-label")
    r.setTextContent(node, text)
    node

  proc descriptionLeaf*(r: CocoaRenderer; text: string): CocoaElement =
    let node = r.createElement("span")
    r.setAttribute(node, "class", "settings-description")
    r.setTextContent(node, text)
    node

  # ----------------------------------------------------------------------------
  # Toggle leaf
  # ----------------------------------------------------------------------------

  proc toggleLeaf*(r: CocoaRenderer; vmRef: SettingsVM;
                   itemId: string): CocoaElement =
    let node = r.createElement("input")
    r.setAttribute(node, "type", "checkbox")
    let captured = vmRef
    let id = itemId
    let rCaptured = r
    createRenderEffect proc() =
      let value = captured.toggleValue(id)
      rCaptured.setAttribute(node, "data-value",
                             (if value: "true" else: "false"))
      if value:
        rCaptured.setAttribute(node, "checked", "checked")
      else:
        rCaptured.removeAttribute(node, "checked")
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
    let rCaptured = r
    createRenderEffect proc() =
      let value = captured.numberValue(id)
      rCaptured.setAttribute(host, "data-value", $value)
      rCaptured.setAttribute(inputNode, "data-value", $value)

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

    if suffix.len > 0:
      let suffixNode = r.createElement("span")
      r.setAttribute(suffixNode, "class", "settings-number-suffix")
      r.setTextContent(suffixNode, suffix)
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

  proc groupHeaderLeaf*(r: CocoaRenderer; label, description: string):
                       CocoaElement =
    let host = r.createElement("header")
    r.setAttribute(host, "class", "settings-group-header")
    r.setAttribute(host, "data-label", label)
    r.setAttribute(host, ComponentPathAttr, SettingsGroupHeaderPath)
    r.setAttribute(host, ElementKindAttr, "group-header")
    # M-EVP-14 round-3: pin the header to a fixed height so the
    # group-container layout reserves its slice up front and lets
    # the per-item rows below claim the remaining vertical space.
    r.setAttribute(host, "data-fixed-height", "44")
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
