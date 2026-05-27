---
briefId: chrome.gallery-compare
schemaVersion: 1
kind: chrome
title: Gallery Overlay — Compare mode (side-by-side, 2 captures)
coversPreviews:
  - storyRef: { group: "Task App / Pages", name: "Inbox", kind: page, index: 0 }
    backends: [web]
captureViewports:
  - { width: 1920, height: 1080, label: "wide" }
  - { width: 1440, height: 900,  label: "laptop" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: chrome, label: "Editor Chrome", weight: 1.0, scale: { min: 1, max: 10 } }
relatedBriefs: [chrome.gallery-grid-and-full-tab]
---


## What You're Reviewing

The IsoNim Editor's design-review **gallery overlay** in Compare
mode with two captures selected. This is the mode that until CHRM-M6
Wave A rendered nothing — the chip flipped the `data-gallery-mode`
attribute but no panel was visible. Wave A added the compare render
branch; this brief governs the polish of that addition.

Captured by `editor-screenshot.mjs` view `gallery-compare` at
viewports `wide` and `laptop`: files
`screenshots/gallery-compare-{wide,laptop}.png`.

## Design Goals

- **Compare mode reads as a deliberate side-by-side comparison
  surface**, not as two thumbnails accidentally placed next to each
  other. Equal-width columns at `wide` and `laptop`; a thin vertical
  divider hairline between them; each column shows the capture image
  + its metadata strip (status dot + previewId + score).
- **Equal column heights even when image aspect ratios differ.**
  Both images are constrained to the same vertical extent; if one is
  narrower, it letterboxes (no stretching — per the user's "No image
  stretching" feedback).
- **Column gutter is visible but quiet.** A 1 px hairline divider
  (`#2D2D3A`) sits centred between the two columns with 16 px
  horizontal margins on either side. The divider lets the eye drop
  vertically between captures without confusing them as a single
  composite.
- **Metadata strips are aligned.** Both columns place their status
  dot + previewId + score on the same baseline at the bottom of the
  column. The two metadata rows read as a comparison table, not as
  per-tile chrome.
- **Compare-mode affordances surface above the columns.** Two
  visible controls: `Clear selection` (returns to grid with
  selection cleared) and `Exit compare` (returns to grid with
  selection preserved). Both are chip-shaped, matching the mode chip
  family. Positioned at the top of the overlay body with ≥8 px
  breathing room from the toolbar above.
- **The selected tiles in the grid behind the compare panel are
  highlighted** via the standard tile-selected outline
  (2 px `#3B82F6`), so re-entering grid mode (via Clear selection or
  Exit compare) makes the selection state legible.
- **Narrow viewport** is OUT OF SCOPE for compare mode (per
  `captureViewports` above). If someone opens compare on a narrow
  device, the existing wide/laptop render rules apply with
  horizontal scroll — fixing narrow compare-mode is a follow-on
  milestone.

## Color Expectations

- Overlay container: as in `gallery-empty-state.md`.
- Mode chip family: as in `gallery-grid-and-full-tab.md`. The
  Compare chip is `aria-selected="true"` with accent fill
  `#3B82F6`.
- Column divider: `#2D2D3A`, 1 px, full vertical extent of the
  compare body.
- Column background: `#0B1220` (overlay background extends behind;
  no inner panel).
- Image matte: `#000000` letterboxing if image aspect doesn't match
  column aspect.
- Metadata strip background: `#111827`, 1 px top border `#1F2937`,
  ~28 px tall, sits at the column bottom.
- `Clear selection` button: chip-shaped, transparent background,
  1 px border `#334155`, text `#A0A2B0`.
- `Exit compare` button: chip-shaped, slightly emphasised — 1 px
  border `#475569`, text `#E5E7EB`.
- Divider hover affordance (optional, CHRM-M6 Wave C): on hover
  over the divider, cursor becomes `col-resize` to hint at a
  future split-pane drag handle. Not required for Wave A acceptance.

## What is Expected on the Screenshot

**The reviewer must verify these elements are present BEFORE
evaluating aesthetics.** If anything expected is missing or replaced
by a placeholder, report that as the first finding and rate ≤ 4/10
regardless of polish.

### Chrome bar (constant)

- Chrome bar with all four clusters in CHRM-M5 Fix A order. The
  Surface cluster's `Preview` pill (index 0) is active.

### Overlay container

- Visible below the chrome bar with the standard 1 px border, 8 px
  radius, calm shadow.

### Mode toolbar

- Four chips. Compare chip is `aria-selected="true"`. Other three
  are idle.

### Compare affordance row

- `Clear selection` chip visible at the top of the overlay body.
- `Exit compare` chip visible next to it.
- ≥8 px breathing room from the toolbar above.

### Two-column compare body

- Two equal-width columns, separated by a 1 px vertical hairline.
- Each column shows an image (centred, no stretching) and a
  metadata strip at the bottom.
- Both metadata strips align on the same baseline.
- The two images respect their native aspect ratios; letterboxing
  is present where needed.
- `data-design-review-gallery-compare-ids` attribute on the
  overlay carries the two selected capture IDs (for Playwright
  cross-reference).

## What to Evaluate

For each viewport, score chrome `1–10` against the rubric:

- **10 — exemplary.** Compare mode invites careful comparison;
  columns are balanced; affordances are obvious; divider is quiet
  but present.
- **8 — production-ready.** All design goals met; minor tuning
  possible (divider weight, affordance label copy, metadata-strip
  height).
- **6 — acceptable but rough.** Columns visible but cluttered;
  affordances unclear; metadata misaligned.
- **4 — placeholder.** Single column shown; affordances missing;
  divider absent; images stretched.
- **≤2 — broken.** Compare mode blank; chip pretends to work but
  nothing visible.

Target: **8+ on `wide` and `laptop`** (narrow out of scope per
above).

## How to Report

For each viewport, in order:

1. **Expected-elements verification.** Pass/fail per the bullets in
   "What is Expected on the Screenshot". If any fail, note them
   first and cap the score at 4.
2. **Score with one-sentence justification.**
3. **Three concrete improvements** if score < 9, each naming the
   target file/line area (e.g., `gallery_overlay.nim:compare divider`,
   `gallery_overlay.nim:metadata strip alignment`, `gallery_overlay.nim:
   affordance copy`).
4. **Wave-A actionable items** the implementation agent can apply
   without further design clarification.
