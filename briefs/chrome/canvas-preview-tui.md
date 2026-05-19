---
briefId: chrome.canvas-preview-tui
schemaVersion: 1
kind: chrome
title: Canvas Preview — real TUI pixels + M-EVP-10 affordances
coversPreviews:
  - storyRef: { group: "Task App / TaskList", name: "Two Active", kind: component, index: 1 }
    backends: [tui]
captureViewports:
  - { width: 1920, height: 1080, label: "wide" }
  - { width: 1440, height: 900, label: "laptop" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: chrome, label: "Editor Chrome", weight: 1.0, scale: { min: 1, max: 10 } }
relatedBriefs: [chrome.canvas-preview-edit-mode, chrome.canvas-preview-vector-dblclick-open]
---


## What You're Reviewing

The non-Web preview canvas mounted via RS-M11 Pattern A: real TUI
launcher pixels streamed over WebSocket and painted into a
`<canvas>` element inside the component-detail view. The screenshot
captures the canvas mid-interaction so the M-EVP-10 affordances
(hover label, selection outline, breadcrumb) are all visible at
once.

The screenshot tool drives the editor to this state by:

1. Setting `window.__isonimTestMode = true` before the editor boots
   (gates the test-mode mirrors used by the screenshot tool to
   identify manifest entries — the visible affordances themselves
   are user-facing and not gated).
2. Opening the editor.
3. Expanding the `Task App / TaskList` group and selecting one of
   its stories (e.g. `Two Active`).
4. Clicking the `[data-preview-backend="tui"]` chip in the chrome
   bar. The component-detail view switches from the Web iframe to
   the canvas; `attachBridgeClient` connects to the running TUI
   launcher on its bridge port.
5. Waiting for the first non-empty canvas frame AND for the
   `element-tree` manifest mirror at `window.__isonimManifest`.
6. Picking the second `TaskRow` manifest entry, computing its
   center, hovering at that point, then clicking. This paints the
   hover label, selection outline, and breadcrumb simultaneously.

Captured by `editor-screenshot.mjs` view `canvas-preview-tui` at
viewports `wide` and `laptop`: files
`screenshots/canvas-preview-tui-wide.png` and
`screenshots/canvas-preview-tui-laptop.png`.

## Design Goals

- Real TUI raster fills the canvas — distinct **monospaced ASCII**
  appearance, no rounded corners, no drop shadows.
- The four M-EVP-10 affordances coexist without visual conflict.
- Selection outline + handles use the editor accent colour
  consistently.
- Hover label is unobtrusive but unambiguous; it follows the
  cursor / hovered entry's bounding box and shows the entry's
  `componentPath`.

## Color Expectations

- Canvas TUI raster: high-contrast monochrome (white-on-black or
  green-on-black) with ASCII box-drawing characters.
- Hover label background: `bgSidebar` with a hairline `border` and
  `textSecondary` text.
- Selection outline: 2 px accent-coloured border around the
  hovered entry's bounds, scaled into CSS pixel space.
- Breadcrumb: muted background with `textPrimary` for the path
  segments.

## What is Expected on the Screenshot

### Canvas + chrome state

- The chrome bar's `[data-preview-backend="tui"]` chip is active
  (accent highlight + `aria-pressed="true"`).
- The mode chip `[data-preview-mode="view"]` is active (no Edit
  mode in this brief — handles are captured separately by
  `canvas-preview-edit-mode.md`).
- A `<canvas>` element with `data-canvas-active="true"` is visible
  filling the centre column body.
- The canvas paints real, non-empty TUI raster pixels (visible
  glyphs / ASCII text for the selected story; e.g. task rows).
- The canvas's `width` / `height` match the manifest's
  `surfaceWidth` / `surfaceHeight`.

### Overlay affordances

- `[data-canvas-overlay="true"]` overlay wrapper present (the
  pointer-events-none container).
- `[data-canvas-hover-label="true"]` element visible: text equals
  the hovered entry's `componentPath` (a value like
  `task_app/views/TaskRow#1`).
- `[data-canvas-selection-outline="true"]` element visible at the
  hovered/clicked entry's bounds. The outline carries
  `data-element-id="<elementId>"` matching the manifest entry's
  `id`. Outline left/top/width/height correspond to the entry's
  bounds scaled by `canvas.clientWidth / canvas.width`
  (1 px tolerance per the M-EVP-10 spec).
- `[data-canvas-selection-breadcrumb="true"]` element visible with
  text equal to the selected entry's `componentPath`.

### Negative expectations

- `[data-canvas-selection-handle="true"]` elements are HIDDEN
  (mode is View, not Edit).
- No iframe is visible in the centre column (TUI backend → canvas
  path, not Web iframe).

## What to Evaluate

1. **TUI pixel fidelity** — does the canvas read as a real TUI
   raster (monospace, ASCII, no rounded corners)? Or as a
   placeholder / stub?
2. **Overlay coexistence** — hover label + selection outline +
   breadcrumb visible simultaneously without occluding the
   underlying TUI content.
3. **Outline accuracy** — the selection outline visually matches
   the TUI row it represents (its top/left/width/height align with
   the rendered text row).
4. **Hover label placement** — does it follow the hovered entry's
   top-right corner? Is it readable against the canvas
   background?
5. **Breadcrumb placement** — fixed-position panel below or above
   the canvas; text matches the entry's `componentPath`; does not
   compete visually with the hover label.
6. **Accent usage** — selection outline accent matches the chrome
   bar's active backend chip (single accent across editor).
7. **No edit handles** — handles must not appear in View mode.

## How to Report

- Keep under 250 words.
- **First line:** `Expected elements: present` OR
  `Expected elements: missing-<X>` / `replaced-by-<Y>`.
- Lead with one-sentence aesthetic impression.
- Confirm each of the four affordances explicitly: hover label,
  selection outline, breadcrumb, AND that **no handles** are
  visible.
- Quote the `componentPath` shown in the hover label /
  breadcrumb so the reader can verify it matches a real manifest
  entry (e.g. `task_app/views/TaskRow#1`).
- List specific issues with selectors.
- End with **1–2 highest-priority fixes**.
- Rate 1–10. If the canvas is empty or shows iframe content, that's
  ≤ 3/10 regardless of other polish.
