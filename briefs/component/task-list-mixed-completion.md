---
briefId: component.task-list-mixed-completion
schemaVersion: 1
kind: component
title: Task App / TaskList — Mixed Completion
coversPreviews:
  - storyRef: { group: "Task App / TaskList", name: "Mixed Completion", kind: component, index: 2 }
    backends: [web, tui, gpui, freya, cocoa, android, ios]
captureViewports:
  - { width: 1080, height: 720, label: "tablet" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: visual,        label: "Visual Polish",   weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: states,        label: "State Clarity",   weight: 0.3, scale: { min: 1, max: 10 } }
  - { id: accessibility, label: "Accessibility",   weight: 0.3, scale: { min: 1, max: 10 } }
---

# Task App / TaskList — Mixed Completion

> **Status:** Starter brief. Refine the "What to watch for" list as you learn what matters for this story.

## What you're reviewing

The task list with **one active row + one completed row** in
insertion order. This is the canonical "before clear-completed"
state that exercises both row treatments side-by-side.

## What to watch for

- Active row: empty checkbox, primary-text name, no strikethrough.
- Completed row: filled checkbox (accent fill), muted name with
  strikethrough applied. Strikethrough should be subtle (1 px line
  weight in the name's colour), not heavy.
- Row order is insertion order; the completed row does NOT reorder
  to the bottom.
- Sort affordance (`Task Sort Icon`) — verify the glyph is visible
  and not clipped, since both rows are listed via the same renderer.
- Row-to-row vertical gap is consistent — same gap before, between,
  and after the rows.
- Remove affordance (`×` glyph) renders on both rows.

## Cross-backend expectations

All seven backends. Verify the strikethrough effect translates: TUI
may use a Unicode strikethrough combining char or ANSI SGR
`\x1b[9m`; cocoa uses `NSAttributedString` strikethrough; android
uses `paintFlags |= STRIKE_THRU_TEXT_FLAG`.

## Scoring rubric

- **Visual Polish (9/10)**: both row states are visibly distinct
  and shipping-quality. **(5/10)**: one state visibly amateur (e.g.
  no strikethrough on completed). **(2/10)**: rows look identical.
- **State Clarity**: active vs completed is unambiguous from row
  styling alone.
- **Accessibility**: muted text + strikethrough on the completed
  row still meets ≥3:1 contrast (lowered floor since text is
  decorative-with-strikethrough).
