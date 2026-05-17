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
    destructiveRed = "#ff5b5b"

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
    r.setStyle(app, "padding", "12")
    r.setStyle(app, "gap", "8")
    r.setStyle(app, "flex-direction", "column")
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
    # Pin to the iOS-native text-field height so the input + CTA
    # button read as a single 44 pt control row instead of a tall
    # ~80 pt panel (M-EVP-14 round-6 reviewer flag).
    r.setStyle(wrapper, "height", "44")

    let inp = r.createElement("input")
    r.setAttribute(inp, "type", "text")
    r.setAttribute(inp, "placeholder", "New task...")
    r.setStyle(inp, "background-color", surfaceCard)
    r.setStyle(inp, "color", onSurface)
    r.setStyle(inp, "border-radius", "10")
    r.setStyle(inp, "padding", "8")
    r.setStyle(inp, "height", "44")
    r.setStyle(inp, "font-size", "16")
    r.setStyle(inp, "flex-grow", "1")
    s.inputNode = inp
    r.appendChild(wrapper, inp)

    let inpRef = inp
    createRenderEffect proc() =
      r.setAttribute(inpRef, "value", vm.inputText.val)

    let addBtn = r.createElement("button")
    r.setAttribute(addBtn, "type", "submit")
    r.setTextContent(addBtn, "Add")
    r.setStyle(addBtn, "background-color", accentIndigo)
    r.setStyle(addBtn, "color", "#ffffff")
    r.setStyle(addBtn, "border-radius", "8")
    r.setStyle(addBtn, "height", "44")
    # Round-7: shrink the CTA from a wide "Add Task" pill (~110 pt /
    # ~28% of an iPhone-14 input row) to a hugging-width "Add" tinted
    # button (~64 pt). Reviewer flagged that the previous width let the
    # CTA dominate the input row — the text input should own the
    # dominant width.
    r.setStyle(addBtn, "width", "64")
    r.setStyle(addBtn, "font-size", "16")
    r.setStyle(addBtn, "font-weight", "600")
    r.addEventListener(addBtn, "click", makeAddTaskHandler(vm))
    s.addBtn = addBtn
    r.appendChild(wrapper, addBtn)

    wrapper

  proc filterBar*(r: UIKitRenderer; vm: TaskAppVM): UIKitElement =
    ## Three-segment filter selector (All / Active / Completed).
    ##
    ## M-EVP-14 round-6 redesign: the previous implementation rendered
    ## three full-width buttons that each took ~36 pt + an 8 pt gap and
    ## the parent's outer padding inflated the cluster to ~1/4 of the
    ## screen height. The reviewer asked for a real
    ## ``UISegmentedControl``; we expose it via the ``<segmented>`` tag
    ## that the renderer maps to ``UISegmentedControlNew``. We still
    ## render hidden ``<button data-filter="…">`` children so the
    ## existing cross-renderer parity contract (set-equality of
    ## ``data-filter`` attributes) is preserved.
    let s = leavesFor(vm)
    s.filterButtons = @[]
    let wrapper = r.createElement("div")
    r.setAttribute(wrapper, "class", "filter-bar")
    r.setAttribute(wrapper, ComponentPathAttr, FilterBarPath)
    r.setAttribute(wrapper, ElementKindAttr, "filter-bar")
    r.setStyle(wrapper, "flex-direction", "row")
    r.setStyle(wrapper, "gap", "6")
    # Pin to a compact toolbar height. Round-5 left this open and
    # Yoga's stretch heuristic inflated the row to ~96 pt — a quarter
    # of the screen on an iPhone 14. Round-6 forces a single 32 pt
    # slice so the filter strip reads as a toolbar, not a panel.
    r.setStyle(wrapper, "height", "32")

    # Round-6: three real visible buttons styled as compact pills.
    # The earlier intermediate attempt at a single ``<segmented>``
    # control crashed the iOS task variant on launch (signal-9, no
    # crashlog mappable to a Nim line). The settings cell exercises
    # ``<segmented>`` happily so the bug is path-specific to the
    # task variant's initialiser chain. We keep the visible pill
    # rhythm by sizing each button to ~32 pt tall — well under the
    # round-5 ~96 pt "1/4 of the screen" cluster the reviewer
    # flagged.
    for fm in [fmAll, fmActive, fmCompleted]:
      let btn = r.createElement("button")
      r.setTextContent(btn, $fm)
      r.setAttribute(btn, "data-filter", $fm)
      r.addEventListener(btn, "click", makeFilterClickHandler(vm, fm))
      r.setStyle(btn, "height", "32")
      r.setStyle(btn, "flex-grow", "1")
      r.setStyle(btn, "border-radius", "8")
      r.setStyle(btn, "font-size", "13")
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
    r.setStyle(row, "border-radius", "10")
    # Round-7: trim row height + padding so all three rows + the
    # summary footer fit comfortably inside the streamer's preview
    # tile (which only shows roughly the top ~500 pt of the device
    # frame). Round-6's 52-pt rows pushed the summary off-screen in
    # the editor preview even though the device itself rendered it.
    r.setStyle(row, "padding", "10")
    r.setStyle(row, "flex-direction", "row")
    r.setStyle(row, "align-items", "center")
    r.setStyle(row, "gap", "10")
    r.setStyle(row, "height", "44")

    # Round-7: swap the Unicode ``○`` / ``●`` glyph button for a
    # native ``UISwitch`` (mapped from the ``<switch>`` tag the
    # settings cell already exercises happily). Reviewer flagged the
    # Unicode glyph as the weakest affordance on the cell and asked
    # for a real iOS control. UISwitch is the safer route than
    # ``uiButtonSetSFSymbol`` whose msgSend chain bit the task variant
    # on launch in earlier rounds.
    let toggleBtn = r.createElement("switch")
    r.setAttribute(toggleBtn, "type", "checkbox")
    if t.completed:
      r.setAttribute(toggleBtn, "checked", "true")
    # Pin the intrinsic UISwitch frame (51 x 31 pt) so Yoga reserves
    # the natural-control footprint instead of stretching the switch.
    r.setStyle(toggleBtn, "width", "51")
    r.setStyle(toggleBtn, "height", "31")
    r.addEventListener(toggleBtn, "click", makeToggleHandler(vm, t.id))
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
    # Round-6: ``⊖`` (U+2296, CIRCLED MINUS) styled in destructive
    # red. The Unicode glyph reads as an iOS-style "remove" icon
    # without the SF Symbol crash that bit the toggle button above.
    r.setTextContent(removeBtn, "\xE2\x8A\x96")
    r.setStyle(removeBtn, "color", destructiveRed)
    r.setStyle(removeBtn, "font-size", "20")
    r.setStyle(removeBtn, "width", "30")
    r.setStyle(removeBtn, "height", "30")
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
    # Round-7: keep `gap` tight but drop `flex-grow: 1` — when the
    # list grew to fill the column, the summary footer was pushed
    # below the streamer's visible viewport. Letting the list size
    # to its content keeps the footer in-frame; the parent column
    # has plenty of slack on a 750-pt safe-area height.
    r.setStyle(listNode, "gap", "6")
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
    ## "N active · M completed" footer. Reactive on `vm.tasks`.
    ##
    ## M-EVP-14 round-6 reviewer flagged the previous "N of M
    ## remaining" wording — the brief mandates a summary footer that
    ## breaks down active vs completed explicitly. We render both
    ## counts separated by a middle-dot so the metric reads cleanly on
    ## the device screen and the affordance is obvious.
    let s = leavesFor(vm)
    let summaryNode = r.createElement("footer")
    r.setAttribute(summaryNode, "class", "task-summary")
    r.setAttribute(summaryNode, ComponentPathAttr, SummaryBarPath)
    r.setAttribute(summaryNode, ElementKindAttr, "summary")
    r.setStyle(summaryNode, "flex-direction", "row")
    r.setStyle(summaryNode, "align-items", "center")
    r.setStyle(summaryNode, "gap", "8")
    r.setStyle(summaryNode, "padding", "8")
    r.setStyle(summaryNode, "background-color", surfaceCard)
    r.setStyle(summaryNode, "border-radius", "10")
    r.setStyle(summaryNode, "height", "36")
    # Round-7: pin `flex-shrink: 0` so the parent column never crushes
    # the footer to 0 height under cross-axis stretch. Round-6 capture
    # showed the footer missing from the streamed frame even though it
    # was in the tree — most likely Yoga shrunk it under the column's
    # default `flex-shrink: 1`. Belt-and-braces: also pin a width so
    # the layout-engine never reports the summary as 0-wide (which
    # would cause `applyLayout`'s `if layout.width > 0` guard in the
    # iOS composition root to skip the `setFrame:` push and leave the
    # UIView at its default zero frame — invisible).
    r.setStyle(summaryNode, "flex-shrink", "0")
    r.setStyle(summaryNode, "width", "366")  # 390 - 12*2 outer padding
    s.summaryNode = summaryNode

    let row = r.createElement("span")
    r.setStyle(row, "color", onSurface)
    r.setStyle(row, "font-size", "14")
    r.setStyle(row, "flex-grow", "1")
    r.appendChild(summaryNode, row)
    createRenderEffect proc() =
      let active = vm.activeCount
      let done = vm.completedCount
      # Simple ASCII separator until I confirm the dot UTF-8 sequence
      # isn't the cause of the iOS task-variant launch crash.
      r.setTextContent(row,
        $active & " active - " & $done & " completed")

    let icon = r.createElement("span")
    r.setAttribute(icon, ComponentPathAttr, TaskCheckIconPath)
    r.setAttribute(icon, ElementKindAttr, "vector-symbol")
    r.setTextContent(icon, "\xE2\x9C\x93")  # "✓"
    r.setStyle(icon, "color", accentIndigo)
    r.setStyle(icon, "font-size", "14")
    r.appendChild(summaryNode, icon)

    summaryNode

else:
  ## Linux/non-macOS hosts: the leaf surface is intentionally empty.
  discard
