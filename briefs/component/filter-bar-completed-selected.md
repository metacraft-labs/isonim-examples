---
briefId: component.filter-bar-completed-selected
schemaVersion: 1
kind: component
title: Task App / FilterBar — Completed Selected
coversPreviews:
  - storyRef: { group: "Task App / FilterBar", name: "Completed Selected", kind: component, index: 2 }
    backends: [web, tui, gpui, freya, cocoa, android, ios]
captureViewports:
  - { width: 1080, height: 720, label: "tablet" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: visual,        label: "Visual Polish",   weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: states,        label: "State Clarity",   weight: 0.3, scale: { min: 1, max: 10 } }
  - { id: accessibility, label: "Accessibility",   weight: 0.3, scale: { min: 1, max: 10 } }
---

# Task App / FilterBar — Completed Selected

> **Status:** Starter brief. Refine the "What to watch for" list as you learn what matters for this story.

## What you're reviewing

The filter bar with **Completed** as the selected pill. Completed
carries the accent fill; All + Active are inactive.

## What to watch for

- Completed pill: accent fill, white text. The word "Completed" is
  the longest of the three labels — verify no clipping at minimum
  pill width.
- All + Active pills inactive, matching each other.
- Pill order remains All → Active → Completed.
- The active pill rests at the trailing edge of the cluster — verify
  no extra trailing padding that makes the bar look unbalanced.

## Cross-backend expectations

All seven backends. On narrow TUI cells the longer "Completed"
label may force a different layout; document any single-line vs
wrapped behaviour.

## Scoring rubric

- **Visual Polish (9/10)**: clipping-free, shipping-grade segmented
  control. **(5/10)**: visible clipping or misalignment.
- **State Clarity**: selection is unambiguous.
- **Accessibility**: same contrast bar as the sibling briefs.
