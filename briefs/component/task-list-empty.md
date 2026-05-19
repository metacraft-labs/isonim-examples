---
briefId: component.task-list-empty
schemaVersion: 1
kind: component
title: Task App / TaskList — Empty
coversPreviews:
  - storyRef: { group: "Task App / TaskList", name: "Empty", kind: component, index: 0 }
    backends: [web, tui, gpui, freya, cocoa, android, ios]
captureViewports:
  - { width: 1080, height: 720, label: "tablet" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: visual,        label: "Visual Polish",   weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: states,        label: "State Clarity",   weight: 0.3, scale: { min: 1, max: 10 } }
  - { id: accessibility, label: "Accessibility",   weight: 0.3, scale: { min: 1, max: 10 } }
---

# Task App / TaskList — Empty

> **Status:** Starter brief. Refine the "What to watch for" list as you learn what matters for this story.

## What you're reviewing

The task list component in its **empty** state: no rows, friendly
empty-state copy. The reusable `Task Check Icon` vector symbol
appears as an illustrative glyph alongside the empty copy.

## What to watch for

- Empty-state copy is friendly and actionable — not "No data" or a
  bare ellipsis. Something like "No tasks yet — type one above" is
  the target.
- The illustrative glyph (`Task Check Icon`) sits comfortably with
  the copy; not so large that it visually dominates, not so small
  that it reads as a decoration mistake.
- Vertical centring of the empty state within the available list
  area — not pinned to the top edge.
- Colour palette: copy uses muted neutral, glyph uses tertiary
  accent (de-saturated indigo or muted neutral).
- No empty placeholder rectangles or skeleton rows.

## Cross-backend expectations

All seven backends. On TUI the glyph degrades to an ASCII / Unicode
character; on every native backend the SVG-style symbol renders
through the matching `usesVectorSymbols` registration.

## Scoring rubric

- **Visual Polish (9/10)**: empty state reads as intentional UX
  design. **(5/10)**: functional but feels like a fallback.
  **(2/10)**: empty state looks broken or missing.
- **State Clarity**: a reviewer can immediately tell this is empty
  state, not a loading state.
- **Accessibility**: copy contrast meets ≥4.5:1; glyph is decorative
  (not focus-stealing).
