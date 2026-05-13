## task_app/gpui/leaves.nim — Layer-1 leaves for the GPUI target.
##
## EX-M16: each leaf builds its node tree once inside a `ui(r):` block
## and binds reactively via `createRenderEffect` + `forEachKeyed`. There
## is no public `rerender(vm)` proc; VM mutations propagate to the
## rendered tree through the reactive graph.
##
## Concrete platform components for the task-app's high-level view,
## written against the `GpuiRenderer` from `isonim_gpui/renderer`. Each
## leaf returns a `GpuiElement` ready for `appendChild`. Leaves wire
## input through the VM's actions; the VM's signals never leak through
## to the higher layers.
##
## API gap: GPUI's renderer surface does not expose an `onSubmit`-style
## handler for `<input>`-mapped elements (the Rust shim maps `input` to
## a `div`, see `isonim_gpui/renderer.nim:tagMap`). We use the closest
## available primitive: a click on the "Add" button reads the current
## `inputText` signal value (mutated when the composition root sets a
## value, or when a test calls `vm.setInputText`) and pushes a task.

import isonim/core/signals
import isonim/core/computation  # createRenderEffect
import isonim/dsl/components    # forEachKeyed
import isonim_gpui/renderer
import isonim_gpui/bindings
import isonim_render_serve/element_tree_attrs

import task_app/core/vm
import task_app/core/component_paths

# ----------------------------------------------------------------------------
# Per-VM bookkeeping for tests that probe leaf nodes directly.
# ----------------------------------------------------------------------------

type
  TaskAppGpuiLeavesState* = ref object
    inputNode*: GpuiElement
    addBtn*: GpuiElement
    listNode*: GpuiElement
    summaryNode*: GpuiElement
    filterButtons*: seq[GpuiElement]

var gpuiLeavesTable {.threadvar.}: seq[tuple[vm: TaskAppVM;
                                             state: TaskAppGpuiLeavesState]]

proc leavesFor*(vm: TaskAppVM): TaskAppGpuiLeavesState =
  for entry in gpuiLeavesTable:
    if entry.vm == vm: return entry.state
  result = TaskAppGpuiLeavesState(filterButtons: @[])
  gpuiLeavesTable.add (vm: vm, state: result)

proc resetGpuiLeaves*() =
  gpuiLeavesTable.setLen(0)

# ----------------------------------------------------------------------------
# Closure factories — top-level so loop-variable aliasing can't bite.
# ----------------------------------------------------------------------------

proc makeToggleHandler(vm: TaskAppVM; id: int): proc() =
  result = proc() = vm.toggleTask(id)

proc makeRemoveHandler(vm: TaskAppVM; id: int): proc() =
  result = proc() = vm.removeTask(id)

proc makeAddTaskHandler(vm: TaskAppVM): proc() =
  result = proc() = vm.addTask(vm.inputText.val)

proc makeFilterClickHandler(vm: TaskAppVM; fm: FilterMode): proc() =
  result = proc() = vm.setFilter(fm)

# ----------------------------------------------------------------------------
# Layer-1 leaf procs — invoked by views.nim
# ----------------------------------------------------------------------------

proc appShell*(r: GpuiRenderer; vm: TaskAppVM): GpuiElement =
  discard vm
  let app = r.createElement("div")
  r.setAttribute(app, "class", "task-app")
  r.setAttribute(app, "data-app", "task-app")
  # EX-M23b: component-path annotation. The rasteriser keys off
  # ``tag`` + ``label`` (see ``colourForTag`` in
  # ``isonim-render-serve/.../gpui_adapter.nim``); arbitrary ``data-*``
  # attributes do NOT influence pixel output, so adding the path
  # leaves the F-packet stream byte-identical.
  r.setAttribute(app, ComponentPathAttr, TaskAppPath)
  r.setAttribute(app, ElementKindAttr, "app-shell")
  app

proc taskInput*(r: GpuiRenderer; vm: TaskAppVM): GpuiElement =
  ## Text input + add button. The input's `value` attribute mirrors
  ## `vm.inputText` reactively. The add button's click handler reads
  ## `vm.inputText.val` (mutated by tests via `vm.setInputText`) and
  ## pushes the task.
  let s = leavesFor(vm)
  let wrapper = r.createElement("div")
  r.setAttribute(wrapper, "class", "task-input")
  r.setAttribute(wrapper, ComponentPathAttr, TaskInputPath)
  r.setAttribute(wrapper, ElementKindAttr, "input")

  let inp = r.createElement("input")
  r.setAttribute(inp, "type", "text")
  r.setAttribute(inp, "placeholder", "New task...")
  s.inputNode = inp
  r.appendChild(wrapper, inp)

  let inpRef = inp
  createRenderEffect proc() =
    r.setAttribute(inpRef, "value", vm.inputText.val)

  let addBtn = r.createElement("button")
  r.setAttribute(addBtn, "type", "submit")
  r.setTextContent(addBtn, "Add Task")
  r.addEventListener(addBtn, "click", makeAddTaskHandler(vm))
  s.addBtn = addBtn
  r.appendChild(wrapper, addBtn)

  wrapper

