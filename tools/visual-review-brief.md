# Visual Review Brief — IsoNim Examples Editor

## What You're Reviewing

The **IsoNim Examples Editor** is a design-system presentation tool for the
showcase demo apps (`task_app` and `settings_app`). It demonstrates the
IsoNim editor's intended UX: storybook-like sidebar story browser, a
centre preview pane that renders the selected story through any of six
real renderers (Web / TUI / GPUI / Freya / Cocoa / Android), and a
right-side inspector panel for property edits. A left-edge "M57 backend
strip" lets the user switch which renderer drives the preview.

It is built with IsoNim itself (dogfooding the framework). The
authoritative design intent lives in
`codetracer-specs/Front-Ends/IsoNim/isonim-editor.md`.

## Design Goals

- **Dark theme**, professional tool aesthetic similar to VS Code,
  Figma, Storybook dark mode, Linear, or Material Design's docs site.
- **Three-panel layout** — left sidebar (story tree), centre preview
  pane (live demo render), right inspector (properties + AI chat).
- A **left-edge backend strip** (M57) — vertical column of icon-tabs,
  one per renderer; the selected one highlighted with an accent color.
- A **right-edge mode strip** — vertical column of View / Comment /
  Edit toggles.
- Panels feel balanced; the preview pane is the focal point — nothing
  else should visually dominate.
- Spacing rhythm on a 4 px / 8 px grid; nothing cramped, nothing loose.
- Clear typography hierarchy: page title > section heading > story
  label > body > metadata. Single sans-serif family (system stack or
  Inter / similar).
- **Subtle borders** between panels — 1 px hairlines in mid-gray, not
  heavy lines or large gaps.
- **The demos themselves must be beautiful** — they are the editor's
  reason for existing. Task lists and settings panels should look like
  showcase examples from a polished design system (Polaris,
  Material 3, Linear, Notion), not like raw Tailwind boilerplate.

## Color Expectations

- Background canvas: deep dark gray (e.g. `#0f0f14` … `#1a1a2e`)
- Panel surfaces: one step lighter (`#1d1d28` … `#22232e`)
- Borders / dividers: subtle gray (`#2a2b36` … `#34353f`)
- Primary text: near-white (`#e8e9f0` … `#f5f5f7`)
- Secondary text: muted gray (`#8b8d98` … `#a0a2b0`)
- Accent: a single vibrant color (purple / indigo / teal) used
  sparingly for the active backend tab, the selected story, focused
  inputs, and primary actions
- Hover / focus states: visible but subtle (a slightly lighter surface
  or an accent-color border)

## What is Expected on the Screenshot

**The reviewer must verify these elements are present BEFORE evaluating
aesthetics.** If anything expected is missing or replaced by a
placeholder, report that as the first finding and rate ≤ 4/10
regardless of polish.

Different views are captured into different screenshot filenames. The
sub-agent prompt names which view + viewport size the screenshot
represents; use that to pick the right expected-elements block.

### View: `shell-*` (default landing)

The editor's chrome with no story selected (or with the default story
showing):

- **NO global top bar.** The shell should sit edge-to-edge at the very
  top of the viewport — no "IsoNim Editor / isonim-examples / v0.1.0"
  strip above the panels.
- **NO left-edge or right-edge chip columns.** Backend / viewport /
  mode chips have all moved into the preview-pane top toolbar.
- **Left panel:** a story browser with at least two top-level groups
  (`Task App` and `Settings App`), each expandable into a tree of
  categories (`Foundations`, `Components`, `Patterns`, `Pages`,
  `Flows`) and stories underneath.
- **Centre preview pane:** a top toolbar that contains, in one row
  (wrapping to two rows on narrow viewports if needed):
  1. The view-switcher (Flow / Detail / Page / Foundations / Vector).
  2. Backend chips (Web / TUI / GPUI / Freya / Cocoa / Droid). Cocoa
     and Android may appear disabled (greyed) on hosts without those
     launchers.
  3. Viewport chips (Desktop / Laptop / Tablet / Phone or TUI cell
     viewports when TUI is selected).
  4. Mode chips (View / Comment / Edit).
  Below the toolbar is the preview canvas — empty-state landing card,
  or a live story render once a story is selected.
