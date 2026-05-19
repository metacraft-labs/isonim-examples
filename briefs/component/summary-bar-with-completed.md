---
briefId: component.summary-bar-with-completed
schemaVersion: 1
kind: component
title: Task App / SummaryBar — With Completed
coversPreviews:
  - storyRef: { group: "Task App / SummaryBar", name: "With Completed", kind: component, index: 1 }
    backends: [web, tui, gpui, freya, cocoa, android, ios]
captureViewports:
  - { width: 1080, height: 720, label: "tablet" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: visual,        label: "Visual Polish",   weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: states,        label: "State Clarity",   weight: 0.3, scale: { min: 1, max: 10 } }
  - { id: accessibility, label: "Accessibility",   weight: 0.3, scale: { min: 1, max: 10 } }
---

# Task App / SummaryBar — With Completed

> **Status:** Starter brief. Refine the bullets below as you learn what matters most for this story.

## What you're reviewing

The summary bar with at least one completed task present. The
**Clear completed** affordance is **enabled and visible** at the
trailing edge.

## What to watch for

- Clear completed control is rendered as a text-button or link with
  the accent colour (`#7c7aed`) — not a primary CTA button (it must
  feel like a tertiary action).
- Left side shows the active count (e.g. `1 item left`); the
  middle separator (web uses `·` middot) keeps the two phrases
  balanced.
- Hover / pressed state on Clear completed: subtle underline or
  background tint, not a full-button highlight.
- The summary bar's height matches the Active-Only sibling brief
  exactly — no vertical jump when Clear completed appears.
- Trailing edge of the bar aligns with the trailing edge of the
  task rows above.

## Cross-backend expectations

All seven backends. On TUI the affordance reads as a single
underlined or coloured text command.

## Scoring rubric

- **Visual Polish (9/10)**: tertiary CTA treatment is correct.
  **(5/10)**: Clear completed reads as the primary CTA (visually
  competing with Add Task). **(2/10)**: missing or unclickable.
- **State Clarity**: counts and CTA are immediately readable.
- **Accessibility**: link contrast meets 4.5 to 1.
