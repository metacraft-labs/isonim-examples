---
briefId: component.choice-item-alternate
schemaVersion: 1
kind: component
title: Settings App / ChoiceItem — Alternate
coversPreviews:
  - storyRef: { group: "Settings App / ChoiceItem", name: "Alternate", kind: component, index: 1 }
    backends: [web, tui, gpui, freya, cocoa, android, ios]
captureViewports:
  - { width: 1080, height: 720, label: "tablet" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: visual,        label: "Visual Polish",   weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: states,        label: "State Clarity",   weight: 0.3, scale: { min: 1, max: 10 } }
  - { id: accessibility, label: "Accessibility",   weight: 0.3, scale: { min: 1, max: 10 } }
---

# Settings App / ChoiceItem — Alternate

> **Status:** Starter brief. Refine the bullets below as you learn what matters most for this story.

## What you're reviewing

A choice setting row with the second option (Solarized) selected.
This exercises the active-pill shift away from the leading edge
to the middle position.

## What to watch for

- Solarized pill carries the accent fill at the middle position.
- Default + Dracula pills inactive; they match each other exactly.
- The active pill's left and right neighbours have symmetric
  visual weight (no perceived crowding on either side).
- Pill widths remain equivalent; the active state did not visibly
  resize the Solarized pill.
- Selection change from Default to Solarized should look like a
  pure horizontal shift of the accent fill — nothing else moved.

## Cross-backend expectations

All seven backends. On a dropdown-style native control, the popup
shows Solarized as the displayed value.

## Scoring rubric

- **Visual Polish (9/10)**: pill rhythm intact at the middle
  position.
- **State Clarity**: middle-selection is unambiguous.
- **Accessibility**: contrast unchanged from the default sibling.
