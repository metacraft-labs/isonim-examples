---
briefId: pattern.form-with-inline-error
schemaVersion: 1
kind: pattern
title: Patterns — Form With Inline Error
coversPreviews:
  - storyRef: { group: "Patterns", name: "Form With Inline Error", kind: pattern, index: 0 }
    backends: [web, tui, gpui, freya, cocoa, android, ios]
captureViewports:
  - { width: 1080, height: 720, label: "tablet" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: visual,      label: "Visual Polish", weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: reusability, label: "Reusability",   weight: 0.3, scale: { min: 1, max: 10 } }
  - { id: clarity,     label: "Clarity",       weight: 0.3, scale: { min: 1, max: 10 } }
---

# Patterns — Form With Inline Error

> **Status:** Starter brief. Refine the bullets below as you learn what matters most for this story.

## What you're reviewing

A form-input pattern where validation has failed and the inline
error message renders directly underneath the input. The pattern
is a cross-app shared composition; both the task input and the
settings number item could reuse it.

## What to watch for

- Error message colour is a clear danger / error tint (not the
  brand indigo) — a desaturated red around #E5484D is typical;
  must not be a pure red `#FF0000`.
- The input itself carries an error treatment: a red border, a
  red focus ring, or a small leading icon.
- Error copy is one short line, sentence-case, ends without a
  period (microcopy norm).
- Spacing between input and error message: 4 to 6 px.
- Tab / focus order: after submitting, focus should land on the
  errored input (announce in description if the still capture
  cannot show this).

## Cross-backend expectations

All seven backends. Error-state idiom varies: cocoa has
NSAttributedString in red; ios `UILabel` red; android Material
helper-text style; TUI uses an ANSI red SGR.

## Scoring rubric

- **Visual Polish (9/10)**: error state reads as intentional,
  not destructive.
- **Reusability**: the pattern should slot into any input
  (TaskInput, NumberItem) without retooling.
- **Clarity**: error copy and treatment are immediately legible.
