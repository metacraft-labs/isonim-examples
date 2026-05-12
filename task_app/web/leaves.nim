## task_app/web/leaves.nim — Layer-1 leaves for the web target.
##
## EX-M16: each leaf is a single `ui(r):` block with reactive bindings.
## Mutating the VM's signals (via `addTask`, `toggleTask`, `setFilter`,
## …) automatically propagates to the rendered tree through
## `createRenderEffect` / `forEachKeyed` — there is no `rerender(vm)`
## proc and the composition root mounts the tree exactly once.
##
## Concrete platform components for the task-app's high-level view,
## written against the `MockRenderer` from
## `isonim/testing/mock_dom.nim`. `MockRenderer` is the canonical
## headless target for web tests (and the browser `WebRenderer` exposes
## the same proc interface, so the same DSL drives both).
##
## To run under `WebRenderer` in a real browser, swap
## `import isonim/testing/mock_dom` for
## `import isonim/web/web_renderer` in the composition root; every
## proc below has a parity overload on `WebRenderer` thanks to the
## RendererBackend concept.

import std/[strutils, tables]

import isonim/core/signals
import isonim/core/computation  # createRenderEffect (DSL wraps dynamic text/attrs in it)
import isonim/dsl/ui
import isonim/dsl/components  # forEachKeyed
import isonim/testing/mock_dom
import task_app/core/vm

type
  TaskAppWebLeavesState* = ref object
    ## Per-VM bookkeeping for the web target. The composition root
    ## registers one of these through `leavesFor(vm)` so tests can still
    ## probe the canonical leaf nodes (`inputNode`, `listNode`,
    ## `summaryNode`, `filterNodes`) directly.
    inputNode*: MockNode
    listNode*: MockNode
    summaryNode*: MockNode
    filterNodes*: seq[MockNode]
    listWidth*: int

var webLeavesTable {.threadvar.}: seq[tuple[vm: TaskAppVM;
                                            state: TaskAppWebLeavesState]]

proc leavesFor*(vm: TaskAppVM): TaskAppWebLeavesState =
  for entry in webLeavesTable:
    if entry.vm == vm: return entry.state
  result = TaskAppWebLeavesState(filterNodes: @[], listWidth: 30)
  webLeavesTable.add (vm: vm, state: result)

proc resetWebLeaves*() =
  webLeavesTable.setLen(0)

# ----------------------------------------------------------------------------
# Closure factories — top-level so loop-variable aliasing can't bite.
# ----------------------------------------------------------------------------

proc makeAddTaskHandler(r: MockRenderer; vm: TaskAppVM;
                        inp: MockNode): proc() =
  result = proc() =
    let text = inp.attributes.getOrDefault("value")
    vm.addTask(text)
    r.setAttribute(inp, "value", "")

proc makeFilterClickHandler(vm: TaskAppVM; fm: FilterMode): proc() =
  result = proc() =
    vm.setFilter(fm)

proc makeToggleHandler(vm: TaskAppVM; id: int): proc() =
  result = proc() = vm.toggleTask(id)

proc makeRemoveHandler(vm: TaskAppVM; id: int): proc() =
  result = proc() = vm.removeTask(id)

# ----------------------------------------------------------------------------
# Layer-1 leaf procs
# ----------------------------------------------------------------------------

proc appShell*(r: MockRenderer; vm: TaskAppVM): MockNode =
  discard vm
  ui(r):
    tdiv(class = "task-app")

proc taskInput*(r: MockRenderer; vm: TaskAppVM): MockNode =
  ## Text input + add button. The input node is captured via the DSL
  ## `ref =` form; the click handler reads the input's current value at
  ## submit time. The seeded `value` attribute mirrors `vm.inputText`
  ## through a `createRenderEffect` so a programmatic
  ## `vm.setInputText("…")` is reflected without rebuilding the node.
  let s = leavesFor(vm)
  var inpRef, addBtnRef: MockNode
  result = ui(r):
    tdiv(class = "task-input"):
      input(`type` = "text", placeholder = "New task...",
            ref = inpRef)
      button(ref = addBtnRef):
        text "Add Task"
  s.inputNode = inpRef
  let inputRef = inpRef
  createRenderEffect proc() =
    r.setAttribute(inputRef, "value", vm.inputText.val)
  r.addEventListener(addBtnRef, "click",
                     makeAddTaskHandler(r, vm, inpRef))