- **Right panel:** the inspector — a properties / styles / AI-chat
  area. May start collapsed showing only tab labels.

### View: `story-selected-*` (Settings App / Group / Appearance)

After clicking through `Settings App` → `Group stories` → `Appearance`
in the sidebar (default backend is Web):

- Sidebar's `Appearance` row is highlighted with the accent color.
- Preview pane shows the **Appearance settings group rendered through
  the active backend**:
  - A group header reading "Appearance" with a short description.
  - At least three items: a "Dark mode" toggle, a "Font size" number
    input, a "Theme" choice (Default / Solarized / Solar / Mono).
  - Each item has a label and a control widget aligned to a clear grid.
- The preview pane is the visual centre of the screenshot — the demo
  itself is the focal point, not the editor chrome.
- Inspector panel on the right shows properties for the
  currently-selected component / story.

### View: `story-selected-tui-*` (Settings App / Group / Appearance, TUI backend)

Same selection as `story-selected-*`, but with the TUI chip clicked in
the preview-pane toolbar:

- TUI chip in the preview-pane toolbar should be highlighted (accent
  glow / aria-pressed=true).
- Preview iframe should render the **TUI-styled** version of the same
  Appearance group:
  - **Monospace font** throughout (system mono / Menlo / Consolas).
  - **ASCII / box-drawing borders** (`+----+`, `|`, `+`) for cards and
    rows — NO rounded corners, NO drop shadows.
  - Toggle widgets rendered as `[ ]` / `[x]` text instead of CSS
    pills.
  - Choice widgets rendered as `( ) Default  (•) Solarized` text
    radio-style.
  - Distinct, lower-fidelity "this is the terminal" look — clearly
    different from the Web srcdoc.
- The point is that clicking the TUI chip in the toolbar **visibly
  changes the iframe content** to a monospace cell-grid look.

### Viewport notes

- `wide` (1920×1080) and `laptop` (1440×900): all three panels visible.
- `medium` (1280×800): all panels visible; inspector may be narrower.
- `tablet` (1024×768): all panels visible but tight; some text may
  truncate.
- `narrow` (768×1024) and `mobile` (375×812): the editor may collapse
  the inspector or sidebar behind a toggle; this is acceptable as
  long as the active panel is usable.

## What to Evaluate

After confirming the expected elements are present, evaluate:

1. **Alignment** — consistent left/right edges, centered content,
   grid adherence
2. **Spacing** — consistent padding/margins on a 4 px / 8 px rhythm;
   nothing cramped or loose
3. **Color harmony** — cohesive palette, no jarring colors, accent
   used sparingly and meaningfully
4. **Typography** — clear hierarchy, readable sizes, consistent
   weights, no mismatched fonts
5. **Visual weight** — balanced layout, preview pane is the focal
   point; chrome supports it without competing
6. **Demo polish** — the rendered task_app / settings_app inside the
   preview pane looks like a showcase example, not raw HTML
7. **Professional polish overall** — does it look like a shipping
   product (Linear, Notion, Figma) or a prototype? What's the gap?
8. **Responsive behavior** — sensible adaptation at smaller viewports

## How to Report

- Keep under 250 words.
- **First line:** `Expected elements: present` OR
  `Expected elements: missing-<X>` / `replaced-by-<Y>`.
- If any expected element is missing or wrong, report it as the first
  finding and rate ≤ 4/10 regardless of polish elsewhere.
- Otherwise, lead with a one-sentence overall aesthetic impression.
- List specific issues as bullet points with locations
  (e.g. "left sidebar / story tree: indent step is 28 px, should be
  16 px").
- End with **1-2 highest-priority fixes** the implementer should
  do first.
- Rate 1-10 (calibration: 1-3 = broken, 4-5 = functional rough,
  6-7 = good with minor issues, 8-9 = near-shipping, 10 = perfect).
- Be direct and specific — "the inspector tabs look cramped" is
  better than "spacing could be improved".
