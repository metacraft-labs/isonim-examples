# Visual Review Brief — Story Selected (laptop viewport)

## What You're Reviewing

Same selection as `story-selected-wide.md` (`Settings App / Group /
Appearance`, Web backend, View mode) at the **1440 × 900** laptop
viewport. This brief focuses on density-sensitive behaviour the
wider 1920 viewport hides.

Captured by `editor-screenshot.mjs` view `story-selected` at
viewport `laptop`: file `screenshots/story-selected-laptop.png`.

## Design Goals

- Same three-panel layout as wide; no panel collapses at this
  viewport.
- Chrome bar chip clusters remain on a single row.
- Sidebar quick-nav strip stays in a single row of five icons.
- Inspector panel narrower than at wide but still shows tab labels.

## What is Expected on the Screenshot

### Sidebar

- All five quick-nav icons on a single row.
- Components section expanded; **Settings App / Group** expanded
  with the **Appearance** story row selected and visibly accented.
- Section labels not truncated; story names may truncate with
  ellipsis if necessary but the selected row must show its name in
  full.

### Centre column

- Exactly one `[data-preview-chrome-bar="true"]` toolbar.
- Three toolbar clusters on a single row.
- Web backend chip `[data-preview-backend="web"]` is active.
- Mode chip `[data-preview-mode="view"]` is active.
- Iframe renders the Appearance group with:
  - "Appearance" header + short description.
  - Dark mode toggle, Font size input, Theme choice (Default /
    Solarized / Solar / Mono).

### Inspector

- Visible on the right with tab labels readable.
- Narrower than at wide viewport — accept ≥ 200 px width.

### Negative expectations

- No horizontal scroll on any panel.
- No chrome bar cluster wrapping at this viewport.
- No view-switcher; no edge strips.

## What to Evaluate

1. **Density holds** — every chrome bar chip + cluster gap fits on
   one row.
2. **Iframe demo legibility** — the Appearance controls are clearly
   readable at this scale; the toggle, input, and choice widget all
   have ≥ 28 px hit targets.
3. **Sidebar selection cue** — accent border + tinted background
   on the `Appearance` row still unambiguous.
4. **Panel proportions** — sidebar ≤ 280 px, inspector ≤ 280 px,
   centre column ≥ 800 px. Adjust expectations if the editor
   chooses other reasonable values — flag only if the centre column
   feels squeezed.
5. **No truncation regressions** — chip labels not truncated; mode
   chips show full `View / Comment / Edit` text.

## How to Report

- Keep under 200 words.
- **First line:** `Expected elements: present` OR
  `Expected elements: missing-<X>` / `replaced-by-<Y>`.
- Lead with one-sentence aesthetic impression.
- Call out any density failure (wrapped chip cluster, truncated
  story name, hidden inspector tabs) as the first finding.
- End with **1–2 highest-priority fixes**.
- Rate 1–10. Laptop is the canonical professional-use viewport; be
  strict about density and legibility.
