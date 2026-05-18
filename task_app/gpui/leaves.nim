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
  # RS-M14 Phase 2 styling: real headless renderer captures only what
  # the leaves explicitly request. Apply a baseline dark canvas so the
  # F-packet stream is visibly non-black. Caveats (per
  # ``isonim-gpui/rust/.../gpui_app.rs:apply_styles_to_div``):
  # only ``bg``/``text_color``/``p``/``m``/``gap``/``rounded`` plus
  # flex/items/justify map to GPUI methods; ``border``, ``font-size``,
  # ``font-weight`` are accepted by the shim but silently dropped by
  # the renderer. Colors must be ``#RRGGBB`` (no alpha). Padding is a
  # single scalar (no ``8px 12px`` shorthand).
  r.setStyle(app, "background", "#0f0f14")
  r.setStyle(app, "color", "#e8e9f0")
  r.setStyle(app, "padding", "12")
  r.setStyle(app, "flex-direction", "column")
  # Round-2 review: tighten inter-row gaps to ~12px (was rendering at
  # ~32-40px because the appShell `gap` was 12 but every child carried
  # its own 10-12px padding, summing into a visible ~24px well between
  # cards). Dropping appShell gap to 8 brings the visible separator to
  # ~12px once each card's padding contributes.
  r.setStyle(app, "gap", "8")
  r.setStyle(app, "width", "100%")
  r.setStyle(app, "height", "100%")
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
  # Round-2 review: the brief asks for the input field to sit
  # **above** the Add Task button, not beside it. Stack vertically so
  # the field reads as a labelled entry row + a primary CTA below.
  r.setStyle(wrapper, "background", "#1d1d28")
  r.setStyle(wrapper, "padding", "8")
  r.setStyle(wrapper, "gap", "8")
  r.setStyle(wrapper, "flex-direction", "column")
  # Round-4 review: the Add Task pill needs to sit at the right edge of
  # the wrapper instead of bottom-left. The GPUI shim does NOT honour
  # ``margin-left: auto`` or ``align-self`` (see
  # ``apply_styles_to_div`` in
  # ``isonim-gpui/rust/gpui-nim-shim/src/render_sync.rs`` — the
  # property list ignores both), but it does honour ``align-items``
  # on the parent. Flipping the wrapper's cross-axis alignment to
  # ``end`` right-aligns its column children. The full-width input
  # still spans the wrapper because its own ``width: 100%`` overrides
  # the alignment for that child, but the fixed-width Add Task pill
  # below is pushed to the right edge — visually matching "Add Task
  # pill next to the right end of the input row".
  r.setStyle(wrapper, "align-items", "end")
  r.setStyle(wrapper, "border-radius", "8")

  # Round-2 review: the input row was invisible because (a) the inner
  # input had no width so the headless renderer collapsed it to 0px,
  # and (b) it shared too close a tone with its wrapper. Explicit
  # width + brighter input background + visible placeholder text mean
  # the row reads as a real field above the Add Task button.
  let inp = r.createElement("input")
  r.setAttribute(inp, "type", "text")
  r.setAttribute(inp, "placeholder", "New task...")
  r.setStyle(inp, "background", "#2a2b38")
  r.setStyle(inp, "color", "#a0a2b0")
  r.setStyle(inp, "padding", "8")
  r.setStyle(inp, "border-radius", "4")
  r.setStyle(inp, "width", "100%")
  s.inputNode = inp
  r.appendChild(wrapper, inp)

  let inpRef = inp
  createRenderEffect proc() =
    r.setAttribute(inpRef, "value", vm.inputText.val)
    # Render the current text content (or the placeholder when empty)
    # as visible text. The shim's headless renderer reads textContent,
    # not the ``value`` attribute, so without this the input would
    # render as an empty rectangle with no glyphs at all.
    let current = vm.inputText.val
    if current.len > 0:
      r.setTextContent(inpRef, current)
      r.setStyle(inpRef, "color", "#e8e9f0")
    else:
      r.setTextContent(inpRef, "New task…")
      r.setStyle(inpRef, "color", "#6e7080")

  let addBtn = r.createElement("button")
  r.setAttribute(addBtn, "type", "submit")
  r.setTextContent(addBtn, "Add Task")
  r.setStyle(addBtn, "background", "#7c7aed")
  r.setStyle(addBtn, "color", "#ffffff")
  # Round-3 review: in round-2 the button stretched to fill the
  # vertically-stacked wrapper row, blowing up to ~70 px tall and
  # full-width — visually overpowering the task list. Pin explicit
  # pill geometry so it reads as a secondary CTA below the input
  # field instead of a wall-filling primary action. The GPUI shim
  # honours width/height/padding/border-radius (single scalar
  # padding only — no shorthand).
  #
  # Round-4 review: the right-edge positioning of the pill is driven
  # by the wrapper's ``align-items: end`` (see the comment block on
  # the wrapper above) — neither ``margin-left: auto`` nor
  # ``align-self`` is honoured by the GPUI shim.
  r.setStyle(addBtn, "width", "140")
  r.setStyle(addBtn, "height", "40")
  r.setStyle(addBtn, "padding", "8")
  r.setStyle(addBtn, "border-radius", "6")
  r.setStyle(addBtn, "cursor", "pointer")
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
      r.setStyle(btn, "background", "#7c7aed")
      r.setStyle(btn, "color", "#ffffff")
    else:
      r.setAttribute(btn, "class", "")
      r.removeAttribute(btn, "aria-pressed")
      r.setStyle(btn, "background", "#22232e")
      r.setStyle(btn, "color", "#a0a2b0")

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
  r.setStyle(wrapper, "flex-direction", "row")
  r.setStyle(wrapper, "gap", "6")
  r.setStyle(wrapper, "padding", "4")

  for fm in [fmAll, fmActive, fmCompleted]:
    let btn = r.createElement("button")
    r.setTextContent(btn, $fm)
    r.setAttribute(btn, "data-filter", $fm)
    # Baseline style; the selection effect overrides bg/color when active.
    r.setStyle(btn, "background", "#22232e")
    r.setStyle(btn, "color", "#a0a2b0")
    r.setStyle(btn, "padding", "6")
    r.setStyle(btn, "border-radius", "4")
    r.setStyle(btn, "cursor", "pointer")
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
  # Round-3 review: rows were ~60 px tall in round-2 because every leaf
  # (row + toggle + label + remove) carried 8 px padding on top of the
  # row's own padding. Drop padding so the row settles closer to the
  # body-text band and stops dominating the list visually.
  # M-EVP-14 Wave-Q row-card refinement: padding 10→14, border-radius
  # 6→10 so rows read as discrete cards in the strict-reviewer pass
  # (previously the small radius + tight padding made rows blur into
  # the canvas).
  r.setStyle(row, "background", "#1d1d28")
  r.setStyle(row, "padding", "14")
  r.setStyle(row, "gap", "10")
  r.setStyle(row, "flex-direction", "row")
  r.setStyle(row, "align-items", "center")
  r.setStyle(row, "border-radius", "10")
  if t.completed:
    r.setStyle(row, "color", "#6e7080")
  else:
    r.setStyle(row, "color", "#e8e9f0")

  # Round-5 review: GPUI's idiom expectation is "flat surface + rounded
  # corners", not ASCII brackets. Drop the `[ ]` / `[x]` text marker and
  # render the toggle as a small (~14 px) stroked square: indigo when
  # on, neutral when off, with a ✓ glyph inside the on-state. The GPUI
  # shim does honour textContent on a filled div, so the check-mark
  # paints inside the square once flipped.
  let toggleBtn = r.createElement("div")
  if t.completed:
    r.setStyle(toggleBtn, "background", "#7c7aed")
    r.setStyle(toggleBtn, "color", "#ffffff")
    r.setTextContent(toggleBtn, "✓")
  else:
    r.setStyle(toggleBtn, "background", "#3a3a52")
    r.setStyle(toggleBtn, "color", "#e8e9f0")
    r.setTextContent(toggleBtn, "")
  r.setStyle(toggleBtn, "width", "14")
  r.setStyle(toggleBtn, "height", "14")
  r.setStyle(toggleBtn, "border-radius", "3")
  r.setStyle(toggleBtn, "cursor", "pointer")
  r.addEventListener(toggleBtn, "click", makeToggleHandler(vm, t.id))
  r.appendChild(row, toggleBtn)

  let label = r.createElement("span")
  let display =
    if t.completed: t.name & " (done)" else: t.name
  r.setTextContent(label, display)
  # Title sits at body weight (font-size is dropped by the shim — we
  # express emphasis purely through colour). Slightly muted relative to
  # the active state so the hierarchy reads control > title > muted.
  r.setStyle(label, "color", (if t.completed: "#6e7080" else: "#c8cad6"))
  r.appendChild(row, label)

  let removeBtn = r.createElement("button")
  r.setAttribute(removeBtn, "class", "remove")
  r.setTextContent(removeBtn, "x")
  r.setStyle(removeBtn, "background", "#34353f")
  r.setStyle(removeBtn, "color", "#e08080")
  # Round-3 review: pin remove button to the same scale as the leading
  # toggle so the row reads as a balanced [toggle] [title] [×] band.
  r.setStyle(removeBtn, "width", "24")
  r.setStyle(removeBtn, "height", "24")
  r.setStyle(removeBtn, "padding", "4")
  r.setStyle(removeBtn, "border-radius", "4")
  r.setStyle(removeBtn, "cursor", "pointer")
  r.addEventListener(removeBtn, "click", makeRemoveHandler(vm, t.id))
  r.appendChild(row, removeBtn)

  row

