---
briefId: chrome.vector-editor-with-symbol
schemaVersion: 1
kind: chrome
title: Vector Editor with Symbol — split usage-context
coversPreviews:
  - storyRef: { group: "Task App / Vector Symbols", name: "Task Filter Icon", kind: vectorsymbol, index: 1 }
    backends: [web]
captureViewports:
  - { width: 1920, height: 1080, label: "wide" }
  - { width: 1440, height: 900, label: "laptop" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: chrome, label: "Editor Chrome", weight: 1.0, scale: { min: 1, max: 10 } }
relatedBriefs: [chrome.vector-editor-empty, chrome.vector-editor-carousel]
---


## What You're Reviewing

The vector editor with the **stacked usage-context** companion
panel visible — the M-EVP-8 split variant. This brief covers the
case when the target symbol has **≤ 3 usages** across the
workspace: the right-side panel renders each usage as a stacked
preview card. (More than 3 usages flips to the carousel variant,
covered by `vector-editor-carousel.md`.)

The screenshot tool drives the editor to this state by:

1. Opening the editor.
2. Navigating to the `Task Filter Icon` vector symbol (Foundations
   → `Task App / Vector Symbols` → `Task Filter Icon`).
3. Asserting `vm.vectorEditorUsages.val.len` is in `[1, 3]`.
4. If the demo workspace exposes more than 3 usages, the tool
   manipulates the test-mode hook to force a 2-usage subset (so
   this brief always reflects the split variant). Otherwise the
   natural seed is used.

Captured by `editor-screenshot.mjs` view `vector-editor-with-symbol`
at viewports `wide` and `laptop`: files
`screenshots/vector-editor-with-symbol-wide.png` and
`screenshots/vector-editor-with-symbol-laptop.png`.

## Design Goals

- The centre column splits into `[ canvas | usage-context ]`. The
  canvas takes the larger share (flex 1.5 vs flex 1 in
  `vector_editor.nim`).
- Usage panel renders as a vertical stack of cards; each card shows
  the usage's component path + a minimal preview.
- Usage previews are **read-only** — `pointer-events: none` keeps
  hover / selection from bubbling into the main editor canvas.
- Section header reads `USAGE CONTEXT` in uppercase 11 px /
  600-weight / muted colour.

## Color Expectations

- Usage panel background: `bgSidebar` (one shade lighter than
  canvas).
- Card surfaces: `bgCard` with `border` (1 px solid muted gray).
- 1 px `borderFaint` between the panel header and the stacked cards.
- No accent colour on cards (they are non-interactive preview-only).

## What is Expected on the Screenshot

### Vector editor surface

- All of the elements in `vector-editor-empty.md` continue to apply
  (top toolbar, tool palette, canvas, properties, layers).
- The canvas area is narrower than the empty case because the
  usage-context panel claims a chunk of the centre column.

### Split layout markers

- `[data-vector-editor-split="true"]` flex row at the top of the
  centre column (the existing root).
- `[data-vector-editor-canvas-split="true"]` div on the left
  (`flex: 1.5`) holding the vector editor's `mainArea`.
- `[data-vector-editor-usage-split="true"]` div on the right
  (`flex: 1`), `display: flex` (visible).

### Stacked variant (≤ 3 usages)

- `[data-vector-usage-layout="split"]` panel is `display: flex`
  (visible).
- `[data-vector-usage-layout="carousel"]` panel is `display: none`
  (hidden).
- Exactly **N usage cards** (with N ∈ [1, 3]) rendered as direct
  children of the split panel, each carrying:
  - `data-vector-usage="true"`
  - `data-vector-usage-label="<group>/<story-name>"`
  - `data-vector-usage-story="<group>/<story-name>"`
- Each card shows a small uppercase 10 px label (the
  `group / story` line) at the top and a minimal preview area
  (`min-height: 80px`) below.

### Negative expectations

- `[data-vector-usage-carousel="true"]` carousel panel must not be
  visible.
- No Prev/Next buttons or dot indicators are shown.
- Usage cards must not visibly respond to hover (`pointer-events:
  none`).

## What to Evaluate

1. **Split proportion** — canvas (`flex: 1.5`) is the dominant
   area; usage panel (`flex: 1`) supports without competing.
2. **Card stack rhythm** — 10 px gap between cards; 10 / 12 px
   padding inside each; minimal but consistent.
3. **Section header clarity** — `USAGE CONTEXT` reads as a panel
   header, not a card label.
4. **Card visual weight** — each card looks like a tile preview,
   not a button. The reviewer should not be tempted to click a
   card.
5. **Canvas legibility** — even at the reduced width, the canvas
   grid + 720 × 420 fabric host remain clear; no clipping.
6. **Spacing parity** — usage panel's 10 / 12 px padding rhythm
   matches the properties panel's 12 px section padding.

## How to Report

- Keep under 250 words.
- **First line:** `Expected elements: present` OR
  `Expected elements: missing-<X>` / `replaced-by-<Y>`.
- Lead with one-sentence aesthetic impression.
- Specifically count the usage cards in the screenshot and confirm
  it matches the [1, 3] expectation.
- List specific issues with `data-vector-usage-label` values where
  relevant.
- End with **1–2 highest-priority fixes**.
- Rate 1–10.
