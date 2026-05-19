---
briefId: component.choice-item-default
schemaVersion: 1
kind: component
title: Settings App / ChoiceItem — Default
coversPreviews:
  - storyRef: { group: "Settings App / ChoiceItem", name: "Default", kind: component, index: 0 }
    backends: [web, tui, gpui, freya, cocoa, android, ios]
captureViewports:
  - { width: 1080, height: 720, label: "tablet" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: visual,        label: "Visual Polish",   weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: states,        label: "State Clarity",   weight: 0.3, scale: { min: 1, max: 10 } }
  - { id: accessibility, label: "Accessibility",   weight: 0.3, scale: { min: 1, max: 10 } }
---

# Settings App / ChoiceItem — Default

> **Status:** Starter brief. Refine the bullets below as you learn what matters most for this story.

## What you're reviewing

A choice (enum) setting row with the first option selected. The
component is rendered as a pill-segmented control on web (three
pills with the first carrying the accent fill) or a dropdown on
native backends. The seeded story is theme = Default.

## What to watch for

- The Default pill carries the accent fill; Solarized and Dracula
  pills are inactive.
- Pill widths are equivalent; longest label (Solarized) sets the
  minimum.
- On native backends, the dropdown / popup button displays Default
  as the current value; the chevron / disclosure is on the
  trailing edge.
- Label and hint typography matches the toggle and stepper rows.
- Row height matches sibling rows.

## Cross-backend expectations

All seven backends. The pill segmented control on web differs from
the cocoa NSPopUpButton, the ios UISegmentedControl, and the
android dropdown menu; information equivalence is the contract.

## Scoring rubric

- **Visual Polish (9/10)**: choice control reads as shipping.
- **State Clarity**: active option is immediate.
- **Accessibility**: standard contrast and hit-area floor.
