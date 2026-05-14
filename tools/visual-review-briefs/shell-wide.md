# Visual Review Brief — Editor Shell (wide viewport)

## What You're Reviewing

The default editor landing surface at **1920 × 1080** with **no story
selected**. This is the IsoNim Examples Editor's chrome bar — the
single top toolbar above the three-panel layout introduced by
M-EVP-6 (one chrome bar, no per-view inner toolbars) and refined by
M-EVP-7 (no view-switcher) and M-EVP-9 (sidebar quick-nav strip).

Captured by `editor-screenshot.mjs` view `shell` at viewport `wide`:
file `screenshots/shell-wide.png`.

## Design Goals

- **Dark theme**, tool-app aesthetic in the league of VS Code / Linear
  / Figma's dark mode.
- **Three-panel shell**: left sidebar (story tree) — centre preview —
  right inspector. Single 1 px hairline borders, no heavy dividers.
- **Single top chrome bar** above the centre column. NO inner toolbar
  inside the view body (M-EVP-6 acceptance).
- **No left-edge or right-edge chip strips.** All chrome chips
  (backend / viewport / mode) live in the single top bar.
- **Sidebar quick-nav strip** directly below the search input: five
  category icons in a single horizontal row.
- **No view-switcher** anywhere in the shell (M-EVP-7 acceptance).
- 4 / 8 px spacing rhythm; nothing cramped, nothing wasting space at
  this viewport.
- Type hierarchy: section heading (uppercase 10 px) > story label
  (12 px) > body (11 px) > metadata (10 px muted). Single sans-serif.

## Color Expectations

- Canvas background: deep dark gray (`#0f0f14` … `#1a1a2e`).
- Panel surfaces: one step lighter (`#1d1d28` … `#22232e`).
- Borders / dividers: subtle gray (`#2a2b36` … `#34353f`).
- Primary text: near-white; secondary: muted gray; accent: a single
  vibrant colour (purple / indigo / teal) used sparingly.
- Empty-state preview: a quiet card or muted hint copy — NOT a
  hard-coded placeholder rectangle.

## What is Expected on the Screenshot

**The reviewer must verify these elements are present BEFORE evaluating
aesthetics.** If anything expected is missing or replaced by a
placeholder, report that as the first finding and rate ≤ 4/10
regardless of polish.

### Sidebar (left column)

- One `input[data-sidebar-search="true"]` search box at the top with
  the placeholder `Search stories…`.
- Exactly one `[data-sidebar-quicknav="true"]` strip directly below
  the search input.
- Quick-nav strip contains exactly **five icon buttons**, one each
  with `data-category-kind` ∈ `{ skFoundation, skComponent, skPage,
  skFlow, skGuideline }`. The buttons must read left-to-right in that
  order. Each icon is a small geometric glyph (◇, ◻, □, ▷, ○).
- Below the strip: five collapsible sections in this order — **User
  Journeys, Pages, Components, Foundations, Guidelines**. Each
  section has a section header with an uppercase 10 px label and a
  chevron at the right.
- Default expansion (per `defaultSidebarSections`): User Journeys
  expanded, Pages expanded, Components expanded, Foundations
  expanded, Guidelines collapsed.
- Sections expose the two demo projects: **Task App** groups
  (`TaskRow`, `TaskList`, `Settings App / Group`, etc.) under
  Components; **`Task App / Vector Symbols`** (containing `Task Check
  Icon`) appears under Foundations.

### Centre column

- Exactly **one** `[data-preview-chrome-bar="true"]` toolbar at the
  top of the centre column.
- Toolbar exposes **exactly three chip clusters**:
  - `[data-toolbar-cluster="backend"]` — six chips with
    `data-preview-backend` ∈ `{ web, tui, gpui, freya, cocoa,
    android }`. On macOS, `cocoa` is available; `android` is
    available only when the Android launcher built. Unavailable
    backends carry `data-preview-backend-available="false"` and
    appear greyed.
  - `[data-toolbar-cluster="viewport"]` — viewport chips for the
    selected backend (Desktop / Laptop / Tablet / Phone or TUI cell
    viewports).
  - `[data-toolbar-cluster="mode"]` — exactly three chips with
    `data-preview-mode` ∈ `{ view, comment, edit }` labelled **View
    / Comment / Edit**.
- **NO** `[data-preview-view-switcher]` element anywhere (M-EVP-7).
- **NO** `[data-preview-left-edge]` or `[data-preview-right-edge]`
  vertical strip elements visible.
- Below the chrome bar: an empty-state preview surface (the
  storyboard mini-preview tiles, or the default landing card). No
  inner 44 px toolbar inside this body (M-EVP-6 acceptance).

### Right column (inspector)

- A right-hand inspector panel with tab labels (Properties / Styles /
  AI chat or equivalent). May start collapsed showing only tab
  labels at this viewport.
- Hairline 1 px border between the inspector and the centre column.

### Spacing + measurements

- Chrome bar height ≤ 64 px; gap between toolbar clusters in
  [12, 16] px (M-EVP-3 invariant — re-verified in M-EVP-9 regression).
- Sidebar width in [240, 320] px range.
- Inspector width in [220, 340] px range when expanded.

## What to Evaluate

After confirming presence of every expected element above, evaluate:

1. **Alignment** — sidebar items left-aligned on a consistent indent
   step (4 / 8 / 16 px); chrome bar chip clusters horizontally
   centred within their cluster boxes.
2. **Spacing** — 4 / 8 px rhythm; chip gaps consistent; section
   headers breathing room ≥ 6 px above and below.
3. **Color harmony** — single accent colour used sparingly; no
   competing accents; greyed-out chips clearly distinguishable from
   active ones without looking broken.
4. **Typography** — section headers vs story labels vs body have a
   clear three-tier hierarchy.
5. **Visual weight** — centre column is the focal point; the chrome
   bar supports it without competing.
6. **Quick-nav strip** — five icons are well-spaced, hit-targets
   feel ≥ 24 × 24 px, do not look cramped against the search input.
7. **Professional polish** — does it look shipping-grade (Linear /
   Notion) or prototype?

## How to Report

- Keep under 250 words.
- **First line:** `Expected elements: present` OR
  `Expected elements: missing-<X>` / `replaced-by-<Y>`.
- If any expected element is missing or wrong, report it as the first
  finding and rate ≤ 4/10 regardless of polish elsewhere.
- Otherwise, lead with a one-sentence overall aesthetic impression.
- List specific issues as bullet points with locations
  (e.g. "quick-nav strip: gap between icons is 2 px, should be 6 px").
- End with **1–2 highest-priority fixes** the implementer should
  do first.
- Rate 1–10 (calibration: 1-3 = broken, 4-5 = functional rough,
  6-7 = good with minor issues, 8-9 = near-shipping, 10 = perfect).
- Be direct and specific.
