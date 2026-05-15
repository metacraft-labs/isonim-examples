## task_app/freya/leaves.nim — Layer-1 leaves for the Freya target.
##
## EX-M16: each leaf builds its node tree once inside a `ui(r):` block
## and binds reactively via `createRenderEffect` + `forEachKeyed`. There
## is no public `rerender(vm)` proc; VM mutations propagate to the
## rendered tree through the reactive graph.
##
## Concrete platform components for the task-app's high-level view,
## written against the `FreyaRenderer` from `isonim_freya/renderer`.
## Each leaf returns a `FreyaElement` ready for `appendChild`. Leaves
## wire input through the VM's actions; the VM's signals never leak
## through to the higher layers.
##
## API gap: Freya's renderer surface does not expose an `onSubmit`-style
## handler for `<input>`-mapped elements (the Rust shim maps `input` to
## a `rect`, see `isonim_freya/renderer.nim:tagMap`). We use the closest
## available primitive: a click on the "Add" button reads the current
## `inputText` signal value (mutated when the composition root sets a
## value, or when a test calls `vm.setInputText`) and pushes a task.
##
## M-EVP-14 round-2: text on a Freya `rect` (the post-mapping
## destination for `div`/`button`/`input`/`li`) is NOT rendered by the
## Skia raster — only `label` (`span`/headings/etc.) and `paragraph`
## (`p`/`pre`) Freya kinds actually paint text glyphs. So every visible
## bit of text below lives inside a child `span` (mapped to `label`) so
## the headless raster picks it up. The `setTextContent` calls on the
## containing buttons stay too — they expose the same text via
## `freya_get_text_content`, which the leaves-table tests assert on.

import isonim/core/signals
import isonim/core/computation  # createRenderEffect
import isonim/dsl/components    # forEachKeyed
import isonim_freya/renderer
import isonim_freya/bindings
import isonim_render_serve/element_tree_attrs

import task_app/core/vm
import task_app/core/component_paths

# ----------------------------------------------------------------------------
# Per-VM bookkeeping for tests that probe leaf nodes directly.
# ----------------------------------------------------------------------------

type
  TaskAppFreyaLeavesState* = ref object
    inputNode*: FreyaElement
    addBtn*: FreyaElement
    listNode*: FreyaElement
    summaryNode*: FreyaElement
    filterButtons*: seq[FreyaElement]

var freyaLeavesTable {.threadvar.}: seq[tuple[vm: TaskAppVM;
                                              state: TaskAppFreyaLeavesState]]

proc leavesFor*(vm: TaskAppVM): TaskAppFreyaLeavesState =
  for entry in freyaLeavesTable:
    if entry.vm == vm: return entry.state
  result = TaskAppFreyaLeavesState(filterButtons: @[])
  freyaLeavesTable.add (vm: vm, state: result)

proc resetFreyaLeaves*() =
  freyaLeavesTable.setLen(0)

# ----------------------------------------------------------------------------
# Internal helpers
# ----------------------------------------------------------------------------

proc addTextSpan(r: FreyaRenderer; parent: FreyaElement; text: string;
                 color = "rgb(232, 233, 240)";
                 fontSize = "14"; fontWeight = "normal"): FreyaElement
                {.discardable.} =
  ## Append a `<span>` (→ Freya `label`) child carrying `text` and
  ## styled so the headless Skia raster paints it. Returns the span
  ## node so callers can update its text later via `setTextContent`.
  let span = r.createElement("span")
  r.setTextContent(span, text)
  r.setStyle(span, "color", color)
  r.setStyle(span, "font-size", fontSize)
  r.setStyle(span, "font-weight", fontWeight)
  r.appendChild(parent, span)
  span

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

proc makeFilterSelectionEffect(r: FreyaRenderer; vm: TaskAppVM;
                               btn: FreyaElement; fm: FilterMode) =
  createRenderEffect proc() =
    if vm.filter.val == fm:
      r.setAttribute(btn, "class", "selected")
      r.setAttribute(btn, "aria-pressed", "true")
      r.setStyle(btn, "background", "rgb(124, 122, 237)")
    else:
      r.setAttribute(btn, "class", "")
      r.removeAttribute(btn, "aria-pressed")
      r.setStyle(btn, "background", "rgb(34, 35, 46)")

