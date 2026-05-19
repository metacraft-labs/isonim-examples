---
briefId: render.settings-app-appearance
schemaVersion: 1
kind: render
title: Settings App / Pages — Appearance Group
coversPreviews:
  - storyRef: { group: "Settings App / Pages", name: "Appearance Group", kind: page, index: 1 }
    backends: [web, tui, gpui, freya, cocoa, android, ios]
captureViewports:
  - { width: 1920, height: 1080, label: "wide" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: chrome,    label: "Editor Chrome",  weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: rendering, label: "App Rendering",  weight: 0.6, scale: { min: 1, max: 10 } }
relatedBriefs: [render.settings-app, render.settings-app-editor]
---

# Settings App / Pages — Appearance Group

> **Status:** Starter brief. Refine the "What to watch for" list as you learn what matters for this story.

## What you're reviewing

The **Appearance** single-group page of the settings app: a focused
preview of one group rather than the full Preferences screen. Shows
three rows — **Dark mode** toggle, **Theme** segmented choice
(Default / Solarized / Dracula), **Font size** stepper (default
14 pt). Captured per backend at 1920×1080.

## What to watch for

- Exactly three rows in the order Dark mode → Theme → Font size.
- Theme segmented control: Default is the active pill (accent
  fill); Solarized + Dracula are inactive (muted neutral).
- Font size stepper readout includes the unit (`pt` or equivalent
  per backend idiom).
- Single-group framing: no Editor / Notifications groups bleeding
  into the pane — they should be either absent or visibly
  de-emphasised in a sidebar.
- Row-label / row-hint typography hierarchy: title weight visibly
  heavier than hint, hint muted to ~`#9CA0B0` family.

## Cross-backend expectations

Every backend renders the same three items in the same order.
Idiom differs: native cocoa `NSPopUpButton` vs web pill-segmented
control vs Android Material dropdown vs ios `UISegmentedControl`.
Information equivalence is non-negotiable.

## Scoring rubric

- **Editor Chrome score**: same scale as `render.settings-app`.
- **App Rendering score**: 10/10 requires all three rows present,
  correct active selections, and the render-quality dimensions from
  `render.settings-app` all pass.
