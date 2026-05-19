---
briefId: interaction.toggle-setting-adjusts-font-size
schemaVersion: 1
kind: interaction
title: Toggle Setting Flow — Adjusts font size
coversPreviews:
  - storyRef: { group: "Toggle Setting Flow", name: "Adjusts font size", kind: flow, index: 2 }
    backends: [web, tui, gpui, freya, cocoa, android, ios]
captureViewports:
  - { width: 1080, height: 720, label: "tablet" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: clarity,        label: "Step Clarity",       weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: feedback,       label: "Stepper Feedback",   weight: 0.3, scale: { min: 1, max: 10 } }
  - { id: responsiveness, label: "Clamp Behaviour",    weight: 0.3, scale: { min: 1, max: 10 } }
---

# Toggle Setting Flow — Adjusts font size

> **Status:** Starter brief. Refine the "What to watch for" list as you learn what matters for this story.

## What you're reviewing

User uses the **Font size** stepper (`[-] N [+]`) to attempt going
below the minimum (clamped) and then reaches `18 pt`. The preview
captures the stepper at a representative value with clamp behaviour
demonstrated: the minus button should be disabled / visibly inert
when at the floor.

## What to watch for

- Stepper readout shows the units (`pt`) — not a bare integer that
  could be mistaken for "18" of something unspecified.
- Disabled / inert state for the minus button at min: lower opacity,
  no hover affordance, or visibly greyed out.
- Numeric font: tabular-nums or fixed-width digits so the value
  doesn't jump horizontally as digits change (`9` vs `10`).
- The `+` button has a hover / pressed state distinct from the `-`
  button.
- Stepper alignment with adjacent rows (dark-mode toggle, theme
  choice) — the stepper height should match the toggle / pill row
  height so the rhythm is preserved.

## Cross-backend expectations

The web preview uses the in-document `.stepper` style; cocoa /
android / ios should use native stepper widgets (`NSStepper`,
Material `+/-` buttons, iOS `UIStepper`). TUI shows `[-] 18 pt [+]`
as a plain text row.

## Scoring rubric

- **Step Clarity (9/10)**: value, unit, and direction (which arrow
  goes up) are all unambiguous. **(5/10)**: value is readable but
  unit or direction is ambiguous. **(2/10)**: stepper is unreadable
  or misaligned.
- **Stepper Feedback**: button visual treatment, value transition
  smoothness.
- **Clamp Behaviour**: disabled-state styling when at min/max
  boundary is visibly distinct.
