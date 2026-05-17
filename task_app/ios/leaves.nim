## task_app/ios/leaves.nim — Layer-1 leaves for the iOS UIKit target.
##
## Mirrors `task_app/cocoa/leaves.nim` (AppKit) but targets the
## `UIKitRenderer` from `isonim_cocoa/uikit_renderer.nim`. The Stream
## scheme of the iOS app builds the resulting view tree directly into a
## live `UIView` hierarchy on the device, and the Frame Streamer
## captures the rendered frames over Wi-Fi to feed the editor's pbIos
## bridge.
##
## EX-EVP-14 iOS port: leaves wire input through the VM's actions; the
## VM's signals never leak through to the higher layers.
##
## Gating: the whole module body is `when defined(macosx)` because
## `isonim_cocoa/uikit_renderer` transitively imports the Objective-C
## runtime FFI + UIKit shims; those modules carry `{.passL: "-framework
## UIKit".}` / `{.emit: "objc_msgSend".}` blocks that won't compile on
## Linux. On Linux this module collapses to an empty shell so
## `isonim-examples`'s default `just test` keeps working. The Linux
## cross-compile gate for the iOS-target leaves rides on the existing
## Cocoa cross-compile gate (`tests/test_cocoa_leaves_compile.nim`):
## both share the macOS SDK and any drift on the iOS side surfaces in
## the Cocoa-target check first.
##
## Visual palette and topology kept symmetric with the Android leaves
## so a side-by-side comparison in the editor reads as the same demo
## across both mobile renderers.

