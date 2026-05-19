---
briefId: component.toggle-item-off
schemaVersion: 1
kind: component
title: Settings App / ToggleItem — Off
coversPreviews:
  - storyRef: { group: "Settings App / ToggleItem", name: "Off", kind: component, index: 0 }
    backends: [web, tui, gpui, freya, cocoa, android, ios]
captureViewports:
  - { width: 1080, height: 720, label: "tablet" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: visual,        label: "Visual Polish",   weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: states,        label: "State Clarity",   weight: 0.3, scale: { min: 1, max: 10 } }
  - { id: accessibility, label: "Accessibility",   weight: 0.3, scale: { min: 1, max: 10 } }
---

# Settings App / ToggleItem — Off

> **Status:** Starter brief. Refine the bullets below as you learn what matters most for this story.

## What you're reviewing

A single toggle item in the off position: label on the left, hint
copy below the label, switch widget on the right with the thumb at
the leading edge and the track in its neutral / muted state.

## What to watch for

- Switch track in the off state is a muted neutral (web reference
  uses `#2A2C3A`); the accent indigo is NOT applied.
- Thumb is fully at the leading edge — no halfway / indeterminate
  position.
- Label and hint typography hierarchy: title at 13px medium-weight,
  hint at 11px muted.
- Row height matches the on-state sibling brief exactly (no
  vertical jitter when the state changes).
- Hit area for the switch is large enough on touch backends (at
  least 44 by 44 pixel target on iOS).

## Cross-backend expectations

All seven backends. Switch idiom varies: web is a CSS pill; cocoa
NSSwitch; ios UISwitch; android Material switch; TUI uses an ASCII
indicator like `[ ]`.

## Scoring rubric

- **Visual Polish (9/10)**: switch reads as a shipping platform
  control. **(5/10)**: switch looks unstyled or off-palette.
- **State Clarity**: off state is unambiguous and distinct from
  the on sibling brief.
- **Accessibility**: 4.5 to 1 contrast on label and hint; hit area
  meets the platform bar.