proc placeholderRow(r: GpuiRenderer; vm: TaskAppVM): GpuiElement =
  result = r.createElement("p")
  r.setAttribute(result, "class", "empty")
  r.setStyle(result, "color", "#6e7080")
  r.setStyle(result, "padding", "12")
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
  r.setStyle(listNode, "flex-direction", "column")
  # Wave-Q: 10-px row gap so rows visibly separate as cards.
  r.setStyle(listNode, "gap", "10")
  r.setStyle(listNode, "padding", "0")
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
  r.setStyle(summaryNode, "background", "#1d1d28")
  r.setStyle(summaryNode, "color", "#a0a2b0")
  r.setStyle(summaryNode, "padding", "8")
  r.setStyle(summaryNode, "gap", "8")
  r.setStyle(summaryNode, "flex-direction", "row")
  r.setStyle(summaryNode, "border-radius", "6")
  s.summaryNode = summaryNode
  let row = r.createElement("span")
  r.setStyle(row, "color", "#a0a2b0")
  r.appendChild(summaryNode, row)
  createRenderEffect proc() =
    let active = vm.activeCount
    let total = vm.totalCount
    r.setTextContent(row, $active & " of " & $total & " remaining")

  # M-EVP-11: nested vector-symbol leaf. Mirrors the TUI / Freya /
  # Cocoa / Android leaves' minimal check-mark annotation so the
  # editor's canvas dblclick handler can resolve the click back to
  # the matching ``skVectorSymbol`` story and open the vector editor.
  # Round-4 review: the prior placeholder text was the bare letter
  # ``v``, which rendered as an unmoored caret-like glyph at the
  # bottom-left of the summary bar (the web cell omits this leaf
  # entirely, hence the cross-backend asymmetry). Repurposing the
  # text as a Unicode check mark (``✓``) keeps the leaf semantically
  # meaningful — it now reads as the "tasks completed" indicator —
  # while preserving the ``vector-symbol`` annotation that the
  # editor's dblclick handler keys on.
  let icon = r.createElement("span")
  r.setAttribute(icon, ComponentPathAttr, TaskCheckIconPath)
  r.setAttribute(icon, ElementKindAttr, "vector-symbol")
  r.setTextContent(icon, "✓")
  r.setStyle(icon, "color", "#7c7aed")
  r.appendChild(summaryNode, icon)

  summaryNode
