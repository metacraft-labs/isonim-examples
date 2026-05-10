## task_app/gpui/leaves.nim — Layer-1 leaves for the GPUI target.
##
## Concrete platform components for the task-app's high-level view,
## written against the `GpuiRenderer` from `isonim_gpui/renderer`. Each
## leaf returns a `GpuiElement` ready for `appendChild`. Leaves wire
## input through the VM's actions; the VM's signals never leak through
## to the higher layers.
##
## EX-M3: this file replaces the stand-alone, self-contained port that
## previously lived at `isonim-gpui/demos/task-manager/src/main.nim`
## (which redeclared `Task`, `Filter`, `TaskStore`, ...). The canonical
## ViewModel + view template now drive the GPUI target, matching the
## TUI/web pattern set in EX-M1/EX-M2.
##
## Implementation note: the existing GPUI port used "imperative reactive
## rendering" (full subtree rebuild on each effect) "because the memo
## observer notification doesn't yet copy the observers list before
## iterating". The shared core's TUI/web leaves take a similar manual
## re-render path via a `rerender(vm)` proc; we mirror that here so the
## three flavours are consistent and the cross-renderer parity test can
## drive all three with the same script.
##
## API gap: GPUI's renderer surface does not expose an `onSubmit`-style
## handler for `<input>`-mapped elements (the Rust shim maps `input` to
## a `div`, see `isonim_gpui/renderer.nim:tagMap`). Per the milestone
## brief, we use the closest available primitive: a click on the "Add"
## button reads the current `inputText` signal value (mutated when the
## composition root sets a value, or when a test calls
## `vm.setInputText`) and pushes a task. This matches the existing GPUI
## demo's `app.inputValue.val = "..."; fireEvent(addBtn, "click")`
## pattern, while keeping the VM as the single source of truth.

import isonim/core/signals
import isonim_gpui/renderer
import isonim_gpui/bindings

import task_app/core/vm

# ----------------------------------------------------------------------------
# Per-VM bookkeeping (mirrors `tui/leaves.nim` and `web/leaves.nim`).
# ----------------------------------------------------------------------------

type
  TaskAppGpuiLeavesState* = ref object
    ## Per-VM bookkeeping for the GPUI target. The composition root
    ## constructs one of these alongside the VM and the leaves register
    ## via `leavesFor(vm)`. We park it on a side-table keyed by VM id
    ## so `views.nim` stays byte-identical with the TUI/web targets.
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
  ## Reset the per-thread table. Used by tests so VM instances from
  ## prior cases don't leak state into the next case.
  gpuiLeavesTable.setLen(0)

# ----------------------------------------------------------------------------
# Re-render helpers
# ----------------------------------------------------------------------------

proc clearChildren(r: GpuiRenderer; node: GpuiElement) =
  while childCount(node) > 0:
    let c = nthChild(node, 0)
    if c == nil: break
    r.removeChild(node, c)

# Forward declaration: per-row click handlers re-render after mutating
# the VM, but `rerender` itself calls `renderTaskListInto` (which uses
# the closure factories below). Forward-declare so the cycle resolves.
proc rerender*(vm: TaskAppVM)

proc makeToggleHandler(vm: TaskAppVM; id: int): proc() =
  ## Top-level factory so the captured `id` cannot alias a loop
  ## variable in `renderTaskListInto`. Mirrors the per-task closure
  ## pattern used by `web/leaves.nim`'s click handlers.
  result = proc() =
    vm.toggleTask(id)
    # Re-render is driven by the row's owning leaves' `rerender(vm)`
    # call below; we drive it from inside the handler so a click in
    # the live tree (no test driving it) also refreshes.
    rerender(vm)

proc makeRemoveHandler(vm: TaskAppVM; id: int): proc() =
  result = proc() =
    vm.removeTask(id)
    rerender(vm)

proc renderTaskListInto(r: GpuiRenderer; vm: TaskAppVM;
                        listNode: GpuiElement) =
  ## Wipe `listNode`'s children and rebuild from `vm.visibleTasks`.
  clearChildren(r, listNode)
  let visible = vm.visibleTasks
  if visible.len == 0:
    let row = r.createElement("p")
    r.setAttribute(row, "class", "empty")
    let placeholder =
      case vm.filter.val
      of fmAll:       "(no tasks yet)"
      of fmActive:    "(no active tasks)"
      of fmCompleted: "(no completed tasks)"
    r.setTextContent(row, placeholder)
    r.appendChild(listNode, row)
    return
  for t in visible:
    let row = r.createElement("li")
    r.setAttribute(row, "data-task-id", $t.id)
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

    r.appendChild(listNode, row)

proc renderSummaryInto(r: GpuiRenderer; vm: TaskAppVM;
                       summaryNode: GpuiElement) =
  clearChildren(r, summaryNode)
  let row = r.createElement("span")
  let active = vm.activeCount
  let total = vm.totalCount
  let text = $active & " of " & $total & " remaining"
  r.setTextContent(row, text)
  r.appendChild(summaryNode, row)

