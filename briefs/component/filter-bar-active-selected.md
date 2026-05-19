---
briefId: component.filter-bar-active-selected
schemaVersion: 1
kind: component
title: Task App / FilterBar — Active Selected
coversPreviews:
  - storyRef: { group: "Task App / FilterBar", name: "Active Selected", kind: component, index: 1 }
    backends: [web, tui, gpui, freya, cocoa, android, ios]
captureViewports:
  - { width: 1080, height: 720, label: "tablet" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: visual,        label: "Visual Polish",   weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: states,        label: "State Clarity",   weight: 0.3, scale: { min: 1, max: 10 } }
  - { id: accessibility, label: "Accessibility",   weight: 0.3, scale: { min: 1, max: 10 } }
---

# Task App / FilterBar — Active Selected

> **Status:** Starter brief. Refine the "What to watch for" list as you learn what matters for this story.

## What you're reviewing

The filter bar with **Active** as the selected pill. The Active pill
carries the accent fill; All + Completed pills are inactive.

## What to watch for

- Active pill receives the accent fill; the inactive pills (All,
  Completed) match each other exactly (same border / text colour /
  background).
- Pill order is stable: All → Active → Completed (no reorder when
  the selection moves).
- The visual gap between pills did not change versus
  `filter-bar-all-selected` — only the active pill shifted.
- Active pill text contrast remains ≥4.5:1 against the accent.
- Hover / pressed states (if rendered) on the inactive pills do not
  visually compete with the accent fill of the active pill.

## Cross-backend expectations

All seven backends. Same idiom variability as the All-selected
sibling brief.

## Scoring rubric

- **Visual Polish (9/10)**: indistinguishable from a shipping
  segmented control. **(5/10)**: one pill looks misstyled.
- **State Clarity**: selection is unambiguous.
- **Accessibility**: contrast ratios preserved across the
  position-shift.
