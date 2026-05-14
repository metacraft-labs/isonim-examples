## task_app/android/leaves.nim — Layer-1 leaves for the Android target.
##
## EX-M23c follow-up: each leaf builds its node tree once and binds
## reactively via `createRenderEffect` + `forEachKeyed`. There is no
## public `rerender(vm)` proc; VM mutations propagate to the rendered
## tree through the reactive graph.  This mirrors the GPUI / Freya /
## Cocoa reactive pattern (see `task_app/gpui/leaves.nim`,
## `task_app/freya/leaves.nim`, and `task_app/cocoa/leaves.nim`) so a
## single cross-renderer convention drives every renderer.
##
## Concrete platform components for the task-app's high-level view,
## written against the `AndroidRenderer` from `isonim_android/renderer`.
## Each leaf returns an `AndroidElement` ready for `appendChild`. Leaves
## wire input through the VM's actions; the VM's signals never leak
## through to the higher layers.
##
## EX-M6 status: **partial-linux**.
##
## This is the Linux-host scaffold. The whole module body is gated with
## `when defined(android) or defined(mockJni)` because driving the
## *real* Android leaves requires either a JNI runtime (real device /
## emulator, via `-d:commandBuffer`) or the in-process MockJNI shim
## (`-d:mockJni`) that the existing `isonim-android` tests use. The
## `isonim_android/renderer` Nim module itself compiles cleanly on a
## Linux host (no `{.passL.}` / `{.emit.}` C blocks — the
## AndroidRenderer is portable Nim that talks to the JNI bridge through
## `isonim_android/jni_callbacks`, which is a hard `{.error.}` unless
## either `mockJni` or `commandBuffer` is set). On Linux this module
## therefore compiles as an empty shell so the regular `just test`
## keeps passing unchanged. The cross-compile gate test
## (`tests/test_android_leaves_compile.nim`) drives `nim check
## --os:android -d:mockJni` over a thin Android-only fixture so we
## catch leaf-surface drift from this host without needing an emulator.
##
## API gap: AndroidRenderer's `addEventListener` for an `<input>` (=>
## `EditText`) does not currently expose a "submit" event — Android
## input handling is keyboard-driven and the `EditText`-side IME action
## plumbing is JNI-shim work that hasn't landed yet. Per the milestone
## brief, we use the closest available primitive: a click on the "Add"
## button reads the current `inputText` signal value (mutated when the
## composition root sets a value, or when a test calls
## `vm.setInputText`) and pushes a task.