proc syncFilterButtons(r: GpuiRenderer; vm: TaskAppVM;
                       buttons: seq[GpuiElement]) =
  if buttons.len != 3: return
  let want =
    case vm.filter.val
    of fmAll:       0
    of fmActive:    1
    of fmCompleted: 2
  for i, b in buttons:
    if i == want:
      r.setAttribute(b, "class", "selected")
      r.setAttribute(b, "aria-pressed", "true")
    else:
      r.setAttribute(b, "class", "")
      r.removeAttribute(b, "aria-pressed")

proc rerender*(vm: TaskAppVM) =
  ## Re-build any sub-trees that depend on VM state. Called after every
  ## action.
  let s = leavesFor(vm)
  let r = GpuiRenderer()
  if s.listNode != nil:
    renderTaskListInto(r, vm, s.listNode)
  if s.summaryNode != nil:
    renderSummaryInto(r, vm, s.summaryNode)
  if s.filterButtons.len == 3:
    syncFilterButtons(r, vm, s.filterButtons)

# ----------------------------------------------------------------------------
# Closure factories — top-level so loop-variable aliasing can't bite.
# ----------------------------------------------------------------------------

proc makeAddTaskHandler(vm: TaskAppVM): proc() =
  result = proc() =
    vm.addTask(vm.inputText.val)
    rerender(vm)

proc makeFilterClickHandler(vm: TaskAppVM; fm: FilterMode): proc() =
  result = proc() =
    vm.setFilter(fm)
    rerender(vm)

# ----------------------------------------------------------------------------
# Layer-1 leaf procs — invoked by views.nim
# ----------------------------------------------------------------------------

proc appShell*(r: GpuiRenderer; vm: TaskAppVM): GpuiElement =
  ## Top-level container. Holds the rest of the leaves. The four
  ## children (input, filter bar, list, summary) are appended by the
  ## Layer-2 view template `renderTaskApp` in `core/views.nim` — this
  ## leaf only creates the empty container so the topology assertions
  ## downstream see the same shape across all renderers.
  discard vm
  let app = r.createElement("div")
  r.setAttribute(app, "class", "task-app")
  r.setAttribute(app, "data-app", "task-app")
  app

proc taskInput*(r: GpuiRenderer; vm: TaskAppVM): GpuiElement =
  ## Text input + add button. The input node holds the current draft via
  ## its `value` attribute (mirroring `vm.inputText`). The add button's
  ## click handler reads `vm.inputText.val` and pushes the task.
  ##
  ## API gap (see module docstring): GPUI's renderer surface has no
  ## `onSubmit` event for input-mapped elements, so we rely on a click
  ## on the "Add" button instead. Tests drive the input by calling
  ## `vm.setInputText("...")` then `fireEvent(s.addBtn, "click")`.
  let s = leavesFor(vm)
  let wrapper = r.createElement("div")
  r.setAttribute(wrapper, "class", "task-input")

  let inp = r.createElement("input")
  r.setAttribute(inp, "type", "text")
  r.setAttribute(inp, "placeholder", "New task...")
  r.setAttribute(inp, "value", vm.inputText.val)
  s.inputNode = inp
  r.appendChild(wrapper, inp)

  let addBtn = r.createElement("button")
  r.setAttribute(addBtn, "type", "submit")
  r.setTextContent(addBtn, "Add Task")
  r.addEventListener(addBtn, "click", makeAddTaskHandler(vm))
  s.addBtn = addBtn
  r.appendChild(wrapper, addBtn)

  wrapper

proc filterBar*(r: GpuiRenderer; vm: TaskAppVM): GpuiElement =
  ## Three-button filter selector (All / Active / Completed). Each
  ## button click routes through the VM's `setFilter` action; the
  ## visible "selected" class is mirrored back from the VM's filter
  ## signal via `syncFilterButtons` on every `rerender`.
  let s = leavesFor(vm)
  s.filterButtons = @[]
  let wrapper = r.createElement("div")
  r.setAttribute(wrapper, "class", "filter-bar")

  for fm in [fmAll, fmActive, fmCompleted]:
    let btn = r.createElement("button")
    r.setTextContent(btn, $fm)
    r.setAttribute(btn, "data-filter", $fm)
    r.addEventListener(btn, "click", makeFilterClickHandler(vm, fm))
    if vm.filter.val == fm:
      r.setAttribute(btn, "class", "selected")
      r.setAttribute(btn, "aria-pressed", "true")
    else:
      r.setAttribute(btn, "class", "")
    r.appendChild(wrapper, btn)
    s.filterButtons.add btn

  wrapper

proc taskList*(r: GpuiRenderer; vm: TaskAppVM): GpuiElement =
  ## The visible task rows (or an empty-state placeholder). The wrapper
  ## `<ul>` is built once; `renderTaskListInto` populates and re-
  ## populates the body on every `rerender`.
  let s = leavesFor(vm)
  let listNode = r.createElement("ul")
  r.setAttribute(listNode, "class", "task-list")
  s.listNode = listNode
  renderTaskListInto(r, vm, listNode)
  listNode

proc summaryBar*(r: GpuiRenderer; vm: TaskAppVM): GpuiElement =
  ## "N of M remaining" footer.
  let s = leavesFor(vm)
  let summaryNode = r.createElement("footer")
  r.setAttribute(summaryNode, "class", "task-summary")
  s.summaryNode = summaryNode
  renderSummaryInto(r, vm, summaryNode)
  summaryNode
