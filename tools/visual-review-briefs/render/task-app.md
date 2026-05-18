# Visual Review Brief — Task App Preview

## What You're Reviewing

The **Task App** demo is one of two showcase apps in IsoNim's editor.
You are reviewing **full-editor screenshots** of the IsoNim Examples
editor with the Task App demo selected — one PNG per backend, with
the same `TaskAppVM` state rendered through each renderer in the
editor's preview pane.

Each PNG is the full 1920×1080 editor viewport: left sidebar with the
story tree, top chrome bar (backend / viewport / mode chips), the
preview pane (showing the demo rendered through that backend), and
the right-side inspector panel.

The bundle filenames are
`screenshots/render/task-app-<backend>.png` where `<backend>` is one
of: `web`, `tui`, `gpui`, `freya`, `cocoa`, `android`, `ios`.

**Two design surfaces are being reviewed in the same images**:

1. **The IsoNim editor's chrome itself** (sidebar / chrome bar /
   inspector) — this is constant across the 7 cells of this brief but
   you should still critique it. Both the editor design and the app
   inside it can be improved by fix agents.
2. **The Task App demo as rendered through each backend** in the
   preview pane — this is what varies between the 7 cells.

Score and report on both dimensions independently. A weak editor
chrome should not pull down a strong app score and vice versa.

## Editor Chrome Design (Constant Across All Cells)

The editor chrome should look like a professional design-system /
storybook tool — comparable to VS Code, Figma, Storybook dark mode,
Linear, or the Material 3 docs site.

- **Dark theme**, deep dark gray canvas (`#0f0f14` … `#1a1a2e`), one
  step lighter panel surfaces (`#1d1d28` … `#22232e`).
- **Three-panel layout**, edge-to-edge (NO global top bar above the
  panels):
  - **Left sidebar** — story browser. A search input at top, then a
    quick-nav strip of icons (Foundations / Components / Pages /
    User Journeys / Guidelines), then five collapsible sections
    holding the seed workspace's stories. **The Task App story
    must be visible and highlighted** with the accent color in
    every cell of this brief (since the brief covers the Task App
    component); the other stories should be reachable but de-
    emphasised.
  - **Centre preview pane** — a single top toolbar
    `[data-preview-chrome-bar]` with three chip clusters in this
    order:
    1. **Backend chips**: Web / TUI / GPUI / Freya / Cocoa /
       Android / iOS — seven chips. The chip matching this cell's
       backend must be **visibly active** (accent background or
       border). Unavailable backends (e.g. Cocoa / iOS / Android
       on Linux) are greyed.
    2. **Viewport chips**: Desktop / Laptop / Tablet / Phone (or
       TUI cell viewports when TUI is selected).
    3. **Mode chips**: exactly three — View / Comment / Edit.
    Below the toolbar: the preview canvas, containing the live
    demo render.
  - **Right inspector** — properties / styles / AI-chat tabs. May
    start collapsed; should not visually dominate.
- **Subtle 1 px hairline borders** between panels (mid-gray, not
  heavy lines). 4 px / 8 px spacing rhythm.
- **Typography hierarchy** — page title > section heading > story
  label > body > metadata. Single sans-serif family (system stack
  or Inter-like).
- **Single accent color** (`#7c7aed` indigo) used sparingly: active
  backend chip, selected story, focused inputs, primary CTAs. Never
  overused.
- **The preview pane is the focal point** — nothing else should
  visually dominate. Sidebar and inspector frame it without
  competing.

## Preview-Pane Content (Varies Per Backend) — Information Equivalence

Inside the editor's preview pane, every backend's image MUST show all
of the following. **If any item is missing or unreadable, score that
backend's App Rendering ≤ 4/10 and report the missing item as the
first finding.**

1. **Three seeded sample tasks**, in this order:
   - "Buy groceries"
   - "Walk the dog"
   - "Ship EX-M14"
2. **A toggle / completion control** beside each task (a checkbox, an
   ASCII `[ ]` marker, an iOS-style switch, an Android Material
   checkbox — whichever idiom the backend uses).
3. **A remove control** beside each task — a button, `×` glyph, or
   delete affordance. (TUI may use a row indicator instead of a per-
   task button if cell budget is tight; document if you accept this.)
4. **A "New task…" text input** with a placeholder hint AND an
   accompanying **"Add Task" submit control**.
