---
briefId: component.number-item-clamped
schemaVersion: 1
kind: component
title: Settings App / NumberItem — Clamped
coversPreviews:
  - storyRef: { group: "Settings App / NumberItem", name: "Clamped", kind: component, index: 1 }
    backends: [web, tui, gpui, freya, cocoa, android, ios]
captureViewports:
  - { width: 1080, height: 720, label: "tablet" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: visual,        label: "Visual Polish",   weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: states,        label: "State Clarity",   weight: 0.3, scale: { min: 1, max: 10 } }
  - { id: accessibility, label: "Accessibility",   weight: 0.3, scale: { min: 1, max: 10 } }
---

# Settings App / NumberItem — Clamped

> **Status:** Starter brief. Refine the bullets below as you learn what matters most for this story.

## What you're reviewing

A bounded-integer setting after the user attempted to decrement
below the minimum; the value snapped to 10 (the floor). The
stepper readout shows 10 and the minus button is disabled.

## What to watch for

- Minus button is visibly disabled: lower opacity (around 0.4),
  no hover affordance, may carry a disabled-cursor.
- The clamped readout (10) is rendered identically to the default
  readout in font / size / weight — only the surrounding state
  changed.
- Plus button remains enabled.
- No error / shake animation should be triggered by a clamp —
  this is a graceful boundary state, not an error.
- If a min/max hint is rendered anywhere, verify the wording is
  not alarmist (no "Error" copy).

## Cross-backend expectations

All seven backends. Disabled-state styling differs per platform:
cocoa greys NSStepper segments; ios UIStepper has built-in
disabled visuals; android Material disabled is a 38% opacity.

## Scoring rubric

- **Visual Polish (9/10)**: clamp state feels intentional, not
  broken.
- **State Clarity**: disabled minus is unambiguous; value is
  correct.
- **Accessibility**: disabled state still passes 3 to 1 contrast
  for the readout.
