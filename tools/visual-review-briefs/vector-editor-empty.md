# Visual Review Brief — Vector Editor (empty target)

## What You're Reviewing

The IsoNim Vector Editor mounted with **no usage context** — i.e.
`vm.vectorEditorTarget` is set to a symbol that has zero usages
across the workspace. In this state the M-EVP-8 usage-context
companion panel is **hidden**; the canvas, tool palette, properties
panel, and layers panel fill the centre column.

This brief catches the visual baseline of the vector editor — the
canvas affordance the user lands on when they open a brand-new
vector symbol that has not yet been placed anywhere.

The screenshot tool drives the editor to this state by:

1. Opening the editor.
2. Expanding the Foundations section.
3. Expanding the `Task App / Vector Symbols` group.
4. Selecting the `Task Check Icon` story.
5. Asserting the active view is `evVectorEditor` AND
   `vm.vectorEditorUsages.val.len == 0` (or driving an explicit
   empty-target case via the test-mode hook).

Captured by `editor-screenshot.mjs` view `vector-editor-empty` at
viewports `wide` and `laptop`: files
`screenshots/vector-editor-empty-wide.png` and
`screenshots/vector-editor-empty-laptop.png`.

## Design Goals

- The vector editor's chrome (title + boolean ops + Save + Export
  SVG) lives in its **own top toolbar** (shell chrome bar is hidden
  for `evVectorEditor` by `shell.nim`).
- Tool palette runs vertically on the left; properties panel sits
  vertically on the right; layers panel sits below the canvas.
- 16 × 16 px grid background on the canvas surface; rulers along
  the top + left edges.
- Single accent colour for the active tool / selected layer.
- Spacing on a 4 / 8 px rhythm; nothing cramped.

## Color Expectations

- Canvas surface: `bgBase` (deep gray) with subtle
  `borderFaint`-coloured grid lines every 16 px.
- Tool palette / properties / layers: `bgSidebar` surface, hairline
  borders between sections.
- Active tool button: accent background; inactive: transparent.
- Save button: shows pending vs saved state via
  `data-vector-source-stage`.

## What is Expected on the Screenshot

### Top toolbar

- One `[data-vector-editor-toolbar="true"]` row at the top of the
  vector editor surface.
- A `[data-vector-editor-back="true"]` back button with
  `aria-label="Close vector editor"` on the left.
- A title node reading `Vector Editor`.
- Boolean op buttons in document order: `union`, `subtract`,
  `intersect`, `exclude` — each with `data-vector-action="<op>"`.
- A Save button with `aria-label="Save vector source edits"`.

### Tool palette (left column)

- A vertical column of tool buttons with `aria-label="Select <Tool>
  vector tool"`. At minimum the palette exposes: Select, Move, Pen,
  Rectangle, Ellipse, Line, Text (or the canonical
  `vectorTools()` set).
- The Select tool is active by default — its button carries the
  accent background.
- Below the tools: a "Toggle vector grid" toggle (`aria-label=
  "Toggle vector grid"`) and a "Toggle vector snap" toggle
  (`aria-label="Toggle vector snap"`).

### Canvas (centre)

- A scrollable canvas area with the 16 × 16 px grid background.
- A `[data-vector-adapter="fabric"]` host element of size
  720 × 420 px centred on the grid.
- Rulers along the top (20 px) and left (20 px).
- A row of 20 named action buttons above the canvas with
  `data-vector-action` ∈ `{ import-sample, zoom-in, zoom-out,
  pan-right, set-fill, set-stroke, duplicate, delete, group,
  ungroup, transform-selection, move-segment, path-insert,
  path-delete-node, path-convert-smooth, path-handle-drag,
  path-nudge-right, path-undo, path-redo, export }`.

### Layers panel (below canvas)

- A `Layers` header (uppercase 10 px).
- Three demo layer rows: `Circle`, `Rectangle`, `Line`, each with
  `aria-label="Select vector layer <Name>"`.
- The first layer is selected by default (accent tinted background).

### Properties panel (right column)

- A 220 px-wide column with sections in this order:
  - **Transform** — five rows (X / Y / W / H / R) with monospaced
    values.
  - **Fill** — colour swatch + label `No fill`.
  - **Stroke** — accent-coloured swatch + width / cap / join rows.
  - **Accessibility** — Title + Description text fields with
    italic placeholder text (`Check icon` / `Indicates
    completion`).

### Usage-context panel (right of canvas)

- The `[data-vector-editor-usage-split="true"]` panel is **hidden**
  (`display: none`) because `vm.vectorEditorUsages.val.len == 0`.
- Neither `[data-vector-usage-layout="split"]` nor
  `[data-vector-usage-layout="carousel"]` should be visible.

## What to Evaluate

1. **Three-column balance** — tool palette (left) + canvas + props
   (right) + layers (bottom) feel proportioned. Canvas dominates.
2. **Active-tool affordance** — the active tool's accent background
   is clearly distinct from inactive peers.
3. **Grid + rulers** — visible without overwhelming the canvas
   content area.
4. **Boolean op row + action row** — the two rows of buttons above
   the canvas should not look like one wall of buttons; group them
   visually (or separate them with whitespace / a divider).
5. **Spacing** — 4 / 8 px rhythm across the palette, properties
   sections, and layers panel.
6. **No usage panel** — the right-side usage column must NOT show;
   if any usage-context UI is visible, that's a regression of the
   empty-state behaviour.

## How to Report

- Keep under 250 words.
- **First line:** `Expected elements: present` OR
  `Expected elements: missing-<X>` / `replaced-by-<Y>`.
- Lead with one-sentence aesthetic impression.
- List specific issues with selectors / data-vector-action names.
- End with **1–2 highest-priority fixes**.
- Rate 1–10.
- Call out specifically whether the **action-row + boolean-op row**
  feel like one wall or two grouped clusters.
