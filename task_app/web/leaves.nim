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
##
## M-EVP-14 round-8: inline styling matches the cocoa/freya/gpui
## task-app palette so the leaves carry the same design intent — dark
## canvas `#0F1117`, card surface `#1d1d28`, accent indigo `#7c7aed`,
## muted text `#A0A2B0`. Card-chrome rows, content-hugging Add Task
## CTA, indigo-fill active filter chip, and a small rounded checkbox
## that flips to indigo fill when the task is completed. The styles
## live as inline `setStyle` calls (no global stylesheet) because the
## leaf bundle is the sole carrier of platform-specific look for the
## web target.

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
# Design tokens — kept in lock-step with the cocoa / freya / gpui leaves
# so every renderer reaches for the same palette and the cross-backend
# review reads "same intent, native idiom" instead of "different demo".
# ----------------------------------------------------------------------------

const
  ColorCanvas       = "#0F1117"
  ColorSurface      = "#1d1d28"
  ColorSurfaceBorder = "#25263A"
  ColorTextPrimary  = "#E6E6F0"
  ColorTextMuted    = "#A0A2B0"
  ColorAccent       = "#7c7aed"
  ColorWhite        = "#FFFFFF"
  ColorChipBorder   = "rgba(255, 255, 255, 0.08)"
  ColorCheckBorder  = "rgba(255, 255, 255, 0.20)"

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
  ## Outer wrapper — dark canvas, default text colour, generous outer
  ## padding so the first row's card chrome breathes against the pane
  ## edge. Children (input / filter / list / summary) stack vertically
  ## with an 8 px rhythm.
  discard vm
  result = ui(r):
    tdiv(class = "task-app")
  r.setStyle(result, "background-color", ColorCanvas)
  r.setStyle(result, "color", ColorTextPrimary)
  r.setStyle(result, "font-family",
             "-apple-system, BlinkMacSystemFont, 'Inter', 'Segoe UI', system-ui, sans-serif")
  r.setStyle(result, "padding", "16px")
  r.setStyle(result, "display", "flex")
  r.setStyle(result, "flex-direction", "column")
  r.setStyle(result, "gap", "12px")
  r.setStyle(result, "min-height", "100%")

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

  # Wrapper — card-style row carrying input + Add CTA side by side.
  r.setStyle(result, "display", "flex")
  r.setStyle(result, "align-items", "center")
  r.setStyle(result, "gap", "10px")
  r.setStyle(result, "background-color", ColorSurface)
  r.setStyle(result, "border", "1px solid " & ColorSurfaceBorder)
  r.setStyle(result, "border-radius", "10px")
  r.setStyle(result, "padding", "12px 16px")

  # Input field — bezel-less; lives inside the card so the surface and
  # input share one outer chrome (mirrors freya / cocoa).
  r.setStyle(inpRef, "flex", "1")
  r.setStyle(inpRef, "background-color", "transparent")
  r.setStyle(inpRef, "color", ColorTextPrimary)
  r.setStyle(inpRef, "border", "0")
  r.setStyle(inpRef, "outline", "none")
  r.setStyle(inpRef, "font-size", "14px")
  r.setStyle(inpRef, "font-family", "inherit")

  # Add Task CTA — content-hugging, indigo accent, white text.
  r.setStyle(addBtnRef, "background-color", ColorAccent)
  r.setStyle(addBtnRef, "color", ColorWhite)
  r.setStyle(addBtnRef, "border", "0")
  r.setStyle(addBtnRef, "padding", "8px 16px")
  r.setStyle(addBtnRef, "border-radius", "6px")
  r.setStyle(addBtnRef, "font-size", "13px")
  r.setStyle(addBtnRef, "font-weight", "600")
  r.setStyle(addBtnRef, "font-family", "inherit")
  r.setStyle(addBtnRef, "cursor", "pointer")
  r.setStyle(addBtnRef, "min-width", "110px")
  r.setStyle(addBtnRef, "text-align", "center")

  let inputRef = inpRef
  createRenderEffect proc() =
    r.setAttribute(inputRef, "value", vm.inputText.val)
  r.addEventListener(addBtnRef, "click",
                     makeAddTaskHandler(r, vm, inpRef))