when defined(android) or defined(mockJni):
  import isonim/core/signals
  import isonim/core/computation  # createRenderEffect
  import isonim/dsl/components    # forEachKeyed
  import isonim_android/renderer
  import isonim_render_serve/element_tree_attrs

  import task_app/core/vm
  import task_app/core/component_paths

  # ----------------------------------------------------------------------------
  # Per-VM bookkeeping (mirrors `tui/leaves.nim`, `web/leaves.nim`,
  # `gpui/leaves.nim`, `freya/leaves.nim`, `cocoa/leaves.nim`).
  # ----------------------------------------------------------------------------

  type
    TaskAppAndroidLeavesState* = ref object
      ## Per-VM bookkeeping for the Android target. The composition root
      ## constructs one of these alongside the VM and the leaves register
      ## via `leavesFor(vm)`. We park it on a side-table keyed by VM id
      ## so `views.nim` stays byte-identical with the TUI/web/GPUI/Freya/
      ## Cocoa targets.
      inputNode*: AndroidElement
      addBtn*: AndroidElement
      listNode*: AndroidElement
      summaryNode*: AndroidElement
      filterButtons*: seq[AndroidElement]

  var androidLeavesTable {.threadvar.}: seq[tuple[vm: TaskAppVM;
                                                  state: TaskAppAndroidLeavesState]]

  proc leavesFor*(vm: TaskAppVM): TaskAppAndroidLeavesState =
    for entry in androidLeavesTable:
      if entry.vm == vm: return entry.state
    result = TaskAppAndroidLeavesState(filterButtons: @[])
    androidLeavesTable.add (vm: vm, state: result)

  proc resetAndroidLeaves*() =
    ## Reset the per-thread table. Used by tests so VM instances from
    ## prior cases don't leak state into the next case.
    androidLeavesTable.setLen(0)

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

  proc makeFilterSelectionEffect(r: AndroidRenderer; vm: TaskAppVM;
                                 btn: AndroidElement; fm: FilterMode) =
    ## Top-level factory so the captured `fm` / `btn` cannot alias a
    ## loop variable in `filterBar`.
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

  proc appShell*(r: AndroidRenderer; vm: TaskAppVM): AndroidElement =
    ## Top-level container. Holds the rest of the leaves. The four
    ## children (input, filter bar, list, summary) are appended by the
    ## Layer-2 view template `renderTaskApp` in `core/views.nim` — this
    ## leaf only creates the empty container so the topology assertions
    ## downstream see the same shape across all renderers.
    discard vm
    let app = r.createElement("div")
    r.setAttribute(app, "class", "task-app")
    r.setAttribute(app, "data-app", "task-app")
    # EX-M23c: component-path annotation. The Android launcher's
    # F-packet stream comes from `adb exec-out screencap` against the
    # device's framebuffer, which never reads `data-*` attributes.
    # The in-process `-d:mockJni` tree the launcher walks for the
    # manifest does see these.
    r.setAttribute(app, ComponentPathAttr, TaskAppPath)
    r.setAttribute(app, ElementKindAttr, "app-shell")
    app

  proc taskInput*(r: AndroidRenderer; vm: TaskAppVM): AndroidElement =
    ## Text input + add button. The input's `value` attribute mirrors
    ## `vm.inputText` reactively. The add button's click handler reads
    ## `vm.inputText.val` (mutated by tests via `vm.setInputText`) and
    ## pushes the task.
    ##
    ## API gap (see module docstring): AndroidRenderer's input surface
    ## has no submit/IME-action event for `EditText`-mapped elements
    ## (the JNI-side IME action wiring hasn't landed yet), so we rely on
    ## a click on the "Add" button instead. Tests drive the input by
    ## calling `vm.setInputText("...")` then `fireEvent(s.addBtn, "click")`.
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

  proc filterBar*(r: AndroidRenderer; vm: TaskAppVM): AndroidElement =
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

  proc renderTaskRow(r: AndroidRenderer; vm: TaskAppVM; t: Task): AndroidElement =
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

  proc placeholderRow(r: AndroidRenderer; vm: TaskAppVM): AndroidElement =
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

  proc taskList*(r: AndroidRenderer; vm: TaskAppVM): AndroidElement =
    ## The visible task rows (or an empty-state placeholder). Built once;
    ## `forEachKeyed` watches `vm.visibleTasks` and reconciles when the
    ## VM mutates.
    let s = leavesFor(vm)
    let listNode = r.createElement("ul")
    r.setAttribute(listNode, "class", "task-list")
    r.setAttribute(listNode, ComponentPathAttr, TaskListPath)
    r.setAttribute(listNode, ElementKindAttr, "list")
    s.listNode = listNode

    # `AndroidElement = ViewHandle = int64` — the nil/empty sentinel is
    # the literal `0` (mirror of `if c == 0: break` further up in the
    # module's earlier imperative form).
    var placeholder: AndroidElement = 0
    createRenderEffect proc() =
      let visible = vm.visibleTasks
      if visible.len == 0 and placeholder == 0:
        placeholder = placeholderRow(r, vm)
        r.appendChild(listNode, placeholder)
      elif visible.len > 0 and placeholder != 0:
        r.removeChild(listNode, placeholder)
        placeholder = 0

    forEachKeyed(r, listNode,
      proc(): seq[Task] = vm.visibleTasks,
      proc(item: proc(): Task; index: proc(): int): AndroidElement =
        renderTaskRow(r, vm, item()))

    listNode

  proc summaryBar*(r: AndroidRenderer; vm: TaskAppVM): AndroidElement =
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
    # Freya / Cocoa leaves' minimal check-mark annotation so the
    # editor's canvas dblclick handler can resolve the click back to
    # the matching ``skVectorSymbol`` story and open the vector editor.
    let icon = r.createElement("span")
    r.setAttribute(icon, ComponentPathAttr, TaskCheckIconPath)
    r.setAttribute(icon, ElementKindAttr, "vector-symbol")
    r.setTextContent(icon, "v")
    r.appendChild(summaryNode, icon)

    summaryNode

else:
  ## Linux/non-android hosts: the leaf surface is intentionally empty.
  ## See `task_app/cocoa/leaves.nim` for the same gating rationale.
  ## The cross-compile gate (`tests/test_android_leaves_compile.nim`)
  ## validates the Android renderer surface from this host.
  discard