# ----------------------------------------------------------------------------
# Layer-1 leaf procs — invoked by views.nim
# ----------------------------------------------------------------------------

proc appShell*(r: FreyaRenderer; vm: TaskAppVM): FreyaElement =
  discard vm
  let app = r.createElement("div")
  r.setAttribute(app, "class", "task-app")
  r.setAttribute(app, "data-app", "task-app")
  # EX-M23b: component-path annotation. Mirror of GPUI; identical
  # string values keep cross-renderer parity. The Freya rasteriser
  # keys off ``tag`` + ``label`` (``colourForTag`` in
  # ``isonim-render-serve/.../freya_adapter.nim``), so arbitrary
  # ``data-*`` attributes do NOT influence pixel output.
  r.setAttribute(app, ComponentPathAttr, TaskAppPath)
  r.setAttribute(app, ElementKindAttr, "app-shell")
  # M-EVP-14 round-2: paint a dark canvas + add ~16 px outer padding
  # so the first task row's glyphs are not clipped against the top of
  # the surface (the headless Skia raster otherwise hugs y=0).
  r.setStyle(app, "background", "rgb(15, 15, 20)")
  r.setStyle(app, "color", "rgb(232, 233, 240)")
  r.setStyle(app, "padding", "16")
  r.setStyle(app, "flex-direction", "column")
  r.setStyle(app, "gap", "12")
  r.setStyle(app, "width", "100%")
  r.setStyle(app, "height", "100%")
  app

proc taskInput*(r: FreyaRenderer; vm: TaskAppVM): FreyaElement =
  ## Text input + add button. The input's `value` attribute mirrors
  ## `vm.inputText` reactively. The add button's click handler reads
  ## `vm.inputText.val` (mutated by tests via `vm.setInputText`) and
  ## pushes the task.
  let s = leavesFor(vm)
  let wrapper = r.createElement("div")
  r.setAttribute(wrapper, "class", "task-input")
  r.setAttribute(wrapper, ComponentPathAttr, TaskInputPath)
  r.setAttribute(wrapper, ElementKindAttr, "input")
  # Card-style row: input + submit button laid out horizontally.
  r.setStyle(wrapper, "background", "rgb(29, 29, 40)")
  r.setStyle(wrapper, "padding", "10")
  r.setStyle(wrapper, "gap", "8")
  r.setStyle(wrapper, "flex-direction", "row")
  r.setStyle(wrapper, "cross_align", "center")
  r.setStyle(wrapper, "border-radius", "8")

  let inp = r.createElement("input")
  r.setAttribute(inp, "type", "text")
  r.setAttribute(inp, "placeholder", "New task...")
  r.setStyle(inp, "background", "rgb(34, 35, 46)")
  r.setStyle(inp, "padding", "8")
  r.setStyle(inp, "border-radius", "4")
  r.setStyle(inp, "flex-direction", "row")
  r.setStyle(inp, "cross_align", "center")
  s.inputNode = inp
  r.appendChild(wrapper, inp)

  # Placeholder text must live in a child <span> (→ Freya `label`)
  # because the underlying `rect` does not render its own text. The
  # span's text mirrors `vm.inputText.val`; when empty we fall back
  # to the placeholder copy so the cell stays informative.
  let placeholderSpan = r.createElement("span")
  r.setStyle(placeholderSpan, "color", "rgb(160, 162, 176)")
  r.setStyle(placeholderSpan, "font-size", "14")
  r.appendChild(inp, placeholderSpan)

  let inpRef = inp
  let placeRef = placeholderSpan
  createRenderEffect proc() =
    let v = vm.inputText.val
    r.setAttribute(inpRef, "value", v)
    if v.len == 0:
      r.setTextContent(placeRef, "New task...")
      r.setStyle(placeRef, "color", "rgb(110, 112, 128)")
    else:
      r.setTextContent(placeRef, v)
      r.setStyle(placeRef, "color", "rgb(232, 233, 240)")

  let addBtn = r.createElement("button")
  r.setAttribute(addBtn, "type", "submit")
  r.setTextContent(addBtn, "Add Task")
  r.setStyle(addBtn, "background", "rgb(124, 122, 237)")
  r.setStyle(addBtn, "padding", "8")
  r.setStyle(addBtn, "border-radius", "4")
  r.setStyle(addBtn, "flex-direction", "row")
  r.setStyle(addBtn, "cross_align", "center")
  r.addEventListener(addBtn, "click", makeAddTaskHandler(vm))
  s.addBtn = addBtn
  r.appendChild(wrapper, addBtn)
  # Visible label as a span child of the button so the raster paints it.
  addTextSpan(r, addBtn, "Add Task",
              color = "rgb(255, 255, 255)",
              fontSize = "14", fontWeight = "bold")

  wrapper

