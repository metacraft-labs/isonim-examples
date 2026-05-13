## settings_app/tui/leaves.nim — Layer-1 TUI leaves for the settings demo.
##
## EX-M17: per-item subscriptions. Each value-bearing leaf now takes a
## `SettingsVM` reference + the item id and subscribes via
## `createRenderEffect` to the VM's per-item accessor. The widgets'
## live state is updated via their public setters (`setValue` on
## `Switch` / `Input`, `setHighlight` on `OptionList`) so programmatic
## VM mutations propagate to the TUI cell grid without a re-mount.

import std/strutils

import isonim/core/computation  # createRenderEffect
import isonim_tui/renderer
import isonim_tui/widgets/switch
import isonim_tui/widgets/input
import isonim_tui/widgets/option_list
import isonim_tui/widgets/static as staticWidget
import isonim_tui/css/properties

import settings_app/core/vm

# ----------------------------------------------------------------------------
# Constants
# ----------------------------------------------------------------------------

const
  defaultInputWidth = 12
  defaultSuffixWidth = 6
  defaultOptionListWidth = 24
  defaultOptionListHeight = 6
  defaultGroupHeaderWidth = 40

# ----------------------------------------------------------------------------
# Layout containers
# ----------------------------------------------------------------------------

proc itemContainerLeaf*(r: TerminalRenderer): TerminalNode =
  let node = r.createElement("div")
  r.setAttribute(node, "class", "settings-row")
  r.setAttribute(node, "data-orientation", "horizontal")
  # EX-M23: every leaf carries a component path so the element-tree
  # manifest the launcher emits can resolve clicks back to a story.
  r.setAttribute(node, "data-component-path",
    "settings_app/views/SettingsRow")
  r.setAttribute(node, "data-component-kind", "row")
  node

proc labelLeaf*(r: TerminalRenderer; text: string): TerminalNode =
  let node = r.createElement("span")
  r.setAttribute(node, "class", "settings-label")
  r.appendChild(node, r.createTextNode(text))
  node

proc descriptionLeaf*(r: TerminalRenderer; text: string): TerminalNode =
  let node = r.createElement("span")
  r.setAttribute(node, "class", "settings-description")
  r.setStyle(node, "italic", "true")
  r.appendChild(node, r.createTextNode(text))
  node

# ----------------------------------------------------------------------------
# Toggle leaf — Switch widget with reactive VM subscription
# ----------------------------------------------------------------------------

proc toggleLeaf*(r: TerminalRenderer; vmRef: SettingsVM;
                 itemId: string): TerminalNode =
  ## Real `Switch` widget. The widget's onChange dispatches through
  ## `vmRef.setToggle(itemId, …)`. A `createRenderEffect` over
  ## `vmRef.toggleValue(itemId)` keeps the widget's visual state in
  ## sync with the VM — so programmatic mutations (post-load) update
  ## the rendered glyph without a re-mount.
  let captured = vmRef
  let id = itemId
  let initialValue = captured.toggleValue(id)
  let widget = newSwitch(r, value = initialValue,
    onChange = proc(newValue: bool) =
      discard captured.setToggle(id, newValue))
  let host = r.createElement("div")
  r.setAttribute(host, "class", "settings-toggle")
  r.setAttribute(host, "data-value", (if initialValue: "on" else: "off"))
  r.appendChild(host, widget.node)
  # Per-item subscription. Compare against the widget's current value
  # to skip the re-render path when the change originated from the
  # widget itself (the widget's onChange already wrote to the VM; we
  # don't need to write it back to the widget — and doing so would
  # double-fire the keydown handler's internal toggle).
  let widgetRef = widget
  let hostRef = host
  createRenderEffect proc() =
    let value = captured.toggleValue(id)
    if widgetRef.value != value:
      widgetRef.setValue(value)
    r.setAttribute(hostRef, "data-value", (if value: "on" else: "off"))
  host

# ----------------------------------------------------------------------------
# Number leaf — Input widget with reactive VM subscription
# ----------------------------------------------------------------------------

proc isIntegerString(s: string): bool =
  if s.len == 0: return true        # treat empty as "still typing"
  var i = 0
  if s[0] == '-' or s[0] == '+':
    if s.len == 1: return false
    i = 1
  while i < s.len:
    if s[i] notin {'0' .. '9'}: return false
    inc i
  true

