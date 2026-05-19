---
briefId: interaction.add-task-clears-completed
schemaVersion: 1
kind: interaction
title: Add Task Flow — Clears completed tasks
coversPreviews:
  - storyRef: { group: "Add Task Flow", name: "Clears completed tasks", kind: flow, index: 3 }
    backends: [web, tui, gpui, freya, cocoa, android, ios]
captureViewports:
  - { width: 1080, height: 720, label: "tablet" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: clarity,        label: "Step Clarity",       weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: feedback,       label: "Action Feedback",    weight: 0.3, scale: { min: 1, max: 10 } }
  - { id: responsiveness, label: "Responsiveness",     weight: 0.3, scale: { min: 1, max: 10 } }
---

# Add Task Flow — Clears completed tasks

> **Status:** Starter brief. Refine the "What to watch for" list as you learn what matters for this story.

## What you're reviewing

Final flow step: user clicks the **Clear completed** affordance in
the summary bar to remove all completed rows. The preview shows the
post-clear state: completed rows gone, summary bar count updated,
and the clear-completed button hidden (no completed tasks remain).

## What to watch for

- The clear-completed control was visible before the action and is
  now hidden / disabled — it should only appear when at least one
  completed task exists.
- Completed rows removed from the list with no leftover ghost rows
  or 0-height placeholders.
- The summary's `N completed` count went to 0 and the secondary
  affordance retracts cleanly.
- If captured mid-animation: rows should slide / fade out (not just
  pop out instantly), under ~300 ms.
- No accidental removal of active tasks — verify the remaining row
  count matches the pre-action active count exactly.

## Cross-backend expectations

The Clear-completed affordance is rendered as a text-button on web /
gpui / freya, a small text command on TUI, and an icon-button or
text affordance on cocoa / android / ios. Information equivalence:
all backends must show this affordance disappear after the click.

## Scoring rubric

- **Step Clarity (9/10)**: a reviewer can tell what action just
  happened from the still image. **(5/10)**: requires the
  description to interpret. **(2/10)**: state is indistinguishable
  from an empty list that never had completed tasks.
- **Action Feedback**: button hover / pressed state, removal
  transition smoothness.
- **Responsiveness**: clear-completed should not block on a network
  call; expect immediate UI update.
