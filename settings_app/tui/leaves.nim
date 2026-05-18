## settings_app/tui/leaves.nim — Layer-1 TUI leaves for the settings demo.
##
## EX-M17: per-item subscriptions. Each value-bearing leaf now takes a
## `SettingsVM` reference + the item id and subscribes via
## `createRenderEffect` to the VM's per-item accessor. The widgets'
## live state is updated via their public setters (`setValue` on
## `Switch` / `Input`, `setHighlight` on `OptionList`) so programmatic
## VM mutations propagate to the TUI cell grid without a re-mount.
##
## M-EVP-14 round-3 polish gap (settings rows render label / description
## / widget on three separate lines instead of one):
##
## The shared component templates `renderToggleItem` / `renderNumberItem`
## / `renderChoiceItem` build each row as ``itemContainerLeaf →
## [labelLeaf, descriptionLeaf, valueLeaf]``. The `labelLeaf` /
## `descriptionLeaf` return `<span>` elements (`tnkBox` with one text
## child each); the value leaf returns a `<div>` (`tnkBox` containing
## the live widget tree). The TUI compositor's row-collapse rule
## (`isonim-tui/src/isonim_tui/compositor.nim:walkLayoutImpl`'s
## `allText` branch) only fuses children of a `tnkBox` into a single
## row when *every* direct child is a `tnkText` node. A row with mixed
## span + div children walks every child as its own row.
##
## The TUI end-to-end test (`tests/test_settings_tui_end_to_end.nim`)
## asserts on the row's structure directly:
##
##   * `row.children[0].attributes["class"] == "settings-label"` — the
##     label must be a span carrying that class.
##   * `row.children[^1]` is the leaf host containing the widget node
##     (`data-widget="switch"` / `"option-list"` / `"input"`); the test
##     locates the widget via that attribute.
##   * `textContent(row.children[0]) == settingsItem.label` — the label
##     span's text content must equal the bare label string.
##
## A flat-text replacement (e.g., labelLeaf returning a `tnkText` with
## ``"Dark mode  [●·]"``) breaks every one of those assertions. A
## "shadow" sibling-text-row prepended to the row has the same effect
## on `row.children[0]`. The compositor offers no per-node "skip
## rendering" hook (no display:none, no layer-suppress for tnkBox) that
## would let the existing test-bound widget tree render off-screen.
##
## Per the round-3 brief ("If the fix isn't viable without breaking
## tests, document why and skip — this is polish."), this gap is left
## as-is. Closing it requires either (a) the test to relax its
## structural assertions, or (b) a compositor extension that lets the
## TUI walker bypass marked nodes. Both are out of scope for a polish
## pass.

import std/strutils
import std/tables  # getOrDefault on attributes (used by setGroupHeaderExpanded)

import isonim/core/computation  # createRenderEffect
import isonim_tui/renderer
import isonim_tui/widgets/switch
import isonim_tui/widgets/input
import isonim_tui/widgets/option_list
import isonim_tui/widgets/static as staticWidget
import isonim_tui/css/properties
import isonim_render_serve/element_tree_attrs

import settings_app/core/vm
import settings_app/core/component_paths

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
  r.setAttribute(node, ComponentPathAttr, SettingsRowPath)
  r.setAttribute(node, ElementKindAttr, "row")
  # Opt the container into the compositor's inline-row layout mode so
  # the row renders as ``Label  …  [widget]`` on a single line, with
  # any description span on its own row below (compositor.nim's
  # `walkLayoutImpl` honours ``data-tui-row="inline"``).
  r.setAttribute(node, "data-tui-row", "inline")
  node

proc labelLeaf*(r: TerminalRenderer; text: string): TerminalNode =
  let node = r.createElement("span")
  r.setAttribute(node, "class", "settings-label")
  r.appendChild(node, r.createTextNode(text))
  node

