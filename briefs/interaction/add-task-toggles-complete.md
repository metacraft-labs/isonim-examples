---
briefId: interaction.add-task-toggles-complete
schemaVersion: 1
kind: interaction
title: Add Task Flow — Toggles the task complete
coversPreviews:
  - storyRef: { group: "Add Task Flow", name: "Toggles the task complete", kind: flow, index: 2 }
    backends: [web, tui, gpui, freya, cocoa, android, ios]
captureViewports:
  - { width: 1080, height: 720, label: "tablet" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: clarity,        label: "Step Clarity",       weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: feedback,       label: "Toggle Feedback",    weight: 0.3, scale: { min: 1, max: 10 } }
  - { id: responsiveness, label: "Responsiveness",     weight: 0.3, scale: { min: 1, max: 10 } }
---

# Add Task Flow — Toggles the task complete

> **Status:** Starter brief. Refine the "What to watch for" list as you learn what matters for this story.

## What you're reviewing

Flow step where the user toggles a task row to the completed state.
The preview shows the row immediately after the checkbox flip:
checkmark filled, task name strikethrough applied, and the summary
bar count updated to reflect one fewer active task.

## What to watch for

- Tap-target visibility: the checkbox / toggle widget has a hit area
  of at least 24×24 px on touch backends, and a clearly distinct
  pressed state on hover-capable backends.
- Transition timing: animated captures should show the strikethrough
  + checkmark fade in under 250 ms. No jarring 0 ms or sluggish
  500 ms+ transitions.
- The accent indigo (`#7c7aed`) fills the checked checkbox on web /
  gpui / freya; on cocoa it's the system tint; on android Material
  checkmark style; on ios the native `UISwitch` / circular check.
- List ordering after the toggle: the completed row stays in place
  (insertion order) — it should NOT reorder to the bottom unless the
  filter changes.
- Summary bar updated counts in lock-step with the toggle.

## Cross-backend expectations

Cross-renderer parity matters here because the toggle widget is the
most idiom-divergent control across backends. Information equivalence
(checked vs unchecked state visible at a glance) is non-negotiable;
visual treatment varies per platform.

## Scoring rubric

- **Step Clarity (9/10)**: at a glance you can name which row was
  toggled and what state it's in. **(5/10)**: state is readable but
  requires scrutiny. **(2/10)**: state is ambiguous or unreadable at
  preview scale.
- **Toggle Feedback**: strikethrough rendering, checkmark contrast,
  pressed-state affordance.
- **Responsiveness**: the toggle should not require a re-render of
  the whole list (no visible flicker outside the toggled row).
