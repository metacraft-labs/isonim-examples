---
briefId: component.summary-bar-active-only
schemaVersion: 1
kind: component
title: Task App / SummaryBar — Active Only
coversPreviews:
  - storyRef: { group: "Task App / SummaryBar", name: "Active Only", kind: component, index: 0 }
    backends: [web, tui, gpui, freya, cocoa, android, ios]
captureViewports:
  - { width: 1080, height: 720, label: "tablet" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: visual,        label: "Visual Polish",   weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: states,        label: "State Clarity",   weight: 0.3, scale: { min: 1, max: 10 } }
  - { id: accessibility, label: "Accessibility",   weight: 0.3, scale: { min: 1, max: 10 } }
---

# Task App / SummaryBar — Active Only

> **Status:** Starter brief. Refine the bullets below as you learn what matters most for this story.

## What you're reviewing

The summary bar with only active tasks present (`1 item left` or
backend-native equivalent). The **Clear completed** affordance is
NOT shown because zero completed tasks exist.

## What to watch for

- The Clear-completed control is absent (not greyed, not 0-width).
- Active-count text is left-aligned; right edge keeps the same
  alignment as the With-Completed sibling brief.
- Singular vs plural agreement: `1 item` not `1 items`.
- Top hairline border above the summary stays intact.
- Muted neutral text colour, consistent with summary copy across
  other backends.

## Cross-backend expectations

All seven backends. Count phrasing matches the seeded VM exactly.

## Scoring rubric

- **Visual Polish (9/10)**: the absence of Clear-completed feels
  intentional. **(5/10)**: bar feels half-empty. **(2/10)**: layout
  collapses without that affordance.
- **State Clarity**: count is correct and unambiguous.
- **Accessibility**: summary text contrast at least 4.5 to 1.