proc makeFilterSelectionEffect(r: MockRenderer; vm: TaskAppVM;
                               btn: MockNode; fm: FilterMode) =
  ## Top-level factory so the captured `fm` / `btn` cannot alias a loop
  ## variable in `filterBar`. The active chip flips to indigo fill +
  ## white text; inactive chips fall back to transparent fill with a
  ## subtle border + muted text.
  createRenderEffect proc() =
    if vm.filter.val == fm:
      r.setAttribute(btn, "aria-pressed", "true")
      r.setStyle(btn, "background-color", ColorAccent)
      r.setStyle(btn, "color", ColorWhite)
      r.setStyle(btn, "border", "1px solid " & ColorAccent)
    else:
      r.removeAttribute(btn, "aria-pressed")
      r.setStyle(btn, "background-color", "transparent")
      r.setStyle(btn, "color", ColorTextMuted)
      r.setStyle(btn, "border", "1px solid " & ColorChipBorder)

proc filterBar*(r: MockRenderer; vm: TaskAppVM): MockNode =
  ## Three filter buttons. The active chip's indigo accent is driven by
  ## a `createRenderEffect` over `vm.filter` so flipping the signal
  ## updates the chip without rebuilding the bar.
  let s = leavesFor(vm)
  s.filterNodes = @[]
  result = ui(r):
    tdiv(class = "filter-bar"):
      for fm in [fmAll, fmActive, fmCompleted]:
        let lbl = $fm
        button:
          text lbl

  # Filter bar layout — content-hugging pill row with 6 px gap.
  r.setStyle(result, "display", "flex")
  r.setStyle(result, "gap", "6px")
  r.setStyle(result, "align-self", "flex-start")

  for i, fm in [fmAll, fmActive, fmCompleted]:
    let btn = result.children[i]
    s.filterNodes.add btn
    r.setAttribute(btn, "data-filter", ($fm).toLowerAscii)

    # Pill shape, content-hugging width, 4×12 px padding (8-px rhythm).
    r.setStyle(btn, "padding", "4px 12px")
    r.setStyle(btn, "border-radius", "6px")
    r.setStyle(btn, "font-size", "12px")
    r.setStyle(btn, "font-weight", "500")
    r.setStyle(btn, "font-family", "inherit")
    r.setStyle(btn, "min-width", "80px")
    r.setStyle(btn, "text-align", "center")
    r.setStyle(btn, "cursor", "pointer")

    makeFilterSelectionEffect(r, vm, btn, fm)
    r.addEventListener(btn, "click",
                       makeFilterClickHandler(vm, fm))

proc renderTaskRow(r: MockRenderer; vm: TaskAppVM; t: Task): MockNode =
  ## Build a single task row. Each row is its own card surface with
  ## border-radius 8px and 12×16 px padding; the `task-list` parent
  ## supplies the 8-px vertical gap between rows. The toggle is a
  ## small (~20 px) rounded box that flips to indigo fill with a
  ## white checkmark when the task is completed.
  let taskId = t.id
  let completed = t.completed
  let marker = if completed: "✓" else: ""
  let display = t.name
  result = ui(r):
    li(`data-task-id` = $taskId):
      button:
        text marker
      span:
        text display
      button:
        text "×"

  # Row card surface — distinct from canvas, comfortable inner padding,
  # 8-px rhythm courtesy of the parent `task-list` gap.
  r.setStyle(result, "display", "flex")
  r.setStyle(result, "align-items", "center")
  r.setStyle(result, "gap", "12px")
  r.setStyle(result, "background-color", ColorSurface)
  r.setStyle(result, "border", "1px solid " & ColorSurfaceBorder)
  r.setStyle(result, "border-radius", "8px")
  r.setStyle(result, "padding", "12px 16px")
  r.setStyle(result, "list-style", "none")

  let toggleBtn = result.children[0]
  # ~20 px rounded checkbox. Completed → indigo fill + white tick.
  r.setStyle(toggleBtn, "width", "20px")
  r.setStyle(toggleBtn, "height", "20px")
  r.setStyle(toggleBtn, "padding", "0")
  r.setStyle(toggleBtn, "border-radius", "5px")
  r.setStyle(toggleBtn, "display", "inline-flex")
  r.setStyle(toggleBtn, "align-items", "center")
  r.setStyle(toggleBtn, "justify-content", "center")
  r.setStyle(toggleBtn, "font-size", "12px")
  r.setStyle(toggleBtn, "font-weight", "700")
  r.setStyle(toggleBtn, "cursor", "pointer")
  r.setStyle(toggleBtn, "flex-shrink", "0")
  if completed:
    r.setStyle(toggleBtn, "background-color", ColorAccent)
    r.setStyle(toggleBtn, "border", "1px solid " & ColorAccent)
    r.setStyle(toggleBtn, "color", ColorWhite)
  else:
    r.setStyle(toggleBtn, "background-color", "transparent")
    r.setStyle(toggleBtn, "border", "1px solid " & ColorCheckBorder)
    r.setStyle(toggleBtn, "color", "transparent")

  let label = result.children[1]
  r.setStyle(label, "flex", "1")
  r.setStyle(label, "font-size", "14px")
  r.setStyle(label, "line-height", "1.4")
  if completed:
    r.setStyle(label, "color", ColorTextMuted)
    r.setStyle(label, "text-decoration", "line-through")
  else:
    r.setStyle(label, "color", ColorTextPrimary)
    r.setStyle(label, "text-decoration", "none")

  let removeBtn = result.children[2]
  # Tertiary affordance — small, muted, no background fill.
  r.setStyle(removeBtn, "width", "20px")
  r.setStyle(removeBtn, "height", "20px")
  r.setStyle(removeBtn, "padding", "0")
  r.setStyle(removeBtn, "background-color", "transparent")
  r.setStyle(removeBtn, "border", "0")
  r.setStyle(removeBtn, "color", ColorTextMuted)
  r.setStyle(removeBtn, "font-size", "16px")
  r.setStyle(removeBtn, "line-height", "1")
  r.setStyle(removeBtn, "cursor", "pointer")
  r.setStyle(removeBtn, "flex-shrink", "0")
  r.setStyle(removeBtn, "border-radius", "4px")

  r.addEventListener(toggleBtn, "click",
                     makeToggleHandler(vm, taskId))
  r.addEventListener(removeBtn, "click",
                     makeRemoveHandler(vm, taskId))

