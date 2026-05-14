## task_app/cocoa/leaves.nim — Layer-1 leaves for the Cocoa target.
##
## EX-M23c follow-up: each leaf builds its node tree once and binds
## reactively via `createRenderEffect` + `forEachKeyed`. There is no
## public `rerender(vm)` proc; VM mutations propagate to the rendered
## tree through the reactive graph.  This mirrors the GPUI / Freya
## reactive pattern (see `task_app/gpui/leaves.nim` and
## `task_app/freya/leaves.nim`) so a single cross-renderer convention
## drives every renderer.
##
## Concrete platform components for the task-app's high-level view,
## written against the `CocoaRenderer` from `isonim_cocoa/renderer`.
## Each leaf returns a `CocoaElement` ready for `appendChild`. Leaves
## wire input through the VM's actions; the VM's signals never leak
## through to the higher layers.
##
## EX-M5 status: **partial-linux**.
##
## This is the Linux-host scaffold. The whole module body is gated with
## `when defined(macosx)` because `isonim_cocoa/renderer` transitively
## imports `isonim_cocoa/objc_runtime`, `isonim_cocoa/foundation` and
## the `isonim_cocoa/appkit/*` AppKit wrappers. Those modules contain
## `{.passL: "-framework AppKit".}` / `{.passL: "-framework Foundation".}`
## pragmas plus inline `{.emit: "objc_msgSend(...)".}` C blocks and so
## cannot be compiled on a Linux host (the C compiler has no AppKit /
## Objective-C runtime to link against). On Linux the module compiles
## as an empty shell — the canonical `task_app/main_cocoa.nim`
## composition root mirrors the same gating, and the cross-compile gate
## test (`tests/test_cocoa_leaves_compile.nim`) drives `nim check
## --os:macosx` over a thin Cocoa-only fixture so we catch leaf-surface
## drift from this host without needing a macOS box.
##
## API gap: Cocoa's `CocoaRenderer` does not expose an `onSubmit`-style
## handler for `<input>`-mapped elements (`renderer.nim`'s `tagMap`
## maps `input` to `ekInput` -> `NSTextField`; the
## `addEventListener` path for `change` events on text fields requires
## `NSTextField` delegate plumbing that hasn't landed yet — see the
## `# For NSTextField, delegate-based notification would be needed.`
## comment in `renderer.nim`). Per the milestone brief, we use the
## closest available primitive: a click on the "Add" button reads the
## current `inputText` signal value (mutated when the composition root
## sets a value, or when a test calls `vm.setInputText`) and pushes a
## task.

