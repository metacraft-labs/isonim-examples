## settings_app/web/leaves.nim — Layer-1 web leaves for the settings demo.
##
## EX-M11. Concrete platform components for the settings_app shell,
## written against the `MockRenderer` from `isonim/testing/mock_dom.nim`.
## `MockRenderer` is the canonical headless target for web tests; the
## browser `WebRenderer` exposes the same proc shape so the same DSL
## drives both.
##
## The 8-leaf contract documented in
## `settings_app/components/{toggle,number,choice}_item.nim` +
## `settings_app/components/group.nim` is satisfied here against raw
## HTML tags (`div`, `label`, `span`, `input`, `select`, `option`,
## `section`, `header`, `h2`, `p`). Web leaves intentionally avoid the
## `w*` widget wrappers that the TUI leaves use — those are the M11..M14
## widget tier for `TerminalRenderer`; the web side composes plain DOM
## nodes.
##
## Event wiring contract (uniform across web leaves):
##
##   * `toggleLeaf` — `<input type="checkbox">` with a `click` listener
##     that flips the checked state and dispatches `onChange(!current)`
##     through the captured closure. Tests fire the synthetic `click`
##     event via `fireEvent(node, "click")`.
##   * `numberLeaf` — `<input type="number">` with a `change` listener.
##     Tests update `node.attributes["value"]` and dispatch `change` to
##     mimic a real browser's input commit. The closure parses + clamps
##     to `[minValue, maxValue]` before forwarding to the component's
##     `onChange(newValue: int)`.
##   * `choiceLeaf` — `<select>` with `<option>` children and a `change`
##     listener. Tests assign `node.attributes["value"]` and dispatch
##     `change`; the closure forwards the selected value to the
##     component's `onChange(newValue: string)`. Invalid values are
##     rejected by the VM (`setChoice`), not by the leaf.
##
## All eight procs are `proc` (not `template`) so the EX-M11 shell can
## call them by name from inside a `template ... {.dirty.}` include.
## The renderer-agnostic components in `settings_app/components/*.nim`
## resolve the unqualified leaf names through the includer's lexical
## scope: the composition root imports this module *first*, then
## includes the component files, then includes the shell.

import std/strutils
import std/tables

import isonim/testing/mock_dom

# ----------------------------------------------------------------------------
# Layout containers
# ----------------------------------------------------------------------------

proc itemContainerLeaf*(r: MockRenderer): MockNode =
  ## Row container hosting a label, optional description, and the
  ## kind-specific input element. The class is mirrored from the EX-M9
  ## helper so tests / introspection tools keyed on `.settings-item`
  ## continue to match.
  let node = r.createElement("div")
  r.setAttribute(node, "class", "settings-item")
  node

proc labelLeaf*(r: MockRenderer; text: string): MockNode =
  ## Primary item label. `<label>` is the natural fit for an HTML form
  ## row; we do not bother wiring `for=…` to the input id because the
  ## `MockRenderer` does not synthesise label-association semantics —
  ## the click-to-focus behaviour is delivered by the production
  ## `WebRenderer` only when an explicit `for` is set, which is not
  ## part of the EX-M11 contract.
  let node = r.createElement("label")
  r.setAttribute(node, "class", "settings-label")
  r.appendChild(node, r.createTextNode(text))
  node

proc descriptionLeaf*(r: MockRenderer; text: string): MockNode =
  ## Secondary description text. Rendered as a dim `<span>`; the class
  ## is `setting-description` (matches the design-doc HTML in the
  ## EX-M11 milestone description verbatim).
  let node = r.createElement("span")
  r.setAttribute(node, "class", "setting-description")
  r.appendChild(node, r.createTextNode(text))
  node

# ----------------------------------------------------------------------------
# Toggle leaf — <input type="checkbox">
# ----------------------------------------------------------------------------

proc toggleLeaf*(r: MockRenderer; value: bool;
                 onChange: proc(newValue: bool)): MockNode =
  ## Raw HTML checkbox. The current value is stored both as the
  ## `checked` attribute (the standard DOM hook) and `data-value` (a
  ## test-friendly mirror); the `click` event listener flips the
  ## attribute and dispatches `onChange(!current)`.
  ##
  ## We use the no-arg `addEventListener` overload because the captured
  ## state (the node + the `onChange` closure) is enough to compute the
  ## new value without inspecting the `MockEvent`.
  let node = r.createElement("input")
  r.setAttribute(node, "type", "checkbox")
  r.setAttribute(node, "data-value", (if value: "true" else: "false"))
  if value:
    r.setAttribute(node, "checked", "checked")
  # The closure reads the current attribute on dispatch instead of
  # closing over `value` so a test that programmatically toggles
  # `data-value` between fires picks up the latest state. (The browser
  # toggles `checked` automatically on click; `MockRenderer` does not,
  # so we do the toggle ourselves here.)
  let onChangeRef = onChange
  r.addEventListener(node, "click", proc() =
    let current = node.attributes.getOrDefault("data-value") == "true"
    let next = not current
    if next:
      node.attributes["checked"] = "checked"
    else:
      node.attributes.del("checked")
    node.attributes["data-value"] = (if next: "true" else: "false")
    if onChangeRef != nil:
      onChangeRef(next))
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

