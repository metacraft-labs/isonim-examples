---
briefId: chrome.spec-pane-view
schemaVersion: 1
kind: chrome
title: Spec Pane — View mode (TipTap render)
coversPreviews:
  - storyRef: { group: "Task App / Pages", name: "Inbox", kind: page, index: 0 }
    backends: [web]
captureViewports:
  - { width: 1920, height: 1080, label: "wide" }
  - { width: 1440, height: 900,  label: "laptop" }
  - { width: 375,  height: 812,  label: "narrow" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: chrome, label: "Editor Chrome", weight: 1.0, scale: { min: 1, max: 10 } }
relatedBriefs: [chrome.shell-wide, chrome.shell-laptop, chrome.shell-narrow, chrome.spec-pane-comment, chrome.spec-pane-edit]
---


## What You're Reviewing

The editor's **Spec pane in View mode**: the top-bar Surface toggle
is on **Spec**, the mode triplet is on **View**, and the centre
column is replaced by a read-only TipTap render of the active brief's
markdown body. The captured story is **Task App / Pages / Inbox**
(the canonical render brief, `briefs/render/task-app.md`) — its
markdown carries the full CommonMark feature set (H1 → H2 → H3,
bullet + numbered lists, blockquote, fenced code, inline code,
emphasis, links) so the reviewer can score every typographic surface
in one screenshot.

Captured by `editor-screenshot.mjs` view `spec-pane-view` at
viewports `wide` / `laptop` / `narrow`:
files `screenshots/spec-pane-view-{wide,laptop,narrow}.png`.

## Design Goals

- **Typography hierarchy is the focal point.** TipTap's StarterKit
  defaults are CSS-light; the editor's Spec-pane theme should give H1
  vs H2 vs H3 vs body a clear three-tier visual gap. H1 = 28-32 px
  bold; H2 = 22-24 px semibold; H3 = 16-18 px semibold; body = 14 px;
  inline code = 13 px monospace.
- **Comfortable reading line length.** Body paragraphs should target
  60-80 ch (≈ 600-720 px at 14 px body). At the wide viewport this
  means the spec pane has a max-width on the prose container; the
  rest of the centre column's pixel budget is whitespace, not a
  pathological 1800 px-wide single line.
- **Code blocks readable in dark theme.** Inline `code` chips and
  fenced ``` ``` ``` blocks both need clear contrast: a slightly
  lighter background (`#1d1d28` … `#22232e`) on the surrounding canvas
  (`#0f0f14` … `#1a1a2e`); monospace font; 12-13 px size.
- **List indentation rhythm.** Bullet and numbered lists indent in
  4 / 8 / 16 px steps; nested lists shift by exactly one step. No
  hard-left clipping; no excessive 40 px first-line indents.
- **Blockquote treatment.** A left-border accent strip (3-4 px,
  muted accent or muted grey) + slightly muted body text — Linear /
  Notion idiom. NOT a CSS `border: 1px solid grey` box.
- **Whitespace rhythm.** Spacing between headings and following
  paragraphs is generous (≥ 16 px above H2, ≥ 12 px above H3); ≥ 8 px
  between paragraphs. Not cramped, not vertically wasted.
- **Scroll affordance.** Long briefs must scroll within the pane,
  not push the chrome bar off-screen. A standard scrollbar gutter is
  acceptable; a custom-styled scrollbar (Linear / VS Code style) is
  preferred.
- The pane lives in the centre column with the **same chrome bar
  above** as the Preview surface — the top bar's mode triplet should
  read **View** active.

## Color Expectations

- Pane canvas: deep dark gray (`#0f0f14` … `#1a1a2e`).
- Body text: `#e8e9f0` … `#f5f5f7`.
- Secondary text (metadata, blockquote body): `#8b8d98` … `#a0a2b0`.
- Headings: same near-white as body, distinguished by size + weight.
- Inline code: muted-accent foreground (`#7c7cda` … `#a0a0d4`) on a
  one-step-lighter panel surface, OR plain near-white on the same
  panel surface. Avoid jarring red / pink code-chip colours.
- Code blocks: panel-surface background with a 1 px hairline border
  in the divider grey.
- Blockquote accent: a single thin coloured strip on the left edge
  (3-4 px). Either the editor's accent colour or a muted grey.
