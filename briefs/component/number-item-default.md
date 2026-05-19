---
briefId: component.number-item-default
schemaVersion: 1
kind: component
title: Settings App / NumberItem — Default
coversPreviews:
  - storyRef: { group: "Settings App / NumberItem", name: "Default", kind: component, index: 0 }
    backends: [web, tui, gpui, freya, cocoa, android, ios]
captureViewports:
  - { width: 1080, height: 720, label: "tablet" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: visual,        label: "Visual Polish",   weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: states,        label: "State Clarity",   weight: 0.3, scale: { min: 1, max: 10 } }
  - { id: accessibility, label: "Accessibility",   weight: 0.3, scale: { min: 1, max: 10 } }
---

# Settings App / NumberItem — Default

> **Status:** Starter brief. Refine the bullets below as you learn what matters most for this story.

## What you're reviewing

A bounded-integer setting row at its initial seed value (font_size
= 14). The stepper shows minus, the numeric readout (14), and
plus, with both buttons enabled.

## What to watch for

- Numeric readout uses tabular-nums or a fixed-width font so the
  digit does not wobble.
- Both stepper buttons are in the enabled state: same opacity,
  same hover affordance class.
- Unit suffix (pt) is part of the readout where applicable.
- Stepper height matches the toggle and segmented controls in
  neighbouring rows.
- Minus / plus buttons read as two distinct controls — not a
  shared widget that toggles.

## Cross-backend expectations

All seven backends. On cocoa expect NSStepper or a +/- button
pair; on android Material number-input style; on ios UIStepper.

## Scoring rubric

- **Visual Polish (9/10)**: shipping-grade stepper.
- **State Clarity**: value, unit, and direction all unambiguous.
- **Accessibility**: standard hit-area floor; numeric value not
  rendered as a placeholder.
