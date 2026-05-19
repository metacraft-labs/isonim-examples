---
briefId: component.settings-group-editor
schemaVersion: 1
kind: component
title: Settings App / Group — Editor
coversPreviews:
  - storyRef: { group: "Settings App / Group", name: "Editor", kind: component, index: 1 }
    backends: [web, tui, gpui, freya, cocoa, android, ios]
captureViewports:
  - { width: 1080, height: 720, label: "tablet" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: visual,        label: "Visual Polish",   weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: states,        label: "State Clarity",   weight: 0.3, scale: { min: 1, max: 10 } }
  - { id: accessibility, label: "Accessibility",   weight: 0.3, scale: { min: 1, max: 10 } }
---

# Settings App / Group — Editor

> **Status:** Starter brief. Refine the bullets below as you learn what matters most for this story.

## What you're reviewing

The Editor settings group rendered as a single component: header
("EDITOR" uppercase label) followed by three rows — Insert spaces
for tabs toggle, Tab width stepper, Line endings segmented choice.

## What to watch for

- Group header treatment is consistent with Appearance and
  Notifications siblings: uppercase 11px label, 0.08em letter
  spacing, muted color.
- Three rows in declared order; no horizontal jitter from row to
  row.
- Tab width stepper readout is "4" with no doubled-up value
  artifact (the "4 4" regression).
- Line endings segmented control: LF active, CRLF and CR inactive.
- The group reads as a discrete card, not an unbounded list of
  rows.

## Cross-backend expectations

All seven backends. The settings catalog drives all values from the
same VM; idiom variability is the only difference.

## Scoring rubric

- **Visual Polish (9/10)**: group header, row rhythm, and control
  treatments all read as shipping. **(5/10)**: one control looks
  unstyled.
- **State Clarity**: active states on the toggle and the LF pill
  are unambiguous.
- **Accessibility**: header text contrast and control hit areas
  meet the standard bars.
