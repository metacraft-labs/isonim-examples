---
briefId: chrome.gallery-empty-state
schemaVersion: 1
kind: chrome
title: Gallery Overlay — Empty state (no captures yet)
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
relatedBriefs: [chrome.gallery-grid-and-full-tab, chrome.gallery-compare, chrome.shell-wide]
---


## What You're Reviewing

The IsoNim Editor's design-review **gallery overlay** opened against
a brief that has no captures yet. The overlay is summoned by clicking
the History button in the editor chrome bar (REV-M7 / REV-M8 widget
introduced by Design Review Database initiative, history-button fix
reworked in CHRM-M5). When no `record_capture` rows exist for the
selected story's brief, the overlay shows an empty-state panel
instead of a tile grid.

Captured by `editor-screenshot.mjs` view `gallery-empty-state` at
viewports `wide`, `laptop`, `narrow`: files
`screenshots/gallery-empty-state-{wide,laptop,narrow}.png`.

CHRM-M7 closes the narrow-viewport gap: at ≤768 px widths the
editor collapses to sidebar-only and the chrome bar (which holds
the chrome-resident 🕘 history button) is hidden. The narrow build
surfaces a duplicate history button in the sidebar header
(class `editor-sidebar-history-narrow`, attribute
`data-design-review-history-button-sidebar="true"`); clicking it
mounts the gallery as a full-viewport modal drawer attached to
`<body>` with `position: fixed`, `inset: 56px 0 0 0`, and an
explicit close chip (`data-design-review-gallery-close="true"`) in
the top-right corner. The host carries
`data-gallery-mount-mode="drawer"` at narrow widths;
`data-gallery-mount-mode="inline"` at wide/laptop.

## Design Goals

- **Empty state must read as intentional, not broken.** A first-time
  user opening the gallery before any sweep has run should
  understand "you haven't captured anything yet" — not "the gallery
  failed to load" and not "the gallery is loading".
- **Overlay must read as an overlay layer**, not as a fourth panel
  added to the three-panel shell. The overlay's background
  (`#0B1220`) sits one step darker than the editor chrome shell
  (`#0f0f14`) and inside a 1 px border (`#334155`) with an 8 px
  border-radius, so it visibly floats above the centre column rather
  than replacing it.
- **The chrome bar above the overlay remains visible and untouched.**
  The four-cluster chrome bar (Surface / Backend / Viewport / Mode,
  per CHRM-M5 Fix A's reordering) is still on screen and still
  reflects the selected story. The overlay opens inside the centre
  column below the chrome bar.
- **Mode toolbar is present even with no captures.** The Grid /
  Full tab / Full screen / Compare chips render along the overlay
  top, but Compare is `aria-disabled` because no captures exist to
  select. Disabled chips read muted (text `#475569`) without looking
  broken.
- **The empty-state panel anchors the centre of the overlay body.**
  A short heading line (`No captures yet`) and a one-line subtitle
  (`Run a capture sweep to populate the gallery — open a story,
  switch backends, and the capture pipeline will record each
  preview.`). The subtitle copy is calm and informative; no
  exclamation glyphs, no "error" iconography.
- **Status footer** reads `<briefId> · 0 captures` in a muted tone
  at the bottom of the overlay, so the reviewer always knows which
  brief the gallery is bound to.
- **Narrow viewport (375 px)** (CHRM-M7): the gallery mounts as a
  full-viewport modal drawer attached to `<body>` (`position: fixed;
  inset: 56px 0 0 0;`) so it overlays the sidebar rather than living
  inside the (hidden) centre column. The 56 px top inset leaves the
  sidebar header strip (search input + the sidebar-resident history
  button) visible so the user retains a sense of location. The
  drawer's top-right corner carries a 32 × 32 px close chip
  (`data-design-review-gallery-close="true"`) since ESC isn't
  reliable on touch devices. The empty-state heading + subtitle copy
  is identical to wide/laptop; the status footer is identical;
  status footer and toolbar may stack on two rows if needed.

## Color Expectations

- Overlay container background: `#0B1220` (one step darker than the
  editor shell).
- Overlay container border: `#334155`, 1 px, 8 px border-radius.
- Overlay container shadow: `0 12px 32px rgba(0,0,0,0.32)`.
- Overlay-vs-chrome separator: an 8 px gap between the chrome bar
  and the overlay top edge so they don't visually touch.
- Mode toolbar background: transparent (sits directly on the
  overlay).
- Mode chip family: matches the CHRM-M2 ChoiceGroup `cgvTransparent`
  variant — idle pills have transparent background, 1 px border in
  `#2D2D3A`; selected pill has accent fill `#3B82F6` with white
  text; disabled pills have text colour `#475569` and no border.
- Empty-state heading: `#E5E7EB`, 16 px, weight 600.
- Empty-state subtitle: `#A0A2B0`, 13 px, weight 400, line-height
  1.5, max-width 480 px.
- Status footer: `#64748B`, 11 px, weight 500, letter-spacing
  0.3 px, uppercased.

## What is Expected on the Screenshot

**The reviewer must verify these elements are present BEFORE
evaluating aesthetics.** If anything expected is missing or replaced
by a placeholder, report that as the first finding and rate ≤ 4/10
regardless of polish.

### Chrome bar (constant)

- Chrome bar above the centre column with all four clusters
  (Surface, Backend, Viewport, Mode) in CHRM-M5 Fix A order. The
  Surface cluster's `Preview` pill (index 0) is active.

### Overlay container

- Visible (`display: flex`, `data-gallery-host-open="true"`,
  `aria-hidden="false"`) below the chrome bar, inside the centre
  column.
- 1 px border, 8 px radius, calm shadow — visibly distinct from
  the chrome.

### Mode toolbar

- Four chips: `Grid` (selected), `Full tab`, `Full screen`,
  `Compare` (disabled — `aria-disabled="true"`, muted text).
- A `Gallery` cluster label or section heading near the chips.

### Empty-state panel

- `[data-design-review-gallery-empty="true"]` node visible.
- Heading: "No captures yet".
- Subtitle: the calm one-line explanation.
- No tile rows, no thumbnail placeholders, no spinners.

### Status footer

- Reads `<briefId> · 0 captures` in muted uppercased text.

## What to Evaluate

For each viewport, score chrome `1–10` against the rubric:

- **10 — exemplary.** Empty state reads as intentional; overlay
  layer is unambiguous; the mode toolbar invites the next action;
  copy is friendly and informative.
- **8 — production-ready.** All design goals met; minor tuning
  possible (spacing rhythm, copy tightening).
- **6 — acceptable but rough.** Goals met but the panel reads cold
  / cluttered / confusing for a first-time user.
- **4 — placeholder.** Empty state ambiguous with loading/error
  states; overlay reads as a fourth panel; chips broken or
  missing.
- **≤2 — broken.** Overlay blank; missing required elements;
  unreadable.

Target: **8+ on `wide` and `laptop`**.

## How to Report

For each viewport, in order:

1. **Expected-elements verification.** Pass/fail per the bullets in
   "What is Expected on the Screenshot". If any fail, note them
   first and cap the score at 4.
2. **Score with one-sentence justification.**
3. **Three concrete improvements** if score < 9, each naming the
   target file/line area (e.g., `gallery_overlay.nim:empty-state
   padding`, `design_review_mount.nim:overlay shadow strength`).
4. **Wave-A actionable items** the implementation agent can apply
   without further design clarification.
