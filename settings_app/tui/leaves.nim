## settings_app/tui/leaves.nim — Layer-1 TUI leaves for the settings demo.
##
## EX-M10 milestone. The 8-leaf contract spelled out in
## `settings_app/components/{toggle,number,choice}_item.nim` +
## `settings_app/components/group.nim` is satisfied here against the
## production `TerminalRenderer` and the M11-M14 widget tier
## (`Switch`, `Input`, `OptionList`). Where the EX-M9 compile-check
## helper (`tests/helpers/settings_compile_tui.nim`) used inline div
## stubs to prove the include-pattern, this module wires *real*
## widgets so the TUI composition root paints + reacts on the same
## pipeline `task_app` uses for its leaves.
##
## Each leaf returns a `TerminalNode` ready for `appendChild`. The
## item leaves embed real widget instances:
##
##   * ``toggleLeaf``  -> `Switch` (M12). Wraps the widget's `node` in
##     a 1-child container so the toggle row's structural depth
##     matches the other two kinds (label + node-bearing leaf).
##   * ``numberLeaf``  -> `Input` (M13) with an integer validator and
##     a custom keydown handler that parses + clamps + dispatches on
##     `Enter`. The catalog item's `numberSuffix` is shown as a
##     sibling `wStatic` row so callers can locate it in the rendered
##     cells.
##   * ``choiceLeaf``  -> `OptionList` (M14). The widget already wires
##     `onSelect(idx, rowId)`; we forward the selected row id to the
##     component's `onChange(newValue: string)`. The current value is
##     pre-highlighted via `setHighlight`.
##
## The group container is a vertical `div`; the group header is a
## `wStatic` rendered with the `bold` inline style. The expand-collapse
## state lives on the `groupContainerLeaf`'s `data-expanded` attribute
## so the shell can read + flip it during keyboard nav.
##
## All eight procs are `proc` (not `template`) so the EX-M10 shell can
## call them by name from inside a `template ... {.dirty.}` include.
## The renderer-agnostic components in
## `settings_app/components/*.nim` use the same name-resolution
## protocol: import this module *before* including the component
## files; the includer's lexical scope binds the unqualified leaf
## names to the procs below.

import std/strutils

import isonim_tui/renderer
import isonim_tui/widgets/switch
import isonim_tui/widgets/input
import isonim_tui/widgets/option_list
import isonim_tui/widgets/static as staticWidget
import isonim_tui/css/properties

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
  ## Row container hosting a label, optional description, and the
  ## kind-specific input widget. The class is mirrored from the EX-M9
  ## helper so tests / introspection tools keyed on `.settings-row`
  ## continue to match.
  let node = r.createElement("div")
  r.setAttribute(node, "class", "settings-row")
  r.setAttribute(node, "data-orientation", "horizontal")
  node

proc labelLeaf*(r: TerminalRenderer; text: string): TerminalNode =
  ## Primary item label. Built on top of `wStatic` so the cell grid
  ## actually contains the label text — without this, the EX-M9
  ## helper's bare `span` would never paint a glyph into the
  ## compositor.
  let node = r.createElement("span")
  r.setAttribute(node, "class", "settings-label")
  r.appendChild(node, r.createTextNode(text))
  node

proc descriptionLeaf*(r: TerminalRenderer; text: string): TerminalNode =
  ## Secondary description text. Rendered dim (`italic = true` in the
  ## inline style table; the compositor's flatten-to-row pass picks it
  ## up).
  let node = r.createElement("span")
  r.setAttribute(node, "class", "settings-description")
  r.setStyle(node, "italic", "true")
  r.appendChild(node, r.createTextNode(text))
  node

# ----------------------------------------------------------------------------
# Toggle leaf — Switch widget (M12)
# ----------------------------------------------------------------------------

proc toggleLeaf*(r: TerminalRenderer; value: bool;
                 onChange: proc(newValue: bool)): TerminalNode =
  ## Real `Switch` widget. The widget owns its own keydown listener
  ## (`Space`/`Enter` toggles), focus marker (`data-focusable=true`),
  ## and renders the `[●·]` / `[·●]` glyph row. We wire `onChange`
  ## through verbatim so component-level handlers (`vm.setToggle`)
  ## fire on every flip — exactly as the EX-M9 contract requires.
  let widget = newSwitch(r, value = value, onChange = onChange)
  # Wrap in a container so the row's structural shape (1 widget node
  # per leaf) matches the number/choice leaves.
  let host = r.createElement("div")
  r.setAttribute(host, "class", "settings-toggle")
  r.setAttribute(host, "data-value", (if value: "on" else: "off"))
  r.appendChild(host, widget.node)
  host

