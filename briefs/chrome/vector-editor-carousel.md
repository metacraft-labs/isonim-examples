---
briefId: chrome.vector-editor-carousel
schemaVersion: 1
kind: chrome
title: Vector Editor with Symbol — carousel usage-context
coversPreviews:
  - storyRef: { group: "Task App / Vector Symbols", name: "Task Check Icon", kind: vectorsymbol, index: 0 }
    backends: [web]
captureViewports:
  - { width: 1920, height: 1080, label: "wide" }
  - { width: 1440, height: 900, label: "laptop" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: chrome, label: "Editor Chrome", weight: 1.0, scale: { min: 1, max: 10 } }
relatedBriefs: [chrome.vector-editor-empty, chrome.vector-editor-with-symbol]
---


## What You're Reviewing

The vector editor with the **carousel usage-context** companion
panel visible — the M-EVP-8 carousel variant that engages when the
target symbol has **more than 3 usages** across the workspace.
Only the active usage is shown; Prev / Next buttons and dot
indicators expose the rest.

The screenshot tool drives the editor to this state by:

1. Opening the editor.
2. Navigating to the `Task Check Icon` vector symbol.
3. Using the test-mode hook (`window.__isonimTestMode = true`) to
   seed the editor with **5 synthetic usages** (since the demo
   workspace currently exposes only one natural usage). The seed
   path is implemented via the same `vm.vectorEditorUsages.val =
   …` path the editor uses internally.
4. Asserting `vm.vectorEditorUsages.val.len > 3`.
5. Optionally clicking the 3rd dot indicator so the carousel shows
   an interior index (`data-vector-usage-index = "2"`) — proves
   that **both** Prev and Next are enabled (no boundary-disabled
   state).

Captured by `editor-screenshot.mjs` view `vector-editor-carousel`
at viewports `wide` and `laptop`: files
`screenshots/vector-editor-carousel-wide.png` and
`screenshots/vector-editor-carousel-laptop.png`.

## Design Goals

- Same split layout as `vector-editor-with-symbol.md` — canvas
  left, usage panel right.
- The usage panel renders **one** card (the active usage) plus a
  Prev / dots / Next control row.
- Dot indicators read like a slideshow paginator: small circles,
  the active dot in the accent colour, inactive in `borderFaint`.
- Prev / Next buttons clearly affordant; disabled (boundary) state
  uses `opacity: 0.4` and `aria-disabled="true"`.

## Color Expectations

- Active dot: accent (same accent the chrome bar uses).
- Inactive dot: `borderFaint` gray.
- Prev / Next button: `bgSurface` background, `border` border,
  `textSecondary` text colour.
- Disabled Prev / Next: `opacity: 0.4`.

## What is Expected on the Screenshot

### Vector editor surface

- All of the elements in `vector-editor-with-symbol.md` apply
  (split layout, canvas, properties, layers, usage panel header).

### Carousel variant markers

- `[data-vector-usage-layout="carousel"]` panel is `display: flex`
  (visible).
- `[data-vector-usage-layout="split"]` stacked panel is
  `display: none` (hidden).
- `[data-vector-usage-carousel="true"]` panel exposes
  `data-vector-usage-index="2"` (the screenshot setup advances to
  the 3rd usage, zero-indexed).

### Carousel content

- Exactly **one** active card inside
  `[data-vector-usage-carousel-content="true"]`:
  - `data-vector-usage="true"`
  - `data-vector-usage-label` matches the active usage's
    `group / story` string.
  - The card shows the usage's label + a minimal preview tile.

### Carousel controls

- A `[data-vector-usage-prev="true"]` button on the left with
  `aria-label="Previous vector usage"` and text `‹ Prev`.
- A `[data-vector-usage-next="true"]` button on the right with
  `aria-label="Next vector usage"` and text `Next ›`.
- A `[data-vector-usage-dots="true"]` row in the middle containing
  exactly **5 dot indicators** (one per seeded usage).
- Each dot is a `[data-vector-usage-dot]` 8 × 8 px circle.
  `aria-current="true"` marks the **third** dot
  (`data-vector-usage-dot="2"`).
- The third dot's background is the accent colour; the other four
  dots use `borderFaint`.

### Boundary-state expectations

- At index 2 of 5, both Prev and Next are **enabled** —
  `aria-disabled="false"` and full opacity. (If the screenshot is
  ever re-shot at index 0 or 4, the relevant button must flip to
  `aria-disabled="true"` and opacity 0.4 — call that out if you
  see a regression.)

### Negative expectations

- No stacked cards visible (the split layout is hidden).
- Exactly one usage card in the carousel content area; not 2 or 5.

## What to Evaluate

1. **Carousel readability** — can you tell at a glance which usage
   is active among the 5 seeded usages?
2. **Dot affordance** — dots are clearly clickable (verify
   `cursor: pointer` in DOM); the active dot is unambiguously
   distinct.
3. **Prev / Next button balance** — left/right symmetry; same
   width; same colour.
4. **Carousel content card** — same visual weight as a stacked
   card in `vector-editor-with-symbol.md`. The user should not
   perceive a layout shift switching between split and carousel.
5. **Spacing** — 8 px gap between Prev / dots / Next; 6 px gap
   between adjacent dots.
6. **Accent usage** — the active dot's accent colour matches the
   chrome bar's active backend chip (single editor accent).

## How to Report

- Keep under 250 words.
- **First line:** `Expected elements: present` OR
  `Expected elements: missing-<X>` / `replaced-by-<Y>`.
- Lead with one-sentence aesthetic impression.
- Specifically count the dot indicators and confirm exactly 5 are
  visible.
- Confirm the active dot is the **third** (zero-indexed = 2).
- List specific issues with selectors.
- End with **1–2 highest-priority fixes**.
- Rate 1–10.
