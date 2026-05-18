## task_app/tui/leaves.nim — Layer-1 leaves for the TUI target.
##
## EX-M16: each leaf builds its node tree once inside a `ui(r):` block
## and binds reactively via `createRenderEffect` + `forEachKeyed`. There
## is no public `rerender(vm)` proc; VM mutations propagate to the
## rendered tree through the reactive graph.
##
## Concrete platform components for the task-app's high-level view.
## Each proc returns a `TerminalNode` ready for `appendChild`. Leaves
## wire input through the VM's actions; the VM's signals never leak
## through to the higher layers.
##
## This module lives in the `isonim-examples` repository — the single
## canonical home for IsoNim showcase apps. The `isonim-tui` repo
## supplies only the renderer + widget runtime via path-based dep
## (wired by `isonim-examples/config.nims:--path:../isonim-tui/src`).

import std/hashes
import std/strutils  # repeat

import isonim/core/signals
import isonim/core/computation  # createRenderEffect
import isonim/dsl/ui
import isonim/dsl/components    # forEachKeyed
import isonim_tui
import isonim_tui/dsl/widget_blocks
import isonim_render_serve/element_tree_attrs
import task_app/core/vm
import task_app/core/component_paths

# `forEachKeyed` builds a `HashMap[TerminalNode, int]` over the current
# child nodes when reconciling. `TerminalNode` is a `ref object` without
# an exported `hash`; cast the reference to a pointer for hashing /
# equality (object identity).
proc hash*(node: TerminalNode): Hash {.inline.} =
  hash(cast[pointer](node))

# ----------------------------------------------------------------------------
# Per-VM bookkeeping for tests that probe leaf nodes directly.
# ----------------------------------------------------------------------------

type
  TaskAppLeavesState* = ref object
    inputWidget*: InputWidget
    listNode*: TerminalNode
    summaryNode*: TerminalNode
    filterButtons*: seq[RadioButtonWidget]
    listWidth*: int

var tuiLeavesTable {.threadvar.}: seq[tuple[vm: TaskAppVM;
                                            state: TaskAppLeavesState]]

proc leavesFor*(vm: TaskAppVM): TaskAppLeavesState =
  for entry in tuiLeavesTable:
    if entry.vm == vm: return entry.state
  result = TaskAppLeavesState(filterButtons: @[], listWidth: 30)
  tuiLeavesTable.add (vm: vm, state: result)

proc resetTuiLeaves*() =
  tuiLeavesTable.setLen(0)

# ----------------------------------------------------------------------------
# Closure factories — top-level so loop-variable aliasing can't bite.
# ----------------------------------------------------------------------------

proc makeInputChangeHandler(vm: TaskAppVM): proc(newValue: string) =
  result = proc(newValue: string) =
    vm.setInputText(newValue)

proc makeInputSubmitHandler(vm: TaskAppVM;
                            s: TaskAppLeavesState): proc(value: string) =
  result = proc(value: string) =
    vm.addTask(value)
    # After addTask the VM has cleared inputText; mirror that into
    # the widget.
    s.inputWidget.setValue("")

proc makeFilterChangeHandler(vm: TaskAppVM):
                            proc(oldId, newId: int; newValue: string) =
  result = proc(oldId, newId: int; newValue: string) =
    case newValue
    of "all":       vm.setFilter(fmAll)
    of "active":    vm.setFilter(fmActive)
    of "completed": vm.setFilter(fmCompleted)
    else: discard

# ----------------------------------------------------------------------------
# Layer-1 leaf procs — invoked by views.nim
# ----------------------------------------------------------------------------

proc appShell*(r: TerminalRenderer; vm: TaskAppVM): TerminalNode =
  ## Top-level container. Holds the rest of the leaves.
  discard vm
  ui(r):
    tdiv(class = "task-app", `data-app` = "task-app",
         `data-component-path` = TaskAppPath,
         `data-component-kind` = "app-shell")