proc placeholderRow(r: MockRenderer; vm: TaskAppVM): MockNode =
  ## Placeholder shown when `vm.visibleTasks` is empty. The text reflects
  ## the current filter via `createRenderEffect`.
  result = ui(r):
    li()
  r.setStyle(result, "font-style", "italic")
  r.setStyle(result, "color", ColorTextMuted)
  r.setStyle(result, "padding", "12px 16px")
  r.setStyle(result, "background-color", ColorSurface)
  r.setStyle(result, "border", "1px solid " & ColorSurfaceBorder)
  r.setStyle(result, "border-radius", "8px")
  r.setStyle(result, "list-style", "none")
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
  ## reports a row. The 8-px vertical gap between rows is supplied by
  ## the wrapper's `gap` style — each row carries its own card chrome
  ## (see `renderTaskRow`).
  let s = leavesFor(vm)
  var listRef: MockNode
  result = ui(r):
    ul(class = "task-list", ref = listRef)
  s.listNode = listRef
  s.listWidth = 30

  r.setStyle(listRef, "display", "flex")
  r.setStyle(listRef, "flex-direction", "column")
  r.setStyle(listRef, "gap", "8px")
  r.setStyle(listRef, "padding", "0")
  r.setStyle(listRef, "margin", "0")
  r.setStyle(listRef, "list-style", "none")

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
  ## without a rebuild. A 1 px top border separates the summary from the
  ## task list above (carries the cross-renderer "metadata footer"
  ## convention through to the web target).
  let s = leavesFor(vm)
  var summaryRef: MockNode
  result = ui(r):
    footer(class = "task-summary", ref = summaryRef)
  s.summaryNode = summaryRef

  r.setStyle(summaryRef, "display", "flex")
  r.setStyle(summaryRef, "justify-content", "space-between")
  r.setStyle(summaryRef, "align-items", "center")
  r.setStyle(summaryRef, "font-size", "12px")
  r.setStyle(summaryRef, "color", ColorTextMuted)
  r.setStyle(summaryRef, "padding-top", "12px")
  r.setStyle(summaryRef, "margin-top", "4px")
  r.setStyle(summaryRef, "border-top", "1px solid " & ColorSurfaceBorder)

  let row = r.createElement("span")
  let txtNode = r.createTextNode("")
  r.appendChild(row, txtNode)
  r.appendChild(summaryRef, row)
  createRenderEffect proc() =
    let active = vm.activeCount
    let total = vm.totalCount
    r.setTextContent(txtNode, $active & " of " & $total & " remaining")