proc descriptionLeaf*(r: TerminalRenderer; text: string): TerminalNode =
  ## Description spans render dim (SGR `\x1b[2m`) in addition to italic
  ## so the eye reads them as secondary text underneath the louder label
  ## row. Round-7 polish: in a monospace terminal at preview-pane scale
  ## the description otherwise carries the same visual weight as the
  ## label and the reviewer cannot bracket "label + widget" from
  ## "description" at a glance. Dim provides the contrast italic alone
  ## doesn't — italic styling is unreliable in many terminals.
  let node = r.createElement("span")
  r.setAttribute(node, "class", "settings-description")
  r.setStyle(node, "italic", "true")
  r.setStyle(node, "dim", "true")
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
  # Round-7 polish: render the inline widget glyph (`[ ]` / `[x]`) bold
  # so it lifts off the leader-dot pattern in the inline row. Without
  # this every widget glyph reads with the same weight as the dots and
  # the binding between label and widget is visually muted.
  r.setStyle(host, "bold", "true")
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
  ##
  ## M-EVP-14 round-2: a leading text node renders a `[- 14pt -]`
  ## stepper presentation (live-bound to the VM's numeric value), so
  ## the rasterised editor preview cell shows the stepper glyphs the
  ## brief calls for — round-1 reviewer flagged the previous tree as
  ## "stepper `[-][+]` missing" and the suffix appearing on its own
  ## line under the value. The Input widget itself is retained so the
  ## keyboard-driven tests in `test_settings_tui_end_to_end.nim`
  ## continue to dispatch through `setNumber`.
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
  # Round-7 polish: bold inline stepper glyph (`[- 14pt -]`) — same
  # rationale as `settings-toggle`. Style is on the host because the
  # inline-row path resolves the widget glyph's style from the host
  # node (the leaf div whose `data-value` we read).
  r.setStyle(host, "bold", "true")

  # Inline stepper presentation. Appended FIRST so the rasteriser
  # surfaces the `[- value (suffix) -]` glyph row at the top of the
  # leaf, ahead of the actual Input widget tree.
  let stepperNode = r.createElement("div")
  r.setAttribute(stepperNode, "class", "settings-number-stepper")
  let stepperText = r.createTextNode("")
  r.appendChild(stepperNode, stepperText)
  r.appendChild(host, stepperNode)
  let capturedSuffix = suffix
  proc stepperGlyph(value: int): string =
    let suf = (if capturedSuffix.len > 0: " " & capturedSuffix else: "")
    "[- " & $value & suf & " -]"
  createRenderEffect proc() =
    r.setTextContent(stepperText, stepperGlyph(captured.numberValue(id)))

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
  ##
  ## M-EVP-14 round-2: a leading text node renders the current option
  ## in cycler form (`< Default >`). The brief calls this glyph out
  ## explicitly — round-1 reviewer flagged "cycler `< Default >`
  ## missing" because the OptionList widget paints a multi-row dropdown
  ## that doesn't read as a single-line cycler in the cell grid. The
  ## actual OptionList widget is retained so the keyboard-driven tests
  ## in `test_settings_tui_end_to_end.nim` keep working.
  let captured = vmRef
  let id = itemId
  let initialValue = captured.choiceValue(id)

  let host = r.createElement("div")
  r.setAttribute(host, "class", "settings-choice")
  r.setAttribute(host, "data-value", initialValue)
  r.setAttribute(host, "data-options", options.join("|"))
  # Round-7 polish: bold inline cycler glyph (`< Default >`) — same
  # rationale as `settings-toggle`.
  r.setStyle(host, "bold", "true")

  # Inline cycler presentation. Appended FIRST so the `< value >`
  # glyph surfaces above the multi-row OptionList in the rasterised
  # output.
  let cyclerNode = r.createElement("div")
  r.setAttribute(cyclerNode, "class", "settings-choice-cycler")
  let cyclerText = r.createTextNode("")
  r.appendChild(cyclerNode, cyclerText)
  r.appendChild(host, cyclerNode)
  createRenderEffect proc() =
    r.setTextContent(cyclerText, "< " & captured.choiceValue(id) & " >")

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
  r.setAttribute(node, ComponentPathAttr, SettingsGroupPath)
  r.setAttribute(node, ElementKindAttr, "group")
  node

