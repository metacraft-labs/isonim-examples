---
briefId: chrome.gallery-grid-and-full-tab
schemaVersion: 1
kind: chrome
title: Gallery Overlay — Grid + Full-tab modes (populated)
coversPreviews:
  - storyRef: { group: "Task App / Pages", name: "Inbox", kind: page, index: 0 }
    backends: [web]
captureViewports:
  - { width: 1920, height: 1080, label: "wide" }
  - { width: 1440, height: 900,  label: "laptop" }
  - { width: 375,  height: 812,  label: "narrow" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: chrome, label: "Editor Chrome", weight: 1.0, scale: { min: 1, max: 10 } }
relatedBriefs: [chrome.gallery-empty-state, chrome.gallery-compare]
---


## What You're Reviewing

The IsoNim Editor's design-review **gallery overlay** populated with
**six captures** spanning three backends (Web / TUI / GPUI) across
multiple variants (desktop / mobile / wide / default). Two modes
share this brief because they share the toolbar chrome and the tile
treatment:

- **Grid mode** (default): six tiles in three preview-id groups
  rendered as labelled rows. Each tile shows thumbnail + status dot
  + status text + score.
- **Full-tab mode**: one capture selected, the image rendered at its
  native pixel dimensions with a `← Back to grid` affordance above.

Captured by `editor-screenshot.mjs` views `gallery-grid` and
`gallery-full-tab` at the listed viewports: files
`screenshots/gallery-grid-{wide,laptop,narrow}.png` and
`screenshots/gallery-full-tab-{wide,laptop}.png`.

## Design Goals

- **Tile density without clutter.** Six tiles at ~160 × 100 px must
  read crisply on `wide` and `laptop`. Row labels and tile metadata
  remain legible at thumbnail scale (10 px font, letter-spacing
  0.3 px).
- **Row grouping by previewId is the structural anchor.** Tiles
  group under uppercased row labels so the reviewer can scan
  "all Web desktop captures for this preview" without parsing tile
  metadata. Row labels read as section headers (muted, smaller
  than the chrome bar text), not as button affordances.
- **Mode chip family unity.** The four chips (Grid / Full tab /
  Full screen / Compare) read as the same widget family as the
  CHRM-M2 ChoiceGroup chrome chips. Selected chip carries
  `aria-selected="true"` with accent fill; idle chips are
  transparent.
- **Status dot + status text + score sit on one metadata row per
  tile.** Dot is 6 px (`#22C55E` green / `#F59E0B` amber /
  `#EF4444` red); status text is 11 px muted; score is right-edge
  aligned. Tile metadata never wraps to a second row at thumbnail
  scale.
- **Full-tab mode shows the capture at native size.** No
  upscaling, no fill-to-fit distortion (per the user's "No image
  stretching" feedback — devices letterbox honestly). The image is
  centred in the overlay body with a calm matte background around
  it; if the image is smaller than the overlay, it stays at native
  size with whitespace around.
- **Full-tab back button** is a chip-shaped affordance (pill, same
  family as the mode chips) positioned at the top-left of the
  overlay body, with ≥8 px vertical breathing room from the
  toolbar above.
- **Narrow viewport (375 px)**: tiles wrap to one column with row
  labels still uppercased above each group; no horizontal scroll;
  tile metadata reflows but stays readable.

## Color Expectations

- Overlay container: as in `gallery-empty-state.md`.
- Mode toolbar background: transparent.
- Mode chip family: matches CHRM-M2 ChoiceGroup `cgvTransparent`
  variant exactly. Selected = accent fill `#3B82F6` + white text.
- Tile background: `#111827`, 1 px border `#1F2937`, 4 px radius.
- Tile hover state: background steps to `#162033`, border to
  `#334155`; transition 120 ms ease-out.
- Tile selected state: 2 px solid `#3B82F6` outline + 1 px inset
  `#0B1220` so the outline visibly separates from the tile body.
- Row label: `#64748B`, 10 px, weight 600, letter-spacing 0.3 px,
  uppercased.
- Tile metadata row: status dot (`#22C55E` / `#F59E0B` /
  `#EF4444`), status text `#A0A2B0` 11 px, score `#E5E7EB` 11 px
  weight 600.
- Full-tab back button: chip-shaped (pill, 22 px tall, 11 px font),
  transparent background, 1 px border `#334155`; hover fills to
  `#162033`.
- Full-tab matte: `#0B1220` (the overlay background extends behind
  the centred image; no inner panel).

## What is Expected on the Screenshot

**The reviewer must verify these elements are present BEFORE
evaluating aesthetics.** If anything expected is missing or replaced
by a placeholder, report that as the first finding and rate ≤ 4/10
regardless of polish.

### Both modes (constant)

- Chrome bar with all four clusters in CHRM-M5 Fix A order. The
  Surface cluster's `Preview` pill (index 0) is active.
- Overlay container visible below the chrome bar with the standard
  1 px border, 8 px radius, calm shadow.
- Mode toolbar with all four chips. The selected chip has
  `aria-selected="true"`.

### Grid mode (`gallery-grid-*.png`)

- `data-gallery-mode="grid"` on the overlay.
- Grid host visible (`data-gallery-visible="true"`).
- Three uppercased row labels (one per previewId group: e.g.,
  `WEB · DESKTOP`, `TUI · WIDE`, `GPUI · DEFAULT` — exact labels
  depend on the seeded captures, but groupings of 2 each must be
  visible).
- Six tiles total, two per row at `wide` and `laptop` (single
  column at `narrow`).
- Each tile has a thumbnail image, a status dot, status text, and
  a score. No tile is missing metadata.

### Full-tab mode (`gallery-full-tab-*.png`)

- `data-gallery-mode="full-tab"` on the overlay.
- Full-tab host visible (`[data-design-review-gallery-fulltab=
  "true"]`).
- One image rendered at native pixel size, centred.
- `← Back to grid` button at top-left of overlay body with ≥8 px
  breathing room from the toolbar.
- No tile grid visible behind the image.

## What to Evaluate

For each viewport-mode combination, score chrome `1–10` against
the rubric:

- **10 — exemplary.** Tile density is crisp; row grouping reads
  instantly; mode chips share a clear family with chrome chips;
  full-tab back button feels native; native-size rule honoured.
- **8 — production-ready.** All design goals met; minor tuning
  possible (gutter widths, label leading, hover-state subtlety).
- **6 — acceptable but rough.** Tile metadata legible but
  cramped; row labels compete with the toolbar; or full-tab
  back button feels foreign.
- **4 — placeholder.** Tiles missing metadata; rows ungrouped;
  back button missing; image stretched to fit.
- **≤2 — broken.** Mode body blank; tiles unrendered; layout
  collapsed.

Target: **8+ on `wide` and `laptop`, 7+ on `narrow`**.

## How to Report

For each viewport-mode combination, in order:

1. **Expected-elements verification.** Pass/fail per the bullets
   in "What is Expected on the Screenshot". If any fail, note
   them first and cap the score at 4.
2. **Score with one-sentence justification.**
3. **Three concrete improvements** if score < 9, each naming the
   target file/line area (e.g., `gallery_overlay.nim:tile gap`,
   `gallery_overlay.nim:row-label color`, `design_review_mount.nim:
   narrow-overlay positioning`).
4. **Wave-A actionable items** the implementation agent can apply
   without further design clarification.
