---
briefId: chrome.shell-laptop
schemaVersion: 1
kind: chrome
title: Editor Shell — laptop viewport
coversPreviews:
  - storyRef: { group: "Task App / Pages", name: "Inbox", kind: page, index: 0 }
    backends: [web]
captureViewports:
  - { width: 1440, height: 900, label: "laptop" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: chrome, label: "Editor Chrome", weight: 1.0, scale: { min: 1, max: 10 } }
relatedBriefs: [chrome.shell-wide, chrome.shell-narrow]
---


## What You're Reviewing

The default editor landing surface at **1440 × 900** — the laptop
viewport. Same content as `shell-wide.md`; this brief focuses on the
density-sensitive aspects that the wider 1920 viewport hides.

Captured by `editor-screenshot.mjs` view `shell` at viewport
`laptop`: file `screenshots/shell-laptop.png`.

## Design Goals

- **Three-panel shell** stays visible (sidebar + centre + inspector).
  No panel collapses at this viewport.
- All chrome chips remain on a **single row** in the chrome bar; chip
  clusters should not wrap if at all avoidable.
- Sidebar quick-nav strip stays in **one horizontal row** of five
  icons. Icons may shrink slightly but must remain visually distinct
  and have ≥ 24 × 24 px hit targets.
- Inspector keeps tab labels visible even if its inner content reflows.
- 4 / 8 px spacing rhythm preserved; no element looks cramped.

## Color Expectations

Identical to `shell-wide.md` — dark theme, single accent, muted
greys for inactive chips and disabled categories.

## What is Expected on the Screenshot

**Verify presence before evaluating aesthetics.**

### Sidebar (left column)

- `[data-sidebar-search="true"]` input at the top with
  `Search stories…` placeholder, visible without horizontal scroll.
- One `[data-sidebar-quicknav="true"]` strip directly below the
  search; **five icons** in one row, all visible without horizontal
  scroll.
- Five sections in canonical order (User Journeys / Pages /
  Components / Foundations / Guidelines).
- Section headers retain the uppercase 10 px label + chevron at the
  right; no truncation of section labels.

### Centre column

- Exactly one `[data-preview-chrome-bar="true"]` toolbar at the top.
- Three toolbar clusters (`backend`, `viewport`, `mode`) all on a
  single row.
- All six backend chips visible; the active backend (default Web)
  highlighted with the accent.
- All three mode chips visible (View / Comment / Edit); active mode
  (View by default) highlighted.
- NO view-switcher; NO left/right edge strips.
- Below the chrome bar: empty-state preview or storyboard
  mini-previews.

### Right column

- Inspector panel visible; may be narrower than at wide viewport.
- 1 px hairline border between the inspector and the centre column.

### Density measurements

- Chrome bar height ≤ 64 px; chip cluster gap in [12, 16] px.
- Sidebar width in [220, 280] px range at this viewport.
- Inspector width in [200, 300] px range.

## What to Evaluate

1. **Density** — every chip + label fits without truncation or
   wrapping.
2. **Alignment** — chip clusters horizontally centred within their
   cluster boxes; sidebar indent step consistent.
3. **Spacing** — 4 / 8 px rhythm preserved; no cluster collapses
   chips together.
4. **Typography** — readable at this density; secondary text not
   undersized to fit.
5. **Hairline borders** — still visible at 1× scale; not lost.
6. **Quick-nav strip vs. search input** — appropriately separated by
   the section divider; not crammed against each other.

## How to Report

- Keep under 250 words.
- **First line:** `Expected elements: present` OR
  `Expected elements: missing-<X>` / `replaced-by-<Y>`.
- Lead with one-sentence aesthetic impression.
- List specific issues with locations (selector or coordinate).
- End with **1–2 highest-priority fixes**.
- Rate 1–10 with the calibration scale.
- Call out any wrapping / overflow that wide viewport wouldn't reveal.
