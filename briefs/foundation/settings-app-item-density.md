---
briefId: foundation.settings-app-item-density
schemaVersion: 1
kind: foundation
title: Settings App / Foundations — Item Density
coversPreviews:
  - storyRef: { group: "Settings App / Foundations", name: "Item Density", kind: foundation, index: 0 }
    backends: [web]
captureViewports:
  - { width: 800, height: 600, label: "default" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: consistency,   label: "Token Consistency",  weight: 0.5, scale: { min: 1, max: 10 } }
  - { id: documentation, label: "Documentation",      weight: 0.5, scale: { min: 1, max: 10 } }
---

# Settings App / Foundations — Item Density

> **Status:** Starter brief. Refine the bullets below as you learn what matters most for this story.

## What you're reviewing

The row-height and label-control alignment rhythm of settings
items: how tall each row is, where the title sits relative to
the hint, and where the trailing control aligns vertically.

## What to watch for

- A row-height token documented (web reference is approximately
  56-64 px including 10 px vertical padding on each side).
- Label-stack measurements: title-to-hint vertical gap (around
  2 px), title-to-control horizontal gap (around 16 px).
- Trailing control vertical alignment: centred against the label
  stack, not against the title baseline alone.
- Hairline divider treatment between rows is documented (1 px
  border-bottom).
- Density variants if any (compact vs comfortable) — document if
  none.

## Cross-backend expectations

Foundation; web. Native backends approximate the same rhythm via
their default list-cell sizes (cocoa 44 px, ios 44 px, android
56 dp).

## Scoring rubric

- **Token Consistency**: documented row metrics match the
  Appearance and Editor group rows in pixels.
- **Documentation**: gaps and alignment lines are called out with
  pixel values, not adjectives.
