---
briefId: chrome.spec-pane-comment
schemaVersion: 1
kind: chrome
title: Spec Pane — Comment mode with popover open
coversPreviews:
  - storyRef: { group: "Task App / Pages", name: "Inbox", kind: page, index: 0 }
    backends: [web]
captureViewports:
  - { width: 1920, height: 1080, label: "wide" }
  - { width: 1440, height: 900,  label: "laptop" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: chrome, label: "Editor Chrome", weight: 1.0, scale: { min: 1, max: 10 } }
relatedBriefs: [chrome.shell-wide, chrome.spec-pane-view, chrome.spec-pane-edit]
---


## What You're Reviewing

The editor's **Spec pane in Comment mode** with the comment popover
**open** and anchored to a real TipTap text selection. The top-bar
Surface toggle is on **Spec**, the mode triplet is on **Comment**.
The screenshot tool programmatically selects a paragraph in the
rendered TipTap DOM so the popover opens at its natural position
without keyboard interaction.

The captured story is **Task App / Pages / Inbox** — same brief body
as `spec-pane-view`, so the underlying prose rendering should be
unchanged. What this brief evaluates is the popover overlay + the
selection highlight on the underlying TipTap surface.

Captured by `editor-screenshot.mjs` view `spec-pane-comment` at
viewports `wide` / `laptop`:
files `screenshots/spec-pane-comment-{wide,laptop}.png`.

## Design Goals

- **Popover positioning is well-anchored.** The popover anchors to
  the text selection's bounding rect. It must not float visually
  detached from the selection (a 100 px gap between selection and
  popover reads as a positioning bug). 6 px below the selection
  is the current shipping value; the popover may flip above the
  selection when there isn't enough room below (Linear /
  Notion / Slack convention).
- **Popover chrome is calm.** A 1 px hairline border (not heavy),
  a moderate drop shadow (`0 4px 16px rgba(0,0,0,0.4)` is the
  current value — verify it doesn't dominate the surface), and a
  6 px border radius. No bright outlines; no neon glow. The arrow
  pointing at the selection is optional — most editors omit it now.
- **Textarea sized for a quick comment.** 3 rows tall by default,
  resize-vertical, ≥ 240 px wide. Comfortable padding (6 / 8 px)
  inside the input.
- **Preview-of-selection chip.** A muted block at the top of the
  popover that shows a small italic preview of the selected text,
  ellipsised. Differentiates the "what you're commenting on" from
  the "what you're typing".
- **Submit + Cancel button treatment.** Two buttons right-aligned;
  Submit is the primary action (filled accent); Cancel is the
  secondary action (outline/ghost). Both ≥ 24 px touch height.
- **Underlying TipTap selection highlight must be visible** through
  the popover — the user needs to see what they're commenting on.
  Browser default selection highlight (`::selection`) is acceptable;
  a custom highlight that survives blur-on-popover-open is better.
- The pane lives in the centre column with the **same chrome bar
  above** — Surface = Spec, Mode = Comment.

## Color Expectations

- Popover canvas: `#1A1B25` (one step lighter than the spec pane
  canvas).
- Popover border: `#2F3140` (the same divider grey as the chrome).
- Popover text: `#D5D6DB` primary.
- Preview-of-selection background: one step darker (`#0F0F18`),
  left-border accent (`#7C7CDA`).
- Textarea: same dark surface as the selection preview, 1 px border
  in `#2F3140`, focus outline none (or a clearer accent ring).
- Submit button: filled accent `#7C7CDA`, white text.
- Cancel button: transparent background, muted grey text + 1 px
  border.

## What is Expected on the Screenshot

**The reviewer must verify these elements are present BEFORE evaluating
aesthetics.** If anything expected is missing or replaced by a
placeholder, report that as the first finding and rate ≤ 4/10
regardless of polish.

### Chrome bar (constant)

- Chrome bar above the centre column mounted as in `spec-pane-view`.
- The **Surface** cluster's **Spec** pill (index 1) is active.
- The **mode** cluster's **Comment** pill (index 1) is active —
  `aria-pressed="true"`.

### Spec-pane surface

- `[data-spec-pane-tiptap-host="true"]` host carries the rendered
  brief markdown — same TipTap content as `spec-pane-view`.
- A real text selection is visible on the rendered prose (the
  paragraph contents are highlighted by the browser's default
  `::selection` styling, with a translucent accent / blue overlay).

### Comment popover

- A `[data-spec-comment-popover]` overlay is mounted and **visible**
  (`display: flex`). Position is anchored to the selection — the
  popover's left edge tracks the selection's left edge; the popover's
  top is at the selection's bottom + 6 px (or flipped above when
  near the bottom of the viewport).
- The popover carries (top to bottom):
  1. A `[data-spec-comment-popover-preview]` block showing an
     italic, muted preview of the selected text.
  2. A `[data-spec-comment-popover-input]` textarea (3 rows,
     placeholder `Comment on the selected text...`).
  3. (Hidden by default) a
     `[data-spec-comment-popover-error]` row — should NOT be visible
     in the happy-path screenshot.
  4. A button row with two right-aligned buttons:
     `[data-spec-comment-popover-cancel]` (Cancel) and
     `[data-spec-comment-popover-submit]` (Submit).

### Negative expectations

- No comment popover error visible.
- No formatting toolbar (CHRM-M4 is Edit-only).

## What to Evaluate

After confirming presence of every expected element above, evaluate:

1. **Anchoring** — popover is unambiguously associated with the
   selection (≤ 12 px gap between the selection rect bottom and the
   popover top edge; left edges aligned within ~8 px).
2. **Chrome calmness** — 1 px hairline border + moderate shadow, no
   harsh outlines. The popover reads as floating over the spec pane,
   not blasting out of it.
3. **Selection-preview readability** — italic + muted differentiates
   it from the input below. Ellipsis fires cleanly on long
   selections; no overflow leaks.
4. **Textarea ergonomics** — comfortable padding, 3-row default
   height; resize handle visible (corner) but not obtrusive.
5. **Submit / Cancel hierarchy** — Submit (accent fill) is the
   visually heavier button; Cancel is the lighter secondary action.
   Spacing between them ≥ 8 px; right-aligned within the popover.
6. **Type weight** — popover text reads at 11-12 px; secondary text
   doesn't dip below 10 px legibility floor.
7. **Selection visibility under popover** — the user can still see
   what they highlighted; selection highlight is not lost.
8. **Surface harmony** — popover colour palette reads as part of the
   editor design system (matches the chrome bar's ChoiceGroup pills,
   not foreign).

## How to Report

- Keep under 250 words.
- **First line:** `Expected elements: present` OR
  `Expected elements: missing-<X>` / `replaced-by-<Y>`.
- If any expected element is missing or wrong, report it as the first
  finding and rate ≤ 4/10 regardless of polish elsewhere.
- Lead with a one-sentence overall aesthetic impression.
- List specific issues with selectors and pixel prescriptions.
- End with **1-2 highest-priority fixes** as pixel-level prescriptions.
- Rate 1-10 with the calibration scale.
- Be specific about positioning (call out exact px offsets where you
  see them).