5. **A filter selector** with three options: **All / Active /
   Completed**. The active option must be visually distinguishable
   from the inactive options.
6. **A summary bar** showing the active/completed count (e.g. "3
   active · 0 completed" or "3 tasks remaining").

## Design Intent

- **Dark theme** with the IsoNim accent token `#7c7aed` (a vivid
  indigo). Backgrounds in the `#0f0f14` → `#22232e` range; cards one
  step lighter than the canvas; primary text near-white
  (`#e8e9f0`), secondary text muted gray (`#a0a2b0`).
- **Card-style rows**: each task should feel like a discrete row card
  with comfortable inner padding, not a tight HTML `<li>`. The
  three task rows together form a vertically stacked column.
- **Single clear focal point**: the task list should dominate the
  pane. The input and filter chrome live above; the summary lives
  below.
- **Hierarchical typography**: input placeholder and summary use a
  lighter weight than task names. The accent color highlights the
  active filter and primary CTA only — never overused.
- **8-px rhythm**: gaps and padding fall on multiples of 4 px (4 / 8 /
  12 / 16). Nothing cramped (`< 4 px`) or loose (`> 24 px` between
  related items).

## Per-Backend Native-Idiom Expectations

Cross-backend consistency does NOT mean visual identity — each backend
must look natural in its own platform's idiom. Score against the brief
*as expressed through the backend's native conventions*, not against
the Web reference. The information content must match; the look-and-
feel will and should differ.

- **Web** — HTML/CSS in an iframe. Expect: rendered DOM with the dark
  palette, accent buttons, semantic markup. The closest to a "design-
  system reference" baseline.
- **TUI** — monospace cell grid rendered through `xterm.js`. Expect:
  ASCII or Unicode box-drawing for borders, `[ ]` / `[x]` for
  toggles, terminal-native color (256-color or true-color palette
  approximating the brand colors). Information must be readable in
  ~80 cols × ~24 rows.
- **GPUI** — Zed's Rust UI toolkit, headless raster. Expect: flat
  surfaces, sharp pixel edges, rounded corners (`border-radius`),
  the dark palette with `#7c7aed` accent on the active filter and
  Add button. GPUI's renderer ignores `border` / `font-weight` so
  emphasis comes from background + color contrast.
- **Freya** — Skia-rendered, web-inspired layout. Expect: similar to
  Web visually but rasterised; rounded controls; gradients optional
  but discouraged for the showcase.
- **TUI** — terminal renderer streaming a cell grid into xterm.js
  inside the editor preview pane.
  - **Known-clear accent**: the active filter (`<All>` /
    `<Active>` / `<Completed>`) is painted in 24-bit-truecolor
    `#7c7aed` (the IsoNim brand indigo) via a `\x1b[38;2;124;122;237m`
    SGR sequence emitted by `compositor.parseColorOrDefault`'s
    `ckRgb` branch. The leaves emit the literal `#7c7aed` (verified
    in `task_app/tui/leaves.nim` lines 247-249) and the compositor
    fans that through to xterm.js with `allowProposedApi: true`. At
    the editor's preview scale the desaturated indigo can read as
    "muted blue-violet"; if it reads as TEAL (`#06989a`) that is a
    real regression — check that the compositor build is fresh.
    Otherwise treat it as the intended brand accent.
- **Cocoa** — AppKit running in-process on macOS. Expect: native Mac
  controls (`NSButton`, `NSTextField`, `NSTableView`) honouring the
  system Aqua / dark-mode appearance. Mac users should recognise
  this as a Mac app. The IsoNim accent appears as the tinted
  selection color.
  - **Known-clear cells (do NOT flag as missing)**: the Cocoa task
    pane always includes an **Add Task** primary button in the input
    row (top), a per-row **remove glyph** at the trailing edge of
    every task row (Unicode `⨯` U+2A2F, painted in a muted neutral
    `#a0a2b0`), and a per-row **NSSwitch toggle** at the leading
    edge. The remove glyph is intentionally low-contrast (muted
    neutral, not red) so it doesn't compete with the indigo Add CTA
    — this is the Wave-S polish, not a missing affordance. If you
    can't see the trailing `⨯` at the captured scale, that's a
    legibility critique (suggest higher contrast) not a "missing
    element" critique. Source: `task_app/cocoa/leaves.nim`
    `renderTaskRow` line 343 (`<button class="remove">` with text
    `⨯`) and `taskInput` line 219 (`<button type="submit">Add
    Task</button>`).
- **Android** — real device framebuffer via `adb exec-out screencap`.
  Expect: Material 3 components (`Material You` palette tuned to the
  IsoNim accent), Material checkboxes, FAB-shaped Add button is
  acceptable. Status bar / system chrome at the top is part of the
  framebuffer — not a defect.
- **iOS** — real iPhone framebuffer via Wi-Fi from the IsoNim Stream
  app. Expect: UIKit controls (`UISwitch` for toggles, `UIButton`
  with `.tinted` style for Add, large title at the top is
  acceptable). System status bar / Dynamic Island visible at the
  top — part of the framebuffer, not a defect.

## Preview-Pane Render Quality (Pixel-Level)

Independent of content + idiom, the rendered backend frame must look
**production-ready in the preview pane at its captured scale**. The
screenshot tool captures the full 1920×1080 editor; the preview pane
inside it is a smaller rectangle (~800×500 typical). The launcher
produces its native-resolution pixels (e.g. 800×600 for desktop
backends, 1170×2532 for the iPhone) and the editor's `<canvas>`
scales those pixels to fit the preview rect via CSS.

**Check each cell against the following pixel-level dimensions.** Any
failure here caps the score even if Content + Idiom are flawless.

1. **Aspect ratio preserved** — the demo's UI is NOT horizontally or
   vertically stretched. Circles look round (not oval); square cards
   look square (not stretched into rectangles); text characters keep
   their native width-to-height ratio. If aspect is wrong: score ≤ 6.

2. **Letterbox/pillarbox handling** — when the backend's aspect ratio
   doesn't match the preview rect (always the case for the iPhone
   portrait frame in a wider preview), the canvas should letterbox
   cleanly with the bands visually framed (visible border / shadow
   separating demo content from pane chrome). If the letterbox bands
   blend invisibly into the surrounding pane so the demo's edges are
   ambiguous: -1.

