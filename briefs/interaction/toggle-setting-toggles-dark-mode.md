---
briefId: interaction.toggle-setting-toggles-dark-mode
schemaVersion: 1
kind: interaction
title: Toggle Setting Flow — Toggles dark mode
coversPreviews:
  - storyRef: { group: "Toggle Setting Flow", name: "Toggles dark mode", kind: flow, index: 1 }
    backends: [web, tui, gpui, freya, cocoa, android, ios]
captureViewports:
  - { width: 1080, height: 720, label: "tablet" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: clarity,        label: "Step Clarity",       weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: feedback,       label: "Toggle Feedback",    weight: 0.3, scale: { min: 1, max: 10 } }
  - { id: responsiveness, label: "Responsiveness",     weight: 0.3, scale: { min: 1, max: 10 } }
---

# Toggle Setting Flow — Toggles dark mode

> **Status:** Starter brief. Refine the "What to watch for" list as you learn what matters for this story.

## What you're reviewing

User flips the **Dark mode** switch in the Appearance group. The
preview captures the toggle in its new state (off → on or on → off),
and — if the preview pane participates in the theme — the surrounding
chrome re-renders in the corresponding theme.

## What to watch for

- The switch widget shows its new state unambiguously: the thumb has
  travelled fully to the active side, the track colour is filled
  with the accent indigo (or native equivalent on cocoa / ios /
  android).
- If the preview re-renders the theme: every panel surface flipped
  to the new palette consistently — no half-themed regions.
- Switch label ("Dark mode") and hint copy ("Use the system
  preference at startup, then remember the choice") remain readable
  at preview-pane scale.
- No layout reflow during the toggle: row height should be stable.
- Animation: thumb slide should be sub-200 ms, eased (not linear).

## Cross-backend expectations

Native switch idiom varies: web is a styled `div.toggle`; cocoa
uses `NSSwitch`; ios uses `UISwitch`; android uses the Material
switch; TUI uses `[on]` / `[ ]` or `[x]` markers. The semantic
state (on / off) must be readable across all of them.

## Scoring rubric

- **Step Clarity (9/10)**: the switch state is unambiguous in the
  still image. **(5/10)**: state requires close inspection.
  **(2/10)**: the switch is unreadable or mis-aligned.
- **Toggle Feedback**: thumb travel, track colour transition,
  pressed state visibility.
- **Responsiveness**: in animated captures, no perceptible lag
  between click and thumb movement.