proc filterBar*(r: FreyaRenderer; vm: TaskAppVM): FreyaElement =
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
    # Baseline style; the selection effect overrides bg when active.
    r.setStyle(btn, "background", "rgb(34, 35, 46)")
    r.setStyle(btn, "padding", "6")
    r.setStyle(btn, "border-radius", "4")
    r.setStyle(btn, "flex-direction", "row")
    r.setStyle(btn, "cross_align", "center")
    r.addEventListener(btn, "click", makeFilterClickHandler(vm, fm))
    makeFilterSelectionEffect(r, vm, btn, fm)
    r.appendChild(wrapper, btn)
    # Visible label as a span child so the raster paints it. The text
    # colour stays light on both selected (indigo bg) and inactive
    # (dark bg) variants for legibility.
    addTextSpan(r, btn, $fm,
                color = "rgb(232, 233, 240)",
                fontSize = "13", fontWeight = "normal")
    s.filterButtons.add btn

  wrapper

proc renderTaskRow(r: FreyaRenderer; vm: TaskAppVM; t: Task): FreyaElement =
  let row = r.createElement("li")
  r.setAttribute(row, "data-task-id", $t.id)
  r.setAttribute(row, ComponentPathAttr, taskRowPath(t.id))
  r.setAttribute(row, ElementKindAttr, "row")
  if t.completed:
    r.setAttribute(row, "class", "completed")
  # Card-style row separation.
  r.setStyle(row, "background", "rgb(29, 29, 40)")
  r.setStyle(row, "padding", "10")
  r.setStyle(row, "gap", "10")
  r.setStyle(row, "flex-direction", "row")
  r.setStyle(row, "cross_align", "center")
  r.setStyle(row, "border-radius", "6")

  let toggleBtn = r.createElement("button")
  let marker = if t.completed: "[x]" else: "[ ]"
  r.setTextContent(toggleBtn, marker)
  r.setStyle(toggleBtn, "background", "rgb(34, 35, 46)")
  r.setStyle(toggleBtn, "padding", "6")
  r.setStyle(toggleBtn, "border-radius", "4")
  r.setStyle(toggleBtn, "flex-direction", "row")
  r.setStyle(toggleBtn, "cross_align", "center")
  r.addEventListener(toggleBtn, "click", makeToggleHandler(vm, t.id))
  r.appendChild(row, toggleBtn)
  addTextSpan(r, toggleBtn, marker,
              color = (if t.completed: "rgb(124, 122, 237)"
                       else: "rgb(160, 162, 176)"),
              fontSize = "14", fontWeight = "bold")

  let display =
    if t.completed: t.name & " (done)" else: t.name
  addTextSpan(r, row, display,
              color = (if t.completed: "rgb(110, 112, 128)"
                       else: "rgb(232, 233, 240)"),
              fontSize = "14", fontWeight = "normal")

  let removeBtn = r.createElement("button")
  r.setAttribute(removeBtn, "class", "remove")
  r.setTextContent(removeBtn, "x")
  r.setStyle(removeBtn, "background", "rgb(52, 53, 63)")
  r.setStyle(removeBtn, "padding", "6")
  r.setStyle(removeBtn, "border-radius", "4")
  r.setStyle(removeBtn, "flex-direction", "row")
  r.setStyle(removeBtn, "cross_align", "center")
  r.addEventListener(removeBtn, "click", makeRemoveHandler(vm, t.id))
  r.appendChild(row, removeBtn)
  addTextSpan(r, removeBtn, "x",
              color = "rgb(224, 128, 128)",
              fontSize = "14", fontWeight = "bold")

  row

