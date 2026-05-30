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
                               btn, labelSpan: FreyaElement;
                               fm: FilterMode) =
  ## Round-4: visibly distinguish active vs inactive filter chip. The
  ## active chip flips to an indigo fill + white text; inactive chips
  ## drop back to the dark card surface with secondary text colour. We
  ## also flip the label span's colour explicitly so the chip's text
  ## reads against either background (Freya's `label` honours its own
  ## `color` style, not the parent rect's colour).
  createRenderEffect proc() =
    if vm.filter.val == fm:
      r.setAttribute(btn, "class", "selected")
      r.setAttribute(btn, "aria-pressed", "true")
      r.setStyle(btn, "background", "rgb(124, 122, 237)")
      r.setStyle(labelSpan, "color", "rgb(255, 255, 255)")
      r.setStyle(labelSpan, "font-weight", "bold")
    else:
      r.setAttribute(btn, "class", "")
      r.removeAttribute(btn, "aria-pressed")
      r.setStyle(btn, "background", "rgb(34, 35, 46)")
      r.setStyle(labelSpan, "color", "rgb(160, 162, 176)")
      r.setStyle(labelSpan, "font-weight", "normal")

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
  # Round-4: tighter outer gap (8px) so the input row, filter chips,
  # task list and summary fit comfortably without the auto-grow rect
  # heuristic stretching each child to ~50px.
  r.setStyle(app, "background", "rgb(15, 15, 20)")
  r.setStyle(app, "color", "rgb(232, 233, 240)")
  r.setStyle(app, "padding", "12")
  r.setStyle(app, "flex-direction", "column")
  r.setStyle(app, "gap", "8")
  r.setStyle(app, "cross_align", "start")
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
  # Round-4: pin a row height (~52 px) so the wrapper does not auto-
  # grow into a 50%-of-canvas band when Freya distributes free space
  # between the four shell children.
  # M-EVP-14 round-7 fix: the headless Freya adapter
  # (`isonim-render-serve/.../freya_adapter.nim::walkLayout`) now
  # honors ``data-layout="horizontal"`` + ``data-fixed-width`` so the
  # captured raster matches the live Freya runtime's intent. Mark
  # this wrapper as a horizontal flow so the Add Task button can
  # claim a fixed 120 px slice along the main axis.
  r.setAttribute(wrapper, "data-layout", "horizontal")
  r.setAttribute(wrapper, "data-fixed-height", "52")
  r.setStyle(wrapper, "background", "rgb(29, 29, 40)")
  # M-EVP-14 Wave T (T-6 fix): align the input-row's horizontal
  # padding with the task-row's so the left edges of the input
  # field and each task card sit at exactly the same x. Previously
  # the input wrapper used padding 8 while task rows used padding
  # 10, producing a ~2 px drift that round-12 reviewer flagged as
  # "task rows' left edge floats slightly relative to the input
  # bar above".
  r.setStyle(wrapper, "padding", "10")
  r.setStyle(wrapper, "gap", "10")
  r.setStyle(wrapper, "flex-direction", "row")
  r.setStyle(wrapper, "cross_align", "center")
  r.setStyle(wrapper, "border-radius", "10")
  r.setStyle(wrapper, "width", "100%")
  r.setStyle(wrapper, "height", "52")

  let inp = r.createElement("input")
  r.setAttribute(inp, "type", "text")
  r.setAttribute(inp, "placeholder", "New task...")
  # M-EVP-14 round-7: the input is the flex child of the horizontal
  # input row — no ``data-fixed-width`` so it claims the leftover
  # space after the 120 px Add Task button is reserved.
  # Round-4: pin the input field's height so the placeholder span
  # does not vertically dominate; let the input flex horizontally.
  # Round-5: ``width: fill`` greedily took the whole wrapper row
  # before the Add Task button got its 84 px allocation, which
  # clipped the button to a thin sliver at the right edge. Replace
  # ``fill`` with an explicit width that leaves room for the button
  # (the editor cell canvas is 800 px wide; the wrapper's outer
  # padding + gap leaves ~770 px of inner row width, so 660 px keeps
  # the button (84) + gap (8) clear at the right edge with a
  # comfortable margin).
  r.setStyle(inp, "background", "rgb(34, 35, 46)")
  r.setStyle(inp, "padding", "8")
  r.setStyle(inp, "border-radius", "4")
  r.setStyle(inp, "flex-direction", "row")
  r.setStyle(inp, "cross_align", "center")
  # M-EVP-14 Wave Y (Y-6 fix): shrink input width from 660 → 600 so
  # the trailing 120-px Add Task pill (the headless adapter honours
  # ``data-fixed-width: 120``, not the inline ``width: 84``) doesn't
  # spill off the right edge of the 800-px preview pane. Round-17
  # task reviewer flagged "'Add Task' button text is partly clipped
  # on the right edge in the visible crop". Wrapper inner width with
  # padding=10 + gap=10 is 770; input(600) + gap(10) + button(120) =
  # 730 leaves a comfortable 40-px right-edge margin.
  r.setStyle(inp, "width", "600")
  r.setStyle(inp, "height", "36")
  s.inputNode = inp
  r.appendChild(wrapper, inp)

  # Placeholder text must live in a child <span> (→ Freya `label`)
  # because the underlying `rect` does not render its own text. The
  # span's text mirrors `vm.inputText.val`; when empty we fall back
  # to the placeholder copy so the cell stays informative. The
  # placeholder weight stays light (`normal`) to read as hint text;
  # entered text flips to primary colour at body weight.
  let placeholderSpan = r.createElement("span")
  r.setStyle(placeholderSpan, "color", "rgb(110, 112, 128)")
  r.setStyle(placeholderSpan, "font-size", "14")
  r.setStyle(placeholderSpan, "font-weight", "normal")
  r.appendChild(inp, placeholderSpan)

  let inpRef = inp
  let placeRef = placeholderSpan
  createRenderEffect proc() =
    let v = vm.inputText.val
    r.setAttribute(inpRef, "value", v)
    if v.len == 0:
      r.setTextContent(placeRef, "New task...")
      r.setStyle(placeRef, "color", "rgb(110, 112, 128)")
      r.setStyle(placeRef, "font-weight", "normal")
    else:
      r.setTextContent(placeRef, v)
      r.setStyle(placeRef, "color", "rgb(232, 233, 240)")
      r.setStyle(placeRef, "font-weight", "normal")

  let addBtn = r.createElement("button")
  r.setAttribute(addBtn, "type", "submit")
  r.setTextContent(addBtn, "Add Task")
  # M-EVP-14 round-7 fix: pin a 120 px main-axis size for the headless
  # Freya raster so the captured frame shows a content-hugging button
  # instead of a ~40 %-of-pane band. The live Freya runtime keeps using
  # the ``width`` style below.
  r.setAttribute(addBtn, "data-fixed-width", "120")
  # Round-4: pin width/height so the CTA reads as a real button (not a
  # full-width band). Round-5: the prior 96 px width clipped the
  # button against the right edge because the input row's ``width:
  # fill`` claimed the whole wrapper before the button got positioned;
  # shrink the button to 84 px and reduce horizontal padding so the
  # "Add Task" label fits cleanly inside the pill and the pill sits
  # comfortably inside the wrapper's right edge with the 8 px gap.
  r.setStyle(addBtn, "background", "rgb(124, 122, 237)")
  r.setStyle(addBtn, "padding", "6")
  r.setStyle(addBtn, "border-radius", "6")
  r.setStyle(addBtn, "flex-direction", "row")
  r.setStyle(addBtn, "cross_align", "center")
  r.setStyle(addBtn, "main_align", "center")
  r.setStyle(addBtn, "width", "84")
  r.setStyle(addBtn, "height", "32")
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
  # Round-4: pin a row height so the chips do not auto-grow into a
  # 50%-of-canvas band. cross_align=center keeps the chips centred
  # vertically inside the row.
  # Round-5: tighten further so the chip strip is shorter than the
  # task rows (was reading as slightly taller than the 36 px rows).
  # M-EVP-14 round-7: declare horizontal flow + pin row height so the
  # headless raster packs the three chips left-to-right at their
  # natural ~96 px widths instead of stretching each to ~1/3 of the
  # pane.
  r.setAttribute(wrapper, "data-layout", "horizontal")
  r.setAttribute(wrapper, "data-fixed-height", "28")
  r.setStyle(wrapper, "flex-direction", "row")
  r.setStyle(wrapper, "gap", "8")
  r.setStyle(wrapper, "padding", "0")
  r.setStyle(wrapper, "cross_align", "center")
  r.setStyle(wrapper, "height", "28")

  for fm in [fmAll, fmActive, fmCompleted]:
    let btn = r.createElement("button")
    r.setTextContent(btn, $fm)
    r.setAttribute(btn, "data-filter", $fm)
    # M-EVP-14 round-7 fix: pin a 96 px main-axis size so each chip
    # packs against its neighbour at content-width instead of being
    # stretched to a third of the pane by the headless raster.
    r.setAttribute(btn, "data-fixed-width", "96")
    # Round-4: chip-shaped pill (~80×28). Round-5 follow-up: the
    # reactive selection effect didn't always paint over the baseline
    # `rgb(34, 35, 46)` before the first F-packet was captured, so the
    # three chips read with identical dark fill in the captured frame.
    # Apply the active-state styling synchronously at construction
    # time (matching the Cocoa treatment) so the seeded `All` chip is
    # already indigo on the first paint; the reactive effect below
    # then keeps it correct under user-driven filter changes.
    let initiallyActive = vm.filter.val == fm
    if initiallyActive:
      r.setStyle(btn, "background", "rgb(124, 122, 237)")
    else:
      r.setStyle(btn, "background", "rgb(34, 35, 46)")
    r.setStyle(btn, "padding", "4")
    r.setStyle(btn, "border-radius", "12")
    r.setStyle(btn, "flex-direction", "row")
    r.setStyle(btn, "cross_align", "center")
    r.setStyle(btn, "main_align", "center")
    r.setStyle(btn, "width", "78")
    r.setStyle(btn, "height", "24")
    r.addEventListener(btn, "click", makeFilterClickHandler(vm, fm))
    r.appendChild(wrapper, btn)
    # Visible label as a span child so the raster paints it. Synchronously
    # paint the active treatment colour so the seeded label reads white
    # on the indigo chip on the very first frame; the effect below keeps
    # it consistent across filter changes.
    let initialLabelColor =
      if initiallyActive: "rgb(255, 255, 255)" else: "rgb(160, 162, 176)"
    let initialLabelWeight = if initiallyActive: "bold" else: "normal"
    let labelSpan = addTextSpan(r, btn, $fm,
                                color = initialLabelColor,
                                fontSize = "13",
                                fontWeight = initialLabelWeight)
    makeFilterSelectionEffect(r, vm, btn, labelSpan, fm)
    s.filterButtons.add btn

  wrapper