3. **Scaling artifacts** — text and UI edges should be crisp at the
   capture resolution. Watch for:
   - Bilinear blur (looks "soft", text hard to read at preview scale)
   - Nearest-neighbour jaggies (visible staircase on diagonals)
   - Halos around high-contrast edges
   - Moiré patterns in repeated elements
   Heavy downscale ratios (e.g. iPhone 5× downscale) need extra
   scrutiny. If the demo is hard to read because of scaling blur or
   jaggies: -2.

4. **Color fidelity to the brief palette**:
   - Accent indigo should be in the ballpark of `#7c7aed` (medium-
     bright violet-blue). NOT pink, NOT teal, NOT washed-out gray.
     Compare visually against the editor chrome's own accent — if
     the demo's accent looks materially different from the chrome's,
     -1.
   - Backgrounds should be deep dark (`#0f0f14` to `#22232e`),
     NOT muddy brown, NOT navy blue, NOT pure black.
   - Primary text near-white (`#e8e9f0` to `#ffffff`),
     NOT mid-gray, NOT yellow-tinted, NOT pure off-white that
     blends into the surface.

5. **Sub-pixel alignment** — controls on the same row share a
   baseline; cards in a vertical stack share a left edge; toggle/
   text/remove glyphs in a row don't visibly drift up/down by 1-2
   pixels. If elements look "almost aligned but not quite": -1.

6. **Anti-aliasing quality** — vector elements (buttons, rounded
   chips, pill toggles) have smooth curves at the capture
   resolution; text glyph edges are subpixel-rendered or properly
   anti-aliased. Crispiness should be at the level of a real
   production iOS / Android / Web app screenshot, not a rough
   "renderer test" image.

7. **No stretched UI controls** — buttons aren't visually wider
   than their content margin allows; toggles aren't deformed ovals;
   chips don't have stretched corner radii. The launcher's native
   render should look the same proportionally as it does at full
   resolution.

## Cross-Backend Consistency Contract

- **Information equivalence is non-negotiable.** Every required item
  in the *Required Content* checklist must be present in every
  backend's frame. Information missing in one backend but present in
  others is a hard finding.
- **Visual identity is NOT required.** A reviewer should NOT mark
  down TUI for being ASCII, iOS for using a `UISwitch` instead of a
  CSS checkbox, or Android for showing the system status bar. Each
  backend should look natural in its native idiom.