proc numberLeaf*(r: MockRenderer; value: int;
                 minValue, maxValue, stepValue: int;
                 suffix: string;
                 onChange: proc(newValue: int)): MockNode =
  ## Wrapper `<div>` carrying an `<input type="number">` plus an
  ## optional suffix `<span>`. The wrapper hosts the test-friendly
  ## `data-*` attributes (min/max/step/value/suffix); the change
  ## listener lives on the inner input so the standard browser dispatch
  ## path is preserved.
  ##
  ## The closure reads `node.attributes["value"]` at dispatch time to
  ## get the user's typed value (in a real browser this is the input's
  ## live `value` property; `MockRenderer` stores it in the attribute
  ## table). It parses + clamps to `[minValue, maxValue]` and then
  ## forwards the clamped int. The VM also clamps internally so the
  ## leaf can safely emit any int.
  let host = r.createElement("div")
  r.setAttribute(host, "class", "settings-number")
  r.setAttribute(host, "data-min", $minValue)
  r.setAttribute(host, "data-max", $maxValue)
  r.setAttribute(host, "data-step", $stepValue)
  r.setAttribute(host, "data-value", $value)
  if suffix.len > 0:
    r.setAttribute(host, "data-suffix", suffix)

  let inputNode = r.createElement("input")
  r.setAttribute(inputNode, "type", "number")
  r.setAttribute(inputNode, "min", $minValue)
  r.setAttribute(inputNode, "max", $maxValue)
  r.setAttribute(inputNode, "step", $stepValue)
  r.setAttribute(inputNode, "value", $value)
  let onChangeRef = onChange
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
    r.setAttribute(inputNode, "value", $clamped)
    r.setAttribute(host, "data-value", $clamped)
    if onChangeRef != nil:
      onChangeRef(clamped))
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

proc choiceLeaf*(r: MockRenderer; value: string;
                 options: seq[string];
                 onChange: proc(newValue: string)): MockNode =
  ## Wrapper `<div>` hosting a `<select>` with one `<option>` per choice.
  ## The current value lives on both the wrapper's `data-value` (test
  ## hook) and the `<select>`'s `value` attribute (DOM convention). The
  ## `change` listener reads `select.attributes["value"]` and forwards
  ## the new value through the component's `onChange`.
  let host = r.createElement("div")
  r.setAttribute(host, "class", "settings-choice")
  r.setAttribute(host, "data-value", value)
  r.setAttribute(host, "data-options", options.join("|"))

  let selectNode = r.createElement("select")
  r.setAttribute(selectNode, "value", value)
  for opt in options:
    let optionNode = r.createElement("option")
    r.setAttribute(optionNode, "value", opt)
    if opt == value:
      r.setAttribute(optionNode, "selected", "selected")
    r.appendChild(optionNode, r.createTextNode(opt))
    r.appendChild(selectNode, optionNode)

  let onChangeRef = onChange
  r.addEventListener(selectNode, "change", proc() =
    let picked = selectNode.attributes.getOrDefault("value")
    r.setAttribute(host, "data-value", picked)
    if onChangeRef != nil:
      onChangeRef(picked))

  r.appendChild(host, selectNode)
  host

# ----------------------------------------------------------------------------
# Group container + header
# ----------------------------------------------------------------------------

proc groupContainerLeaf*(r: MockRenderer): MockNode =
  ## `<section>` wrapping a settings group's header + items. The web
  ## shell uses one container per *visible* group — in the sidebar+pane
  ## composition only the active group's container is built into the
  ## right-hand pane.
  let node = r.createElement("section")
  r.setAttribute(node, "class", "settings-group")
  node

proc groupHeaderLeaf*(r: MockRenderer; label, description: string): MockNode =
  ## Group header: an `<h2>` for the label and (when non-empty) a `<p>`
  ## for the description. The wrapper `<header>` lets tests locate the
  ## header by `class="settings-group-header"` while the inner heading
  ## carries the visible text.
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
