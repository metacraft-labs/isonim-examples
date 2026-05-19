---
briefId: chrome.shell-narrow
schemaVersion: 1
kind: chrome
title: Editor Shell — narrow viewport
coversPreviews:
  - storyRef: { group: "Task App / Pages", name: "Inbox", kind: page, index: 0 }
    backends: [web]
captureViewports:
  - { width: 375, height: 812, label: "narrow" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: chrome, label: "Editor Chrome", weight: 1.0, scale: { min: 1, max: 10 } }
relatedBriefs: [chrome.shell-wide, chrome.shell-laptop]
---


## What You're Reviewing

The editor shell at the **narrow viewport** (375 × 812). This is
the most demanding density case for the shell.

Captured by `editor-screenshot.mjs` view `shell` at viewport
`narrow`: file `screenshots/shell-narrow.png`.

## Design Goals

- Some panels MAY collapse behind a toggle at this viewport (per the
  existing brief's responsive notes) — this is acceptable as long as
  the active panel is usable and the chrome bar's essential chips
  are reachable.
- Sidebar quick-nav strip must still be visible OR demonstrably
  reachable through a toggle / accordion.
- Chrome bar chip clusters may wrap onto two rows; if so, the wrap
  must align cleanly (no orphan single chips).
- No horizontal scroll on the root viewport.

## What is Expected on the Screenshot

### Editor chrome present

- The editor sidebar (or its collapsed toggle affordance) is mounted.
- The centre column shows either the empty-state landing or the
  storyboard mini-previews.
- A single `[data-preview-chrome-bar="true"]` toolbar (may wrap onto
  two rows). It is NOT replaced by an inner per-view toolbar.
- NO `[data-preview-view-switcher]` anywhere.

### Sidebar (when visible)

- If shown, the `[data-sidebar-search="true"]` input is present and
  not truncated.
- If shown, the `[data-sidebar-quicknav="true"]` strip exposes
  exactly five icons (one per `data-category-kind`). Icons may
  shrink to ≥ 20 × 20 px hit targets.

### Centre column

- Chrome bar present with at least the **backend** and **mode**
  clusters reachable (viewport cluster may collapse into a dropdown
  / overflow menu at this size).
- Active backend chip highlighted with accent.

### Inspector

- May be collapsed behind a tab / drawer toggle; if collapsed, that
  toggle must be visible (e.g. a small chevron or labelled button).
- If shown inline, must not push the centre column off-screen.

### Negative expectations

- No element extends past the viewport's right edge.
- No element overlaps another (chrome bar chips, sidebar entries,
  inspector tabs).

## What to Evaluate

1. **Layout adaptation** — does the editor make sensible compromises
   (collapsing the right panel, wrapping the chrome bar) or does it
   look broken (squashed, clipped, overlapping)?
2. **Hit targets** — every interactive element ≥ 20 × 20 px.
3. **Type legibility** — body text not < 11 px; secondary text not
   < 10 px.
4. **Chrome bar** — single toolbar (possibly multi-row) carrying the
   surviving clusters; no per-view inner toolbar appears here either.
5. **Density** — no chip cluster wraps a single orphan chip onto a
   new row; if a cluster wraps, the wrap is balanced.

## How to Report

- Keep under 200 words.
- **First line:** `Expected elements: present` OR
  `Expected elements: missing-<X>` / `replaced-by-<Y>`.
- Lead with one-sentence aesthetic impression.
- Call out any clipping / horizontal scroll / overlap as the first
  finding if present.
- End with **1–2 highest-priority fixes**.
- Rate 1–10. Narrow-viewport tolerance: rate 8/10 even if the
  inspector is hidden behind a toggle, as long as nothing is broken
  and the active surface is usable.
