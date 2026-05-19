---
briefId: component.filter-bar-all-selected
schemaVersion: 1
kind: component
title: Task App / FilterBar — All Selected
coversPreviews:
  - storyRef: { group: "Task App / FilterBar", name: "All Selected", kind: component, index: 0 }
    backends: [web, tui, gpui, freya, cocoa, android, ios]
captureViewports:
  - { width: 1080, height: 720, label: "tablet" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: visual,        label: "Visual Polish",   weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: states,        label: "State Clarity",   weight: 0.3, scale: { min: 1, max: 10 } }
  - { id: accessibility, label: "Accessibility",   weight: 0.3, scale: { min: 1, max: 10 } }
---

# Task App / FilterBar — All Selected

> **Status:** Starter brief. Refine the "What to watch for" list as you learn what matters for this story.

## What you're reviewing

The filter bar in its default state: three pills — **All**, **Active**,
**Completed** — with **All** as the active selection (accent fill).
Captured on a transparent / neutral background so the pill states
read clearly.

## What to watch for

- All pill: accent `#7c7aed` background, white text, no border or
  border matching the fill.
- Active / Completed pills: muted neutral text (`#A0A2B0`), subtle
  border or transparent background, no accent fill.
- Pill widths feel equivalent — minimum width ~80 px in the web
  reference so labels don't visibly jump as selection changes.
- Gap between pills is consistent (~6 px on web).
- Pills sit on a shared baseline; no vertical drift.

## Cross-backend expectations

The TUI compositor emits `\x1b[38;2;124;122;237m` truecolor for the
active pill; on cocoa the active pill is the system tint; on ios a
`UISegmentedControl` with selected segment; on android Material's
`SingleChoiceSegmentedButtonRow`.

## Scoring rubric

- **Visual Polish (9/10)**: pill treatment is shipping-grade
  segmented-control quality. **(5/10)**: visibly off-palette or
  default-styled. **(2/10)**: pills are misaligned or unreadable.
- **State Clarity**: the active pill is unambiguous; no risk of
  reading two pills as active.
- **Accessibility**: active-pill text on accent fill meets contrast
  ≥4.5:1 (white on `#7c7aed` is ~5.0:1).
