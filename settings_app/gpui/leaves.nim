## settings_app/gpui/leaves.nim — Layer-1 GPUI leaves for the settings demo.
##
## EX-M12. Concrete platform components for the settings_app shell,
## written against the `GpuiRenderer` from `isonim_gpui/renderer` (which
## wraps the real `gpui-nim-shim` Rust cdylib). Each leaf returns a
## `GpuiElement` ready for `appendChild`. The 8-leaf contract is the
## same surface satisfied by `settings_app/{tui,web}/leaves.nim`; the
## per-renderer differences are confined to which DOM-like primitives a
## leaf reaches for and how it observes user input.
##
## API gaps and design notes
## -------------------------
##
## The GPUI shim's element surface is intentionally flat: `createElement`
## takes an HTML-like tag string which the Rust side maps onto its own
## element model (`div` for containers, `span/p/h*/...` for text,
## `div`-with-events for interactive tags like `<input>` and `<select>`).
## We therefore lean on `class` and `data-*` attributes for everything
## test-introspectable; the same pattern matches what the EX-M3 GPUI
## task_app leaves already do.
##
## Just like EX-M3, GPUI's `<input>`-style elements have no native
## `change` / `submit` event surface — every interactive element fires
## `click`. The number leaf therefore exposes its current value through
## `data-value` and accepts user input by having the test (or a
## composition root acting as a host driver) set `data-value` and fire
## `click`. The closure parses + clamps and forwards to `onChange`. The
## choice leaf works the same way: tests set `data-value` to the option
## string and fire `click`; the closure forwards.
##
## All eight procs are `proc` (not `template`) so the EX-M12 shell can
## call them by name from inside a `template ... {.dirty.}` include.
## The renderer-agnostic components in `settings_app/components/*.nim`
## resolve the unqualified leaf names through the includer's lexical
## scope: the composition root imports this module *first*, then
## includes the component files, then includes the shell.

import std/strutils

import isonim_gpui/renderer
import isonim_gpui/bindings

# ----------------------------------------------------------------------------
# Layout containers
# ----------------------------------------------------------------------------

proc itemContainerLeaf*(r: GpuiRenderer): GpuiElement =
  ## Row container hosting a label, optional description, and the
  ## kind-specific input element. The class mirrors the TUI/web leaves
  ## (`settings-item`) so cross-renderer parity probes line up.
  let node = r.createElement("div")
  r.setAttribute(node, "class", "settings-item")
  node

proc labelLeaf*(r: GpuiRenderer; text: string): GpuiElement =
  ## Primary item label. Built with a `label`-mapped element so the
  ## text content lands in the shim's text bucket.
  let node = r.createElement("label")
  r.setAttribute(node, "class", "settings-label")
  r.setTextContent(node, text)
  node

proc descriptionLeaf*(r: GpuiRenderer; text: string): GpuiElement =
  ## Secondary description text.
  let node = r.createElement("span")
  r.setAttribute(node, "class", "settings-description")
  r.setTextContent(node, text)
  node

# ----------------------------------------------------------------------------
# Toggle leaf — clickable element
# ----------------------------------------------------------------------------

proc toggleLeaf*(r: GpuiRenderer; value: bool;
                 onChange: proc(newValue: bool)): GpuiElement =
  ## Clickable toggle. The current value lives on `data-value`
  ## (`"true"`/`"false"`); a `click` listener flips it and dispatches
  ## `onChange(!current)`. Tests fire `click` via the real shim event
  ## dispatcher (`fireEvent(node, "click")`).
  let node = r.createElement("input")
  r.setAttribute(node, "type", "checkbox")
  r.setAttribute(node, "data-value", (if value: "true" else: "false"))
  if value:
    r.setAttribute(node, "checked", "checked")
  let onChangeRef = onChange
  r.addEventListener(node, "click", proc() =
    let current = getAttribute(node, "data-value") == "true"
    let next = not current
    if next:
      r.setAttribute(node, "checked", "checked")
      r.setAttribute(node, "data-value", "true")
    else:
      r.removeAttribute(node, "checked")
      r.setAttribute(node, "data-value", "false")
    if onChangeRef != nil:
      onChangeRef(next))
  node