when defined(macosx):
  import std/hashes
  import isonim/core/signals
  import isonim/core/computation  # createRenderEffect
  import isonim/dsl/components    # forEachKeyed
  import isonim_cocoa/uikit_renderer
  import isonim_cocoa/objc_runtime
  import isonim_render_serve/element_tree_attrs

  import task_app/core/vm
  import task_app/core/component_paths

  # `UIKitElement = Id = distinct pointer`; `Id`'s borrowed `==` lives
  # in `isonim_cocoa/objc_runtime`. `forEachKeyed`/`reconcileArrays` is
  # generic and uses `mixin ==` / `mixin hash` at the instantiation
  # site (reconcile's `Table[N, int]`). `hash(Id)` is already defined
  # in `uikit_renderer` so we only need to re-export `==` here.

  # Visual palette. Mirrors the Android leaves' indigo + neutral
  # surfaces so the two mobile demos read as siblings on capture.
  const
    accentIndigo  = "#7c7aed"
    surfaceCard   = "#1d1d28"
    onSurface     = "#e6e6f0"
    mutedText     = "#a0a0b8"
    chipInactive  = "#22232e"
    screenBg      = "#0f0f17"

  # ----------------------------------------------------------------------------
  # Per-VM bookkeeping (mirrors `task_app/cocoa/leaves.nim`).
  # ----------------------------------------------------------------------------

  type
    TaskAppIosLeavesState* = ref object
      ## Per-VM bookkeeping for the iOS target. The composition root
      ## constructs one of these alongside the VM and the leaves register
      ## via `leavesFor(vm)`. Parked on a per-thread side-table keyed by
      ## VM identity so `views.nim` stays byte-identical with the other
      ## renderers.
      inputNode*: UIKitElement
      addBtn*: UIKitElement
      listNode*: UIKitElement
      summaryNode*: UIKitElement
      filterButtons*: seq[UIKitElement]

  var iosLeavesTable {.threadvar.}: seq[tuple[vm: TaskAppVM;
                                              state: TaskAppIosLeavesState]]

  proc leavesFor*(vm: TaskAppVM): TaskAppIosLeavesState =
    for entry in iosLeavesTable:
      if entry.vm == vm: return entry.state
    result = TaskAppIosLeavesState(filterButtons: @[])
    iosLeavesTable.add (vm: vm, state: result)

  proc resetIosLeaves*() =
    iosLeavesTable.setLen(0)

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

  proc makeFilterSelectionEffect(r: UIKitRenderer; vm: TaskAppVM;
                                 btn: UIKitElement; fm: FilterMode) =
    ## Top-level factory so the captured `fm` / `btn` cannot alias a
    ## loop variable in `filterBar`.
    createRenderEffect proc() =
      if vm.filter.val == fm:
        r.setAttribute(btn, "class", "selected")
        r.setAttribute(btn, "aria-pressed", "true")
        r.setStyle(btn, "background-color", accentIndigo)
        r.setStyle(btn, "color", "#ffffff")
      else:
        r.setAttribute(btn, "class", "")
        r.removeAttribute(btn, "aria-pressed")
        r.setStyle(btn, "background-color", chipInactive)
        r.setStyle(btn, "color", accentIndigo)

  # ----------------------------------------------------------------------------
  # Layer-1 leaf procs — invoked by views.nim
  # ----------------------------------------------------------------------------

  proc appShell*(r: UIKitRenderer; vm: TaskAppVM): UIKitElement =
    ## Top-level container. The four children (input, filter bar, list,
    ## summary) are appended by the Layer-2 view template
    ## `renderTaskApp` in `core/views.nim`.
    discard vm
    let app = r.createElement("div")
    r.setAttribute(app, "class", "task-app")
    r.setAttribute(app, "data-app", "task-app")
    r.setAttribute(app, ComponentPathAttr, TaskAppPath)
    r.setAttribute(app, ElementKindAttr, "app-shell")
    # Vertical stack with comfortable padding for the iPhone safe area.
    r.setStyle(app, "background-color", screenBg)
    r.setStyle(app, "padding", "16")
    r.setStyle(app, "gap", "12")
    app

  proc taskInput*(r: UIKitRenderer; vm: TaskAppVM): UIKitElement =
    ## Text input + add button. The input's `value` attribute mirrors
    ## `vm.inputText` reactively. The add button's click handler reads
    ## `vm.inputText.val` and pushes the task.
    let s = leavesFor(vm)
    let wrapper = r.createElement("div")
    r.setAttribute(wrapper, "class", "task-input")
    r.setAttribute(wrapper, ComponentPathAttr, TaskInputPath)
    r.setAttribute(wrapper, ElementKindAttr, "input")
    r.setStyle(wrapper, "flex-direction", "row")
    r.setStyle(wrapper, "gap", "8")

    let inp = r.createElement("input")
    r.setAttribute(inp, "type", "text")
    r.setAttribute(inp, "placeholder", "New task...")
    r.setStyle(inp, "background-color", surfaceCard)
    r.setStyle(inp, "color", onSurface)
    r.setStyle(inp, "border-radius", "8")
    r.setStyle(inp, "padding", "8")
    r.setStyle(inp, "height", "44")
    r.setStyle(inp, "flex-grow", "1")
    s.inputNode = inp
    r.appendChild(wrapper, inp)

    let inpRef = inp
    createRenderEffect proc() =
      r.setAttribute(inpRef, "value", vm.inputText.val)

    let addBtn = r.createElement("button")
    r.setAttribute(addBtn, "type", "submit")
    r.setTextContent(addBtn, "Add Task")
    r.setStyle(addBtn, "background-color", accentIndigo)
    r.setStyle(addBtn, "color", "#ffffff")
    r.setStyle(addBtn, "border-radius", "8")
    r.setStyle(addBtn, "height", "44")
    r.setStyle(addBtn, "width", "110")
    r.addEventListener(addBtn, "click", makeAddTaskHandler(vm))
    s.addBtn = addBtn
    r.appendChild(wrapper, addBtn)

    wrapper

  proc filterBar*(r: UIKitRenderer; vm: TaskAppVM): UIKitElement =
    ## Three-chip filter selector (All / Active / Completed).
    let s = leavesFor(vm)
    s.filterButtons = @[]
    let wrapper = r.createElement("div")
    r.setAttribute(wrapper, "class", "filter-bar")
    r.setAttribute(wrapper, ComponentPathAttr, FilterBarPath)
    r.setAttribute(wrapper, ElementKindAttr, "filter-bar")
    r.setStyle(wrapper, "flex-direction", "row")
    r.setStyle(wrapper, "gap", "8")
    r.setStyle(wrapper, "height", "40")

    for fm in [fmAll, fmActive, fmCompleted]:
      let btn = r.createElement("button")
      r.setTextContent(btn, $fm)
      r.setAttribute(btn, "data-filter", $fm)
      r.addEventListener(btn, "click", makeFilterClickHandler(vm, fm))
      r.setStyle(btn, "height", "36")
      r.setStyle(btn, "flex-grow", "1")
      r.setStyle(btn, "border-radius", "18")
      let initiallyActive = vm.filter.val == fm
      if initiallyActive:
        r.setAttribute(btn, "class", "selected")
        r.setAttribute(btn, "aria-pressed", "true")
        r.setStyle(btn, "background-color", accentIndigo)
        r.setStyle(btn, "color", "#ffffff")
      else:
        r.setStyle(btn, "background-color", chipInactive)
        r.setStyle(btn, "color", accentIndigo)
      makeFilterSelectionEffect(r, vm, btn, fm)
      r.appendChild(wrapper, btn)
      s.filterButtons.add btn

    wrapper

  proc renderTaskRow(r: UIKitRenderer; vm: TaskAppVM; t: Task): UIKitElement =
    let row = r.createElement("li")
    r.setAttribute(row, "data-task-id", $t.id)
    r.setAttribute(row, ComponentPathAttr, taskRowPath(t.id))
    r.setAttribute(row, ElementKindAttr, "row")
    if t.completed:
      r.setAttribute(row, "class", "completed")
    r.setStyle(row, "background-color", surfaceCard)
    r.setStyle(row, "border-radius", "8")
    r.setStyle(row, "padding", "12")
    r.setStyle(row, "flex-direction", "row")
    r.setStyle(row, "gap", "12")
    r.setStyle(row, "height", "52")

    let toggleBtn = r.createElement("button")
    let marker = if t.completed: "\xE2\x98\x91" else: "\xE2\x98\x90"
    r.setTextContent(toggleBtn, marker)
    r.addEventListener(toggleBtn, "click", makeToggleHandler(vm, t.id))
    r.setStyle(toggleBtn, "width", "32")
    r.setStyle(toggleBtn, "height", "32")
    r.setStyle(toggleBtn, "font-size", "20")
    if t.completed:
      r.setStyle(toggleBtn, "color", accentIndigo)
    else:
      r.setStyle(toggleBtn, "color", mutedText)
    r.appendChild(row, toggleBtn)

    let label = r.createElement("span")
    let display =
      if t.completed: t.name & " (done)" else: t.name
    r.setTextContent(label, display)
    r.setStyle(label, "font-size", "16")
    r.setStyle(label, "color", onSurface)
    r.setStyle(label, "flex-grow", "1")
    r.appendChild(row, label)

    let removeBtn = r.createElement("button")
    r.setAttribute(removeBtn, "class", "remove")
    r.setTextContent(removeBtn, "x")
    r.setStyle(removeBtn, "color", mutedText)
    r.setStyle(removeBtn, "width", "32")
    r.setStyle(removeBtn, "height", "32")
    r.addEventListener(removeBtn, "click", makeRemoveHandler(vm, t.id))
    r.appendChild(row, removeBtn)

    row

  proc placeholderRow(r: UIKitRenderer; vm: TaskAppVM): UIKitElement =
    result = r.createElement("p")
    r.setAttribute(result, "class", "empty")
    r.setStyle(result, "color", mutedText)
    r.setStyle(result, "padding", "12")
    let placeholderNode = result
    createRenderEffect proc() =
      let placeholder =
        case vm.filter.val
        of fmAll:       "(no tasks yet)"
        of fmActive:    "(no active tasks)"
        of fmCompleted: "(no completed tasks)"
      r.setTextContent(placeholderNode, placeholder)

  proc taskList*(r: UIKitRenderer; vm: TaskAppVM): UIKitElement =
    let s = leavesFor(vm)
    let listNode = r.createElement("ul")
    r.setAttribute(listNode, "class", "task-list")
    r.setAttribute(listNode, ComponentPathAttr, TaskListPath)
    r.setAttribute(listNode, ElementKindAttr, "list")
    r.setStyle(listNode, "gap", "8")
    r.setStyle(listNode, "flex-grow", "1")
    s.listNode = listNode

    var placeholder: UIKitElement = UIKitElement(Id(nil))
    createRenderEffect proc() =
      let visible = vm.visibleTasks
      if visible.len == 0 and pointer(placeholder) == nil:
        placeholder = placeholderRow(r, vm)
        r.appendChild(listNode, placeholder)
      elif visible.len > 0 and pointer(placeholder) != nil:
        r.removeChild(listNode, placeholder)
        placeholder = UIKitElement(Id(nil))

    forEachKeyed(r, listNode,
      proc(): seq[Task] = vm.visibleTasks,
      proc(item: proc(): Task; index: proc(): int): UIKitElement =
        renderTaskRow(r, vm, item()))

    listNode

  proc summaryBar*(r: UIKitRenderer; vm: TaskAppVM): UIKitElement =
    let s = leavesFor(vm)
    let summaryNode = r.createElement("footer")
    r.setAttribute(summaryNode, "class", "task-summary")
    r.setAttribute(summaryNode, ComponentPathAttr, SummaryBarPath)
    r.setAttribute(summaryNode, ElementKindAttr, "summary")
    r.setStyle(summaryNode, "flex-direction", "row")
    r.setStyle(summaryNode, "gap", "8")
    r.setStyle(summaryNode, "padding", "8")
    s.summaryNode = summaryNode

    let row = r.createElement("span")
    r.setStyle(row, "color", onSurface)
    r.setStyle(row, "font-size", "14")
    r.appendChild(summaryNode, row)
    createRenderEffect proc() =
      let active = vm.activeCount
      let total = vm.totalCount
      r.setTextContent(row, $active & " of " & $total & " remaining")

    let icon = r.createElement("span")
    r.setAttribute(icon, ComponentPathAttr, TaskCheckIconPath)
    r.setAttribute(icon, ElementKindAttr, "vector-symbol")
    r.setTextContent(icon, "\xE2\x9C\x93")  # "✓"
    r.setStyle(icon, "color", onSurface)
    r.appendChild(summaryNode, icon)

    summaryNode

else:
  ## Linux/non-macOS hosts: the leaf surface is intentionally empty.
  discard
