---
briefId: component.settings-group-notifications
schemaVersion: 1
kind: component
title: Settings App / Group — Notifications
coversPreviews:
  - storyRef: { group: "Settings App / Group", name: "Notifications", kind: component, index: 2 }
    backends: [web, tui, gpui, freya, cocoa, android, ios]
captureViewports:
  - { width: 1080, height: 720, label: "tablet" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: visual,        label: "Visual Polish",   weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: states,        label: "State Clarity",   weight: 0.3, scale: { min: 1, max: 10 } }
  - { id: accessibility, label: "Accessibility",   weight: 0.3, scale: { min: 1, max: 10 } }
---

# Settings App / Group — Notifications

> **Status:** Starter brief. Refine the bullets below as you learn what matters most for this story.

## What you're reviewing

The Notifications settings group: header plus three rows — Play
sounds toggle (on), Show badges toggle (off), Poll interval stepper
(default 5 s, displayed as "5 s" via the humanised formatter).

## What to watch for

- Two toggles in different positions (one on, one off) — verify
  the on/off difference is immediate to read.
- Poll interval readout uses the humanised format ("5 s" not
  "5000 ms"); but the underlying catalog value is in ms.
- The toggle thumb travel for the on state aligns with the
  Appearance group's Dark mode toggle exactly (same thumb size,
  travel distance, color).
- Hint copy under each title is muted and clipped consistently.
- Group header NOTIFICATIONS matches the Appearance and Editor
  group headers byte-for-byte in styling.

## Cross-backend expectations

All seven backends. The humanised display formatter is a shared
helper; verify each backend exposes the same display string.

## Scoring rubric

- **Visual Polish (9/10)**: matches the other two groups perfectly
  in rhythm and treatment. **(5/10)**: a single inconsistency vs
  Appearance/Editor.
- **State Clarity**: on vs off on the two toggles is unambiguous;
  the stepper readout is unambiguous.
- **Accessibility**: hit-areas meet the standard bar.