- **Accent usage should rhyme.** The active filter, the primary Add
  CTA, and the focused-state markers should all use the same accent
  (`#7c7aed` or its closest native-palette analog).
- **The seeded task names must be byte-identical** across all
  backends (they come from the same VM via the same seed function).
- **The order must match**: "Buy groceries" → "Walk the dog" → "Ship
  EX-M14" (the VM is sorted by insertion order).

## Scoring Rubric (Absolute 1-10, two scores per cell)

Score each backend's cell against TWO independent dimensions. The
target is **10/10 on both** across every cell.

### Editor Chrome score

How the editor itself looks in this screenshot (sidebar, chrome bar,
inspector, story highlight, backend-chip active state, accent usage).
Since the chrome is constant across the 7 cells of this brief, your
chrome score may be similar across cells; differences are only:
which backend chip is highlighted, and whether the preview pane is
sized appropriately for that backend's content.

### App Rendering score

How the Task App demo looks rendered through this specific backend
inside the preview pane.

Both scores use the same scale:

- **10** — Production-ready showcase. Every required element
  present, perfectly composed, native-idiomatic, accent usage
  spot-on, typography hierarchy crisp, spacing balanced, **AND
  the rendered pixels are crisp at preview-pane scale: correct
  aspect ratio, palette-true colors, no visible blur, no
  alignment drift, no stretched controls**. Could ship as a
  design-system example.
- **9** — Excellent. One minor polish issue OR one mild render-
  quality nit (e.g. slight blur from aggressive downscale).
  Content perfect.
- **7-8** — Solid content / native idiom but render quality is
  visibly imperfect: noticeable bilinear blur, slightly off-palette
  colors, sub-pixel alignment drift, OR a polish gap (typography
  hierarchy muted, spacing rhythm off, accent missing or overused).
- **5-6** — Functional but rough. Content present but render or
  composition is visibly compromised: stretched UI, wrong colors,
  poor alignment, generic default-styles look. The image would NOT
  be confused with a real production app screenshot.
- **4 or below** — One or more required items missing, unreadable,
  replaced by a placeholder, OR the render is so distorted/blurry
  that it fails the "production app screenshot" bar entirely.
  Triggers an immediate fix before re-scoring.

**Important: a cell can only score 10/10 if it passes BOTH the
Content/Idiom checks AND every dimension of the Preview-Pane Render
Quality section above.** Don't grade content perfection in isolation
— the user judges these PNGs the way they'd judge a real product
screenshot in a design-system gallery.

## Reviewer Methodology (READ BEFORE SCORING)

This is a strict review aimed at world-class design quality. Score
honestly — past rounds drifted to leniency and missed real defects.

**Anti-cheat rules**:

1. **Flake detection first**. Before scoring any cell, confirm the
   rendered content is the **Task App** (input + Add Task + filter
   chips + 3 seeded tasks + summary), NOT the Settings App
   (Appearance / Editor / Notifications groups). If you see Settings
   content in a Task cell: score **1/10**, label it
   `WRONG-DEMO FLAKE`, do not bother scoring render quality.

2. **Empty-pane check**. If the preview pane is blank / mostly the
   editor canvas background with no demo content: score **1/10**,
   label it `EMPTY PANE — DEMO NOT RENDERING`.

3. **Per-dimension annotation**. Comment on EVERY Render Quality
   dimension (aspect, letterbox, scaling, color, alignment, AA,
   stretching) for every cell — even when the dimension passes. No
   omissions. A dimension that you don't mention is treated as a
   missed check.

4. **World-class anchor**. For each backend, hold the cell against a
   concrete production app reference and score by the visible gap:
   - Web → compare to Linear, Polaris docs, Storybook dark mode.
   - TUI → compare to lazygit, gitui, Textual sample apps.
   - GPUI → compare to Zed's UI / Linear's panel chrome.
   - Freya → compare to a published Freya demo or Material 3 dark.
   - Cocoa → compare to macOS Reminders app or Linear macOS.
   - Android → compare to Material 3 Tasks template apps.
   - iOS → compare to Apple's stock Reminders app.
   If the gap is "obvious" to a senior designer: max **6/10**.
   If the gap is "small but visible": max **8/10**.
   If a senior designer would ship it as-is in a production gallery:
   **10/10**. If you can't confidently say "ship it": NOT 10.

