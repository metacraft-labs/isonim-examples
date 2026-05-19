---
briefId: chrome.story-selected-wide
schemaVersion: 1
kind: chrome
title: Story Selected — wide viewport
coversPreviews:
  - storyRef: { group: "Settings App / Group", name: "Appearance", kind: component, index: 0 }
    backends: [web]
captureViewports:
  - { width: 1920, height: 1080, label: "wide" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: chrome, label: "Editor Chrome", weight: 1.0, scale: { min: 1, max: 10 } }
relatedBriefs: [chrome.story-selected-laptop]
---


## What You're Reviewing

The editor at **1920 × 1080** after clicking through
`Settings App / Group` → `Appearance` in the sidebar. Default
backend is **Web**, default mode is **View**. This brief verifies
the post-M-EVP-6/7/9 chrome bar density at the wide viewport with
a story actively rendered in the preview iframe.

Captured by `editor-screenshot.mjs` view `story-selected` at
viewport `wide`: file `screenshots/story-selected-wide.png`.

## Design Goals

- Sidebar's selected `Appearance` row is highlighted with the
  accent colour border + tinted background (M-EVP-4 invariant).
- Preview iframe renders the **Appearance settings group** through
  the Web backend — visible as a group header, three controls
  (Dark mode toggle / Font size / Theme choice), and demo polish
  reading like a real settings panel.
- Preview pane is the visual centre of the screenshot — chrome bar
  supports it, sidebar + inspector frame it.
- Single chrome bar (M-EVP-6) with three clusters (M-EVP-7); no
  inner per-view toolbar inside the centre column body.

## Color Expectations

- Selected sidebar row: accent-tinted background and a 2-3 px
  left border in the accent colour.
- Iframe content: the Appearance demo's own colour scheme — should
  read as a polished settings UI, not raw HTML.
- Chrome bar's Web chip highlighted with the accent.

## What is Expected on the Screenshot

### Sidebar (left column)

- `[data-sidebar-search="true"]` input + `[data-sidebar-quicknav=
  "true"]` strip at the top with five icons.
- Components section expanded; **Settings App / Group** group
  expanded.
- The story row with `aria-label="Select story Settings App /
  Group / Appearance"` is **selected** — its row carries the M-EVP-4
  accent marker (accent left border + tinted background).

### Centre column

- Exactly one `[data-preview-chrome-bar="true"]` toolbar above the
  preview iframe.
- Three toolbar clusters present: `data-toolbar-cluster="backend"`,
  `data-toolbar-cluster="viewport"`, `data-toolbar-cluster="mode"`.
- The backend chip with `data-preview-backend="web"` carries
  `aria-pressed="true"` and the accent highlight.
- The mode chip with `data-preview-mode="view"` is the active mode.
- Iframe with `body[data-backend="pbWeb"]` and a main element
  whose `data-story` attribute equals `Settings App /
  Group/Appearance`.
- Iframe content shows:
  - A group header reading **Appearance** with a short subtitle /
    description.
  - At least three controls: a **Dark mode** toggle, a **Font size**
    input, and a **Theme** choice (Default / Solarized / Solar /
    Mono).
  - Each control has a left-side label and a right-aligned widget
    on a clear grid.
- NO inner per-view toolbar inside the centre column body
  (M-EVP-6 invariant).
- NO view-switcher anywhere (M-EVP-7).

### Right column

- Inspector panel shows properties / styles for the selected story.
- Hairline border between inspector and centre column.

## What to Evaluate

1. **Sidebar selection cue** — accent border + tinted background
   on the `Appearance` row is unambiguous; selection visual is
   load-bearing and must read at a glance.
2. **Iframe demo polish** — does the Appearance settings group
   look like a showcase example (Polaris / Material 3 / Linear) or
   raw boilerplate? The demos are the editor's reason for existing.
3. **Chrome bar density at wide** — clusters have ≥ 12 px gap
   between them; no cluster looks crowded.
4. **Focal hierarchy** — preview iframe dominates the screenshot;
   chrome + sidebar + inspector frame it without competing.
5. **Spacing** — 4 / 8 px rhythm across sidebar entries and chrome
   chips.
6. **Alignment** — preview iframe horizontally aligned with the
   chrome bar above; no off-by-1 misalignment on the left edge.

## How to Report

- Keep under 250 words.
- **First line:** `Expected elements: present` OR
  `Expected elements: missing-<X>` / `replaced-by-<Y>`.
- Lead with one-sentence aesthetic impression.
- List specific issues with locations.
- End with **1–2 highest-priority fixes**.
- Rate 1–10.
- Call out specifically whether the **Appearance demo** itself looks
  like a polished design-system example.
