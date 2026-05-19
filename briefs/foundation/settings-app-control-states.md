---
briefId: foundation.settings-app-control-states
schemaVersion: 1
kind: foundation
title: Settings App / Foundations — Control States
coversPreviews:
  - storyRef: { group: "Settings App / Foundations", name: "Control States", kind: foundation, index: 1 }
    backends: [web]
captureViewports:
  - { width: 800, height: 600, label: "default" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: consistency,   label: "Token Consistency",  weight: 0.5, scale: { min: 1, max: 10 } }
  - { id: documentation, label: "Documentation",      weight: 0.5, scale: { min: 1, max: 10 } }
---

# Settings App / Foundations — Control States

> **Status:** Starter brief. Refine the bullets below as you learn what matters most for this story.

## What you're reviewing

The tonal palette for control states: default, hover, pressed,
disabled. Each state should be rendered against the same shared
control idiom (a pill or a toggle) so the tonal shift is
isolated.

## What to watch for

- Four states rendered in a horizontal strip: default, hover,
  pressed, disabled.
- Each state labelled with its token name.
- Tonal shift between states is monotonic: hover slightly
  brighter than default; pressed slightly darker than default;
  disabled visibly muted (around 40 percent opacity).
- Accent indigo `#7c7aed` participates correctly in the hover
  / pressed states (it should brighten under hover, not shift
  to teal).
- Disabled state retains a hint of structure (border or 1 px
  outline) so it does not vanish.

## Cross-backend expectations

Foundation; web canonical. Native backends use their platform
ripple / highlight system.

## Scoring rubric

- **Token Consistency**: the four states are visibly different
  from each other and consistently applied across all controls.
- **Documentation**: each state has a name and a pixel
  characterisation.
