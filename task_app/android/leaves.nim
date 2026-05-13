## task_app/android/leaves.nim — Layer-1 leaves for the Android target.
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
## `when defined(android)` because driving the *real* Android leaves
## requires either a JNI runtime (real device / emulator, via
## `-d:commandBuffer`) or the in-process MockJNI shim
## (`-d:mockJni`) that the existing `isonim-android` tests use. The
## `isonim_android/renderer` Nim module itself compiles cleanly on a
## Linux host (no `{.passL.}` / `{.emit.}` C blocks — the AndroidRenderer
## is portable Nim that talks to the JNI bridge through
## `isonim_android/jni_callbacks`, which is a hard `{.error.}` unless
## either `mockJni` or `commandBuffer` is set). On Linux this module
## therefore compiles as an empty shell so the regular `just test` keeps
## passing unchanged. The cross-compile gate test
## (`tests/test_android_leaves_compile.nim`) drives `nim check
## --os:android -d:mockJni` over a thin Android-only fixture so we
## catch leaf-surface drift from this host without needing an emulator.
##
## On Android (and on the macOS host running the emulator) the module
## ships the same shape as the EX-M3 (GPUI), EX-M4 (Freya), and EX-M5
## (Cocoa) leaves — same per-VM `leavesFor(vm)` side-table, the same
## `rerender(vm)` manual re-render pattern (matching the existing
## `isonim-android/demos/task-manager/src/main.nim` "imperative
## reactive rendering" pattern, which is honest for the same reactive-
## core reasons as the GPUI/Freya/Cocoa leaves), and the same
## `appShell` / `taskInput` / `filterBar` / `taskList` / `summaryBar`
## leaf names so `task_app/core/views.nim`'s include-pattern resolves
## transparently.
##
## Implementation note (carried over from EX-M3/EX-M4/EX-M5): the
## existing Android demo also takes the manual re-render path because
## the shared reactive core's memo-observer notification doesn't yet
## copy the observers list before iterating. The shared core's
## TUI/web/GPUI/Freya/Cocoa leaves take the same path via
## `rerender(vm)`; we mirror it here so the six flavours stay
## consistent and the cross-renderer parity test can drive all of them
## with the same script.
##
## API gap: AndroidRenderer's `addEventListener` for an `<input>` (=>
## `EditText`) does not currently expose a "submit" event — Android
## input handling is keyboard-driven and the `EditText`-side IME action
## plumbing is JNI-shim work that hasn't landed yet. Per the milestone
## brief, we use the closest available primitive: a click on the "Add"
## button reads the current `inputText` signal value (mutated when the
## composition root sets a value, or when a test calls
## `vm.setInputText`) and pushes a task. This matches what
## `isonim-android/demos/task-manager/src/main.nim` already did with
## its programmatic add path, while keeping the VM as the single source
## of truth.
##
## Hand-off to the macOS M1 engineer (full list in the EX-M6 status
## entry's `:notes:` block):
##   1. Verify this module builds cleanly on a real Android target
##      (emulator on Apple Silicon) with the JNI runtime available
##      (`-d:commandBuffer`) — the Linux side proves the leaf surface
##      compiles via `nim check --os:android -d:mockJni` on the
##      Android-only fixture in `tests/test_android_leaves_compile.nim`.
##   2. Run the integration test
##      `tests/test_android_leaves_android_only.nim` on the emulator —
##      the assertions mirror EX-M3/EX-M4/EX-M5's scripted scenario and
##      exercise the real Android view tree + the `fireEvent` testing
##      helper from `renderer.nim`. Compile with `-d:android -d:mockJni`
##      for host-side runs and `-d:android -d:commandBuffer` for the
##      real emulator path.
##   3. After both checks pass, delete
##      `isonim-android/demos/task-manager/src/main.nim` (~221 LOC, the
##      from-scratch port that this module supersedes) and add
##      forwarding wiring (Justfile / README / CI) mirroring
##      `isonim-gpui` (EX-M3), `isonim-freya` (EX-M4), and `isonim-cocoa`
##      (EX-M5) cleanups.
##   4. Extend the cross-renderer parity test (currently in
##      `tests/test_freya_leaves_end_to_end.nim`) to include Android as
##      the 6th renderer, gated `when defined(android)`. The
##      `from task_app/main_android as android_app import runTaskApp,
##      rerender, resetAndroidLeaves` import pattern (mirroring the
##      EX-M4 GPUI workaround) avoids the `pointer`-alias overload
##      ambiguity flagged in the EX-M4 status notes (see "Symbol-
##      collision gotcha" in EX-M5 — `AndroidElement = ViewHandle = int64`
##      so the collision shape is slightly different from
##      `Cocoa/GPUI/Freya`'s `distinct pointer`, but the workaround
##      idiom is the same).
##   5. Flip the EX-M6 `:status:` from `partial-linux` to `complete`.

when defined(android) or defined(mockJni):
  import isonim/core/signals
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
  # Re-render helpers
  # ----------------------------------------------------------------------------

  proc clearChildren(r: AndroidRenderer; node: AndroidElement) =
    while r.childCount(node) > 0:
      let c = r.nthChild(node, 0)
      if c == 0: break
      r.removeChild(node, c)

  # Forward declaration: per-row click handlers re-render after mutating
  # the VM, but `rerender` itself calls `renderTaskListInto` (which uses
  # the closure factories below). Forward-declare so the cycle resolves.
  proc rerender*(vm: TaskAppVM)

  proc makeToggleHandler(vm: TaskAppVM; id: int): proc() =
    ## Top-level factory so the captured `id` cannot alias a loop
    ## variable in `renderTaskListInto`. Mirrors the per-task closure
    ## pattern used by the GPUI / Freya / Cocoa / web leaves' click
    ## handlers.
    result = proc() =
      vm.toggleTask(id)
      rerender(vm)

  proc makeRemoveHandler(vm: TaskAppVM; id: int): proc() =
    result = proc() =
      vm.removeTask(id)
      rerender(vm)

  proc renderTaskListInto(r: AndroidRenderer; vm: TaskAppVM;
                          listNode: AndroidElement) =
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

  proc renderSummaryInto(r: AndroidRenderer; vm: TaskAppVM;
                         summaryNode: AndroidElement) =
    clearChildren(r, summaryNode)
    let row = r.createElement("span")
    let active = vm.activeCount
    let total = vm.totalCount
    let text = $active & " of " & $total & " remaining"
    r.setTextContent(row, text)
    r.appendChild(summaryNode, row)

  proc syncFilterButtons(r: AndroidRenderer; vm: TaskAppVM;
                         buttons: seq[AndroidElement]) =
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
    let r = AndroidRenderer()
    if s.listNode != 0:
      renderTaskListInto(r, vm, s.listNode)
    if s.summaryNode != 0:
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
    ## Text input + add button. The input node holds the current draft via
    ## its `value` attribute (mirroring `vm.inputText`). The add button's
    ## click handler reads `vm.inputText.val` and pushes the task.
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

  proc filterBar*(r: AndroidRenderer; vm: TaskAppVM): AndroidElement =
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

  proc taskList*(r: AndroidRenderer; vm: TaskAppVM): AndroidElement =
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

  proc summaryBar*(r: AndroidRenderer; vm: TaskAppVM): AndroidElement =
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
  ## Linux/non-android hosts: the leaf surface is intentionally empty.
  ## See the module docstring for the EX-M6 partial-linux rationale and
  ## the macOS hand-off checklist. Use `nim check --os:android
  ## -d:mockJni` (driven by `tests/test_android_leaves_compile.nim`)
  ## to validate the leaf bodies' JNI-facing surface from this host.
  discard