# ----------------------------------------------------------------------------
# Number leaf — Input widget (M13) constrained to integers
# ----------------------------------------------------------------------------

proc isIntegerString(s: string): bool =
  ## Accept optional leading sign + digits. The Input widget's
  ## validator runs on every keystroke; we use it to set the
  ## `data-invalid` attribute so tests / introspection can observe
  ## the validity state.
  if s.len == 0: return true        # treat empty as "still typing"
  var i = 0
  if s[0] == '-' or s[0] == '+':
    if s.len == 1: return false
    i = 1
  while i < s.len:
    if s[i] notin {'0' .. '9'}: return false
    inc i
  true

proc numberLeaf*(r: TerminalRenderer; value: int;
                 minValue, maxValue, stepValue: int;
                 suffix: string;
                 onChange: proc(newValue: int)): TerminalNode =
  ## Real `Input` widget restricted to integers. The widget submits
  ## on `Enter` (via `onSubmit`); we parse the value, clamp to
  ## `[minValue, maxValue]`, and dispatch through `onChange`. The
  ## catalog's `numberSuffix` is rendered as a sibling `wStatic` so
  ## the suffix is reachable from the cell grid.
  let host = r.createElement("div")
  r.setAttribute(host, "class", "settings-number")
  r.setAttribute(host, "data-min", $minValue)
  r.setAttribute(host, "data-max", $maxValue)
  r.setAttribute(host, "data-step", $stepValue)
  r.setAttribute(host, "data-value", $value)
  if suffix.len > 0:
    r.setAttribute(host, "data-suffix", suffix)

  let submitHandler = proc(submittedValue: string) =
    var parsed: int
    try:
      parsed = parseInt(submittedValue.strip())
    except ValueError:
      return
    var clamped = parsed
    if clamped < minValue: clamped = minValue
    if clamped > maxValue: clamped = maxValue
    r.setAttribute(host, "data-value", $clamped)
    if onChange != nil:
      onChange(clamped)

  let input = newInput(r,
    value = $value,
    placeholder = "",
    width = defaultInputWidth,
    border = bsRound,
    validator = isIntegerString,
    onSubmit = submitHandler)
  r.appendChild(host, input.node)

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
# Choice leaf — OptionList widget (M14)
# ----------------------------------------------------------------------------

proc indexOfOption(options: openArray[string]; value: string): int =
  for i in 0 ..< options.len:
    if options[i] == value: return i
  -1

proc choiceLeaf*(r: TerminalRenderer; value: string;
                 options: seq[string];
                 onChange: proc(newValue: string)): TerminalNode =
  ## Real `OptionList` widget. The widget owns up/down navigation;
  ## activation (`Enter`) fires `onSelect(idx, rowId)`. We wire that
  ## to the component-level `onChange(newValue: string)` so the VM's
  ## `setChoice` is called with the row id — which we set to the
  ## option string itself, matching the contract documented in
  ## `choice_item.nim`.
  let host = r.createElement("div")
  r.setAttribute(host, "class", "settings-choice")
  r.setAttribute(host, "data-value", value)
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
      r.setAttribute(host, "data-value", rowId)
      if onChange != nil:
        onChange(rowId))

  # Pre-highlight the row matching the current value so a user's first
  # `Enter` re-selects the same value rather than the first option.
  let initialIdx = indexOfOption(options, value)
  if initialIdx >= 0:
    widget.setHighlight(initialIdx)

  r.appendChild(host, widget.node)
  host

# ----------------------------------------------------------------------------
# Group container + header
# ----------------------------------------------------------------------------

proc groupContainerLeaf*(r: TerminalRenderer): TerminalNode =
  ## Vertical container for one settings group. The expand-collapse
  ## state lives on `data-expanded` (set by the shell). The shell
  ## flips this attribute to toggle whether the per-item rows are
  ## appended; the leaf itself never decides.
  let node = r.createElement("section")
  r.setAttribute(node, "class", "settings-group")
  r.setAttribute(node, "data-orientation", "vertical")
  r.setAttribute(node, "data-expanded", "false")
  node

proc groupHeaderLeaf*(r: TerminalRenderer; label, description: string):
                     TerminalNode =
  ## Bold header row for a settings group. The label is the primary
  ## content; when a non-empty description is supplied, it is appended
  ## as a dim sibling row.
  let host = r.createElement("header")
  r.setAttribute(host, "class", "settings-group-header")
  r.setAttribute(host, "data-label", label)
  if description.len > 0:
    r.setAttribute(host, "data-description", description)

  # Bold label row. We build the static manually rather than via
  # `wStatic` so we can pin the styled child the compositor picks up.
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
