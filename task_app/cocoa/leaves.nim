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
##
## TODO(M-EVP-14 follow-up — native Aqua polish):
##   * The renderer maps `<input>` → ekInput (NSTextField) and
##     `<button>` → ekButton (NSButton). The current leaves leave them
##     unstyled, so the headless capture shows raw view rectangles
##     instead of Aqua-native chrome (system-blue button tint,
##     bordered text-field bezel, NSTableView separator hairlines for
##     the task list).
##   * To get a native look without changing the cross-renderer
##     leaf surface, the renderer needs:
##       - `<ul>` → NSTableView (already mapped to ekStack today).
##       - `setBezelStyle:` / `setKeyEquivalent:` for the Add Task
##         button so AppKit paints it as the default action.
##       - `setBezeled:YES` + `setDrawsBackground:YES` on
##         NSTextField for the input row.
##     Tracking the polish here so the next pass can promote these
##     elements without rewriting the leaf composition.

when defined(macosx):
  import std/hashes
  import isonim/core/signals
  import isonim/core/computation # createRenderEffect
  import isonim/dsl/components # forEachKeyed
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
    ##
    ## M-EVP-14 round-3: the active chip gets an indigo (#7c7aed)
    ## background so the user can tell which filter is current. The
    ## inactive chips fall back to a neutral dark fill so the renderer
    ## doesn't paint them with the depth-keyed neutral tint that the
    ## selected chip uses for accent purposes.
    createRenderEffect proc() =
      if vm.filter.val == fm:
        r.setAttribute(btn, "class", "selected")
        r.setAttribute(btn, "aria-pressed", "true")
        r.setStyle(btn, "background-color", "#7c7aed")
      else:
        r.setAttribute(btn, "class", "")
        r.removeAttribute(btn, "aria-pressed")
        r.setStyle(btn, "background-color", "#22232e")

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
    # M-EVP-14 Wave-X (X-2 fix): the appShell defaults to vertical
    # equal-share split (input/filter/list/summary each get ~25 % of
    # the canvas), which inflated the summary to ~180 px and left a
    # ~200 px dead band between the last task row and the summary
    # text. Pin a 4-px outer padding so the cards sit on the dark
    # canvas with a consistent rhythm — the children themselves
    # carry data-fixed-height now (input=64, filter=44, summary=44)
    # so list claims the remainder.
    #
    # M-EVP-14 Wave AA (AA-1 fix): clamp the inner column to a
    # comfortable 700-px max width so the input row, filter chips,
    # task list, and summary footer do not stretch across the full
    # ~1050-px preview pane width. Round-19 reviewer flagged Cocoa
    # rows as spanning the full pane width with a ~750-px gap
    # between the task name and the trailing × glyph. The cocoa
    # adapter honours ``data-fixed-width`` (Wave W-1 adapter work),
    # so pin ``data-fixed-width: 700`` on the appShell itself and
    # centre it horizontally via ``align-self: center``.
    r.setStyle(app, "padding", "8")
    r.setAttribute(app, "data-fixed-width", "700")
    r.setStyle(app, "align-self", "center")
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
    # M-EVP-14 round-3: arrange the input field and the Add button
    # side by side instead of stacking them vertically. The adapter's
    # ``layoutTreeForCapture`` reads ``data-layout="horizontal"`` and
    # switches axis accordingly.
    # M-EVP-14 Wave-X (X-2 fix): bump fixed height 44→56 so the row
    # has a comfortable ~56 px slice in the app shell instead of
    # ballooning to 25 % of the canvas.
    r.setAttribute(wrapper, "data-layout", "horizontal")
    r.setAttribute(wrapper, "data-fixed-height", "56")
    # M-EVP-14 Wave AA (AA-1 fix): clamp the input row to the same
    # 700-px max width as the appShell so the input field + Add
    # button don't stretch across the full pane width.
    r.setAttribute(wrapper, "data-fixed-width", "700")
    r.setStyle(wrapper, "align-self", "center")

    let inp = r.createElement("input")
    r.setAttribute(inp, "type", "text")
    r.setAttribute(inp, "placeholder", "New task...")
    # M-EVP-14 round-7: NSTextField's default bezel paints a white field
    # background which jars badly against the dark task-app palette
    # (the round-6 review flagged the white input bezel as "looks like
    # an unstyled web form"). Setting an explicit background-color here
    # triggers the renderer's bezel-less branch in ``applyStyle`` (see
    # ``isonim_cocoa/renderer.nim`` lines 379-432) which drops
    # ``setBordered:`` + ``setDrawsBackground:`` and lets our dark
    # surface fill replace the system chrome.
    r.setStyle(inp, "background-color", "#15161f")
    r.setStyle(inp, "color", "#ecedf3")
    s.inputNode = inp
    r.appendChild(wrapper, inp)

    let inpRef = inp
    createRenderEffect proc() =
      r.setAttribute(inpRef, "value", vm.inputText.val)

    let addBtn = r.createElement("button")
    r.setAttribute(addBtn, "type", "submit")
    r.setTextContent(addBtn, "Add Task")
    # Pin the Add button to a fixed trailing width so the input
    # field consumes the remaining horizontal slice.
    r.setAttribute(addBtn, "data-fixed-width", "96")
    # Round-10 fix: the reviewer flagged the Add Task button as a "flat
    # outlined chip" rather than a tinted NSButton CTA. The renderer's
    # bezel-less branch only fires when ``background-color`` is set —
    # we already do that, but the reviewer's complaint was that the
    # white title + indigo fill don't read as a *primary* action
    # without a slight rounded corner + explicit white text override.
    # Set ``color`` + ``border-radius`` so the renderer's ekButton
    # accent-fill paints a soft-cornered indigo pill with white text,
    # which is what a macOS primary CTA looks like on a dark surface.
    r.setStyle(addBtn, "background-color", "#7c7aed")
    r.setStyle(addBtn, "color", "#ffffff")
    r.setStyle(addBtn, "border-radius", "8")
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
    # M-EVP-14 round-3: lay the three chips out left-to-right so the
    # filter strip reads as a single horizontal toolbar instead of a
    # vertical stack of equally-sized buttons.
    # M-EVP-14 Wave-X (X-2 fix): bump fixed height 36→44 so the chip
    # strip has a comfortable slice without inflating to 25 % of the
    # canvas.
    r.setAttribute(wrapper, "data-layout", "horizontal")
    r.setAttribute(wrapper, "data-fixed-height", "44")
    # M-EVP-14 Wave AA (AA-1 fix): clamp the filter bar to the same
    # 700-px max width so the chip strip doesn't stretch across the
    # full preview pane.
    r.setAttribute(wrapper, "data-fixed-width", "700")
    r.setStyle(wrapper, "align-self", "center")

    for fm in [fmAll, fmActive, fmCompleted]:
      let btn = r.createElement("button")
      r.setTextContent(btn, $fm)
      r.setAttribute(btn, "data-filter", $fm)
      # M-EVP-14 Wave-Q: pin a content-hugging 96-px main-axis width
      # so the chips don't share the wrapper's row width equally
      # (which produces ~33%-each stretched bands the reviewer
      # flagged). Matches the GPUI/Freya chip-width convention.
      r.setAttribute(btn, "data-fixed-width", "96")
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
    # FUH-M2 Phase A. See ``task_app/gpui/leaves.nim`` for the
    # rationale; hover handlers flip ``ElementKindAttr`` between
    # ``"row"`` and ``"row-hovered"`` to make hover-induced layout
    # mutations observable via the ETS-M2 sparse delta encoder.
    let rowRef = row
    r.addEventListener(row, "mouseenter", proc() =
      r.setAttribute(rowRef, ElementKindAttr, "row-hovered"))
    r.addEventListener(row, "mouseleave", proc() =
      r.setAttribute(rowRef, ElementKindAttr, "row"))
    # M-EVP-14 round-3: arrange the toggle marker, the title label,
    # and the trailing remove glyph horizontally instead of stacking
    # them vertically. The ``data-fixed-height`` reservation gives
    # each row a real ~48 px slice inside the task-list parent (which
    # otherwise distributes its body height equally among rows and,
    # under the round-2 heuristic, collapsed deeper levels to single-
    # digit pixels).
    r.setAttribute(row, "data-layout", "horizontal")
    r.setAttribute(row, "data-fixed-height", "48")
    # M-EVP-14 Wave AA (AA-1 fix): pin per-row main-axis width to
    # the 700-px clamp so each task card hugs the same width as
    # the input row + filter strip + summary footer above/below.
    # Without this, the ``<li>`` rows inherited the cocoa
    # adapter's full-pane stretch and produced a ~750-px gap
    # between the task name and the trailing × glyph.
    r.setAttribute(row, "data-fixed-width", "684")  # 700 - 16 padding
    r.setStyle(row, "min-height", "48px")
    r.setStyle(row, "padding", "8px 12px")
    # M-EVP-14 Wave-Q row-card surface: explicit dark fill +
    # 10-px corners so rows read as discrete cards instead of
    # disappearing into the cocoa adapter's neutralTint canvas.
    # The cocoa adapter honors background-color + border-radius
    # via the bezel-less branch on the row's NSView container.
    r.setStyle(row, "background-color", "#1d1d28")
    r.setStyle(row, "border-radius", "10px")
    if t.completed:
      r.setAttribute(row, "class", "completed")

    # Round-10 fix: the reviewer flagged the previous toggle (a
    # ``<button>`` with ``☐`` / ``☑`` glyphs) as invisible in the
    # captured PNG — the bezel-less NSButton with a single-glyph
    # label paints essentially nothing visible against the dark row
    # background at small sizes. Settings_app's ``toggleLeaf`` after
    # Wave Q-C maps ``<switch>`` → ``ekSwitch`` → real NSSwitch which
    # ships its own pill-shaped on/off chrome (track + knob, animated)
    # and is unambiguous in any capture. Use the same element here so
    # the task row's leading affordance reads as a recognisable
    # completion toggle instead of an empty pixel block.
    let toggleBtn = r.createElement("switch")
    # Pin the toggle widget to the row's leading band. NSSwitch's
    # natural size is ~32×20 px on macOS; reserve 44 px so the row's
    # padding stays consistent with the existing layout convention.
    r.setAttribute(toggleBtn, "data-fixed-width", "44")
    r.setAttribute(toggleBtn, "data-fixed-height", "22")
    # Drive the switch's on/off state via the ``checked`` attribute —
    # the cocoa renderer maps ``checked`` → ``setSwitchState:`` for
    # ekSwitch (see ``isonim_cocoa/renderer.nim`` line 542-544).
    if t.completed:
      r.setAttribute(toggleBtn, "checked", "true")
    else:
      r.setAttribute(toggleBtn, "checked", "false")
    r.addEventListener(toggleBtn, "click", makeToggleHandler(vm, t.id))
    r.appendChild(row, toggleBtn)

    let label = r.createElement("span")
    let display =
      if t.completed: t.name & " (done)" else: t.name
    r.setTextContent(label, display)
    # M-EVP-14 round-8: the cocoa adapter paints task-row containers
    # with the neutral dark-grey ``neutralTint`` palette (#28282E /
    # #323238 / #3A3A40 — see ``cocoa_adapter.layoutTreeForCapture``).
    # NSTextField's default ``controlTextColor`` is near-black, so the
    # title text painted black on dark = invisible. The renderer's
    # ``applyStyle "color"`` branch wires ``setTextColor:`` for
    # ``ekLabel`` (which is what ``<span>`` maps to — see ``tagMap``
    # in ``isonim-cocoa/src/isonim_cocoa/renderer.nim``), so setting an
    # explicit foreground here makes the row title legible.
    r.setStyle(label, "color", "#ecedf3")
    r.appendChild(row, label)

    let removeBtn = r.createElement("button")
    r.setAttribute(removeBtn, "class", "remove")
    # Round-10 fix: the reviewer flagged the ASCII ``"x"`` as reading
    # like a stray hyphen / en-dash at the row's trailing edge rather
    # than a real delete affordance. Swap for the Unicode "vector or
    # cross product" glyph ``⨯`` (U+2A2F) which paints as a
    # proportional, visibly-X-shaped delete mark inside the NSButton
    # bezel-less label slot.
    r.setTextContent(removeBtn, "⨯")
    # Pin the trailing remove glyph to a small fixed width.
    r.setAttribute(removeBtn, "data-fixed-width", "32")
    # Round-7 fix: drop the default NSButton bezel so the remove
    # affordance reads as a subtle dark slot instead of a bright white
    # square at the row's trailing edge.
    r.setStyle(removeBtn, "background-color", "#1f2030")
    # M-EVP-14 Wave-S polish: round-11 reviewer flagged the macOS-red
    # tint on this glyph as "competing with the indigo Add CTA". Pin
    # an explicit muted-neutral text colour (matches the web/freya
    # `.task .remove` convention). The Wave-Q-A renderer edit made
    # ``setStyle "color"`` apply to ekButton bezel-less labels.
    r.setStyle(removeBtn, "color", "#a0a2b0")
    r.addEventListener(removeBtn, "click", makeRemoveHandler(vm, t.id))
    r.appendChild(row, removeBtn)

    row

  proc placeholderRow(r: CocoaRenderer; vm: TaskAppVM): CocoaElement =
    result = r.createElement("p")
    r.setAttribute(result, "class", "empty")
    # M-EVP-14 round-8: paint the empty-state placeholder in the
    # same light foreground used by the row title (see the comment
    # in ``renderTaskRow``) so the text stays legible on the
    # adapter's dark ``neutralTint`` surface.
    r.setStyle(result, "color", "#a3a4ad")
    let placeholderNode = result
    createRenderEffect proc() =
      let placeholder =
        case vm.filter.val
        of fmAll: "(no tasks yet)"
        of fmActive: "(no active tasks)"
        of fmCompleted: "(no completed tasks)"
      r.setTextContent(placeholderNode, placeholder)

  proc taskList*(r: CocoaRenderer; vm: TaskAppVM): CocoaElement =
    ## The visible task rows (or an empty-state placeholder). Built once;
    ## `forEachKeyed` watches `vm.visibleTasks` and reconciles when the
    ## VM mutates.
    ##
    ## M-EVP-14 Wave Y (Y-3 fix): pin the list's main-axis height to
    ## its rows-plus-gaps content size via a reactive
    ## ``data-fixed-height`` so the cocoa adapter no longer hands the
    ## list ALL the leftover shell height. Round-17 task reviewer
    ## flagged a ~300-px dead band between the last row and the
    ## summary; root-cause was that the list was the appShell's only
    ## flex child (input/filter/summary all carried explicit
    ## ``data-fixed-height``), so it absorbed every extra pixel and
    ## the rows sat top-aligned inside a 450-px tall pane. With the
    ## list now content-sized, the cocoa adapter's vertical-stack
    ## heuristic lays the children out tightly from the top: input
    ## (56) → filter (44) → list (rows×48 + gaps) → summary (44).
    ## Any leftover space in the shell ends up as background-tinted
    ## empty area at the BOTTOM of the canvas, which is the natural
    ## visual rhythm for a top-aligned task list with a sticky
    ## summary footer.
    let s = leavesFor(vm)
    let listNode = r.createElement("ul")
    r.setAttribute(listNode, "class", "task-list")
    r.setAttribute(listNode, ComponentPathAttr, TaskListPath)
    r.setAttribute(listNode, ElementKindAttr, "list")
    # EMC2-M3: opt the list into the synthetic walker's
    # ``space-around`` justify behaviour. Mirror of the freya
    # task_app leaf change — at narrow viewports the list owns
    # ~700 px of height while three 48-px rows only consume
    # ~144 px + gaps, leaving the canvas centre in the LIST's
    # blank space (so every jittered hover sample resolves to
    # the same id and the MutationObserver records zero samples).
    # With ``space-around`` the rows spread across the list, so
    # the EMC-M4 / FUH-M8 matrix harness captures non-null hover
    # measurements. See spec EMC2-M3 in
    # ``codetracer-specs/.../Editor-Matrix-Closer-2.milestones.org``.
    r.setAttribute(listNode, "data-justify", "space-around")
    # Wave-Q: 10-px gap so the row-card backgrounds visibly separate.
    r.setStyle(listNode, "gap", "10")
    r.setStyle(listNode, "flex-direction", "column")
    # M-EVP-14 Wave AA (AA-1 fix): clamp the task-list main-axis
    # width so each row's full-width fill is bounded to 700 px
    # instead of stretching across the entire ~1050 px preview
    # pane. Round-19 reviewer flagged "Cocoa rows stretch to span
    # the full preview pane width" with a ~750-px gap between the
    # task name and the trailing × glyph. The cocoa adapter
    # honours ``data-fixed-width`` for both the list and its
    # ``<li>`` children, so the row-card surfaces now hug the
    # 700-px clamp.
    r.setAttribute(listNode, "data-fixed-width", "700")
    r.setStyle(listNode, "align-self", "center")
    # EMC2-M3: previously the list reactively pinned its own
    # ``data-fixed-height`` to the rows-plus-gaps content size so
    # the appShell's vertical-stack heuristic could lay the
    # children out tightly with any leftover space landing as
    # background at the bottom (Wave Y-3 fix for the round-17
    # "~300-px dead band between last row and summary" reviewer
    # finding). With EMC2-M3's ``data-justify="space-around"`` on
    # the list, the rows now spread across the list's full
    # allocated height instead — at Phone (390x844) that puts row
    # #2 near the canvas centre (y~422) where the editor's
    # hover-label hit-test can resolve different jittered cursor
    # samples to different rows. The previous content-tight list
    # left the centre as blank list area (every sample resolved
    # to the LIST itself, zero hover-label samples captured).
    # Drop the dynamic ``data-fixed-height`` so the list becomes
    # the appShell's flex child again; the EMC2-M3 walker change
    # then distributes the rows with even surrounding space.
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
    # M-EVP-14 Wave-X (X-2 fix): without ``data-layout="horizontal"``
    # the cocoa adapter stacked the summary's two children (the text
    # span and the vector-symbol ✓ glyph) vertically and gave each
    # half of the summary's body — the ✓ ended up floating ~90 px
    # below the text as an orphan glyph. Pin a 44-px-tall horizontal
    # band so text + glyph sit side by side on the same baseline.
    r.setAttribute(summaryNode, "data-layout", "horizontal")
    r.setAttribute(summaryNode, "data-fixed-height", "44")
    # M-EVP-14 Wave AA (AA-1 fix): clamp the summary footer to the
    # same 700-px max width so the "N of M remaining" text + check
    # glyph sit on a bounded row, not spread across the full pane.
    r.setAttribute(summaryNode, "data-fixed-width", "700")
    r.setStyle(summaryNode, "align-self", "center")
    s.summaryNode = summaryNode
    let row = r.createElement("span")
    # M-EVP-14 round-8: the summary footer sits on the adapter's
    # ``neutralTint`` palette (dark grey at the bottom of the app
    # shell). Without an explicit foreground colour, NSTextField
    # paints the "N of M remaining" copy in near-black and the
    # whole summary row reads as empty.
    r.setStyle(row, "color", "#ecedf3")
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
    # Round-4: replace the placeholder ``v`` glyph with the Unicode
    # check mark so the summary's affordance reads as a "tasks
    # completed" indicator instead of an unmoored caret/typo.
    r.setTextContent(icon, "✓")
    # M-EVP-14 round-8: the check-glyph rides the same dark surface
    # as the summary footer; tint it with the indigo accent so the
    # affordance reads as an interactive vector-symbol slot rather
    # than blending into the background.
    r.setStyle(icon, "color", "#7c7aed")
    # M-EVP-14 Wave-X (X-2 fix): pin a 24-px main-axis width so the
    # horizontal flow keeps the glyph snug next to the text span
    # instead of letting it claim the row's flex remainder.
    r.setAttribute(icon, "data-fixed-width", "24")
    r.appendChild(summaryNode, icon)

    summaryNode

else:
  ## Linux/non-macOS hosts: the leaf surface is intentionally empty.
  ## See the module docstring for the EX-M5 partial-linux rationale.
  ## Use `nim check --os:macosx` (driven by
  ## `tests/test_cocoa_leaves_compile.nim`) to validate the leaf
  ## bodies' AppKit-facing surface from this host.
  discard