- Links: editor accent colour (`#7c7cda`) with underline.

## What is Expected on the Screenshot

**The reviewer must verify these elements are present BEFORE evaluating
aesthetics.** If anything expected is missing or replaced by a
placeholder, report that as the first finding and rate ≤ 4/10
regardless of polish.

### Chrome bar (constant)

- The chrome bar above the centre column is mounted (CHRM-M2 four-
  cluster layout: backend / surface / viewport / mode).
- The **Surface** cluster's **Spec** pill (index 1) is active —
  `aria-pressed="true"`.
- The **mode** cluster's **View** pill (index 0) is active.

### Spec-pane surface (centre column body)

- A single `[data-spec-pane-tiptap="true"]` wrapper carries the
  pane. Inside it a `[data-spec-pane-tiptap-host="true"]` host is
  populated by the TipTap editor.
- The host contains rendered markdown — NOT raw markdown source.
  Expect a top-level `<h1>` (the brief title prepended by the
  shell's effect), multiple `<h2>` section headings, at least one
  list, at least one fenced code block, at least one blockquote,
  and at least one inline `<code>` span.
- The pane is read-only: no Save / Cancel button row visible
  (`[data-spec-pane-edit-controls="true"]` carries `display: none`).
- No floating toolbar (the CHRM-M4 toolbar is gated on Edit mode and
  must be absent here).
- No comment popover (`[data-spec-comment-popover]` is absent or
  hidden — Comment mode is not active).

### Negative expectations

- No raw `# Heading` / `**bold**` markdown source visible — that would
  mean the TipTap mount failed and the fallback `setTextContent` ran.
- No "No brief available for the selected story." placeholder text.

### Viewport notes

- `wide` (1920×1080): full three-panel shell + spec pane; prose
  surface targets 60-80ch comfortable line length.
- `laptop` (1440×900): same three-panel shell; prose surface may sit
  narrower but the line length should still feel comfortable.
- `narrow` (375×812): sidebar may collapse; the spec pane occupies
  the visible centre column. Headings should not wrap awkwardly;
  body text must be at least 13 px.

## What to Evaluate

After confirming presence of every expected element above, evaluate:

1. **Typography hierarchy** — H1 > H2 > H3 > body is unambiguous at
   a glance. Each tier carries a clear visual jump in size + weight.
2. **Line length** — body paragraphs in the 60-80ch ideal range at
   the wide viewport (no 1800 px single lines, no comically narrow
   columns).
3. **Code-block contrast** — fenced code blocks pop from the canvas
   without being garish. Monospace is present and consistent.
4. **Inline code chip treatment** — readable in flowing prose,
   visually distinct from the surrounding body text.
5. **List indentation** — bullet + numbered lists indent on a 4/8/16
   px rhythm; nested lists shift one step; no overhang past the
   prose container.
6. **Blockquote** — clearly distinguishable from body paragraphs;
   left-border accent strip rather than a box border.
7. **Whitespace rhythm** — heading-to-paragraph gaps generous;
   inter-paragraph gaps consistent; no cramped or floating-in-space
   content.
8. **Scroll affordance** — a scrollbar appears (custom-styled is
   preferred); the chrome bar above stays sticky.
9. **Reactive surface fidelity** — Surface=Spec + Mode=View should
   read consistently with the chrome bar's active pills.

## How to Report

- Keep under 250 words.
- **First line:** `Expected elements: present` OR
  `Expected elements: missing-<X>` / `replaced-by-<Y>`.
- If any expected element is missing or wrong, report it as the first
  finding and rate ≤ 4/10 regardless of polish elsewhere.
- Otherwise, lead with a one-sentence overall aesthetic impression.
- List specific issues as bullet points with locations + pixel
  prescriptions (e.g. "H2 looks identical to H1 at the same size;
  drop H2 to 22 px / 600 weight, keep H1 at 28 px / 700").
- End with **1-2 highest-priority fixes** the implementer should
  do first, each as a pixel-level prescription.
- Rate 1-10 (calibration: 1-3 = broken, 4-5 = functional rough,
  6-7 = good with minor issues, 8-9 = near-shipping, 10 = perfect).
- Be direct and specific. Avoid vague aesthetic language ("looks
  cramped"); give measurements.
