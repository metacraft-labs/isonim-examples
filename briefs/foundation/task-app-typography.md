---
briefId: foundation.task-app-typography
schemaVersion: 1
kind: foundation
title: Task App / Foundations — Typography
coversPreviews:
  - storyRef: { group: "Task App / Foundations", name: "Typography", kind: foundation, index: 1 }
    backends: [web]
captureViewports:
  - { width: 800, height: 600, label: "default" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: consistency,   label: "Token Consistency",  weight: 0.5, scale: { min: 1, max: 10 } }
  - { id: documentation, label: "Documentation",      weight: 0.5, scale: { min: 1, max: 10 } }
---

# Task App / Foundations — Typography

> **Status:** Starter brief. Refine the bullets below as you learn what matters most for this story.

## What you're reviewing

The type-style catalog for the task app: body, label, and
placeholder type styles with size, weight, line-height, and
colour annotations.

## What to watch for

- Three styles documented in a stack: Body (14 px regular near-
  white), Label (13 px medium), Placeholder (13 px muted).
- Each style has a real sample sentence using it, not lorem
  ipsum.
- Line-height ratios documented (typically 1.4 for body, 1.5 for
  hint copy).
- Hierarchy visible at a glance: body is the heaviest; placeholder
  is the lightest.
- Single sans-serif family used across the stack (system stack
  acceptable).

## Cross-backend expectations

Foundation; rendered on web. Other backends substitute the closest
native equivalent (monospace on TUI, San Francisco on cocoa /
ios, Roboto on android).

## Scoring rubric

- **Token Consistency**: each documented style matches a real
  consumer (task name, hint copy, etc.) in pixels.
- **Documentation**: style attributes are listed with values;
  sample copy is meaningful.
