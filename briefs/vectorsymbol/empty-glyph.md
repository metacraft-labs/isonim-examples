---
briefId: vectorsymbol.empty-glyph
schemaVersion: 1
kind: vectorsymbol
title: Task App / Vector Symbols — Empty Glyph
coversPreviews:
  - storyRef: { group: "Task App / Vector Symbols", name: "Empty Glyph", kind: vectorsymbol, index: 3 }
    backends: [web]
captureViewports:
  - { width: 800, height: 600, label: "default" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: clarity,     label: "Glyph Clarity",  weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: scalability, label: "Scalability",    weight: 0.3, scale: { min: 1, max: 10 } }
  - { id: brand_fit,   label: "Brand Fit",      weight: 0.3, scale: { min: 1, max: 10 } }
---

# Task App / Vector Symbols — Empty Glyph

> **Status:** Starter brief. Refine the bullets below as you learn what matters most for this story.

## What you're reviewing

A reserved glyph with no current usages. The story acts as a
visual-review baseline for the vector editor's empty usage-panel
state. Designers can experiment here without disturbing the
shipping icons.

## What to watch for

- The glyph is intentional — even though it has no usages, it
  should look complete (not a placeholder cross or "TODO" shape).
- Stroke weight and visual weight are aligned with the rest of
  the catalog (Task Check Icon, Task Filter Icon, Task Sort
  Icon).
- The vector editor's right-side usage panel renders an
  empty-state message ("No usages of this glyph") clearly when
  this symbol is opened.

## Cross-backend expectations

Web canonical. This glyph is used to drive the
`vector-editor-empty` chrome brief (the editor screenshot test);
that brief covers the editor's empty-panel state, while this
brief covers the glyph itself as a designable object.

## Scoring rubric

- **Glyph Clarity (9/10)**: the glyph is a coherent shape, not
  noise. **(5/10)**: shape is ambiguous but recognisable as
  intentional. **(2/10)**: looks like an artifact.
- **Scalability**: legible at 12 px to 32 px.
- **Brand Fit**: matches the catalog's stroke and weight.
