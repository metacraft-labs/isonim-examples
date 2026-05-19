---
briefId: pattern.list-with-empty-state
schemaVersion: 1
kind: pattern
title: Patterns — List With Empty State
coversPreviews:
  - storyRef: { group: "Patterns", name: "List With Empty State", kind: pattern, index: 1 }
    backends: [web, tui, gpui, freya, cocoa, android, ios]
captureViewports:
  - { width: 1080, height: 720, label: "tablet" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: visual,      label: "Visual Polish", weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: reusability, label: "Reusability",   weight: 0.3, scale: { min: 1, max: 10 } }
  - { id: clarity,     label: "Clarity",       weight: 0.3, scale: { min: 1, max: 10 } }
---

# Patterns — List With Empty State

> **Status:** Starter brief. Refine the bullets below as you learn what matters most for this story.

## What you're reviewing

A reusable empty-state pattern for any list or grid: illustrative
glyph, headline, secondary copy, and a primary CTA pointing to
the action that would populate the list.

## What to watch for

- Glyph size is balanced with the copy — not gigantic, not a
  pinprick.
- Glyph stroke / color is a desaturated accent (the indigo at
  about 40 percent opacity) so it does not steal focus from the
  CTA.
- Vertical centring within the available list area; not pinned to
  the top.
- Headline plus secondary copy follows a clear 2-tier hierarchy.
- Primary CTA uses the accent fill; sentence-case label.
- No empty-state-looks-like-loading ambiguity (no spinner, no
  skeleton bars).

## Cross-backend expectations

All seven backends. TUI renders the glyph as a small ASCII /
Unicode character; native backends use the SVG-style symbol.

## Scoring rubric

- **Visual Polish (9/10)**: empty-state reads as intentional UX
  design.
- **Reusability**: pattern slots into TaskList, SettingsGroup, or
  any future list without refactoring.
- **Clarity**: a glance tells the reviewer what to do next.
