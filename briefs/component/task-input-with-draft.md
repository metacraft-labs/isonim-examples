---
briefId: component.task-input-with-draft
schemaVersion: 1
kind: component
title: Task App / TaskInput — With Draft
coversPreviews:
  - storyRef: { group: "Task App / TaskInput", name: "With Draft", kind: component, index: 1 }
    backends: [web, tui, gpui, freya, cocoa, android, ios]
captureViewports:
  - { width: 1080, height: 720, label: "tablet" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: visual,        label: "Visual Polish",   weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: states,        label: "State Clarity",   weight: 0.3, scale: { min: 1, max: 10 } }
  - { id: accessibility, label: "Accessibility",   weight: 0.3, scale: { min: 1, max: 10 } }
---

# Task App / TaskInput — With Draft

> **Status:** Starter brief. Refine the "What to watch for" list as you learn what matters for this story.

## What you're reviewing

The task-input component with draft text `buy milk` typed and
**not yet submitted**. The placeholder is gone, draft text occupies
the input, and the **Add Task** button should be in its enabled
state (some backends may also use a brighter accent to signal that
Enter / click will commit).

## What to watch for

- Draft text colour is the primary-text colour (near-white
  `#E8E9F0`), distinctly brighter than the placeholder used in the
  Empty story.
- Caret is visible inside the draft (still or animated capture).
- The Add Task button is in an **enabled** state — should not be
  greyed out simply because the input previously had no value.
- Draft text byte-content matches `buy milk` exactly (no autocaps,
  no trailing-space variants).
- No focus ring artifacts overlapping the typed text.

## Cross-backend expectations

All seven backends. The biggest variability is the caret rendering
(blink rate, colour) and how each backend handles input baseline
when the leading `+` glyph is present.

## Scoring rubric

- **Visual Polish (9/10)**: typed text is crisp, the button reads
  as primary-and-enabled. **(5/10)**: typed text legible but caret
  / button states are ambiguous. **(2/10)**: typed text overlaps
  glyphs or is unreadable.
- **State Clarity**: difference from the Empty story is immediate
  (draft visible, button enabled).
- **Accessibility**: typed text contrast ≥7:1; caret high-contrast.