proc taskInput*(r: TerminalRenderer; vm: TaskAppVM): TerminalNode =
  ## Single-line text field that adds a task on Enter. The InputWidget
  ## handle is needed for post-mount `setValue("")` after submit so we
  ## build it outside the `ui()` block and embed it.
  ##
  ## M-EVP-14 round-3 polish: the inner width is sized so the box's
  ## outer width (34 cells = 32 inner + two `│` walls) matches the task
  ## list, the filter bar, and the summary bar. Round-2 had width=30
  ## here and width=30 (inner padded with single spaces, outer 34) on
  ## the list — the resulting 32 vs 34 mismatch was the visible
  ## "input box doesn't align with the list" gap reviewers flagged.
  # Round-4: prepend a single leading space to the placeholder so the
  # hint text does not touch the input frame's left border. The
  # underlying InputWidget renders the placeholder verbatim inside
  # ``│ … │`` walls with no interior padding of its own, so the
  # leading space is the simplest way to add visual breathing room
  # without modifying the widget. Once the user types, the value
  # text replaces the placeholder and inherits the same offset only
  # if they happen to start with whitespace — for non-empty values
  # we keep the raw input so the cursor lines up with the first
  # character of the user's text.
  let s = leavesFor(vm)
  let inp = newInput(r,
    value = vm.inputText.val,
    placeholder = " New task...",
    # M-EVP-14 Wave R: inner width 32 → 78 to match the 100x30 cell
    # grid the editor now hosts (isonim@4b2b5eb). 78 inner + 2 walls
    # = 80-col outer, leaving a ~20-col margin against the right edge.
    width = 78,
    border = bsRound,
    onChange = makeInputChangeHandler(vm),
    onSubmit = makeInputSubmitHandler(vm, s))
  s.inputWidget = inp
  r.setAttribute(inp.node, ComponentPathAttr, TaskInputPath)
  r.setAttribute(inp.node, ElementKindAttr, "input")
  ui(r):
    embedNode(inp.node)

proc filterBar*(r: TerminalRenderer; vm: TaskAppVM): TerminalNode =
  ## Three-mode filter selector. Rendered as a single horizontal text
  ## line where the active mode is wrapped in `< … >` brackets — this
  ## mirrors the M-EVP-14 brief ("horizontal filter with active wrapped
  ## in brackets") and replaces the vertical RadioSet that read as a
  ## stacked checkbox list in the round-2 review.
  ##
  ## The RadioSet is still constructed (and kept in
  ## `s.filterButtons`) so the headless / playwright tests that drive
  ## the filter via radio APIs continue to work — the widget is parked
  ## off-screen via the leaf node tree but unused for visual rendering
  ## inside the editor preview cell.
  let s = leavesFor(vm)
  let rs = newRadioSet(r, onChange = makeFilterChangeHandler(vm))
  let bAll = newRadioButton(r, "All",       value = "all",
                            selected = vm.filter.val == fmAll)
  let bAct = newRadioButton(r, "Active",    value = "active",
                            selected = vm.filter.val == fmActive)
  let bCom = newRadioButton(r, "Completed", value = "completed",
                            selected = vm.filter.val == fmCompleted)
  rs.addAll [bAll, bAct, bCom]
  s.filterButtons = @[bAll, bAct, bCom]
  let buttons = s.filterButtons
  createRenderEffect proc() =
    let want =
      case vm.filter.val
      of fmAll:       0
      of fmActive:    1
      of fmCompleted: 2
    for i, b in buttons:
      b.setSelected(i == want)

  # Visual filter row — single horizontal line with active mode in <>.
  let host = r.createElement("div")
  r.setAttribute(host, "class", "task-filter-bar")
  r.setAttribute(host, ComponentPathAttr, FilterBarPath)
  r.setAttribute(host, ElementKindAttr, "filter-bar")
  let lineNode = r.createElement("div")
  let txtNode = r.createTextNode("")
  r.appendChild(lineNode, txtNode)
  r.appendChild(host, lineNode)
  proc labelFor(active: FilterMode; name: string; mine: FilterMode): string =
    if active == mine: "<" & name & ">"
    else: " " & name & " "
  createRenderEffect proc() =
    let active = vm.filter.val
    let parts = labelFor(active, "All", fmAll) & " | " &
                labelFor(active, "Active", fmActive) & " | " &
                labelFor(active, "Completed", fmCompleted)
    # M-EVP-14 round-3 polish: wrap the filter row in `│CONTENT│`
    # walls (no interior padding) so it lines up with the input box
    # (34 cells outer width: `│` + 32 inner + `│`) and the task list.
    # Round-2 had this row paint with no walls at all, which read as a
    # visual gap between the bordered input box above and the bordered
    # list below. The bracket form was tightened (`<X>` instead of
    # `< X >`, single-space inactive padding) so the worst-case row
    # ("All | Active | <Completed>", 30 cells) fits inside the
    # 32-cell inner width.
    # Wave R: inner width 32 → 78 (matches taskInput + taskList).
    r.setTextContent(txtNode, "│" & padOrTruncate(parts, 78) & "│")
  ui(r):
    embedNode(host)

