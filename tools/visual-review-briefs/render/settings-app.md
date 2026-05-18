# Visual Review Brief — Settings App Preview

## What You're Reviewing

The **Settings App** demo is one of two showcase apps in IsoNim's
editor. You are reviewing **full-editor screenshots** of the IsoNim
Examples editor with the Settings App demo selected — one PNG per
backend, with the same `SettingsVM` + `buildDemoSettingsCatalog()`
state rendered through each renderer in the editor's preview pane.

Each PNG is the full 1920×1080 editor viewport: left sidebar with the
story tree, top chrome bar (backend / viewport / mode chips), the
preview pane (showing the demo rendered through that backend), and
the right-side inspector panel.

The bundle filenames are
`screenshots/render/settings-app-<backend>.png` where `<backend>` is
one of: `web`, `tui`, `gpui`, `freya`, `cocoa`, `android`, `ios`.

**Two design surfaces are being reviewed in the same images**:

1. **The IsoNim editor's chrome itself** (sidebar / chrome bar /
   inspector) — this is constant across the 7 cells of this brief but
   you should still critique it. Both the editor design and the app
   inside it can be improved by fix agents.
2. **The Settings App demo as rendered through each backend** in the
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
    holding the seed workspace's stories. **The Settings App story
    must be visible and highlighted** with the accent color in
    every cell of this brief (since the brief covers the Settings
    App component); the other stories should be reachable but de-
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

Inside the editor's preview pane, the catalog has three groups:
**Appearance**, **Editor**, **Notifications**. Each group has three items totalling **nine
controls of three kinds** (toggle, choice, number). Different backends
display the catalog differently (accordion / sidebar / two-column /
card stack) — the per-backend section below documents what is
acceptable. The information that MUST be conveyed (in one frame or
discoverable from one foregrounded state) is:

1. **All three group labels are visible or reachable in one click**:
   "Appearance", "Editor", "Notifications".
2. **The active / foregrounded group's items are fully rendered with
   labels AND control widgets**. For the default capture (with
   "Appearance" foregrounded) that means:
   - `Dark mode` — toggle, default OFF.
   - `Theme` — choice with options `Default / Solarized / Dracula`,
     currently `Default`.
   - `Font size` — number, range 10-32, default 14, suffix `pt`.
3. **Each item shows its description text** when one is present in
   the catalog (e.g. "Use the dark colour palette.").
4. **Control widgets are functional-looking and aligned**: toggles
   look toggleable, the choice control looks selectable, the number
   shows the current value with a clear suffix and a way to increment
   / decrement (spinner buttons, slider, or text input).

For backends that show ALL groups at once (Freya card stack, web
sidebar+pane, GPUI two-column), the OTHER groups' headers must also
be visible. For backends that show only the active group (TUI
accordion, native single-pane), the other groups must be **navigable**
— their labels must be readable in the navigation chrome.

## Design Intent

- **Dark theme**, IsoNim accent `#7c7aed` (vivid indigo). Group
  surfaces are cards (`#1d1d28`) on a deep canvas (`#0f0f14`).
  Primary text near-white (`#e8e9f0`), descriptions / secondary text
  muted (`#a0a2b0`).
- **Hierarchical grouping**: group header (h2-ish) >> item label >>
  description >> control. Inter-item spacing roughly twice the
  intra-item spacing.
- **Accent moments**: the active toggle, the selected choice, the
  current numeric value, and the focused group header.
- **Settings should feel like a settings page in a modern app** —
  System Preferences (macOS), Settings (iOS / Android), VS Code
  preferences pane. Not a raw `<form>` dump.

## Per-Backend Native-Idiom Expectations

Cross-backend consistency does NOT mean visual identity. Score against
the brief *as expressed through the backend's native conventions*.

- **Web** — HTML in iframe. Expect: sidebar of group labels on the
  left, the active group's items in the right pane. Each item is a
  styled row with label / description / control. Dark palette,
  accent on the active group + active toggle.
- **TUI** — `xterm.js` cell grid. Expect: an accordion (one group
  open at a time); the active group's three items rendered with
  ASCII / Unicode for toggle `[x]` / `[ ]`, choice `< Default >` (or
  similar), number `font_size: 14pt [-][+]`. Other group labels
  must be visible above/below the open accordion section.
- **GPUI** — Zed Rust UI. Expect: two-column layout — left column
  lists groups, right column shows the active group's items as
  stacked rows. GPUI's renderer drops `border` / `font-size`, so
  emphasis comes from `background` + `color` contrast.
- **Freya** — Skia raster, card stack. Expect: each of the three
  groups rendered as its own vertically stacked card, all visible
  at once on screen. Inside each card: group header, then items.
  This is the only backend that shows ALL items simultaneously.
- **Cocoa** — AppKit on macOS. Expect: native `NSToolbar`-style
  group switcher OR a side list, with `NSSwitch` toggles, `NSPopUp`
  for choices, `NSStepper` + `NSTextField` for numbers. Mac users
  should recognise this as System Settings.
