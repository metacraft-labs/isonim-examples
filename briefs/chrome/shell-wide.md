---
briefId: chrome.shell-wide
schemaVersion: 1
kind: chrome
title: Editor Shell — wide viewport
coversPreviews:
  - storyRef: { group: "Task App / Pages", name: "Inbox", kind: page, index: 0 }
    backends: [web]
captureViewports:
  - { width: 1920, height: 1080, label: "wide" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: chrome, label: "Editor Chrome", weight: 1.0, scale: { min: 1, max: 10 } }
relatedBriefs: [chrome.shell-laptop, chrome.shell-narrow, chrome.spec-pane-view, chrome.spec-pane-comment, chrome.spec-pane-edit]
---


## What You're Reviewing

The default editor landing surface at **1920 × 1080** with **no story
selected**. This is the IsoNim Examples Editor's chrome bar — the
single top toolbar above the three-panel layout introduced by
M-EVP-6 (one chrome bar, no per-view inner toolbars) and refined by
M-EVP-7 (no view-switcher), M-EVP-9 (sidebar quick-nav strip), TBAR-M3
(Preview / Spec surface switch in the chrome bar), and CHRM-M2 (all
four chrome clusters unified under the ChoiceGroup widget family).

Captured by `editor-screenshot.mjs` view `shell` at viewport `wide`:
file `screenshots/shell-wide.png`.

## Design Goals

- **Dark theme**, tool-app aesthetic in the league of VS Code / Linear
  / Figma's dark mode.
- **Three-panel shell**: left sidebar (story tree) — centre preview —
  right inspector. Single 1 px hairline borders, no heavy dividers.
- **Single top chrome bar** above the centre column. NO inner toolbar
  inside the view body (M-EVP-6 acceptance). No in-pane Preview/Brief
  mode-toggle row anywhere in the view body (CHRM-M2 deleted it; the
  top-bar Surface toggle is the only switch between the preview
  workspace and the brief markdown).
- **No left-edge or right-edge chip strips.** All chrome chips
  (backend / surface / viewport / mode) live in the single top bar.
- **Four-cluster chrome bar.** Cluster order is
  `[backend, surface, viewport, mode]`. **Every cluster is built on
  the ChoiceGroup widget family** (CHRM-M2): backend + mode are
  segmented choice groups (no longer ad-hoc `<button>` rows); surface
  is a 2-pill segmented toggle (Preview / Spec); viewport is a
  chevron-popup ChoiceGroup. Every cluster uses the
  `cgvTransparent` variant so the pills sit directly on the toolbar
  surface — there is no individual filled backdrop / pill chrome on
  the cluster's outer container, only on the active pill itself.
  No `tiltHorizontal` setStyle / no bespoke transform on the chrome.
- **Sidebar quick-nav strip** directly below the search input: five
  category icons in a single horizontal row.
- **No view-switcher** anywhere in the shell (M-EVP-7 acceptance).
- **"Review this preview" button** at the trailing edge of the chrome
  bar, immediately before the 🕘 history button. Single button mount,
  preserved from the deleted in-pane Preview/Brief row (CHRM-M2).
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
- Toolbar exposes **exactly four chip clusters** (CHRM-M2 unified
  every cluster under the ChoiceGroup widget family):
  - `[data-toolbar-cluster="backend"]` — backend chips (Web / TUI /
    GPUI / Freya / Cocoa / Android / iOS) rendered as a
    `mountSegmentedChoice` ChoiceGroup with the `cgvTransparent`
    variant. Carries `role="group"`. Unavailable backends carry the
    ChoiceGroup `data-choice-group-pill-disabled="true"` and appear
    greyed; the macOS host shows Cocoa as available, Android only
    when its launcher built.
  - `[data-toolbar-cluster="surface"]` (also tagged
    `[data-preview-surface-switch="true"]`) — TBAR-M3 + CHRM-M2 ten:
    a 2-pill segmented ChoiceGroup labelled **Preview / Spec**.
    Active pill on initial load is Preview. This is the only
    Preview ⇄ Spec switch in the entire editor.
  - `[data-toolbar-cluster="viewport"]` — viewport selector rendered
    as a chevron-popup ChoiceGroup (`mountChevronChoice`,
    `cgvTransparent`). The active label reads e.g. "Desktop" / TUI
    cell viewports etc., with a chevron icon and `aria-haspopup="listbox"`
    so options open into a popup rather than spreading across the
    bar.
  - `[data-toolbar-cluster="mode"]` — a `mountSegmentedChoice`
    ChoiceGroup (CHRM-M2). Exactly three pills positionally indexed
    0 = **View**, 1 = **Comment**, 2 = **Edit**. The cluster carries
    `aria-label="Preview mode"` and the active pill carries
    `aria-pressed="true"`.
- **Trailing-edge slot:** a "Review this preview" button (re-located
  here by CHRM-M2 from the deleted in-pane Preview/Brief row),
  then the 🕘 history button — only visible when the active brief
  has history.
- **NO** `[data-preview-view-switcher]` element anywhere (M-EVP-7).
- **NO** `[data-preview-left-edge]` or `[data-preview-right-edge]`
  vertical strip elements visible.
- **NO** in-pane Preview/Brief toggle row anywhere inside the centre
  column body (CHRM-M2 deleted it; the Surface cluster above is the
  only switch).
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
  [12, 16] px (M-EVP-3 invariant — re-verified in M-EVP-9 regression
  and CHRM-M2 cluster unification).
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
6. **ChoiceGroup unification** (CHRM-M2): every cluster reads as the
   same widget family — same pill border radius, same active-pill
   accent treatment, same separator handling. No cluster should look
   like a foreign affordance imported from a different design.
7. **Quick-nav strip** — five icons are well-spaced, hit-targets
   feel ≥ 24 × 24 px, do not look cramped against the search input.
8. **Trailing-edge button group** — the "Review this preview" button
   and 🕘 history button sit together at the right edge of the
   chrome bar. They must not collide with the mode cluster on the
   left or appear visually orphaned from the toolbar surface.
9. **Professional polish** — does it look shipping-grade (Linear /
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