proc numberLeaf*(r: TerminalRenderer; vmRef: SettingsVM; itemId: string;
                 minValue, maxValue, stepValue: int;
                 suffix: string): TerminalNode =
  ## Real `Input` widget restricted to integers. The widget submits on
  ## `Enter`; we parse + clamp + dispatch through `vmRef.setNumber`. A
  ## `createRenderEffect` over `vmRef.numberValue(itemId)` keeps the
  ## widget's value in sync with the VM.
  let captured = vmRef
  let id = itemId
  let initialValue = captured.numberValue(id)

  let host = r.createElement("div")
  r.setAttribute(host, "class", "settings-number")
  r.setAttribute(host, "data-min", $minValue)
  r.setAttribute(host, "data-max", $maxValue)
  r.setAttribute(host, "data-step", $stepValue)
  if suffix.len > 0:
    r.setAttribute(host, "data-suffix", suffix)

  let lo = minValue
  let hi = maxValue
  let submitHandler = proc(submittedValue: string) =
    var parsed: int
    try:
      parsed = parseInt(submittedValue.strip())
    except ValueError:
      return
    var clamped = parsed
    if clamped < lo: clamped = lo
    if clamped > hi: clamped = hi
    discard captured.setNumber(id, clamped)

  let input = newInput(r,
    value = $initialValue,
    placeholder = "",
    width = defaultInputWidth,
    border = bsRound,
    validator = isIntegerString,
    onSubmit = submitHandler)
  r.appendChild(host, input.node)

  let inputRef = input
  let hostRef = host
  createRenderEffect proc() =
    let value = captured.numberValue(id)
    let s = $value
    if inputRef.value != s:
      inputRef.setValue(s)
    r.setAttribute(hostRef, "data-value", s)

  if suffix.len > 0:
    let suffixNode = newStatic(r,
      content = suffix,
      width = max(defaultSuffixWidth, suffix.len + 1),
      height = 1,
      border = bsNone).node
    r.setAttribute(suffixNode, "class", "settings-number-suffix")
    r.appendChild(host, suffixNode)

  host

# ----------------------------------------------------------------------------
# Choice leaf — OptionList widget with reactive VM subscription
# ----------------------------------------------------------------------------

proc indexOfOption(options: openArray[string]; value: string): int =
  for i in 0 ..< options.len:
    if options[i] == value: return i
  -1

proc choiceLeaf*(r: TerminalRenderer; vmRef: SettingsVM; itemId: string;
                 options: seq[string]): TerminalNode =
  ## Real `OptionList` widget. Activation fires `onSelect(idx, rowId)`;
  ## we forward the selected row id through `vmRef.setChoice`. A
  ## `createRenderEffect` over `vmRef.choiceValue(itemId)` keeps the
  ## highlighted row in sync with the VM.
  let captured = vmRef
  let id = itemId
  let initialValue = captured.choiceValue(id)

  let host = r.createElement("div")
  r.setAttribute(host, "class", "settings-choice")
  r.setAttribute(host, "data-value", initialValue)
  r.setAttribute(host, "data-options", options.join("|"))

  var rows: seq[OptionRow] = @[]
  for opt in options:
    rows.add OptionRow(kind: orkOption, id: opt, label: opt,
                       disabled: false)

  let widget = newOptionList(r,
    rows = rows,
    width = defaultOptionListWidth,
    viewportHeight = min(defaultOptionListHeight, max(1, rows.len)),
    border = bsRound,
    onSelect = proc(idx: int; rowId: string) =
      discard captured.setChoice(id, rowId))

  let initialIdx = indexOfOption(options, initialValue)
  if initialIdx >= 0:
    widget.setHighlight(initialIdx)

  r.appendChild(host, widget.node)

  let widgetRef = widget
  let hostRef = host
  let capturedOptions = options
  createRenderEffect proc() =
    let value = captured.choiceValue(id)
    let idx = indexOfOption(capturedOptions, value)
    if idx >= 0:
      widgetRef.setHighlight(idx)
    r.setAttribute(hostRef, "data-value", value)

  host

# ----------------------------------------------------------------------------
# Group container + header
# ----------------------------------------------------------------------------

proc groupContainerLeaf*(r: TerminalRenderer): TerminalNode =
  let node = r.createElement("section")
  r.setAttribute(node, "class", "settings-group")
  r.setAttribute(node, "data-orientation", "vertical")
  r.setAttribute(node, "data-expanded", "false")
  r.setAttribute(node, "data-component-path",
    "settings_app/views/SettingsGroup")
  r.setAttribute(node, "data-component-kind", "group")
  node

proc groupHeaderLeaf*(r: TerminalRenderer; label, description: string):
                     TerminalNode =
  let host = r.createElement("header")
  r.setAttribute(host, "class", "settings-group-header")
  r.setAttribute(host, "data-label", label)
  r.setAttribute(host, "data-component-path",
    "settings_app/views/SettingsGroupHeader")
  r.setAttribute(host, "data-component-kind", "group-header")
  if description.len > 0:
    r.setAttribute(host, "data-description", description)

  let labelRow = r.createElement("div")
  r.setStyle(labelRow, "bold", "true")
  r.setAttribute(labelRow, "class", "settings-group-header-label")
  r.appendChild(labelRow, r.createTextNode(label))
  r.appendChild(host, labelRow)

  if description.len > 0:
    let descRow = r.createElement("div")
    r.setStyle(descRow, "italic", "true")
    r.setAttribute(descRow, "class", "settings-group-header-description")
    r.appendChild(descRow, r.createTextNode(description))
    r.appendChild(host, descRow)

  discard defaultGroupHeaderWidth  # reserved for future width clamping
  host