proc makeFilterSelectionEffect(r: GpuiRenderer; vm: TaskAppVM;
                               btn: GpuiElement; fm: FilterMode) =
  ## Top-level factory so the captured `fm` / `btn` cannot alias a loop
  ## variable in `filterBar`.
  createRenderEffect proc() =
    if vm.filter.val == fm:
      r.setAttribute(btn, "class", "selected")
      r.setAttribute(btn, "aria-pressed", "true")
    else:
      r.setAttribute(btn, "class", "")
      r.removeAttribute(btn, "aria-pressed")

proc filterBar*(r: GpuiRenderer; vm: TaskAppVM): GpuiElement =
  ## Three-button filter selector (All / Active / Completed). Each
  ## button click routes through the VM's `setFilter` action; the
  ## "selected" class is driven by a `createRenderEffect` per button.
  let s = leavesFor(vm)
  s.filterButtons = @[]
  let wrapper = r.createElement("div")
  r.setAttribute(wrapper, "class", "filter-bar")
  r.setAttribute(wrapper, ComponentPathAttr, FilterBarPath)
  r.setAttribute(wrapper, ElementKindAttr, "filter-bar")

  for fm in [fmAll, fmActive, fmCompleted]:
    let btn = r.createElement("button")
    r.setTextContent(btn, $fm)
    r.setAttribute(btn, "data-filter", $fm)
    r.addEventListener(btn, "click", makeFilterClickHandler(vm, fm))
    makeFilterSelectionEffect(r, vm, btn, fm)
    r.appendChild(wrapper, btn)
    s.filterButtons.add btn

  wrapper

proc renderTaskRow(r: GpuiRenderer; vm: TaskAppVM; t: Task): GpuiElement =
  let row = r.createElement("li")
  r.setAttribute(row, "data-task-id", $t.id)
  r.setAttribute(row, ComponentPathAttr, taskRowPath(t.id))
  r.setAttribute(row, ElementKindAttr, "row")
  if t.completed:
    r.setAttribute(row, "class", "completed")

  let toggleBtn = r.createElement("button")
  let marker = if t.completed: "[x]" else: "[ ]"
  r.setTextContent(toggleBtn, marker)
  r.addEventListener(toggleBtn, "click", makeToggleHandler(vm, t.id))
  r.appendChild(row, toggleBtn)

  let label = r.createElement("span")
  let display =
    if t.completed: t.name & " (done)" else: t.name
  r.setTextContent(label, display)
  r.appendChild(row, label)

  let removeBtn = r.createElement("button")
  r.setAttribute(removeBtn, "class", "remove")
  r.setTextContent(removeBtn, "x")
  r.addEventListener(removeBtn, "click", makeRemoveHandler(vm, t.id))
  r.appendChild(row, removeBtn)

  row

proc placeholderRow(r: GpuiRenderer; vm: TaskAppVM): GpuiElement =
  result = r.createElement("p")
  r.setAttribute(result, "class", "empty")
  let placeholderNode = result
  createRenderEffect proc() =
    let placeholder =
      case vm.filter.val
      of fmAll:       "(no tasks yet)"
      of fmActive:    "(no active tasks)"
      of fmCompleted: "(no completed tasks)"
    r.setTextContent(placeholderNode, placeholder)

proc taskList*(r: GpuiRenderer; vm: TaskAppVM): GpuiElement =
  ## The visible task rows (or an empty-state placeholder). Built once;
  ## `forEachKeyed` watches `vm.visibleTasks` and reconciles when the VM
  ## mutates.
  let s = leavesFor(vm)
  let listNode = r.createElement("ul")
  r.setAttribute(listNode, "class", "task-list")
  r.setAttribute(listNode, ComponentPathAttr, TaskListPath)
  r.setAttribute(listNode, ElementKindAttr, "list")
  s.listNode = listNode

  var placeholder: GpuiElement = nil
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
    proc(item: proc(): Task; index: proc(): int): GpuiElement =
      renderTaskRow(r, vm, item()))

  listNode

proc summaryBar*(r: GpuiRenderer; vm: TaskAppVM): GpuiElement =
  ## "N of M remaining" footer. Reactive on `vm.tasks`.
  let s = leavesFor(vm)
  let summaryNode = r.createElement("footer")
  r.setAttribute(summaryNode, "class", "task-summary")
  r.setAttribute(summaryNode, ComponentPathAttr, SummaryBarPath)
  r.setAttribute(summaryNode, ElementKindAttr, "summary")
  s.summaryNode = summaryNode
  let row = r.createElement("span")
  r.appendChild(summaryNode, row)
  createRenderEffect proc() =
    let active = vm.activeCount
    let total = vm.totalCount
    r.setTextContent(row, $active & " of " & $total & " remaining")
  summaryNode