- **Android** — real device. Expect: Material 3 `Preference` rows —
  ListItem with title + summary, `MaterialSwitch` for toggles,
  Material spinner / dialog for choices, Material text input with
  stepper for numbers. Device status bar visible at top is not a
  defect.
- **iOS** — real iPhone via Stream app. Expect: UIKit settings
  conventions — grouped table view with section headers
  ("Appearance" / "Editor" / "Notifications"), `UISwitch` toggles,
  disclosure-arrow rows for choices, segmented controls or stepper
  for numbers. Dynamic Island / status bar at top is not a defect.

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
   vertically stretched. UISwitch pills are oval (not deformed
   circles); cards are rectangular at their intended proportions;
   text characters keep their native width-to-height ratio. If
   aspect is wrong: score ≤ 6.

2. **Letterbox/pillarbox handling** — when the backend's aspect ratio
   doesn't match the preview rect (always the case for the iPhone
   portrait frame in a wider preview), the canvas should letterbox
   cleanly with the bands visually framed (visible border / shadow
   separating demo content from pane chrome). If the letterbox bands
   blend invisibly into the surrounding pane so the demo's edges are
   ambiguous: -1.

3. **Scaling artifacts** — text and UI edges should be crisp at the
   capture resolution. Watch for:
   - Bilinear blur (looks "soft", description text hard to read)
   - Nearest-neighbour jaggies (visible staircase on diagonals)
   - Halos around high-contrast edges (especially around accent-
     filled segmented control selection pills)
   - Moiré patterns in repeated elements
   Heavy downscale ratios (e.g. iPhone 5× downscale) need extra
   scrutiny. If the demo is hard to read because of scaling blur or
   jaggies: -2.

4. **Color fidelity to the brief palette**:
   - Accent indigo should be in the ballpark of `#7c7aed` (medium-
     bright violet-blue). NOT pink, NOT teal, NOT washed-out gray.
     Compare against the editor chrome's own accent — if the demo's
     accent looks materially different, -1.
   - Backgrounds should be deep dark (`#0f0f14` to `#22232e`),
     NOT muddy brown, NOT navy blue, NOT pure black.
   - Primary text near-white (`#e8e9f0` to `#ffffff`).
   - Muted/secondary text should be visibly dimmer than primary —
     the description / caption tier should READ as secondary.

5. **Sub-pixel alignment** — controls on the same row share a
   baseline; toggle pills on different rows align to a consistent
   trailing edge; segmented control pills are clamped to their
   cell boundaries (the selection pill width must equal
   `bounds.width / segmentCount`, not bleed past one cell). If
   elements look "almost aligned but not quite": -1.

6. **Anti-aliasing quality** — vector elements (UISwitch pills,
   segmented control rounded corners, stepper buttons) have smooth
   curves at the capture resolution; text glyph edges are
   subpixel-rendered or properly anti-aliased. Crispiness should
   be at the level of a real production iOS / Android / Web app
   screenshot, not a rough "renderer test" image.

7. **No stretched UI controls** — UISwitch pills aren't deformed
   ovals; segmented control cells aren't stretched; stepper
   buttons keep their circular/rounded shape. The launcher's
   native render should look the same proportionally as it does
   at full resolution.

## Cross-Backend Consistency Contract

- **Information equivalence is non-negotiable.** Every required item
  in the *Required Content* checklist must be conveyed in every
  backend's frame (either inline or via clearly visible navigation
  to the foregrounded group).
- **Visual identity is NOT required.** Don't penalise iOS for using
  a grouped `UITableView`, TUI for using ASCII, or Freya for
  showing all groups at once when other backends show only the
  active one.
- **Catalog values must be byte-identical** across all backends —
  same group labels, same item labels, same default values, same
  choice options. They come from the same `buildDemoSettingsCatalog`
  via the same VM.
- **The accent color should rhyme** across backends — active
  toggle, selected group, focused control should all use the
  IsoNim indigo or its closest native-palette analog.

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

How the Settings App demo looks rendered through this specific
backend inside the preview pane.

Both scores use the same scale:

- **10** — Production-ready showcase settings page. All required
  items present, perfect composition, native-idiomatic widgets,
  accent usage spot-on, hierarchical typography crisp, three-group
  navigation immediately obvious, **AND the rendered pixels are
  crisp at preview-pane scale: correct aspect ratio, palette-true
  colors, no visible blur, segmented-control pill bounds clamped
  to one cell, sub-pixel alignment intact**. Could ship as a
  Polaris / Material 3 / iOS Settings reference.
- **9** — Excellent. One minor polish miss OR one mild render-
  quality nit (e.g. slight blur from downscale). Content perfect.
- **7-8** — Solid content / native widgets but render quality is
  visibly imperfect: noticeable bilinear blur, slightly off-palette
  colors, sub-pixel alignment drift, OR descriptions blend into
  labels, accent missing.
