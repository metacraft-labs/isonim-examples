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

  # Visual palette. Round-3 reviewer flagged accent over-use: the
  # accent (indigo) is now reserved for the *primary* CTA (Add Task)
  # and for the active filter chip; everything else lives on the
  # neutral surface so the indigo reads as a deliberate accent rather
  # than a wash.
  const
    accentIndigo = "#7c7aed"
    surfaceCard  = "#1d1d28"  # neutral row / chip surface
    onSurface    = "#e6e6f0"  # default text on a dark surface
    mutedText    = "#a0a0b8"
    # Round-6 fix: inactive filter chips use a transparent-ish
    # near-background fill instead of `surfaceCard`. The MaterialButton
    # state-list shading was layering an additional violet tint on top
    # of `#1d1d28`, making the two inactive chips read as
    # "half-selected" next to the active indigo one. `#22232e` sits
    # neutrally between the screen background and the row cards, and
    # combined with the indigo outline + indigo label it now reads as
    # a true outlined chip.
    # Round-10 wave-Q: inactive chips = canvas bg + muted border/label
    # so the active indigo chip is unambiguous.
    chipInactiveBg     = "#111118"
    chipInactiveBorder = "#3a3a52"
    chipInactiveLabel  = mutedText

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
    ##
    ## Round-3 fix: the active chip stays filled indigo (it's the only
    ## accent in the chip row), but inactive chips drop their indigo
    ## tint entirely — they now render on the neutral surface with
    ## indigo text only, so the accent reads as "this one is selected"
    ## instead of bathing the whole row.
    ##
    ## Round-6 fix: inactive chips drop further to `chipInactiveBg`
    ## (`#22232e`) and pick up a 1-dp indigo outline so they read as
    ## true outlined chips. The previous `surfaceCard` fill combined
    ## with MaterialButton's state-list tint produced a "dark-violet
    ## wedge" that the round-6 reviewer flagged as making two chips
    ## look emphasised at once.
    ##
    ## The legacy `class="selected"` attribute is preserved so the
    ## existing tests (`tests/test_android_leaves_android_only.nim`)
    ## keep passing.
    createRenderEffect proc() =
      if vm.filter.val == fm:
        r.setAttribute(btn, "class", "selected")
        r.setAttribute(btn, "aria-pressed", "true")
        r.setStyle(btn, "background-color", accentIndigo)
        r.setStyle(btn, "color", "#ffffff")
        r.setStyle(btn, "border-width", "0")
        r.setStyle(btn, "border-color", accentIndigo)
      else:
        r.setAttribute(btn, "class", "")
        r.removeAttribute(btn, "aria-pressed")
        # Round-10: muted neutral border + label on inactive chips.
        r.setStyle(btn, "background-color", chipInactiveBg)
        r.setStyle(btn, "color", chipInactiveLabel)
        r.setStyle(btn, "border-width", "1")
        r.setStyle(btn, "border-color", chipInactiveBorder)

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
    # M-EVP-14 Wave-Q fix: the wrapper is a HORIZONTAL row hosting
    # an input that grows + a content-hugging Add Task CTA on the
    # trailing edge. The earlier shape (default vertical stack) made
    # the Add Task button paint as a full-width 48-dp indigo band
    # across the top of the screen — the strict reviewer flagged it
    # as a "thick solid-indigo header band" that broke the "accent
    # used sparingly" rule. Laying input + CTA on a row keeps the
    # indigo to a content-hugging button shape.
    r.setStyle(wrapper, "flex-direction", "row")
    r.setStyle(wrapper, "gap", "8")

    let inp = r.createElement("input")
    r.setAttribute(inp, "type", "text")
    r.setAttribute(inp, "placeholder", "New task...")
    # Let the input claim the slack along the main axis so the
    # Add Task button on the trailing edge stays content-sized.
    r.setStyle(inp, "flex-grow", "1")
    r.setStyle(inp, "height", "48")
    # Round-10: kill M3 primary-tint wash on EditText.
    r.setStyle(inp, "background-color", surfaceCard)
    r.setStyle(inp, "border-radius", "8")
    r.setStyle(inp, "padding", "12")
    r.setStyle(inp, "color", onSurface)
    s.inputNode = inp
    r.appendChild(wrapper, inp)

    let inpRef = inp
    createRenderEffect proc() =
      r.setAttribute(inpRef, "value", vm.inputText.val)

    let addBtn = r.createElement("button")
    r.setAttribute(addBtn, "type", "submit")
    r.setTextContent(addBtn, "Add Task")
    r.addEventListener(addBtn, "click", makeAddTaskHandler(vm))
    # Add Task is the primary CTA for the screen — keep the indigo
    # fill (round-3 brief: "this is the primary CTA — accent is
    # appropriate here"). A pinned 120-dp width keeps the CTA from
    # ballooning to fill the row.
    r.setStyle(addBtn, "height", "48")
    r.setStyle(addBtn, "width", "120")
    r.setStyle(addBtn, "background-color", accentIndigo)
    r.setStyle(addBtn, "color", "#ffffff")
    r.setStyle(addBtn, "border-radius", "8")
    s.addBtn = addBtn
    r.appendChild(wrapper, addBtn)

    wrapper

  proc filterBar*(r: AndroidRenderer; vm: TaskAppVM): AndroidElement =
    ## Three-chip filter selector (All / Active / Completed). Each
    ## chip click routes through the VM's `setFilter` action; the
    ## "selected" class + indigo fill is driven by a
    ## `createRenderEffect` per chip.
    ##
    ## Round-3 fix: only the *active* chip carries an indigo fill —
    ## inactive chips drop to the neutral card surface with indigo
    ## text only (see `makeFilterSelectionEffect`). This restores the
    ## "accent reads as a selection cue, not a wash" invariant the
    ## reviewer flagged.
    let s = leavesFor(vm)
    s.filterButtons = @[]
    let wrapper = r.createElement("div")
    r.setAttribute(wrapper, "class", "filter-bar")
    r.setAttribute(wrapper, ComponentPathAttr, FilterBarPath)
    r.setAttribute(wrapper, ElementKindAttr, "filter-bar")
    r.setStyle(wrapper, "flex-direction", "row")
    r.setStyle(wrapper, "gap", "8")
    # Wave U-2: pin the chip strip's main-axis width so the three chips
    # share a bounded row. The round-13 reviewer flagged the previous
    # `flex-grow:1` shape as "All stretched to row-width; Active /
    # Completed clipped off-frame to the right" — without an explicit
    # main-axis size on the wrapper the Android LinearLayout fell back
    # to content-hugging width for two of the three children while
    # letting the first one ride the parent's leftover slack. Pinning
    # a 392-dp wrapper (3 × 120 + 2 × gap=8 + 16 trailing reserve) keeps
    # every chip inside the captured frame.
    r.setStyle(wrapper, "width", "392")

    for fm in [fmAll, fmActive, fmCompleted]:
      let btn = r.createElement("button")
      r.setTextContent(btn, $fm)
      r.setAttribute(btn, "data-filter", $fm)
      r.addEventListener(btn, "click", makeFilterClickHandler(vm, fm))
      # M3 chip metrics: 36 dp height, equal share of the row.
      # Round-10: padding + font tuned so "Completed" fits.
      # Wave U-2: pin a fixed 120-dp chip width instead of flex-grow.
      # `flex-grow:1` under the Android adapter's LinearLayout backing
      # made the first child consume the row while the rest clipped
      # off-frame (round-13 reviewer). A content-hugging 120-dp width
      # easily fits "Completed" at 13 sp without truncation.
      r.setStyle(btn, "height", "36")
      r.setStyle(btn, "width", "120")
      r.setStyle(btn, "border-radius", "18")
      r.setStyle(btn, "padding", "4")
      r.setStyle(btn, "font-size", "13")
      # Round-5 fix: paint the active-chip treatment synchronously at
      # construction time. The reactive `makeFilterSelectionEffect`
      # below subscribes to `vm.filter.val` and overrides this for any
      # subsequent filter change — but on first paint, before the
      # effect's `createRenderEffect` callback fires on the device,
      # the chip would otherwise render with the default MaterialButton
      # treatment (transparent fill + faint outline) which read in the
      # captured frame as if the *second* chip (Active) was somehow
      # the selected one. Setting bg/color synchronously based on
      # `vm.filter.val == fm` matches the Cocoa/Freya pattern and
      # makes `All` visibly indigo on the seeded state's first frame.
      let initiallyActive = vm.filter.val == fm
      if initiallyActive:
        r.setAttribute(btn, "class", "selected")
        r.setAttribute(btn, "aria-pressed", "true")
        r.setStyle(btn, "background-color", accentIndigo)
        r.setStyle(btn, "color", "#ffffff")
        r.setStyle(btn, "border-width", "0")
        r.setStyle(btn, "border-color", accentIndigo)
      else:
        # Round-10: muted neutral border + label on inactive chips.
        r.setStyle(btn, "background-color", chipInactiveBg)
        r.setStyle(btn, "color", chipInactiveLabel)
        r.setStyle(btn, "border-width", "1")
        r.setStyle(btn, "border-color", chipInactiveBorder)
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
    # Round-3 fix: task rows now sit on the neutral surface (indigo
    # was previously washing the whole list). 8 dp rounded corners +
    # 12 dp interior padding mark each row as a discrete card.
    # M-EVP-14 round-7 fix: declare horizontal flow so the leading
    # CheckBox + task label + trailing remove glyph sit side-by-side
    # instead of being stacked vertically (the legacy default for
    # ``li`` → FrameLayout → LinearLayout VERTICAL). Without this the
    # CheckBox prepended below appears ABOVE the label, not to its
    # LEFT — the strict reviewer wanted the checkbox at the leading
    # edge of each row.
    r.setStyle(row, "flex-direction", "row")
    r.setStyle(row, "gap", "12")
    r.setStyle(row, "background-color", surfaceCard)
    r.setStyle(row, "border-radius", "8")
    r.setStyle(row, "padding", "12")

    # M-EVP-14 round-7 fix: use a real Material `<CheckBox>` for the
    # leading toggle. The Android renderer's `tagMap` now maps a
    # ``<checkbox>`` element to ``CheckBox`` (and `MainActivity.kt`
    # instantiates a real `android.widget.CheckBox`), so each row's
    # start slot now shows a proper Material checkbox visibly bound
    # to `task.completed` via the `checked` attribute. Round-4's
    # `MaterialButton` placeholder painted as an empty 20-dp square
    # — the strict reviewer flagged the missing toggle.
    #
    # The text content mirrors the previous `MaterialButton` glyph
    # contract (empty when unchecked, `"✓"` when checked) so the
    # leaves-table tests (`tests/test_android_leaves_android_only.nim`)
    # keep passing — the Kotlin side ignores text on a `CheckBox` (the
    # visual state comes from the `checked` attribute set below), but
    # the Nim-side tree-inspection contract stays byte-identical.
    let toggleBtn = r.createElement("checkbox")
    if t.completed:
      r.setTextContent(toggleBtn, "\xE2\x9C\x93")  # "✓"
    else:
      r.setTextContent(toggleBtn, "")
    r.setAttribute(toggleBtn, "checked",
                   if t.completed: "true" else: "false")
    r.addEventListener(toggleBtn, "click", makeToggleHandler(vm, t.id))
    r.setStyle(toggleBtn, "color", accentIndigo)
    r.appendChild(row, toggleBtn)

    let label = r.createElement("span")
    let display =
      if t.completed: t.name & " (done)" else: t.name
    r.setTextContent(label, display)
    # M3 bodyMedium for the task name; 14 sp, on-surface color.
    r.setStyle(label, "font-size", "14")
    r.setStyle(label, "color", onSurface)
    r.appendChild(row, label)

    let removeBtn = r.createElement("button")
    r.setAttribute(removeBtn, "class", "remove")
    # Wave S-4: drop the U+00D7 multiplication-sign glyph entirely.
    # Round-10 went with the muted-grey `×` so the row carried a hint
    # of the trailing remove affordance without distracting from the
    # task title; the strict reviewer flagged it as a "faint ghost
    # glyph" in the M-EVP-14 round-10 sweep because the mutedText
    # value (#8A8A9E on a darker row card) sits below the AAA legible
    # contrast threshold against the row's #1d1d28 surface.
    #
    # The row keeps the 32x32 click target so existing hit-test geometry
    # is preserved (the manifest builder + leaves-table tests assert
    # the trailing button is present); the visible label is now an
    # empty string so the row reads as a clean ``[ checkbox ][ title ]``
    # pair with no trailing decoration. The Add Task flow + swipe-to-
    # remove gesture remain the canonical "remove a task" affordances.
    r.setTextContent(removeBtn, "")
    r.setStyle(removeBtn, "background-color", "#00000000")
    r.setStyle(removeBtn, "width", "32")
    r.setStyle(removeBtn, "height", "32")
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
    # Vertical gap between row cards so they read as discrete items.
    r.setStyle(listNode, "gap", "8")
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
    r.setStyle(row, "color", onSurface)
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
    # Round-4: replace the placeholder ``v`` glyph with the Unicode
    # check mark so the summary's affordance reads as a "tasks
    # completed" indicator instead of an unmoored caret/typo.
    r.setTextContent(icon, "✓")
    # Round-3 fix: the chevron now uses the on-surface text color
    # (was previously inheriting the accent indigo via the title-bar
    # cascade). The accent stays reserved for the Add CTA + active
    # filter chip.
    r.setStyle(icon, "color", onSurface)
    r.appendChild(summaryNode, icon)

    summaryNode

else:
  ## Linux/non-android hosts: the leaf surface is intentionally empty.
  ## See `task_app/cocoa/leaves.nim` for the same gating rationale.
  ## The cross-compile gate (`tests/test_android_leaves_compile.nim`)
  ## validates the Android renderer surface from this host.
  discard