# ----------------------------------------------------------------------------
# Number leaf — input-like element with `data-value` driving the value.
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

proc numberLeaf*(r: GpuiRenderer; value: int;
                 minValue, maxValue, stepValue: int;
                 suffix: string;
                 onChange: proc(newValue: int)): GpuiElement =
  ## Wrapper `div` carrying an input-mapped element plus an optional
  ## suffix `<span>`. The host hosts the test-friendly `data-*`
  ## attributes (min/max/step/value/suffix); the click listener lives
  ## on the inner input so the standard shim dispatch path is preserved.
  ##
  ## API gap (see module docstring): GPUI's renderer surface has no
  ## `change`/`submit` event for input-mapped elements, so the leaf
  ## listens to `click` instead. The closure reads `data-value` from
  ## the inner input (mutated by the test driver before each fire),
  ## parses + clamps to `[minValue, maxValue]`, and forwards.
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
  r.setAttribute(inputNode, "data-min", $minValue)
  r.setAttribute(inputNode, "data-max", $maxValue)
  r.setAttribute(inputNode, "data-step", $stepValue)
  r.setAttribute(inputNode, "data-value", $value)
  let onChangeRef = onChange
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
    r.setAttribute(inputNode, "data-value", $clamped)
    r.setAttribute(host, "data-value", $clamped)
    if onChangeRef != nil:
      onChangeRef(clamped))
  r.appendChild(host, inputNode)

  if suffix.len > 0:
    let suffixNode = r.createElement("span")
    r.setAttribute(suffixNode, "class", "settings-number-suffix")
    r.setTextContent(suffixNode, suffix)
    r.appendChild(host, suffixNode)

  host

# ----------------------------------------------------------------------------
# Choice leaf — picker element with `data-value` driving the selection.
# ----------------------------------------------------------------------------

proc choiceLeaf*(r: GpuiRenderer; value: string;
                 options: seq[string];
                 onChange: proc(newValue: string)): GpuiElement =
  ## Wrapper `div` hosting a `select`-mapped element with one `option`
  ## child per choice. The current value lives on the wrapper's
  ## `data-value` (and the select's `data-value`). Test drivers assign
  ## `data-value` and fire `click`; the closure forwards through
  ## `onChange`. Invalid values are rejected by the VM (`setChoice`),
  ## not by the leaf.
  let host = r.createElement("div")
  r.setAttribute(host, "class", "settings-choice")
  r.setAttribute(host, "data-value", value)
  r.setAttribute(host, "data-options", options.join("|"))

  let selectNode = r.createElement("select")
  r.setAttribute(selectNode, "data-value", value)
  for opt in options:
    let optionNode = r.createElement("option")
    r.setAttribute(optionNode, "data-value", opt)
    if opt == value:
      r.setAttribute(optionNode, "selected", "selected")
    r.setTextContent(optionNode, opt)
    r.appendChild(selectNode, optionNode)

  let onChangeRef = onChange
  r.addEventListener(selectNode, "click", proc() =
    let picked = getAttribute(selectNode, "data-value")
    r.setAttribute(host, "data-value", picked)
    if onChangeRef != nil:
      onChangeRef(picked))

  r.appendChild(host, selectNode)
  host

# ----------------------------------------------------------------------------
# Group container + header
# ----------------------------------------------------------------------------

proc groupContainerLeaf*(r: GpuiRenderer): GpuiElement =
  ## `section`-mapped (→ div) wrapper for a settings group.
  let node = r.createElement("section")
  r.setAttribute(node, "class", "settings-group")
  node

proc groupHeaderLeaf*(r: GpuiRenderer; label, description: string):
                     GpuiElement =
  ## Group header. A `header`-mapped (→ div) wrapper carrying the label
  ## (as an `<h2>` child) and, when non-empty, the description (as a
  ## `<p>` child).
  let host = r.createElement("header")
  r.setAttribute(host, "class", "settings-group-header")
  r.setAttribute(host, "data-label", label)
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
