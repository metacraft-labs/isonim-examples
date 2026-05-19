---
briefId: interaction.add-task-types-name
schemaVersion: 1
kind: interaction
title: Add Task Flow — Types a task name
coversPreviews:
  - storyRef: { group: "Add Task Flow", name: "Types a task name", kind: flow, index: 0 }
    backends: [web, tui, gpui, freya, cocoa, android, ios]
captureViewports:
  - { width: 1080, height: 720, label: "tablet" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: clarity,        label: "Step Clarity",       weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: feedback,       label: "Input Feedback",     weight: 0.3, scale: { min: 1, max: 10 } }
  - { id: responsiveness, label: "Responsiveness",     weight: 0.3, scale: { min: 1, max: 10 } }
---

# Add Task Flow — Types a task name

> **Status:** Starter brief. Refine the "What to watch for" list as you learn what matters for this story.

## What you're reviewing

The opening step of the **Add Task** user journey: the task-app input
gains focus and the user types the literal string `pick up groceries`.
The preview captures the input at full focus with the typed draft
visible.

## What to watch for

- Caret position is clearly visible inside the input (no clipped
  caret, no zero-width caret in TUI).
- The placeholder copy (`New task…`) has disappeared once typing
  starts — no double-up of placeholder + draft text.
- Focus ring or border treatment on the input is visibly distinct
  from the unfocused state in the rest of the editor chrome.
- The accent colour (`#7c7aed`) is used for the focus indicator, not
  a competing hue.
- Tab order: focus arriving at the input should not steal scroll
  position from the surrounding task list.

## Cross-backend expectations

This flow runs against every backend (web, tui, gpui, freya, cocoa,
android, ios). Each renders the input through its native idiom — an
HTML `<input>` for web, a cell-grid prompt for TUI, an `NSTextField`
for cocoa, a Material `EditText` for android, a `UITextField` for
ios. Information content stays identical; idiom differs.

## Scoring rubric

- **Step Clarity (9/10)**: a reviewer can instantly tell the user is
  in the middle of typing a task. **(5/10)**: ambiguous — could be
  hovering or selecting. **(2/10)**: it is unclear which control is
  focused at all.
- **Input Feedback**: caret blink rate, draft text legibility,
  focus-ring contrast against panel background.
- **Responsiveness**: in animated captures, does the draft text
  appear within one frame of the keystroke? (For still captures,
  score based on whether the input visibly responds to having focus.)
