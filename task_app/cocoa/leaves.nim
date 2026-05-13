## task_app/cocoa/leaves.nim — Layer-1 leaves for the Cocoa target.
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
## On macOS the module ships the same shape as the EX-M3 (GPUI) and
## EX-M4 (Freya) leaves — same per-VM `leavesFor(vm)` side-table, the
## same `rerender(vm)` manual re-render pattern (matching the existing
## `isonim-cocoa/demos/task-manager/src/main.nim` "imperative reactive
## rendering" comment, which is honest for the same reactive-core
## reasons as the GPUI/Freya leaves), and the same `appShell` /
## `taskInput` / `filterBar` / `taskList` / `summaryBar` leaf names so
## `task_app/core/views.nim`'s include-pattern resolves transparently.
##
## Implementation note (carried over from EX-M3/EX-M4): the existing
## Cocoa demo also takes the manual re-render path because the shared
## reactive core's memo-observer notification doesn't yet copy the
## observers list before iterating. The shared core's TUI/web/GPUI/
## Freya leaves take the same path via `rerender(vm)`; we mirror it
## here so the five flavours stay consistent and the cross-renderer
## parity test can drive all of them with the same script.
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
## task. This matches what `isonim-cocoa/demos/task-manager/src/main.nim`
## already did with its placeholder "Task N" generation, while keeping
## the VM as the single source of truth.
##
## Hand-off to the macOS M1 engineer (full list in the EX-M5 status
## entry's `:notes:` block):
##   1. Verify this module builds cleanly on a real macOS host with
##      AppKit available (the Linux side proves the leaf surface
##      compiles via `nim check --os:macosx` on the Cocoa-only fixture
##      in `tests/test_cocoa_leaves_compile.nim`).
##   2. Run the integration test
##      `tests/test_cocoa_leaves_macos_only.nim` on macOS — the assertions
##      mirror EX-M3/EX-M4's scripted scenario and exercise the real
##      AppKit view tree + the `fireEvent` testing helper from
##      `renderer.nim`.
##   3. After both checks pass on macOS, delete
##      `isonim-cocoa/demos/task-manager/src/main.nim` (453 LOC, the
##      from-scratch port that this module supersedes) and add
##      forwarding wiring (Justfile / README / CI) mirroring
##      `isonim-gpui` (EX-M3) and `isonim-freya` (EX-M4) cleanups.
##   4. Extend the cross-renderer parity test (currently in
##      `tests/test_freya_leaves_end_to_end.nim`) to include Cocoa as
##      the 5th renderer, gated `when defined(macosx)`. The
##      `from task_app/main_cocoa as cocoa_app import runTaskApp,
##      rerender, resetCocoaLeaves` import pattern (mirroring the
##      EX-M4 GPUI workaround) avoids the `pointer`-alias overload
##      ambiguity flagged in the EX-M4 status notes.
##   5. Flip the EX-M5 `:status:` from `partial-linux` to `complete`.

when defined(macosx):
  import isonim/core/signals
  import isonim_cocoa/renderer
  import isonim_render_serve/element_tree_attrs

  import task_app/core/vm
  import task_app/core/component_paths

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
  # Re-render helpers
  # ----------------------------------------------------------------------------

  proc clearChildren(r: CocoaRenderer; node: CocoaElement) =
    while r.childCount(node) > 0:
      let c = r.nthChild(node, 0)
      if pointer(c) == nil: break
      r.removeChild(node, c)

  # Forward declaration: per-row click handlers re-render after mutating
  # the VM, but `rerender` itself calls `renderTaskListInto` (which uses
  # the closure factories below). Forward-declare so the cycle resolves.
  proc rerender*(vm: TaskAppVM)

  proc makeToggleHandler(vm: TaskAppVM; id: int): proc() =
    ## Top-level factory so the captured `id` cannot alias a loop
    ## variable in `renderTaskListInto`. Mirrors the per-task closure
    ## pattern used by the GPUI / Freya / web leaves' click handlers.
    result = proc() =
      vm.toggleTask(id)
      rerender(vm)

  proc makeRemoveHandler(vm: TaskAppVM; id: int): proc() =
    result = proc() =
      vm.removeTask(id)
      rerender(vm)

  proc renderTaskListInto(r: CocoaRenderer; vm: TaskAppVM;
                          listNode: CocoaElement) =
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

      r.appendChild(listNode, row)

  proc renderSummaryInto(r: CocoaRenderer; vm: TaskAppVM;
                         summaryNode: CocoaElement) =
    clearChildren(r, summaryNode)
    let row = r.createElement("span")
    let active = vm.activeCount
    let total = vm.totalCount
    let text = $active & " of " & $total & " remaining"
    r.setTextContent(row, text)
    r.appendChild(summaryNode, row)

  proc syncFilterButtons(r: CocoaRenderer; vm: TaskAppVM;
                         buttons: seq[CocoaElement]) =
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
    let r = CocoaRenderer()
    if pointer(s.listNode) != nil:
      renderTaskListInto(r, vm, s.listNode)
    if pointer(s.summaryNode) != nil:
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
    ## Text input + add button. The input node holds the current draft via
    ## its `value` attribute (mirroring `vm.inputText`). The add button's
    ## click handler reads `vm.inputText.val` and pushes the task.
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

  proc filterBar*(r: CocoaRenderer; vm: TaskAppVM): CocoaElement =
    ## Three-button filter selector (All / Active / Completed). Each
    ## button click routes through the VM's `setFilter` action; the
    ## visible "selected" class is mirrored back from the VM's filter
    ## signal via `syncFilterButtons` on every `rerender`.
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
      if vm.filter.val == fm:
        r.setAttribute(btn, "class", "selected")
        r.setAttribute(btn, "aria-pressed", "true")
      else:
        r.setAttribute(btn, "class", "")
      r.appendChild(wrapper, btn)
      s.filterButtons.add btn

    wrapper

  proc taskList*(r: CocoaRenderer; vm: TaskAppVM): CocoaElement =
    ## The visible task rows (or an empty-state placeholder). The wrapper
    ## `<ul>` is built once; `renderTaskListInto` populates and re-
    ## populates the body on every `rerender`.
    let s = leavesFor(vm)
    let listNode = r.createElement("ul")
    r.setAttribute(listNode, "class", "task-list")
    r.setAttribute(listNode, ComponentPathAttr, TaskListPath)
    r.setAttribute(listNode, ElementKindAttr, "list")
    s.listNode = listNode
    renderTaskListInto(r, vm, listNode)
    listNode

  proc summaryBar*(r: CocoaRenderer; vm: TaskAppVM): CocoaElement =
    ## "N of M remaining" footer.
    let s = leavesFor(vm)
    let summaryNode = r.createElement("footer")
    r.setAttribute(summaryNode, "class", "task-summary")
    r.setAttribute(summaryNode, ComponentPathAttr, SummaryBarPath)
    r.setAttribute(summaryNode, ElementKindAttr, "summary")
    s.summaryNode = summaryNode
    renderSummaryInto(r, vm, summaryNode)
    summaryNode

else:
  ## Linux/non-macOS hosts: the leaf surface is intentionally empty.
  ## See the module docstring for the EX-M5 partial-linux rationale and
  ## the macOS hand-off checklist. Use `nim check --os:macosx` (driven
  ## by `tests/test_cocoa_leaves_compile.nim`) to validate the leaf
  ## bodies' AppKit-facing surface from this host.
  discard