when defined(macosx):
  import std/hashes
  import isonim/core/signals
  import isonim/core/computation  # createRenderEffect
  import isonim/dsl/components    # forEachKeyed
  import isonim_cocoa/renderer
  # `CocoaElement = Id = distinct pointer`; `Id`'s borrowed `==` lives
  # in `isonim_cocoa/objc_runtime`. `forEachKeyed`/`reconcileArrays` is
  # generic and uses `mixin \`==\`` / `mixin hash` at the instantiation
  # site (reconcile's `Table[N, int]`), so we need both operators
  # visible in this module.
  import isonim_cocoa/objc_runtime
  import isonim_render_serve/element_tree_attrs

  import task_app/core/vm
  import task_app/core/component_paths

  proc hash(e: CocoaElement): Hash {.inline.} =
    ## Required for `forEachKeyed`'s reconcile-step `Table[CocoaElement,
    ## int]` lookup. Re-uses `pointer`'s `hash` so distinct elements
    ## sharing the same backing pointer (impossible in practice) would
    ## hash identically.
    hashes.hash(cast[pointer](e))

  # ----------------------------------------------------------------------------
  # Per-VM bookkeeping (mirrors `tui/leaves.nim`, `web/leaves.nim`,
  # `gpui/leaves.nim`, `freya/leaves.nim`).
  # ----------------------------------------------------------------------------

  type
    TaskAppCocoaLeavesState* = ref object
      ## Per-VM bookkeeping for the Cocoa target. The composition root
      ## constructs one of these alongside the VM and the leaves register
      ## via `leavesFor(vm)`. We park it on a side-table keyed by VM id
      ## so `views.nim` stays byte-identical with the TUI/web/GPUI/Freya
      ## targets.
      inputNode*: CocoaElement
      addBtn*: CocoaElement
      listNode*: CocoaElement
      summaryNode*: CocoaElement
      filterButtons*: seq[CocoaElement]

  var cocoaLeavesTable {.threadvar.}: seq[tuple[vm: TaskAppVM;
                                                state: TaskAppCocoaLeavesState]]

  proc leavesFor*(vm: TaskAppVM): TaskAppCocoaLeavesState =
    for entry in cocoaLeavesTable:
      if entry.vm == vm: return entry.state
    result = TaskAppCocoaLeavesState(filterButtons: @[])
    cocoaLeavesTable.add (vm: vm, state: result)

  proc resetCocoaLeaves*() =
    ## Reset the per-thread table. Used by tests so VM instances from
    ## prior cases don't leak state into the next case.
    cocoaLeavesTable.setLen(0)

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

  proc makeFilterSelectionEffect(r: CocoaRenderer; vm: TaskAppVM;
                                 btn: CocoaElement; fm: FilterMode) =
    ## Top-level factory so the captured `fm` / `btn` cannot alias a loop
    ## variable in `filterBar`.
    createRenderEffect proc() =
      if vm.filter.val == fm:
        r.setAttribute(btn, "class", "selected")
        r.setAttribute(btn, "aria-pressed", "true")
      else:
        r.setAttribute(btn, "class", "")
        r.removeAttribute(btn, "aria-pressed")

  # ----------------------------------------------------------------------------
  # Layer-1 leaf procs — invoked by views.nim
  # ----------------------------------------------------------------------------

  proc appShell*(r: CocoaRenderer; vm: TaskAppVM): CocoaElement =
    ## Top-level container. Holds the rest of the leaves. The four
    ## children (input, filter bar, list, summary) are appended by the
    ## Layer-2 view template `renderTaskApp` in `core/views.nim` — this
    ## leaf only creates the empty container so the topology assertions
    ## downstream see the same shape across all renderers.
    discard vm
    let app = r.createElement("div")
    r.setAttribute(app, "class", "task-app")
    r.setAttribute(app, "data-app", "task-app")
    # EX-M23c: component-path annotation. The RS-M5 AppKit capture
    # path keys off real ``NSView`` geometry + draw calls and never
    # reads ``data-*`` attributes, so adding the path leaves the
    # F-packet stream byte-identical.
    r.setAttribute(app, ComponentPathAttr, TaskAppPath)
    r.setAttribute(app, ElementKindAttr, "app-shell")
    app

  proc taskInput*(r: CocoaRenderer; vm: TaskAppVM): CocoaElement =
    ## Text input + add button. The input's `value` attribute mirrors
    ## `vm.inputText` reactively. The add button's click handler reads
    ## `vm.inputText.val` (mutated by tests via `vm.setInputText`) and
    ## pushes the task.
    ##
    ## API gap (see module docstring): Cocoa's renderer surface has no
    ## `onSubmit` event for input-mapped elements (NSTextField needs
    ## delegate plumbing that hasn't landed yet), so we rely on a click
    ## on the "Add" button instead. Tests drive the input by calling
    ## `vm.setInputText("...")` then `fireEvent(s.addBtn, "click")`.
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

  proc filterBar*(r: CocoaRenderer; vm: TaskAppVM): CocoaElement =
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

  proc renderTaskRow(r: CocoaRenderer; vm: TaskAppVM; t: Task): CocoaElement =
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

  proc placeholderRow(r: CocoaRenderer; vm: TaskAppVM): CocoaElement =
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

  proc taskList*(r: CocoaRenderer; vm: TaskAppVM): CocoaElement =
    ## The visible task rows (or an empty-state placeholder). Built once;
    ## `forEachKeyed` watches `vm.visibleTasks` and reconciles when the
    ## VM mutates.
    let s = leavesFor(vm)
    let listNode = r.createElement("ul")
    r.setAttribute(listNode, "class", "task-list")
    r.setAttribute(listNode, ComponentPathAttr, TaskListPath)
    r.setAttribute(listNode, ElementKindAttr, "list")
    s.listNode = listNode

    # `CocoaElement = Id = distinct pointer` — the nil sentinel is
    # `CocoaElement(Id(nil))` and the "is set" check goes through
    # `pointer(...)`. Mirrors the existing `pointer(s.listNode) != nil`
    # idiom further up in the module.
    var placeholder: CocoaElement = CocoaElement(Id(nil))
    createRenderEffect proc() =
      let visible = vm.visibleTasks
      if visible.len == 0 and pointer(placeholder) == nil:
        placeholder = placeholderRow(r, vm)
        r.appendChild(listNode, placeholder)
      elif visible.len > 0 and pointer(placeholder) != nil:
        r.removeChild(listNode, placeholder)
        placeholder = CocoaElement(Id(nil))

    forEachKeyed(r, listNode,
      proc(): seq[Task] = vm.visibleTasks,
      proc(item: proc(): Task; index: proc(): int): CocoaElement =
        renderTaskRow(r, vm, item()))

    listNode

  proc summaryBar*(r: CocoaRenderer; vm: TaskAppVM): CocoaElement =
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

    # M-EVP-11: nested vector-symbol leaf. Mirrors the TUI / GPUI /
    # Freya / Android leaves' minimal check-mark annotation so the
    # editor's canvas dblclick handler can resolve the click back to
    # the matching ``skVectorSymbol`` story and open the vector editor.
    let icon = r.createElement("span")
    r.setAttribute(icon, ComponentPathAttr, TaskCheckIconPath)
    r.setAttribute(icon, ElementKindAttr, "vector-symbol")
    r.setTextContent(icon, "v")
    r.appendChild(summaryNode, icon)

    summaryNode

else:
  ## Linux/non-macOS hosts: the leaf surface is intentionally empty.
  ## See the module docstring for the EX-M5 partial-linux rationale.
  ## Use `nim check --os:macosx` (driven by
  ## `tests/test_cocoa_leaves_compile.nim`) to validate the leaf
  ## bodies' AppKit-facing surface from this host.
  discard
