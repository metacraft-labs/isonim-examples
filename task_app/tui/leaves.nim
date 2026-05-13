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
  let s = leavesFor(vm)
  let inp = newInput(r,
    value = vm.inputText.val,
    placeholder = "New task...",
    width = 30,
    border = bsRound,
    onChange = makeInputChangeHandler(vm),
    onSubmit = makeInputSubmitHandler(vm, s))
  s.inputWidget = inp
  r.setAttribute(inp.node, ComponentPathAttr, TaskInputPath)
  r.setAttribute(inp.node, ElementKindAttr, "input")
  ui(r):
    embedNode(inp.node)

proc filterBar*(r: TerminalRenderer; vm: TaskAppVM): TerminalNode =
  ## Three-mode filter selector. The RadioSet builds its own internal
  ## tree; we wire `onChange` to the VM and use a `createRenderEffect`
  ## to keep the radio buttons in sync with `vm.filter` (so programmatic
  ## `setFilter` calls reflect in the widget too).
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
  r.setAttribute(rs.node, ComponentPathAttr, FilterBarPath)
  r.setAttribute(rs.node, ElementKindAttr, "filter-bar")
  ui(r):
    embedNode(rs.node)

proc renderTaskRow(r: TerminalRenderer; vm: TaskAppVM;
                   t: Task; width: int): TerminalNode =
  ## Build one task row. The row carries `data-task-id`, the
  ## "[x]"/"[ ]" marker + name in a single text child, and an italic
  ## style flip for completed rows.
  let marker = if t.completed: "[x] " else: "[ ] "
  let label = marker & t.name
  let body = (if cellWidth(label) > width:
                padOrTruncate(label, width)
              else:
                label)
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

proc placeholderRow(r: TerminalRenderer; vm: TaskAppVM): TerminalNode =
  ## Empty-state placeholder. The text reflects the current filter via
  ## `createRenderEffect`.
  result = r.createElement("div")
  r.setStyle(result, "italic", "true")
  let txtNode = r.createTextNode("")
  r.appendChild(result, txtNode)
  createRenderEffect proc() =
    let placeholder =
      case vm.filter.val
      of fmAll:       "(no tasks yet)"
      of fmActive:    "(no active tasks)"
      of fmCompleted: "(no completed tasks)"
    r.setTextContent(txtNode, placeholder)

proc taskList*(r: TerminalRenderer; vm: TaskAppVM): TerminalNode =
  ## Visible task rows. Built once; `forEachKeyed` watches
  ## `vm.visibleTasks` and reconciles when the VM mutates.
  let s = leavesFor(vm)
  var listRef: TerminalNode
  result = ui(r):
    tdiv(class = "task-list", ref = listRef,
         `data-component-path` = TaskListPath,
         `data-component-kind` = "list")
  s.listNode = listRef
  s.listWidth = 30
  let listNode = listRef
  let width = s.listWidth

  var placeholder: TerminalNode = nil
  createRenderEffect proc() =
    let visible = vm.visibleTasks
    if visible.len == 0 and placeholder == nil:
      placeholder = placeholderRow(r, vm)
      r.appendChild(listNode, placeholder)
    elif visible.len > 0 and placeholder != nil:
      r.removeChild(listNode, placeholder)
      placeholder = nil

  forEachKeyed(r, listNode,
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
    r.setTextContent(txtNode, $active & " of " & $total & " remaining")