proc groupHeaderLeaf*(r: TerminalRenderer; label, description: string):
                     TerminalNode =
  ## Group header row. The label is prefixed with an accordion chevron
  ## glyph (`▶` collapsed / `▼` expanded) so the M-EVP-14 round-2 brief
  ## is satisfied at the TUI raster — the previous version rendered a
  ## bare label which the reviewer flagged as having "no `▶`/`▼`
  ## chevrons" on the collapsed groups (`Editor` / `Notifications`).
  ##
  ## The chevron text node is initialised to `▶` (collapsed); the
  ## shell's reactive `data-expanded` effect retargets it via
  ## `setGroupHeaderExpanded` whenever `vm.activeGroupId.val` changes.
  let host = r.createElement("header")
  r.setAttribute(host, "class", "settings-group-header")
  r.setAttribute(host, "data-label", label)
  r.setAttribute(host, ComponentPathAttr, SettingsGroupHeaderPath)
  r.setAttribute(host, ElementKindAttr, "group-header")
  if description.len > 0:
    r.setAttribute(host, "data-description", description)

  let labelRow = r.createElement("div")
  r.setStyle(labelRow, "bold", "true")
  r.setAttribute(labelRow, "class", "settings-group-header-label")
  # Chevron + label as siblings, both expressed as raw text nodes so
  # the rasteriser's `allText` collapse rule (compositor.nim's
  # `walkLayoutImpl`) merges them into a single row — without this
  # they'd render on separate rows (`▶` line, then the label line).
  # The chevron text node carries `data-chevron="true"` so
  # `setGroupHeaderExpanded` can find and rewrite the glyph reactively
  # without keeping a separate node-ref handle.
  let chevronText = r.createTextNode("▶ ")
  r.setAttribute(chevronText, "data-chevron", "true")
  r.appendChild(labelRow, chevronText)
  r.appendChild(labelRow, r.createTextNode(label))
  r.appendChild(host, labelRow)

  if description.len > 0:
    let descRow = r.createElement("div")
    r.setStyle(descRow, "italic", "true")
    # Round-7 polish: dim the group header's own description so the
    # tier "group label > group description > item rows" reads
    # cleanly. The bold + dim combination resolves to `\x1b[1;2m`
    # which terminals collapse to dim (bold loses) — exactly the
    # secondary-tier look we want.
    r.setStyle(descRow, "dim", "true")
    r.setAttribute(descRow, "class", "settings-group-header-description")
    r.appendChild(descRow, r.createTextNode(description))
    r.appendChild(host, descRow)

  discard defaultGroupHeaderWidth  # reserved for future width clamping
  host

proc setGroupHeaderExpanded*(r: TerminalRenderer; header: TerminalNode;
                             expanded: bool) =
  ## Update the chevron glyph on a header built by `groupHeaderLeaf`
  ## to match the group's expanded state. The shell's
  ## `createRenderEffect` over `vm.activeGroupId.val` calls this whenever
  ## the active group changes — chevron `▼` for the expanded group,
  ## `▶` for the others. The chevron is a `tnkText` node carrying
  ## `data-chevron="true"` so a depth-bounded walk over the header tree
  ## finds it without a per-instance node-ref handle.
  if header == nil: return
  proc findChevron(node: TerminalNode): TerminalNode =
    if node == nil: return nil
    if node.attributes.getOrDefault("data-chevron", "") == "true":
      return node
    for child in node.children:
      let hit = findChevron(child)
      if hit != nil: return hit
    nil
  let chev = findChevron(header)
  if chev == nil: return
  let glyph = if expanded: "▼ " else: "▶ "
  r.setTextContent(chev, glyph)