proc makeFilterSelectionEffect(r: MockRenderer; vm: TaskAppVM;
                               btn: MockNode; fm: FilterMode) =
  ## Top-level factory so the captured `fm` / `btn` cannot alias a loop
  ## variable in `filterBar`.
  createRenderEffect proc() =
    if vm.filter.val == fm:
      r.setAttribute(btn, "aria-pressed", "true")
    else:
      r.removeAttribute(btn, "aria-pressed")

proc filterBar*(r: MockRenderer; vm: TaskAppVM): MockNode =
  ## Three filter buttons. The selected `aria-pressed` attribute is
  ## driven by a `createRenderEffect` over `vm.filter`, so flipping the
  ## filter signal updates the buttons without rebuilding the bar.
  let s = leavesFor(vm)
  s.filterNodes = @[]
  result = ui(r):
    tdiv(class = "filter-bar"):
      for fm in [fmAll, fmActive, fmCompleted]:
        let lbl = $fm
        button:
          text lbl
  for i, fm in [fmAll, fmActive, fmCompleted]:
    let btn = result.children[i]
    s.filterNodes.add btn
    r.setAttribute(btn, "data-filter", ($fm).toLowerAscii)
    makeFilterSelectionEffect(r, vm, btn, fm)
    r.addEventListener(btn, "click",
                       makeFilterClickHandler(vm, fm))

proc renderTaskRow(r: MockRenderer; vm: TaskAppVM; t: Task): MockNode =
  ## Build a single task row. Each row's marker text / display name /
  ## per-task handlers are derived once from the task value (the value
  ## type `Task` is the `forEachKeyed` identity key — task changes
  ## flow through the keyed-list reconciliation).
  let taskId = t.id
  let marker = if t.completed: "[x]" else: "[ ]"
  let display = if t.completed: t.name & " (done)" else: t.name
  result = ui(r):
    li(`data-task-id` = $taskId):
      button:
        text marker
      span:
        text display
      button:
        text "x"
  r.addEventListener(result.children[0], "click",
                     makeToggleHandler(vm, taskId))
  r.addEventListener(result.children[2], "click",
                     makeRemoveHandler(vm, taskId))

proc placeholderRow(r: MockRenderer; vm: TaskAppVM): MockNode =
  ## Placeholder shown when `vm.visibleTasks` is empty. The text reflects
  ## the current filter via `createRenderEffect`.
  result = ui(r):
    li()
  r.setStyle(result, "font-style", "italic")
  let row = result
  let txtNode = r.createTextNode("")
  r.appendChild(row, txtNode)
  createRenderEffect proc() =
    let placeholder =
      case vm.filter.val
      of fmAll:       "(no tasks yet)"
      of fmActive:    "(no active tasks)"
      of fmCompleted: "(no completed tasks)"
    r.setTextContent(txtNode, placeholder)

proc taskList*(r: MockRenderer; vm: TaskAppVM): MockNode =
  ## The visible task rows. Built once; `forEachKeyed` watches
  ## `vm.visibleTasks` and reconciles the list when tasks are added /
  ## removed / toggled / filtered. An additional `createRenderEffect`
  ## paints / clears the empty-state placeholder so the empty list still
  ## reports a row.
  let s = leavesFor(vm)
  var listRef: MockNode
  result = ui(r):
    ul(class = "task-list", ref = listRef)
  s.listNode = listRef
  s.listWidth = 30

  var placeholder: MockNode = nil
  let listNode = listRef
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
    proc(item: proc(): Task; index: proc(): int): MockNode =
      renderTaskRow(r, vm, item()))

proc summaryBar*(r: MockRenderer; vm: TaskAppVM): MockNode =
  ## "N of M remaining" footer. The inner span's text is driven by a
  ## `createRenderEffect` over `vm.tasks`, so any mutation surfaces here
  ## without a rebuild.
  let s = leavesFor(vm)
  var summaryRef: MockNode
  result = ui(r):
    footer(class = "task-summary", ref = summaryRef)
  s.summaryNode = summaryRef
  let row = r.createElement("span")
  let txtNode = r.createTextNode("")
  r.appendChild(row, txtNode)
  r.appendChild(summaryRef, row)
  createRenderEffect proc() =
    let active = vm.activeCount
    let total = vm.totalCount
    r.setTextContent(txtNode, $active & " of " & $total & " remaining")
