## settings_app/web/leaves.nim — Layer-1 web leaves for the settings demo.
##
## EX-M17: per-item subscriptions. Each value-bearing leaf now takes a
## `SettingsVM` reference + the item id and subscribes to the VM's
## per-item value signal via `createRenderEffect`. This is the
## load-bearing fix for the EX-M16 review architectural note —
## programmatic VM mutations (post-load by fake_db's refresh) now
## propagate to the DOM without a re-mount.
##
## Event wiring contract (uniform across web leaves):
##
##   * `toggleLeaf` — `<input type="checkbox">` with a `click` listener
##     that calls `vmRef.setToggle(itemId, !current)`. A
##     `createRenderEffect` over `vmRef.toggleValue(itemId)` keeps the
##     `data-value` / `checked` attributes in sync with the VM.
##   * `numberLeaf` — `<input type="number">` with a `change` listener
##     that parses, clamps, and calls `vmRef.setNumber(itemId, …)`. A
##     `createRenderEffect` over `vmRef.numberValue(itemId)` keeps the
##     `value` / `data-value` attributes in sync.
##   * `choiceLeaf` — `<select>` with a `change` listener that calls
##     `vmRef.setChoice(itemId, picked)`. A `createRenderEffect` over
##     `vmRef.choiceValue(itemId)` keeps the `data-value` /
##     `<option selected>` markers in sync.
##
## All eight procs are `proc` (not `template`) so the EX-M11 shell can
## call them by name from inside a `template ... {.dirty.}` include.

import std/strutils
import std/tables

import isonim/core/computation  # createRenderEffect
import isonim/testing/mock_dom

import settings_app/core/vm

# ----------------------------------------------------------------------------
# Layout containers
# ----------------------------------------------------------------------------

proc itemContainerLeaf*(r: MockRenderer): MockNode =
  let node = r.createElement("div")
  r.setAttribute(node, "class", "settings-item")
  node

proc labelLeaf*(r: MockRenderer; text: string): MockNode =
  let node = r.createElement("label")
  r.setAttribute(node, "class", "settings-label")
  r.appendChild(node, r.createTextNode(text))
  node

proc descriptionLeaf*(r: MockRenderer; text: string): MockNode =
  let node = r.createElement("span")
  r.setAttribute(node, "class", "setting-description")
  r.appendChild(node, r.createTextNode(text))
  node

# ----------------------------------------------------------------------------
# Toggle leaf — <input type="checkbox">
# ----------------------------------------------------------------------------

proc toggleLeaf*(r: MockRenderer; vmRef: SettingsVM;
                 itemId: string): MockNode =
  ## Raw HTML checkbox. The attribute mirror is driven reactively from
  ## `vmRef.toggleValue(itemId)`; the click handler reads the VM's
  ## current value (untracked) and dispatches the inverse through
  ## `vmRef.setToggle`. The `createRenderEffect` re-runs whenever the
  ## VM's per-item signal mutates — including programmatic mutations
  ## from fake_db's refresh path.
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
    let current = node.attributes.getOrDefault("data-value") == "true"
    discard captured.setToggle(id, not current))
  node

# ----------------------------------------------------------------------------
# Number leaf — <input type="number">
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

proc numberLeaf*(r: MockRenderer; vmRef: SettingsVM; itemId: string;
                 minValue, maxValue, stepValue: int;
                 suffix: string): MockNode =
  ## Wrapper `<div>` carrying an `<input type="number">` plus an
  ## optional suffix `<span>`. The visible value mirrors
  ## `vmRef.numberValue(itemId)` via `createRenderEffect`; the change
  ## listener parses, clamps, and dispatches through
  ## `vmRef.setNumber(itemId, …)`.
  let host = r.createElement("div")
  r.setAttribute(host, "class", "settings-number")
  r.setAttribute(host, "data-min", $minValue)
  r.setAttribute(host, "data-max", $maxValue)
  r.setAttribute(host, "data-step", $stepValue)
  if suffix.len > 0:
    r.setAttribute(host, "data-suffix", suffix)

  let inputNode = r.createElement("input")
  r.setAttribute(inputNode, "type", "number")
  r.setAttribute(inputNode, "min", $minValue)
  r.setAttribute(inputNode, "max", $maxValue)
  r.setAttribute(inputNode, "step", $stepValue)
  let captured = vmRef
  let id = itemId
  createRenderEffect proc() =
    let value = captured.numberValue(id)
    r.setAttribute(host, "data-value", $value)
    r.setAttribute(inputNode, "value", $value)
  let lo = minValue
  let hi = maxValue
  r.addEventListener(inputNode, "change", proc() =
    let raw = inputNode.attributes.getOrDefault("value").strip()
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
    r.appendChild(suffixNode, r.createTextNode(suffix))
    r.appendChild(host, suffixNode)

  host

# ----------------------------------------------------------------------------
# Choice leaf — <select> with <option> children
# ----------------------------------------------------------------------------

proc choiceLeaf*(r: MockRenderer; vmRef: SettingsVM; itemId: string;
                 options: seq[string]): MockNode =
  ## Wrapper `<div>` hosting a `<select>` with one `<option>` per choice.
  ## The current value lives on both the wrapper's `data-value` and
  ## the `<select>`'s `value` attribute, kept in sync with
  ## `vmRef.choiceValue(itemId)` via `createRenderEffect`. The `change`
  ## listener forwards the picked value through `vmRef.setChoice(itemId, …)`.
  let host = r.createElement("div")
  r.setAttribute(host, "class", "settings-choice")
  r.setAttribute(host, "data-options", options.join("|"))

  let selectNode = r.createElement("select")
  let captured = vmRef
  let id = itemId
  let capturedOptions = options

  # Build option children once; the `selected` attribute on each is
  # repositioned by the createRenderEffect.
  for opt in options:
    let optionNode = r.createElement("option")
    r.setAttribute(optionNode, "value", opt)
    r.appendChild(optionNode, r.createTextNode(opt))
    r.appendChild(selectNode, optionNode)

  createRenderEffect proc() =
    let value = captured.choiceValue(id)
    r.setAttribute(host, "data-value", value)
    r.setAttribute(selectNode, "value", value)
    for optionNode in selectNode.children:
      if optionNode.attributes.getOrDefault("value") == value:
        r.setAttribute(optionNode, "selected", "selected")
      else:
        r.removeAttribute(optionNode, "selected")

  r.addEventListener(selectNode, "change", proc() =
    let picked = selectNode.attributes.getOrDefault("value")
    # Reject values not in our options — match the VM's policy.
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

proc groupContainerLeaf*(r: MockRenderer): MockNode =
  let node = r.createElement("section")
  r.setAttribute(node, "class", "settings-group")
  node

proc groupHeaderLeaf*(r: MockRenderer; label, description: string): MockNode =
  let host = r.createElement("header")
  r.setAttribute(host, "class", "settings-group-header")
  r.setAttribute(host, "data-label", label)
  if description.len > 0:
    r.setAttribute(host, "data-description", description)

  let h2 = r.createElement("h2")
  r.setAttribute(h2, "class", "settings-group-header-label")
  r.appendChild(h2, r.createTextNode(label))
  r.appendChild(host, h2)

  if description.len > 0:
    let p = r.createElement("p")
    r.setAttribute(p, "class", "settings-group-header-description")
    r.appendChild(p, r.createTextNode(description))
    r.appendChild(host, p)

  host
