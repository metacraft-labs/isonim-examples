---
briefId: component.toggle-item-on
schemaVersion: 1
kind: component
title: Settings App / ToggleItem — On
coversPreviews:
  - storyRef: { group: "Settings App / ToggleItem", name: "On", kind: component, index: 1 }
    backends: [web, tui, gpui, freya, cocoa, android, ios]
captureViewports:
  - { width: 1080, height: 720, label: "tablet" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: visual,        label: "Visual Polish",   weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: states,        label: "State Clarity",   weight: 0.3, scale: { min: 1, max: 10 } }
  - { id: accessibility, label: "Accessibility",   weight: 0.3, scale: { min: 1, max: 10 } }
---

# Settings App / ToggleItem — On

> **Status:** Starter brief. Refine the bullets below as you learn what matters most for this story.

## What you're reviewing

A toggle item in the on position: switch track filled with the
accent indigo, thumb fully at the trailing edge. Same label / hint
typography as the off sibling.

## What to watch for

- Track fill is the accent indigo `#7c7aed` (not pure white, not
  navy).
- Thumb fully translated to the trailing edge; no halfway state.
- Track-to-thumb contrast keeps the thumb visible against the
  accent fill.
- Pressed / hover state if rendered: subtle tint, not a full
  brightening of the track.
- Same row height as the off sibling.

## Cross-backend expectations

All seven backends. The cocoa NSSwitch on-state may use the system
accent (not necessarily IsoNim indigo) — document the gap if it
deviates noticeably.

## Scoring rubric

- **Visual Polish (9/10)**: shipping-grade on state.
- **State Clarity**: on vs off is immediate.
- **Accessibility**: thumb-on-accent contrast at least 3 to 1.
