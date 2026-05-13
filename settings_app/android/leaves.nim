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

when defined(android) or defined(mockJni):
  import std/strutils

  import isonim/core/computation  # createRenderEffect
  import isonim_android/renderer
  import isonim_render_serve/element_tree_attrs

  import settings_app/core/vm
  import settings_app/core/component_paths

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
    node

  proc labelLeaf*(r: AndroidRenderer; text: string): AndroidElement =
    let node = r.createElement("label")
    r.setAttribute(node, "class", "settings-label")
    r.setTextContent(node, text)
    node

  proc descriptionLeaf*(r: AndroidRenderer; text: string): AndroidElement =
    let node = r.createElement("span")
    r.setAttribute(node, "class", "settings-description")
    r.setTextContent(node, text)
    node

  # ----------------------------------------------------------------------------
  # Toggle leaf
  # ----------------------------------------------------------------------------

  proc toggleLeaf*(r: AndroidRenderer; vmRef: SettingsVM;
                   itemId: string): AndroidElement =
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

  proc numberLeaf*(r: AndroidRenderer; vmRef: SettingsVM; itemId: string;
                   minValue, maxValue, stepValue: int;
                   suffix: string): AndroidElement =
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

  proc choiceLeaf*(r: AndroidRenderer; vmRef: SettingsVM; itemId: string;
                   options: seq[string]): AndroidElement =
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

  proc groupContainerLeaf*(r: AndroidRenderer): AndroidElement =
    let node = r.createElement("section")
    r.setAttribute(node, "class", "settings-group")
    r.setAttribute(node, ComponentPathAttr, SettingsGroupPath)
    r.setAttribute(node, ElementKindAttr, "group")
    node

  proc groupHeaderLeaf*(r: AndroidRenderer; label, description: string):
                       AndroidElement =
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

else:
  ## Linux/non-android hosts: the leaf surface is intentionally empty.
  ## See `task_app/android/leaves.nim` for the same gating rationale.
  ## The cross-compile gate (`tests/test_android_leaves_compile.nim`)
  ## validates the Android renderer surface from this host.
  discard
