---
briefId: vectorsymbol.task-sort-icon
schemaVersion: 1
kind: vectorsymbol
title: Task App / Vector Symbols — Task Sort Icon
coversPreviews:
  - storyRef: { group: "Task App / Vector Symbols", name: "Task Sort Icon", kind: vectorsymbol, index: 2 }
    backends: [web]
captureViewports:
  - { width: 800, height: 600, label: "default" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: clarity,     label: "Glyph Clarity",  weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: scalability, label: "Scalability",    weight: 0.3, scale: { min: 1, max: 10 } }
  - { id: brand_fit,   label: "Brand Fit",      weight: 0.3, scale: { min: 1, max: 10 } }
---

# Task App / Vector Symbols — Task Sort Icon

> **Status:** Starter brief. Refine the bullets below as you learn what matters most for this story.

## What you're reviewing

The reusable sort glyph used by the task-list sort affordance.
Conceptually two arrows (up and down) stacked or side-by-side; the
glyph stands in for "rearrange / order" actions.

## What to watch for

- Stroke weight is uniform; arrow heads have matching angle and
  length.
- Glyph is balanced inside its viewBox — no off-centre crowding.
- At 16-px render size the arrows are still distinguishable from
  each other (no merged double-arrow blob).
- Optical centring: if the glyph is composed of two arrows of
  different visual weight, ensure the bounding box is shifted to
  compensate so the glyph reads as centred.
- Stroke colour is a muted neutral by default; the glyph never
  ships with a hard-coded accent fill.

## Cross-backend expectations

SVG-shaped on every backend; rendered on the canonical web
backend here. Vector editor opens this story on canvas double-
click for any leaf that resolves to TaskSortIcon.

## Scoring rubric

- **Glyph Clarity (9/10)**: instantly readable as a sort /
  rearrange affordance. **(5/10)**: requires context.
  **(2/10)**: reads as something else entirely.
- **Scalability**: legible from 12 px up to 32 px.
- **Brand Fit**: stroke weight matches Task Check Icon and
  Task Filter Icon siblings.