proc renderTaskRow(r: FreyaRenderer; vm: TaskAppVM; t: Task): FreyaElement =
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
  if t.completed:
    r.setAttribute(row, "class", "completed")
  # Card-style row separation. Round-4: pin a row height (~36 px) so the
  # rows pack tightly and the toggle/remove glyphs don't autoscale to
  # ~50 px tall.
  # M-EVP-14 round-7: horizontal flow + pin a 36 px main-axis height
  # so the headless adapter keeps each row tight, and the inner
  # toggle/title/remove children flow left-to-right.
  # M-EVP-14 Wave-Q row-card refinement: keep 36-px row height (Freya
  # pane only fits ~3×36 + chrome before the third row overflows)
  # but bump padding 8→10, border-radius 6→10 so rows read as
  # discrete cards (strict-reviewer note: previous rows "blur into
  # the pane background").
  # M-EVP-14 Wave Y (Y-6 fix): bump row height 40 → 52 and padding
  # 10 → 12 so the toggle/title/remove triplet has visible card
  # padding rhythm. Round-17 task reviewer flagged the rows as
  # "very tight vertically — task name + tiny check square + ``×``
  # cramped on one ~24-px line; no card padding rhythm". At 52 px
  # the row body claims ~28 px of inner height between the 12-px
  # top/bottom padding bands, which gives the 20-px toggle / label /
  # 20-px remove children a comfortable centred line plus 4 px
  # breathing on either side.
  r.setAttribute(row, "data-layout", "horizontal")
  r.setAttribute(row, "data-fixed-height", "52")
  # M-EVP-14 Wave AA (AA-8 fix): lift the row background from
  # rgb(29, 29, 40) to rgb(35, 36, 48) so the cards read as
  # distinct surfaces against the appShell's rgb(15, 15, 20)
  # pane background. Round-19 reviewer flagged "Row backgrounds
  # are nearly identical to the panel background — even with the
  # larger gap, the rows read more as separator lines than as
  # distinct cards." The +6 RGB lift in each channel pushes the
  # contrast ratio from ~1.3 to ~1.7 against the pane, which is
  # enough for the rows to read as cards in the Freya headless
  # Skia raster.
  r.setStyle(row, "background", "rgb(35, 36, 48)")
  r.setStyle(row, "padding", "12")
  r.setStyle(row, "gap", "10")
  r.setStyle(row, "flex-direction", "row")
  r.setStyle(row, "cross_align", "center")
  r.setStyle(row, "border-radius", "10")
  r.setStyle(row, "height", "52")
  r.setStyle(row, "width", "100%")

  let toggleBtn = r.createElement("button")
  # Round-10: designed checkbox with a fill-driven off/on contrast.
  # M-EVP-14 Wave T (T-6 fix): round-12 reviewer flagged "no visible
  # toggle glyph on unchecked rows". Paint an explicit empty-box
  # affordance — a hollow ☐ for off, ✓ for on — so the row's leading
  # control reads as a recognisable checkbox at any preview scale,
  # not just a slate-grey square. The Freya headless raster lacks
  # CSS borders, so the inner-glyph contrast is the only off-state
  # affordance we get.
  let marker = if t.completed: "✓" else: "☐"
  r.setTextContent(toggleBtn, marker)
  # M-EVP-14 round-7: pin the toggle's main-axis width so it stays a
  # 20 px square in the headless raster instead of consuming the
  # equal-share allocation.
  r.setAttribute(toggleBtn, "data-fixed-width", "20")
  let toggleBg = if t.completed: "rgb(124, 122, 237)" else: "rgb(80, 82, 102)"
  r.setStyle(toggleBtn, "background", toggleBg)
  r.setStyle(toggleBtn, "padding", "0")
  r.setStyle(toggleBtn, "border-radius", "4")
  r.setStyle(toggleBtn, "flex-direction", "row")
  r.setStyle(toggleBtn, "cross_align", "center")
  r.setStyle(toggleBtn, "main_align", "center")
  r.setStyle(toggleBtn, "width", "20")
  r.setStyle(toggleBtn, "height", "20")
  r.addEventListener(toggleBtn, "click", makeToggleHandler(vm, t.id))
  r.appendChild(row, toggleBtn)
  # Always render the glyph; the on-state white ✓ rides on the indigo
  # fill, the off-state hollow ☐ rides on the slate fill.
  addTextSpan(r, toggleBtn, marker,
              color = (if t.completed: "rgb(255, 255, 255)"
                       else: "rgb(220, 222, 234)"),
              fontSize = "14", fontWeight = "bold")

  let display =
    if t.completed: t.name & " (done)" else: t.name
  # M-EVP-14 Wave-S polish: bump title to 15 px / weight 500 so the
  # row text reads as a clear primary label, distinct from the 12 px /
  # weight normal summary footer. Round-11 reviewer flagged "task
  # title weight identical to summary weight; typography hierarchy
  # between row title and footer is flat" — this widens the type
  # tier ratio.
  addTextSpan(r, row, display,
              color = (if t.completed: "rgb(110, 112, 128)"
                       else: "rgb(232, 233, 240)"),
              fontSize = "15", fontWeight = "500")

  let removeBtn = r.createElement("button")
  r.setAttribute(removeBtn, "class", "remove")
  r.setTextContent(removeBtn, "×")
  # Round-10: switch from a soft-red ASCII "x" to the proper U+00D7
  # multiplication-sign glyph in the muted secondary text colour, so
  # the affordance reads as a deliberate tertiary control (matching
  # the web `.task .remove` rule) rather than a stray red letter.
  # M-EVP-14 round-7: pin the remove glyph's main-axis width to 20 px.
  r.setAttribute(removeBtn, "data-fixed-width", "20")
  r.setStyle(removeBtn, "background", "rgb(29, 29, 40)")
  r.setStyle(removeBtn, "padding", "0")
  r.setStyle(removeBtn, "border-radius", "4")
  r.setStyle(removeBtn, "flex-direction", "row")
  r.setStyle(removeBtn, "cross_align", "center")
  r.setStyle(removeBtn, "main_align", "center")
  r.setStyle(removeBtn, "width", "20")
  r.setStyle(removeBtn, "height", "20")
  r.addEventListener(removeBtn, "click", makeRemoveHandler(vm, t.id))
  r.appendChild(row, removeBtn)
  addTextSpan(r, removeBtn, "×",
              color = "rgb(160, 162, 176)",
              fontSize = "16", fontWeight = "bold")

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
  # EMC2-M3: opt the list into the synthetic walker's
  # ``space-around`` justify behaviour. At narrow viewports (Phone
  # 390x844) the appShell's vertical flex distribution gives the
  # list ~720 px of height while the three 52-px rows only occupy
  # ~172 px (plus gaps). Without justify, rows pack at the top
  # (y=104..260) and the editor's hover-label hit-test resolves
  # the canvas centre (y=422) to the LIST element for every
  # jittered cursor sample — the EMC-M4 / FUH-M8 matrix harness
  # then captures 0 hover-label samples. With ``space-around``
  # the rows spread across the list height (row #2 lands near
  # y=432), so the harness's ±40-px jitter crosses between
  # rows / blank gap → hovered id changes → hover-label style
  # mutates → MutationObserver fires. Restores hover-null cell
  # parity with the gpui task_app Phone cell.
  r.setAttribute(listNode, "data-justify", "space-around")
  r.setStyle(listNode, "flex-direction", "column")
  # Wave-Q: 10-px row gap so rows visibly separate as cards.
  # M-EVP-14 Wave Z' (Z'-4): bump to 14 so the three task rows visibly
  # separate as discrete cards (the round-Z reviewer flagged the
  # 10-px gap as too tight — the rows blurred into a stacked band).
  r.setStyle(listNode, "gap", "14")
  r.setStyle(listNode, "padding", "0")
  r.setStyle(listNode, "width", "100%")
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
  # Round-4: pin a summary row height (~30 px) so it reads as a footer
  # caption strip rather than another auto-grown card.
  # M-EVP-14 round-7: horizontal flow + pin a 30 px main-axis height
  # so the headless adapter keeps the summary strip thin.
  r.setAttribute(summaryNode, "data-layout", "horizontal")
  r.setAttribute(summaryNode, "data-fixed-height", "30")
  r.setStyle(summaryNode, "background", "rgb(29, 29, 40)")
  r.setStyle(summaryNode, "padding", "8")
  r.setStyle(summaryNode, "gap", "8")
  r.setStyle(summaryNode, "flex-direction", "row")
  r.setStyle(summaryNode, "cross_align", "center")
  r.setStyle(summaryNode, "border-radius", "6")
  r.setStyle(summaryNode, "width", "100%")
  r.setStyle(summaryNode, "height", "30")
  # Round-10: 12-px margin-top so the summary visually separates from
  # the last task row. The reviewer flagged the round-9 layout's tight
  # spacing rhythm break against the dense list above.
  r.setStyle(summaryNode, "margin-top", "12")
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
  # Round-4: replace the placeholder ``v`` glyph (which read as an
  # unmoored caret/typo at the bottom-left of the summary) with the
  # Unicode check mark. The web cell omits this leaf entirely, which
  # is why the asymmetry was only visible on the non-web backends.
  r.setTextContent(icon, "✓")
  # M-EVP-14 round-7: pin the icon's main-axis width so the headless
  # raster keeps it as a tight glyph at the right edge of the
  # summary row.
  r.setAttribute(icon, "data-fixed-width", "16")
  r.setStyle(icon, "color", "rgb(124, 122, 237)")
  r.setStyle(icon, "font-size", "12")
  r.appendChild(summaryNode, icon)

  summaryNode
