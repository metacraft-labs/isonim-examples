---
briefId: foundation.task-app-spacing
schemaVersion: 1
kind: foundation
title: Task App / Foundations — Spacing
coversPreviews:
  - storyRef: { group: "Task App / Foundations", name: "Spacing", kind: foundation, index: 0 }
    backends: [web]
captureViewports:
  - { width: 800, height: 600, label: "default" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: consistency,   label: "Token Consistency",  weight: 0.5, scale: { min: 1, max: 10 } }
  - { id: documentation, label: "Documentation",      weight: 0.5, scale: { min: 1, max: 10 } }
---

# Task App / Foundations — Spacing

> **Status:** Starter brief. Refine the bullets below as you learn what matters most for this story.

## What you're reviewing

The spacing token catalog used by the task app: padding and gap
values on the 4-pixel rhythm. Expected scale: 4, 8, 12, 16, 24,
32, 48 px.

## What to watch for

- Each token rendered at native pixel-perfect spacing, not
  rounded to the nearest 5 px.
- Tokens labelled with their numeric value and a usage example
  (where the token is consumed).
- Visual differentiation between adjacent tokens is obvious — 8
  vs 12 should not look identical at preview-pane scale.
- Dark-mode contrast: the spacing-block backgrounds remain
  distinguishable from the surrounding canvas.
- Tokens listed in ascending order; no gaps in the scale (8 then
  16 with no 12 between would be a finding).

## Cross-backend expectations

Foundation-style story; rendered on the canonical web backend.
Other backends consume the same token values via the shared
catalog.

## Scoring rubric

- **Token Consistency (9/10)**: every used spacing token in the
  task app appears in this catalog and at the correct value.
  **(5/10)**: a couple of off-by-rhythm exceptions documented.
  **(2/10)**: tokens disagree with their consumers.
- **Documentation**: each token's label is unambiguous and the
  usage example is concrete.
