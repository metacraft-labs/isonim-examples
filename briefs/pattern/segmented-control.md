---
briefId: pattern.segmented-control
schemaVersion: 1
kind: pattern
title: Patterns — Segmented Control
coversPreviews:
  - storyRef: { group: "Patterns", name: "Segmented Control", kind: pattern, index: 2 }
    backends: [web, tui, gpui, freya, cocoa, android, ios]
captureViewports:
  - { width: 1080, height: 720, label: "tablet" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: visual,      label: "Visual Polish", weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: reusability, label: "Reusability",   weight: 0.3, scale: { min: 1, max: 10 } }
  - { id: clarity,     label: "Clarity",       weight: 0.3, scale: { min: 1, max: 10 } }
---

# Patterns — Segmented Control

> **Status:** Starter brief. Refine the bullets below as you learn what matters most for this story.

## What you're reviewing

A radio-style group rendered as horizontally adjacent pills with
one active selection. This is the shared pattern used by both the
task-app filter bar and the settings-app choice item.

## What to watch for

- All pills have equal width — the longest label sets the minimum.
- Active pill carries the accent fill; inactive pills are visibly
  inactive but not greyed-out (they remain interactive).
- Pill cluster has a 1-px hairline border or a subtle background
  to read as a single segmented control, not three separate
  buttons.
- Spacing between pills is consistent (0 px overlap or a small
  internal gap; pick one and stay consistent).
- Focus / keyboard navigation: visible focus ring on whichever
  pill has focus, even when it is not the active one.

## Cross-backend expectations

All seven backends. The pattern is the canonical reference for
both FilterBar and ChoiceItem; verify both consumers use it
consistently.

## Scoring rubric

- **Visual Polish (9/10)**: shipping-grade segmented control.
- **Reusability**: drop-in replacement for any radio-style group.
- **Clarity**: active selection is unambiguous; inactive options
  are clearly interactive.
