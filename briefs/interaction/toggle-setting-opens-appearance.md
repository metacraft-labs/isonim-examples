---
briefId: interaction.toggle-setting-opens-appearance
schemaVersion: 1
kind: interaction
title: Toggle Setting Flow — Opens Appearance group
coversPreviews:
  - storyRef: { group: "Toggle Setting Flow", name: "Opens Appearance group", kind: flow, index: 0 }
    backends: [web, tui, gpui, freya, cocoa, android, ios]
captureViewports:
  - { width: 1080, height: 720, label: "tablet" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: clarity,        label: "Step Clarity",       weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: feedback,       label: "Navigation Feedback", weight: 0.3, scale: { min: 1, max: 10 } }
  - { id: responsiveness, label: "Responsiveness",     weight: 0.3, scale: { min: 1, max: 10 } }
---

# Toggle Setting Flow — Opens Appearance group

> **Status:** Starter brief. Refine the "What to watch for" list as you learn what matters for this story.

## What you're reviewing

Opening step of the settings flow: user selects the **Appearance**
section from the settings sidebar (or accordion header on TUI /
Android card). The preview captures the Appearance group expanded,
showing dark mode toggle, theme choice, and font size stepper.

## What to watch for

- The Appearance sidebar entry / accordion header is visibly active
  (accent border, filled background, or expanded chevron) — clearly
  distinct from the inactive Editor / Notifications entries.
- The Appearance content area is fully populated: dark mode toggle,
  theme choice (Default / Solarized / Dracula), font size stepper.
- No flash of empty content while the section is being expanded.
- Sibling sections (Editor / Notifications) are collapsed or
  de-emphasised — the focal point is Appearance.
- On Freya the layout is a stacked card; on TUI it's an expanded
  accordion section; on web it's a sidebar selection + content
  swap. All show the same three items.

## Cross-backend expectations

The settings catalog is shared (`buildDemoSettingsCatalog`), so all
backends MUST render the same three Appearance items (`dark_mode`,
`theme`, `font_size`) in the same order.

## Scoring rubric

- **Step Clarity (9/10)**: a reviewer can name the section and read
  every item label. **(5/10)**: section is visible but item labels
  are cramped or cropped. **(2/10)**: section is unclear or content
  area is empty.
- **Navigation Feedback**: how visibly the Appearance entry
  signals its active state.
- **Responsiveness**: no loading spinners; settings should be
  instantaneous from the local catalog.
