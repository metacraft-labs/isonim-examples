---
briefId: render.task-app-today
schemaVersion: 1
kind: render
title: Task App / Pages — Today
coversPreviews:
  - storyRef: { group: "Task App / Pages", name: "Today", kind: page, index: 1 }
    backends: [web, tui, gpui, freya, cocoa, android, ios]
captureViewports:
  - { width: 1920, height: 1080, label: "wide" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: chrome,    label: "Editor Chrome",  weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: rendering, label: "App Rendering",  weight: 0.6, scale: { min: 1, max: 10 } }
relatedBriefs: [render.task-app, render.task-app-completed]
---

# Task App / Pages — Today

> **Status:** Starter brief. Refine the "What to watch for" list as you learn what matters for this story.

## What you're reviewing

The **Today** page of the task app: the filter is set to **Active**
and the list shows a single in-progress task. The preview captures
the full 1920×1080 editor with this story selected — sidebar +
chrome bar + preview pane + inspector all visible — once per backend.

## What to watch for

- The **Active** filter chip is the selected pill in the filter bar
  (accent fill, distinct from All / Completed).
- Exactly one active task row visible in the list — no completed
  rows, no empty-state copy.
- Summary bar reflects `1 active` and zero completed (the
  clear-completed affordance should be absent).
- Cross-backend information equivalence: the same single seeded
  active task name appears on every backend.
- Backend chip in the chrome bar matches the cell's backend (web /
  tui / gpui / freya / cocoa / android / ios).
- All Render Quality dimensions from `render.task-app` apply:
  aspect, letterbox, scaling, colors, alignment, AA, no stretching.

## Cross-backend expectations

This brief is the **Active-filter** twin of `render.task-app`
(which captures the `Inbox` All-filter page). All seven backends
participate. Use the same anti-cheat methodology as `render.task-app`:
flake detection, empty-pane check, per-dimension annotation, world-
class anchor references.

## Scoring rubric

- **Editor Chrome score**: same scale as `render.task-app` —
  evaluate the constant chrome (sidebar, chrome bar, inspector,
  story highlight).
- **App Rendering score**: production-ready showcase of the
  Active-filter Task App rendered through this specific backend.
  10/10 requires all required-content + render-quality dimensions
  pass.
