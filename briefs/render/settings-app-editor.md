---
briefId: render.settings-app-editor
schemaVersion: 1
kind: render
title: Settings App / Pages — Editor Group
coversPreviews:
  - storyRef: { group: "Settings App / Pages", name: "Editor Group", kind: page, index: 2 }
    backends: [web, tui, gpui, freya, cocoa, android, ios]
captureViewports:
  - { width: 1920, height: 1080, label: "wide" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: chrome,    label: "Editor Chrome",  weight: 0.4, scale: { min: 1, max: 10 } }
  - { id: rendering, label: "App Rendering",  weight: 0.6, scale: { min: 1, max: 10 } }
relatedBriefs: [render.settings-app, render.settings-app-appearance]
---

# Settings App / Pages — Editor Group

> **Status:** Starter brief. Refine the "What to watch for" list as you learn what matters for this story.

## What you're reviewing

The **Editor** single-group page of the settings app, captured per
backend at 1920×1080. Shows three rows: **Insert spaces for tabs**
toggle (on), **Tab width** stepper (default 4), **Line endings**
segmented choice (LF / CRLF / CR; LF active).

## What to watch for

- Three rows in the order Insert spaces for tabs → Tab width →
  Line endings.
- Tab-width stepper readout is `4` (or the equivalent integer) —
  watch for the "4 4" doubling regression flagged in the catalog
  comments. The bare `<input class="number">` rendering must be
  replaced with the explicit `[-] N [+]` stepper.
- Line endings choice shows three options; LF is the selected pill.
- "Insert spaces for tabs" toggle is in the on position.
- All three control idioms (toggle / stepper / segmented) are
  visibly distinct from each other and consistent with the
  Appearance group's idioms.

## Cross-backend expectations

Editor settings are the same across backends; native idiom varies.
On TUI, the line-endings pill collapses to `[*LF] CRLF CR`; on
cocoa the segmented control is `NSSegmentedControl`; etc.

## Scoring rubric

- **Editor Chrome score**: same scale as `render.settings-app`.
- **App Rendering score**: 10/10 requires correct values + state
  + render-quality.