5. **One-strike rule on Render Quality**. Any single Render Quality
   dimension failure (e.g. visible stretching, off-palette accent,
   blurred text) caps the cell at **8/10** even if every other
   dimension is perfect. Two failures cap at **6/10**.

6. **Accent-fidelity check**. The accent indigo must be visibly
   `#7c7aed`-family. If the "accent" on a chip / CTA / active state
   is white (no fill), pale lavender, navy, or any shade noticeably
   different from `#7c7aed`: that is an accent failure, NOT a
   stylistic choice. -1 minimum.

7. **Counterfactual test for 10/10**: write the sentence "A senior
   designer at Linear / Apple / Vercel would ship this cell as a
   production showcase image" out loud. If you hesitate on any
   word, the cell is NOT 10/10. Drop to the highest score you can
   confidently assert.

8. **No anchoring to prior scores**. Previous reviewer rounds gave
   inflated scores. Treat this as a fresh review.

9. **MANDATORY native-resolution crop before scoring text content**.
   The captured PNG is 1920×1080 but most reviewer image tools
   display it as a small thumbnail where small text anti-aliases
   into illegible / wrong-glyph readings. Past rounds had a real
   reviewer call the cocoa task summary "0 of 0 remaining" when
   the actual rendered text was "3 of 3 remaining" — only a
   thumbnail-scale anti-aliasing artifact.

   **Before scoring any text-based content (summary counts,
   filter labels, item descriptions, stepper digits, segmented
   choice text)**, crop the relevant region at native resolution
   using `sips`:

   ```sh
   # General form: sips -c <height> <width> --cropOffset <x> <y> <src> --out <dst>
   # IMPORTANT: keep every crop UNDER 2000 px on EACH axis. Tools that
   # consume the cropped PNG will reject larger images. Tight regional
   # crops (≤ 1500×900) are the right size for verifying a single row /
   # widget / chip cluster.
   #
   # Example — crop the summary footer of the cocoa task cell
   # (1920×1080 capture, summary region is roughly the bottom-third of
   # the preview pane which itself sits at x≈100, y≈80, w≈1080, h≈720).
   sips -c 60 400 --cropOffset 120 700 \
     /Users/zahary/metacraft/isonim-examples/screenshots/render/task-app-cocoa.png \
     --out /tmp/task-app-cocoa-summary.png
   ```

   Then `Read` the cropped file with the image-aware Read tool.
   This shows you the actual pixels at the resolution the user
   sees them in the editor preview pane (not the 5× downscaled
   thumbnail your tool may default to).

   If after cropping the text is STILL illegible, that is a real
   render-quality defect — flag it. Conversely, if you see "X of Y"
   at thumbnail scale but native crop reveals it's correct, DO NOT
   penalize the cell — the underlying rendering is fine. Use crops
   liberally; better one extra `sips` call than a misread.

## How to Report

Begin with an **Editor Chrome** section that applies to all 7 cells
of this brief (since the chrome is constant):

- **Editor Chrome score** (1-10).
- **Findings on the editor itself** — bulleted list of concrete issues
  visible in the chrome (sidebar, chrome bar, inspector, story-
  highlight, backend-chip cluster). Mention any backend chip that
  doesn't show its active state correctly in its cell.
- **Quickest path to chrome 10/10** — one or two targeted edits a
  fix agent should make (paths in `~/metacraft/isonim/src/isonim/
  editor/` if you can guess them; otherwise component name).

Then one section per backend, in this order: web, tui, gpui, freya,
cocoa, android, ios. Each section must include:

- **App Rendering score** (1-10).
- **Required-content check** — ✓ / ✗ for each of the 6 items in the
  *Preview-Pane Content* checklist.
- **Findings on the app rendering** — bulleted list of specific
  issues in the preview pane. Be concrete: not "spacing feels off"
  but "the input row's bottom margin is roughly 4 px while the row
  gap between task cards is 10 px — pick one rhythm". **Explicitly
  comment on each Render Quality dimension** (aspect ratio,
  letterbox, scaling artifacts, color fidelity, sub-pixel
  alignment, anti-aliasing, control stretching). If a dimension
  looks fine, say "render: aspect ✓, colors ✓, etc."; don't omit.
- **Quickest path to app 10/10** — one or two targeted edits
  (paths in `~/metacraft/isonim-examples/task_app/<backend>/
  leaves.nim` if you can guess them; otherwise component name).
