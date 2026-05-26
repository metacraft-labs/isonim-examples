---
briefId: chrome.spec-pane-edit
schemaVersion: 1
kind: chrome
title: Spec Pane — Edit mode with CHRM-M4 formatting toolbar
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
relatedBriefs: [chrome.shell-wide, chrome.spec-pane-view, chrome.spec-pane-comment]
---


## What You're Reviewing

The editor's **Spec pane in Edit mode** with the **CHRM-M4 formatting
toolbar** visible above the TipTap editable surface. The top-bar
Surface toggle is on **Spec**, the mode triplet is on **Edit**, and
the TipTap host is editable. The captured story is **Task App /
Pages / Inbox** so the editable content is the rendered brief
markdown.

CHRM-M4 ships a fixed-toolbar (Linear-style) variant: a single
toolbar mounted above the editor host, always visible while Edit
mode is active. It groups buttons by function with thin vertical
separators between groups.

Captured by `editor-screenshot.mjs` view `spec-pane-edit` at viewports
`wide` / `laptop` / `narrow`:
files `screenshots/spec-pane-edit-{wide,laptop,narrow}.png`.

## Design Goals

- **Compact, dense toolbar.** Linear's editor toolbar is ~32 px
  tall total; the CHRM-M4 implementation is ~28-32 px. Pills should
  feel tight without becoming illegible. 26 px button width, 22 px
  height, 11 px / 600-weight font on glyphs.
- **Group separators are visible but quiet.** A 1 px vertical
  hairline 16 px tall in the divider grey (`#2D2D3A`) between each
  group, with 6 px horizontal margins. Not a heavy column rule.
- **Active-state pills read clearly.** When the user's caret is in
  bold text, the Bold button must visibly look "pressed" — accent
  fill (`#3B82F6`) on the button with white glyph; `aria-pressed
  ="true"` for screen readers.
- **Heading dropdown is a ChoiceGroup chevron-popup.** Reads as
  same widget family as the chrome bar's viewport cluster.
- **Group ordering matches CommonMark feature density.** Heading
  dropdown → inline marks (Bold / Italic / Strike / Code) →
  Link → Lists (Bullet / Ordered) → Block (Blockquote / CodeBlock /
  Horizontal rule) → History (Undo / Redo).
- **Tooltip rendering.** Each icon button carries a `title=` with
  the keyboard shortcut. Tooltips appear on hover with the OS
  default tooltip styling — this is acceptable; a custom dark
  tooltip is preferred but not required for CHRM-M3.
- **The toolbar is full-width above the editor**, sharing the same
  horizontal padding as the prose below.
- The chrome bar above remains unchanged — only the centre column's
  spec-pane subtree gains the toolbar.

## Color Expectations

- Toolbar background: `#15151C` (one step darker than the spec pane
  surface, providing a subtle stripe).
- Toolbar border: `#2D2D3A`, 1 px, 6 px border radius.
- Idle button glyph: `#A0A2B0` (muted grey).
- Active button: filled `#3B82F6` background, white glyph.
- Group separator: `#2D2D3A`, 1 px, 16 px tall.
- Heading-dropdown trigger: transparent background, 1 px border in
  divider grey; chevron icon at the right.
- Heading-dropdown popup: `#151D2E` background, 1 px `#334155`
  border, 6 px radius, `0 8px 24px rgba(0,0,0,0.28)` shadow.

## What is Expected on the Screenshot

**The reviewer must verify these elements are present BEFORE evaluating
aesthetics.** If anything expected is missing or replaced by a
placeholder, report that as the first finding and rate ≤ 4/10
regardless of polish.

### Chrome bar (constant)

- Chrome bar above the centre column mounted as in `spec-pane-view`.
- The **Surface** cluster's **Spec** pill (index 1) is active.
- The **mode** cluster's **Edit** pill (index 2) is active —
  `aria-pressed="true"`.

