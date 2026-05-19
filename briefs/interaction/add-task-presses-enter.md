---
briefId: interaction.add-task-presses-enter
schemaVersion: 1
kind: interaction
title: Add Task Flow — Presses Enter to add
coversPreviews:
  - storyRef: { group: "Add Task Flow", name: "Presses Enter to add", kind: flow, index: 1 }
    backends: [web, tui, gpui, freya, cocoa, android, ios]
captureViewports:
  - { width: 1080, height: 720, label: "tablet" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: clarity,        label: "Step Clarity",       weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: feedback,       label: "Commit Feedback",    weight: 0.3, scale: { min: 1, max: 10 } }
  - { id: responsiveness, label: "Responsiveness",     weight: 0.3, scale: { min: 1, max: 10 } }
---

# Add Task Flow — Presses Enter to add

> **Status:** Starter brief. Refine the "What to watch for" list as you learn what matters for this story.

## What you're reviewing

The commit step in the Add Task flow: the user has typed a task name
and presses Enter (or taps the Add button). The preview captures the
moment immediately after commit, when the list now contains one
active row and the input has reset to its empty state.

## What to watch for

- The task row that just got added appears in the list — verify it
  is the bottommost row (insertion-order sort) and that it carries
  the correct typed name.
- The input has cleared back to its placeholder; no draft text
  lingers between commits.
- The summary bar count incremented by one ("1 active" / "1 task
  remaining").
- Commit affordance: was there a visible flash, slide, or fade as
  the row appeared? (Animated captures only; still images note the
  resting state.)
- No double-insert (two identical rows from a single Enter press).

## Cross-backend expectations

All seven backends must reflect the same VM state after the Enter
keypress. On TUI the row should be a single line with the task name;
on cocoa / ios / android the native list-row appearance applies.

## Scoring rubric

- **Step Clarity (9/10)**: list visibly grew by exactly one row and
  the summary bar count matches. **(5/10)**: row appeared but
  summary is stale. **(2/10)**: no observable state change.
- **Commit Feedback**: was there any visual cue that Enter was
  acknowledged (input clear, focus retention, brief highlight on
  new row)?
- **Responsiveness**: time from keypress to first visible change
  should feel sub-100 ms. On still captures this is the absence of
  loading spinners or pending-state UI.
