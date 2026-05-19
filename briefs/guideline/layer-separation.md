---
briefId: guideline.layer-separation
schemaVersion: 1
kind: guideline
title: Guidelines — Layer separation
coversPreviews:
  - storyRef: { group: "Guidelines", name: "Layer separation", kind: guideline, index: 1 }
    backends: [web]
captureViewports:
  - { width: 800, height: 600, label: "default" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: clarity,       label: "Clarity",       weight: 0.5, scale: { min: 1, max: 10 } }
  - { id: actionability, label: "Actionability", weight: 0.5, scale: { min: 1, max: 10 } }
---

# Guidelines — Layer separation

> **Status:** Starter brief. Refine the bullets below as you learn what matters most for this story.

## What you're reviewing

The layer-separation guideline: a Layer-1 leaf (per-platform
widget) must never be imported from `core/`. Core contains the
shared view model and view template; leaves are imported only by
the per-platform composition root.

## What to watch for

- One-sentence statement of the rule at the top.
- A short, concrete violation example (a TUI widget imported from
  `task_app/core/views.nim`) with a marked X next to it.
- A short concrete correct example (the same leaf consumed via
  the `Leaves` bundle parameter) with a marked tick next to it.
- A "how to verify" instruction: `grep -r 'from .leaves' core/`
  must yield zero hits.
- The guideline cross-references the cross-platform architecture
  spec so a reader can dig further.

## Cross-backend expectations

Doc-style; web only.

## Scoring rubric

- **Clarity (9/10)**: the rule is unambiguous after one read.
- **Actionability**: a reviewer can identify a violation in a
  diff in under 10 seconds.