- **5-6** — Functional but rough. Content present but render or
  composition is visibly compromised: stretched widgets, wrong
  colors, poor alignment, generic default-styles look. The image
  would NOT be confused with a real production Settings screen.
- **4 or below** — Missing items, unreadable controls, unnavigable
  groups, OR the render is so distorted/blurry that it fails the
  "production app screenshot" bar entirely. Triggers immediate
  fix before re-scoring.

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
   rendered content is the **Settings App** (Appearance / Editor /
   Notifications groups with Dark mode / Theme / Font size /
   Insert spaces / Tab width / Line endings / Play sounds / Show
   badges / Poll interval), NOT the Task App ("New task" input,
   "Add Task" button, "All / Active / Completed" filter, "Buy
   groceries / Walk the dog / Ship EX-M14" task list). If you see
   Task content in a Settings cell: score **1/10**, label it
   `WRONG-DEMO FLAKE`, do not bother scoring render quality.

2. **Empty-pane check**. If the preview pane is blank / mostly the
   editor canvas background with no demo content: score **1/10**,
   label it `EMPTY PANE — DEMO NOT RENDERING`.

3. **Per-dimension annotation**. Comment on EVERY Render Quality
   dimension (aspect, letterbox, scaling, color, alignment, AA,
   segmented-pill bounds, stretching) for every cell — even when
   the dimension passes. No omissions. A dimension that you don't
   mention is treated as a missed check.

4. **World-class anchor**. For each backend, hold the cell against
   a concrete production Settings UI reference and score by the
   visible gap:
   - Web → compare to GitHub Settings, Stripe Dashboard, Notion
     preferences.
   - TUI → compare to neovim's `:checkhealth` or a Textual settings
     example.
   - GPUI → compare to Zed's settings panel.
   - Freya → compare to Material 3 Settings dark theme.
   - Cocoa → compare to macOS System Settings.
   - Android → compare to Material 3 Preferences template.
   - iOS → compare to Apple's Settings app.
   If the gap is "obvious" to a senior designer: max **6/10**.
   If the gap is "small but visible": max **8/10**.
   If a senior designer would ship it as-is in a production gallery:
   **10/10**. If you can't confidently say "ship it": NOT 10.

5. **One-strike rule on Render Quality**. Any single Render Quality
   dimension failure caps the cell at **8/10** even if every other
   dimension is perfect. Two failures cap at **6/10**.

6. **Accent-fidelity check**. The accent indigo must be visibly
   `#7c7aed`-family. If the "accent" on a segmented-control
   selection / active toggle / focused state is white (no fill),
   pale lavender, navy, or any shade noticeably different from
   `#7c7aed`: that is an accent failure, NOT a stylistic choice.
   -1 minimum.

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
   reviewer call the cocoa task summary "0 of 0 remaining" when the
   actual rendered text was "3 of 3 remaining" — only a
   thumbnail-scale anti-aliasing artifact.

   **Before scoring any text-based content (item labels,
   descriptions, segmented choice options, stepper digits, "Default"
   pill text)**, crop the relevant region at native resolution using
   `sips`:

   ```sh
   # General form: sips -c <height> <width> --cropOffset <x> <y> <src> --out <dst>
   # IMPORTANT: keep every crop UNDER 2000 px on EACH axis. Tools that
   # consume the cropped PNG will reject larger images. Tight regional
   # crops (≤ 1500×900) are the right size for verifying a single row /
   # widget / chip cluster.
   #
   # Example — crop the Theme segmented control region in settings-app-gpui
   sips -c 80 600 --cropOffset 600 200 \
     /Users/zahary/metacraft/isonim-examples/screenshots/render/settings-app-gpui.png \
     --out /tmp/settings-app-gpui-theme.png
   ```

   Then `Read` the cropped file. This shows the actual pixels at
   the resolution a designer would see them in the editor preview
   pane (not the 5× downscaled thumbnail your tool may default to).

   If after cropping the text is STILL illegible / accent still
   reads wrong / segmented pill still missing, that's a real
   render-quality defect — flag it. Conversely, if a thumbnail
   reading like "white selection pill" turns out to be a saturated
   indigo at native crop, DO NOT penalize the cell. Use crops
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
- **Required-content check** — ✓ / ✗ for each of the 4 items in the
  *Preview-Pane Content* checklist, plus a note on how the other
  (non-active) groups are reachable.
- **Findings on the app rendering** — bulleted list of concrete
  issues in the preview pane. Concrete: "the Font size number
  widget has no visible spinner buttons; users can't tell it's
  editable". **Explicitly comment on each Render Quality
  dimension** (aspect ratio, letterbox, scaling artifacts, color
  fidelity, sub-pixel alignment, anti-aliasing, segmented-control
  pill bounds, widget stretching). If a dimension looks fine, say
  "render: aspect ✓, colors ✓, etc."; don't omit.
- **Quickest path to app 10/10** — one or two targeted edits
  (paths in `~/metacraft/isonim-examples/settings_app/<backend>/
  leaves.nim` if you can guess them; otherwise component name).
