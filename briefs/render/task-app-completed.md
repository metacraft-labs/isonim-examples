---
briefId: render.task-app-completed
schemaVersion: 1
kind: render
title: Task App / Pages — Completed
coversPreviews:
  - storyRef: { group: "Task App / Pages", name: "Completed", kind: page, index: 2 }
    backends: [web, tui, gpui, freya, cocoa, android, ios]
captureViewports:
  - { width: 1920, height: 1080, label: "wide" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: chrome,    label: "Editor Chrome",  weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: rendering, label: "App Rendering",  weight: 0.6, scale: { min: 1, max: 10 } }
relatedBriefs: [render.task-app, render.task-app-today]
---

# Task App / Pages — Completed

> **Status:** Starter brief. Refine the "What to watch for" list as you learn what matters for this story.

## What you're reviewing

The **Completed** page of the task app: the filter is set to
**Completed** and the list shows only completed rows along with the
**Clear completed** affordance. Captured per backend at 1920×1080.

## What to watch for

- The **Completed** filter chip is the selected pill (accent fill).
- Every visible row is in the completed state: checkmark filled,
  strikethrough on the task name, muted text colour.
- The **Clear completed** affordance is visible and primary — this
  is the page's main CTA.
- Summary bar shows `0 active` (or the equivalent native phrasing).
- If no completed tasks exist in the seeded state: the empty-state
  copy is friendly and references the completed filter explicitly
  (not the generic "no tasks").
- Cross-backend information equivalence: the set of completed tasks
  is byte-identical across backends.

## Cross-backend expectations

This is the **Completed-filter** sibling of `render.task-app`. All
seven backends participate. Apply the full render-quality rubric
from `render.task-app`.

## Scoring rubric

- **Editor Chrome score**: same scale as `render.task-app`.
- **App Rendering score**: 10/10 requires every required-content
  item plus all render-quality dimensions pass. The Clear-completed
  CTA is **required content** for this page — flag as missing if
  absent.
