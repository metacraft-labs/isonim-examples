---
briefId: chrome.canvas-preview-edit-mode
schemaVersion: 1
kind: chrome
title: Canvas Preview — Edit mode with handles visible
coversPreviews:
  - storyRef: { group: "Task App / TaskList", name: "Two Active", kind: component, index: 1 }
    backends: [tui]
captureViewports:
  - { width: 1920, height: 1080, label: "wide" }
  - { width: 1440, height: 900, label: "laptop" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: chrome, label: "Editor Chrome", weight: 1.0, scale: { min: 1, max: 10 } }
relatedBriefs: [chrome.canvas-preview-tui, chrome.canvas-preview-vector-dblclick-open]
---


## What You're Reviewing

The canvas preview surface in **Edit mode** — the M-EVP-10
acceptance criterion that switching to `emEdit` via the chrome bar
mode chip paints **8 selection handles** at the selected element's
corners + edge midpoints. View / Comment modes hide them.

The screenshot tool drives the editor to this state by:

1. Same boot path as `canvas-preview-tui.md`: enable test mode,
   open editor, select a TaskList story, switch backend to TUI,
   wait for the first frame + the manifest.
2. Compute the centre point of the second TaskRow manifest entry
   and click it (paints the selection outline + breadcrumb).
3. Click the `[data-preview-mode="edit"]:not([data-preview-mode-
   disabled="true"])` chip in the chrome bar.
4. Wait for exactly 8 `[data-canvas-selection-handle="true"]`
   elements to be present and visible.

Captured by `editor-screenshot.mjs` view `canvas-preview-edit-mode`
at viewports `wide` and `laptop`: files
`screenshots/canvas-preview-edit-mode-wide.png` and
`screenshots/canvas-preview-edit-mode-laptop.png`.

## Design Goals

- Edit mode adds the **handle layer** without changing any other
  affordance — hover label, selection outline, breadcrumb still
  visible.
- Handles read as drag affordances: 8 small squares in the accent
  colour positioned at the selection outline's 4 corners + 4 edge
  midpoints.
- The 8 handles do not visually drown out the underlying TUI
  raster.

## Color Expectations

- Handle background: accent (same as selection outline).
- Handle border: 1 px solid lighter accent (or `bgBase`) to give a
  ring on the corner glyph.
- Handle size: between 6 px and 10 px square; consistent across
  the 8 markers.

## What is Expected on the Screenshot

### Chrome state

- `[data-preview-backend="tui"]` chip active (accent highlight).
- `[data-preview-mode="edit"]` chip active; `[data-preview-mode=
  "view"]` and `[data-preview-mode="comment"]` not active.

### Canvas + overlays (carried over from canvas-preview-tui)

- Canvas with `data-canvas-active="true"` painting real TUI
  raster.
- `[data-canvas-selection-outline="true"]` visible at the selected
  TaskRow's bounds, with `data-element-id="<id>"` matching the
  manifest entry.
- `[data-canvas-selection-breadcrumb="true"]` visible with the
  selected entry's `componentPath`.
- `[data-canvas-hover-label="true"]` MAY be visible if the cursor
  is still hovering the same entry, OR MAY have cleared if the
  mode-chip click moved the cursor off the canvas. Either is
  acceptable; the brief is about the handles.

### Handle group (the load-bearing M-EVP-10 acceptance)

- Exactly **eight** `[data-canvas-selection-handle="true"]`
  markers visible.
- Each handle carries a `data-handle-position` attribute whose
  values, collected across the 8 handles, equal the set
  `{ nw, n, ne, e, se, s, sw, w }`.
- Handles surround the selection outline at:
  - 4 corners (`nw`, `ne`, `se`, `sw`).
  - 4 edge midpoints (`n`, `e`, `s`, `w`).
- Each handle is centred on its target coordinate (handle box
  visually straddles the outline edge, not flush inside or fully
  outside).

### Negative expectations

- No more than 8 handles.
- No fewer than 8 handles.
- Handles must not appear if Edit chip is NOT active (sanity:
  re-asserted by the `canvas-preview-tui.md` brief).

## What to Evaluate

1. **Exactly 8 handles** — count them in the screenshot.
2. **Handle positions** — verify each handle sits at the expected
   corner / midpoint of the selection outline.
3. **Accent consistency** — handle fill colour matches the
   selection outline and the active backend chip.
4. **Visual readability** — handles do not overlap each other; do
   not occlude the underlying TaskRow content; are not hidden
   behind the breadcrumb or hover label.
5. **Mode chip visual** — the Edit chip in the chrome bar is
   clearly the active one (accent highlight, `aria-pressed=
   "true"`).
6. **No regression** — selection outline + breadcrumb still
   present.

## How to Report

- Keep under 250 words.
- **First line:** `Expected elements: present (handles=8)` OR
  `Expected elements: missing-<X>` / `replaced-by-<Y>`.
- Lead with one-sentence aesthetic impression.
- Explicitly state the handle count you see in the screenshot.
- List specific issues with handle positions if any look
  misplaced.
- End with **1–2 highest-priority fixes**.
- Rate 1–10. Wrong handle count = ≤ 3/10; otherwise normal
  calibration.