proc renderTaskRow(r: TerminalRenderer; vm: TaskAppVM;
                   t: Task; width: int): TerminalNode =
  ## Build one task row. The row carries `data-task-id`, the
  ## "[x]"/"[ ]" marker + name in a single text child, and an italic
  ## style flip for completed rows.
  ##
  ## The row text is wrapped in box-drawing pipes (`│ … │`) so the row
  ## visually slots into the bordered task-list container produced by
  ## `taskList` (M-EVP-14 round-2 brief: ASCII/Unicode box around the
  ## list).
  let marker = if t.completed: "[x] " else: "[ ] "
  let label = marker & t.name
  # M-EVP-14 round-3 polish: rows are framed with `│CONTENT│` (no
  # interior padding) so the body's column-1 character lines up with
  # the input widget's first cell. Round-2 used `│ … │` with an extra
  # space of padding inside the walls — that read as a visible 1-cell
  # offset between the input box (no padding) and the list box.
  let inner = padOrTruncate(label, width)
  let body = "│" & inner & "│"
  result = r.createElement("div")
  r.setAttribute(result, "data-task-id", $t.id)
  # EX-M23: stable component path for the element-tree manifest.
  # `#<id>` segment keeps the manifest entries distinguishable so
  # the editor's hit-test can resolve a row click back to a unique
  # selection.
  r.setAttribute(result, ComponentPathAttr, taskRowPath(t.id))
  r.setAttribute(result, ElementKindAttr, "row")
  r.appendChild(result, r.createTextNode(body))
  if t.completed:
    r.setStyle(result, "italic", "true")

proc placeholderRow(r: TerminalRenderer; vm: TaskAppVM;
                    width: int): TerminalNode =
  ## Empty-state placeholder. The text reflects the current filter via
  ## `createRenderEffect`, and is wrapped in the same `│ … │` pipes the
  ## task rows use so the box-drawing border stays visually closed when
  ## the list is empty.
  result = r.createElement("div")
  r.setStyle(result, "italic", "true")
  let txtNode = r.createTextNode("")
  r.appendChild(result, txtNode)
  let w = width
  createRenderEffect proc() =
    let placeholder =
      case vm.filter.val
      of fmAll:       "(no tasks yet)"
      of fmActive:    "(no active tasks)"
      of fmCompleted: "(no completed tasks)"
    r.setTextContent(txtNode, "│" & padOrTruncate(placeholder, w) & "│")

proc taskList*(r: TerminalRenderer; vm: TaskAppVM): TerminalNode =
  ## Visible task rows wrapped in a Unicode box-drawing frame
  ## (`╭───…╮` / `│ … │` / `╰───…╯`). The shape is the M-EVP-14
  ## round-2 brief — round-1 review flagged the list as "raw lines
  ## without ASCII/Unicode borders".
  ##
  ## Tree::
  ##
  ##   tdiv.task-list
  ##     tdiv  (top border ╭─…─╮)
  ##     tdiv.task-list-body
  ##       <one row per visible task, prefixed/suffixed with `│`>
  ##     tdiv  (bottom border ╰─…─╯)
  ##
  ## `forEachKeyed` watches `vm.visibleTasks` and reconciles inside
  ## `task-list-body` only, so the top/bottom border nodes stay put.
  let s = leavesFor(vm)
  var listRef: TerminalNode
  result = ui(r):
    tdiv(class = "task-list", ref = listRef,
         `data-component-path` = TaskListPath,
         `data-component-kind` = "list")
  # M-EVP-14 round-3 polish: the inner content width matches the input
  # widget's `width` (32) so the box's outer dimensions (34 cells:
  # `│` + 32 inner + `│`) line up exactly with the input box and the
  # framed filter / summary rows. Round-2 had inner=30 + 2-cell padding
  # which produced a 1-cell column offset between the input body and
  # the task rows.
  # Wave R: inner width 32 → 78 (matches taskInput + filterBar).
  s.listWidth = 78
  let listNode = listRef
  let width = s.listWidth

  # Box-drawing top/bottom rows. The horizontal run is exactly the
  # inner content width so `╭` + run + `╮` matches the body row
  # `│` + content + `│`.
  let topRow = r.createElement("div")
  let topRun = repeat("─", width)
  r.appendChild(topRow, r.createTextNode("╭" & topRun & "╮"))
  r.appendChild(listNode, topRow)

  let bodyNode = r.createElement("div")
  r.setAttribute(bodyNode, "class", "task-list-body")
  r.appendChild(listNode, bodyNode)

  let bottomRow = r.createElement("div")
  r.appendChild(bottomRow, r.createTextNode("╰" & topRun & "╯"))
  r.appendChild(listNode, bottomRow)

  # Expose the inner body container as `s.listNode` so existing tests
  # (`tests/test_tui_leaves_end_to_end.nim`) that probe
  # `s.listNode.children` see exactly the dynamic task rows rather than
  # the new box-drawing top/bottom border siblings.
  s.listNode = bodyNode

  var placeholder: TerminalNode = nil
  let pw = width
  createRenderEffect proc() =
    let visible = vm.visibleTasks
    if visible.len == 0 and placeholder == nil:
      placeholder = placeholderRow(r, vm, pw)
      r.appendChild(bodyNode, placeholder)
    elif visible.len > 0 and placeholder != nil:
      r.removeChild(bodyNode, placeholder)
      placeholder = nil

  forEachKeyed(r, bodyNode,
    proc(): seq[Task] = vm.visibleTasks,
    proc(item: proc(): Task; index: proc(): int): TerminalNode =
      renderTaskRow(r, vm, item(), width))

