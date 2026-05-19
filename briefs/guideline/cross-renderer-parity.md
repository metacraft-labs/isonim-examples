---
briefId: guideline.cross-renderer-parity
schemaVersion: 1
kind: guideline
title: Guidelines — Cross-renderer parity
coversPreviews:
  - storyRef: { group: "Guidelines", name: "Cross-renderer parity", kind: guideline, index: 0 }
    backends: [web]
captureViewports:
  - { width: 800, height: 600, label: "default" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: clarity,       label: "Clarity",       weight: 0.5, scale: { min: 1, max: 10 } }
  - { id: actionability, label: "Actionability", weight: 0.5, scale: { min: 1, max: 10 } }
---

# Guidelines — Cross-renderer parity

> **Status:** Starter brief. Refine the bullets below as you learn what matters most for this story.

## What you're reviewing

The cross-renderer parity guideline: every demo component must
round-trip on TUI, web, GPUI, Freya, Cocoa, Android, and iOS.
Information equivalence is the contract; visual identity is not
required.

## What to watch for

- Guideline copy lays out the rule in one sentence at the top.
- Examples of "information equivalence" are concrete (the
  filter pill exists on all backends; on TUI it is `[All]
  Active Completed`, on web it is a pill cluster).
- Examples of "visual identity not required" call out specific
  expected differences (cocoa NSSwitch vs Material switch).
- A short "How to check" list points reviewers at the render
  briefs that exercise the rule.
- The guideline page is concise (under 300 words of body copy).

## Cross-backend expectations

Doc-style story; rendered on web only.

## Scoring rubric

- **Clarity (9/10)**: the rule is unambiguous after one read.
  **(5/10)**: the rule requires interpretation.
- **Actionability**: a reviewer can apply the rule to a new
  story without ambiguity.