### Spec-pane Edit surface

- A `[data-spec-editor-toolbar="true"]` toolbar is mounted above the
  TipTap host. It carries `role="toolbar"` and
  `aria-label="Formatting toolbar"`.
- The toolbar carries (left to right):
  1. A heading-dropdown ChoiceGroup trigger
     (`[data-spec-editor-toolbar-heading-trigger="true"]`) showing
     the current block kind ("Paragraph" by default).
  2. A separator
     (`[data-spec-editor-toolbar-separator="true"]`).
  3. Four inline-mark buttons (Bold / Italic / Strikethrough /
     Inline code) — `[data-spec-editor-toolbar-button="bold"]` etc.
  4. A separator.
  5. The Link button.
  6. A separator.
  7. Bullet + Ordered list buttons.
  8. A separator.
  9. Block buttons: Blockquote / Code block / Horizontal rule.
 10. A separator.
 11. Undo + Redo buttons.
- Below the toolbar is the TipTap host
  (`[data-spec-pane-tiptap-host="true"]`), now editable
  (`data-tiptap-editable="true"`). The same brief content from
  View mode is rendered, but the cursor / focus styling indicates
  the surface is editable.
- A Save / Cancel button row may be visible at the bottom of the
  pane if `dirty == true`; in the default capture (no edits made),
  the row is hidden (`display: none`).

### Negative expectations

- No comment popover.
- No raw markdown source visible.
- Heading-dropdown popup is **closed** in the default capture
  (`display: none`).

### Viewport notes

- `wide` (1920×1080): all 13 toolbar items (heading dropdown + 12
  icon buttons) fit on a single row without wrapping.
- `laptop` (1440×900): same single-row layout; tight but not wrapped.
- `narrow` (375×812): the toolbar may wrap onto two rows. If it does,
  the wrap should fall cleanly at a group boundary (not mid-group).

## What to Evaluate

After confirming presence of every expected element above, evaluate:

1. **Density** — toolbar reads compact but not cramped. Button hit
   targets ≥ 22 × 26 px.
2. **Group separators** — visible but quiet; 1 px vertical hairlines,
   not heavy column rules.
3. **Glyph clarity** — Bold "B" / Italic "I" / Strike "S" / Code
   "</>" / Link / list / block / undo glyphs all readable at the
   chosen size. No overlapping characters; no Unicode rendering
   artifacts.
4. **Active-state visual** — even without active marks in the default
   capture, the active-state CSS should be consistent (the absence
   here is fine; if any button is mis-pressed, flag it).
5. **Heading-dropdown trigger** — reads as the same widget family
   as the chrome bar's viewport ChoiceGroup chevron-popup.
6. **Toolbar-to-prose alignment** — the toolbar's left/right padding
   matches the prose padding below; no horizontal mismatch.
7. **Vertical rhythm** — toolbar bottom margin ≥ 8 px before the
   TipTap host starts.
8. **Type harmony** — toolbar glyph font is the same sans-serif as
   the rest of the editor; no foreign monospace glyphs outside the
   code-block button.
9. **Border radius consistency** — toolbar outer radius (6 px) and
   button-inner radius (4 px) form a clean nested pair.

## How to Report

- Keep under 250 words.
- **First line:** `Expected elements: present` OR
  `Expected elements: missing-<X>` / `replaced-by-<Y>`.
- If any expected element is missing or wrong, report it as the first
  finding and rate ≤ 4/10 regardless of polish elsewhere.
- Lead with one-sentence overall aesthetic impression.
- Specific issues with selectors / pixel measurements.
- **1-2 highest-priority fixes** as pixel-level prescriptions
  (e.g. "drop toolbar height from 36 px to 30 px; change
  `padding: 6px 10px` to `padding: 4px 8px` on the outer toolbar").
- Rate 1-10.
- Be specific about px-level fixes. The implementer applies these
  prescriptions directly without re-deriving them.