proc placeholderRow(r: FreyaRenderer; vm: TaskAppVM): FreyaElement =
  result = r.createElement("p")
  r.setAttribute(result, "class", "empty")
  r.setStyle(result, "color", "rgb(110, 112, 128)")
  r.setStyle(result, "padding", "12")
  r.setStyle(result, "font-size", "13")
  let placeholderNode = result
  createRenderEffect proc() =
    let placeholder =
      case vm.filter.val
      of fmAll:       "(no tasks yet)"
      of fmActive:    "(no active tasks)"
      of fmCompleted: "(no completed tasks)"
    r.setTextContent(placeholderNode, placeholder)

proc taskList*(r: FreyaRenderer; vm: TaskAppVM): FreyaElement =
  ## Visible task rows (or empty placeholder). `forEachKeyed` watches
  ## `vm.visibleTasks` and reconciles when the VM mutates.
  let s = leavesFor(vm)
  let listNode = r.createElement("ul")
  r.setAttribute(listNode, "class", "task-list")
  r.setAttribute(listNode, ComponentPathAttr, TaskListPath)
  r.setAttribute(listNode, ElementKindAttr, "list")
  r.setStyle(listNode, "flex-direction", "column")
  r.setStyle(listNode, "gap", "6")
  r.setStyle(listNode, "padding", "4")
  s.listNode = listNode

  var placeholder: FreyaElement = nil
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
    proc(item: proc(): Task; index: proc(): int): FreyaElement =
      renderTaskRow(r, vm, item()))

  listNode

proc summaryBar*(r: FreyaRenderer; vm: TaskAppVM): FreyaElement =
  ## "N of M remaining" footer. Reactive on `vm.tasks`.
  let s = leavesFor(vm)
  let summaryNode = r.createElement("footer")
  r.setAttribute(summaryNode, "class", "task-summary")
  r.setAttribute(summaryNode, ComponentPathAttr, SummaryBarPath)
  r.setAttribute(summaryNode, ElementKindAttr, "summary")
  r.setStyle(summaryNode, "background", "rgb(29, 29, 40)")
  r.setStyle(summaryNode, "padding", "10")
  r.setStyle(summaryNode, "gap", "8")
  r.setStyle(summaryNode, "flex-direction", "row")
  r.setStyle(summaryNode, "cross_align", "center")
  r.setStyle(summaryNode, "border-radius", "6")
  s.summaryNode = summaryNode
  let row = r.createElement("span")
  r.setStyle(row, "color", "rgb(160, 162, 176)")
  r.setStyle(row, "font-size", "12")
  r.appendChild(summaryNode, row)
  createRenderEffect proc() =
    let active = vm.activeCount
    let total = vm.totalCount
    r.setTextContent(row, $active & " of " & $total & " remaining")

  # M-EVP-11: nested vector-symbol leaf. Mirrors the TUI / GPUI /
  # Cocoa / Android leaves' minimal check-mark annotation so the
  # editor's canvas dblclick handler can resolve the click back to
  # the matching ``skVectorSymbol`` story and open the vector editor.
  let icon = r.createElement("span")
  r.setAttribute(icon, ComponentPathAttr, TaskCheckIconPath)
  r.setAttribute(icon, ElementKindAttr, "vector-symbol")
  r.setTextContent(icon, "v")
  r.setStyle(icon, "color", "rgb(124, 122, 237)")
  r.setStyle(icon, "font-size", "12")
  r.appendChild(summaryNode, icon)

  summaryNode