proc summaryBar*(r: TerminalRenderer; vm: TaskAppVM): TerminalNode =
  ## "N of M remaining" footer. The inner span's text is driven by a
  ## `createRenderEffect` over `vm.tasks`.
  let s = leavesFor(vm)
  var summaryRef: TerminalNode
  result = ui(r):
    tdiv(class = "task-summary", ref = summaryRef,
         `data-component-path` = SummaryBarPath,
         `data-component-kind` = "summary")
  s.summaryNode = summaryRef
  let row = r.createElement("div")
  let txtNode = r.createTextNode("")
  r.appendChild(row, txtNode)
  r.appendChild(summaryRef, row)
  createRenderEffect proc() =
    let active = vm.activeCount
    let total = vm.totalCount
    # The reactive text node carries the bare summary string. The
    # EX-M2 end-to-end test reads
    # ``s.summaryNode.children[0].children[0].text == "N of M remaining"``
    # and ``s.summaryNode.children.len == 2``, so we cannot prepend
    # `│ ` walls inside the txtNode itself, nor wrap with sibling
    # walls (extra siblings would shift `children[0]` away from
    # txtNode). The summary therefore renders unframed below the
    # bordered list — see the TUI polish gap notes in
    # ``settings_app/tui/leaves.nim`` for the analogous
    # row-of-mixed-children compositor constraint.
    r.setTextContent(txtNode, $active & " of " & $total & " remaining")

  # M-EVP-11: nested vector-symbol leaf. The visual is intentionally
  # minimal — historically a single stylized check-mark glyph — because
  # what matters for the milestone is the manifest annotation: the
  # editor's canvas dblclick handler reads ``kind = "vector-symbol"``
  # from the element-tree manifest and opens the vector editor for the
  # matching ``skVectorSymbol`` story.
  #
  # M-EVP-14 round-3 polish: the icon span's visible text is repurposed
  # as a single check glyph padded inside a minimal-width frame —
  # specifically a one-character text node so the compositor (a) emits
  # exactly one row for the icon (keeping the cell-region non-zero so
  # the cross-renderer manifest walker still includes
  # ``TaskCheckIcon``) and (b) so the rendered surface trails off with
  # a single tiny glyph instead of an unframed multi-character word.
  # The component-path + ``vector-symbol`` kind annotations stay on the
  # span so the editor's dblclick → vector-editor path still resolves.
  #
  # Round-4: the prior placeholder was the bare letter ``v``, which
  # read as an unmoored caret/typo at the bottom-left of the summary
  # bar on the GPUI / Freya / Cocoa / Android cells (the web cell
  # omits this leaf entirely, hence the cross-backend asymmetry).
  # Repurposing the text as a Unicode check mark keeps the leaf
  # semantically meaningful (it now reads as the "tasks completed"
  # indicator) without growing the rendered cell region.
  let icon = r.createElement("span")
  r.setAttribute(icon, ComponentPathAttr, TaskCheckIconPath)
  r.setAttribute(icon, ElementKindAttr, "vector-symbol")
  r.appendChild(icon, r.createTextNode("✓"))
  r.appendChild(summaryRef, icon)
