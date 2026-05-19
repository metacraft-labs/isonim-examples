---
briefId: component.task-input-empty
schemaVersion: 1
kind: component
title: Task App / TaskInput — Empty
coversPreviews:
  - storyRef: { group: "Task App / TaskInput", name: "Empty", kind: component, index: 0 }
    backends: [web, tui, gpui, freya, cocoa, android, ios]
captureViewports:
  - { width: 1080, height: 720, label: "tablet" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: visual,        label: "Visual Polish",   weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: states,        label: "State Clarity",   weight: 0.3, scale: { min: 1, max: 10 } }
  - { id: accessibility, label: "Accessibility",   weight: 0.3, scale: { min: 1, max: 10 } }
---

# Task App / TaskInput — Empty

> **Status:** Starter brief. Refine the "What to watch for" list as you learn what matters for this story.

## What you're reviewing

The task-input component in its **empty** resting state: no draft
text typed, placeholder copy (`New task… (press Enter to add)`)
visible, and the accompanying **Add Task** primary button at the
trailing edge.

## What to watch for

- Placeholder colour is a muted neutral (`#A0A2B0` family) — readable
  but visibly secondary to a typed value would be.
- Placeholder copy alignment is left-aligned, vertically centred.
- The leading `+` glyph (or backend-equivalent icon) is balanced with
  the placeholder text — no excessive gap, no overlap.
- The trailing **Add Task** button is in its primary-CTA treatment:
  accent `#7c7aed` fill, white text, sufficient padding.
- The component's outer border / background combination yields a
  visibly elevated card (not a floating bare `<input>`).
- No focus ring in the empty state (component is unfocused here).

## Cross-backend expectations

Component-level brief; all seven backends participate to verify
cross-renderer parity. Idiom differs: cocoa = `NSTextField` with
trailing `NSButton`; android = Material `OutlinedTextField` +
filled button; ios = `UITextField` + tinted `UIButton`.

## Scoring rubric

- **Visual Polish (9/10)**: card composition, button treatment, and
  placeholder copy all read as production-grade. **(5/10)**: one
  element clearly amateur — e.g. UA-default button. **(2/10)**: the
  component looks unstyled or broken.
- **State Clarity**: empty state is unambiguous and the affordances
  (input vs submit) are visually distinct.
- **Accessibility**: placeholder contrast against background meets
  ≥4.5:1; button hit area ≥ 24×24 px on touch backends.
