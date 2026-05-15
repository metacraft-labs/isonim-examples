# Visual Review Brief — Settings App Preview

## What You're Reviewing

The **Settings App** demo is one of two showcase apps in IsoNim's
editor. You are reviewing the live-rendered preview of this demo
across every backend the editor supports. The screenshot bundle for
this review contains one PNG per backend, all rendered from the same
`SettingsVM` + `buildDemoSettingsCatalog()` state — same data, same
demo, different renderers.

The bundle filenames are
`screenshots/render/settings-app-<backend>.png` where `<backend>` is
one of: `web`, `tui`, `gpui`, `freya`, `cocoa`, `android`, `ios`.

## Required Content (Information Equivalence)

The catalog has three groups: **Appearance**, **Editor**,
**Notifications**. Each group has three items totalling **nine
controls of three kinds** (toggle, choice, number). Different backends
display the catalog differently (accordion / sidebar / two-column /
card stack) — the per-backend section below documents what is
acceptable. The information that MUST be conveyed (in one frame or
discoverable from one foregrounded state) is:

1. **All three group labels are visible or reachable in one click**:
   "Appearance", "Editor", "Notifications".
2. **The active / foregrounded group's items are fully rendered with
   labels AND control widgets**. For the default capture (with
   "Appearance" foregrounded) that means:
   - `Dark mode` — toggle, default OFF.
   - `Theme` — choice with options `Default / Solarized / Dracula`,
     currently `Default`.
   - `Font size` — number, range 10-32, default 14, suffix `pt`.
3. **Each item shows its description text** when one is present in
   the catalog (e.g. "Use the dark colour palette.").
4. **Control widgets are functional-looking and aligned**: toggles
   look toggleable, the choice control looks selectable, the number
   shows the current value with a clear suffix and a way to increment
   / decrement (spinner buttons, slider, or text input).

For backends that show ALL groups at once (Freya card stack, web
sidebar+pane, GPUI two-column), the OTHER groups' headers must also
be visible. For backends that show only the active group (TUI
accordion, native single-pane), the other groups must be **navigable**
— their labels must be readable in the navigation chrome.

## Design Intent

- **Dark theme**, IsoNim accent `#7c7aed` (vivid indigo). Group
  surfaces are cards (`#1d1d28`) on a deep canvas (`#0f0f14`).
  Primary text near-white (`#e8e9f0`), descriptions / secondary text
  muted (`#a0a2b0`).
- **Hierarchical grouping**: group header (h2-ish) >> item label >>
  description >> control. Inter-item spacing roughly twice the
  intra-item spacing.
- **Accent moments**: the active toggle, the selected choice, the
  current numeric value, and the focused group header.
- **Settings should feel like a settings page in a modern app** —
  System Preferences (macOS), Settings (iOS / Android), VS Code
  preferences pane. Not a raw `<form>` dump.

## Per-Backend Native-Idiom Expectations

Cross-backend consistency does NOT mean visual identity. Score against
the brief *as expressed through the backend's native conventions*.

- **Web** — HTML in iframe. Expect: sidebar of group labels on the
  left, the active group's items in the right pane. Each item is a
  styled row with label / description / control. Dark palette,
  accent on the active group + active toggle.
- **TUI** — `xterm.js` cell grid. Expect: an accordion (one group
  open at a time); the active group's three items rendered with
  ASCII / Unicode for toggle `[x]` / `[ ]`, choice `< Default >` (or
  similar), number `font_size: 14pt [-][+]`. Other group labels
  must be visible above/below the open accordion section.
- **GPUI** — Zed Rust UI. Expect: two-column layout — left column
  lists groups, right column shows the active group's items as
  stacked rows. GPUI's renderer drops `border` / `font-size`, so
  emphasis comes from `background` + `color` contrast.
- **Freya** — Skia raster, card stack. Expect: each of the three
  groups rendered as its own vertically stacked card, all visible
  at once on screen. Inside each card: group header, then items.
  This is the only backend that shows ALL items simultaneously.
- **Cocoa** — AppKit on macOS. Expect: native `NSToolbar`-style
  group switcher OR a side list, with `NSSwitch` toggles, `NSPopUp`
  for choices, `NSStepper` + `NSTextField` for numbers. Mac users
  should recognise this as System Settings.
- **Android** — real device. Expect: Material 3 `Preference` rows —
  ListItem with title + summary, `MaterialSwitch` for toggles,
  Material spinner / dialog for choices, Material text input with
  stepper for numbers. Device status bar visible at top is not a
  defect.
- **iOS** — real iPhone via Stream app. Expect: UIKit settings
  conventions — grouped table view with section headers
  ("Appearance" / "Editor" / "Notifications"), `UISwitch` toggles,
  disclosure-arrow rows for choices, segmented controls or stepper
  for numbers. Dynamic Island / status bar at top is not a defect.

## Cross-Backend Consistency Contract

- **Information equivalence is non-negotiable.** Every required item
  in the *Required Content* checklist must be conveyed in every
  backend's frame (either inline or via clearly visible navigation
  to the foregrounded group).
- **Visual identity is NOT required.** Don't penalise iOS for using
  a grouped `UITableView`, TUI for using ASCII, or Freya for
  showing all groups at once when other backends show only the
  active one.
- **Catalog values must be byte-identical** across all backends —
  same group labels, same item labels, same default values, same
  choice options. They come from the same `buildDemoSettingsCatalog`
  via the same VM.
- **The accent color should rhyme** across backends — active
  toggle, selected group, focused control should all use the
  IsoNim indigo or its closest native-palette analog.

## Scoring Rubric (Absolute 1-10)

Score each backend's cell INDEPENDENTLY against this rubric. The target
is **10/10 on every cell**.

- **10** — Production-ready showcase settings page. All required
  items, perfect composition, native-idiomatic widgets, accent
  usage spot-on, hierarchical typography crisp, three-group
  navigation immediately obvious. Could ship as a Polaris /
  Material 3 / iOS Settings reference.
- **9** — Excellent. One minor polish miss (a slightly tight gap,
  a description not styled distinctly enough). Information perfect.
- **7-8** — Solid. All items present and aesthetically pleasant
  but missing polish: descriptions blend into labels, accent
  missing, controls look default-styled.
- **5-6** — Functional but rough. Information present but visually
  flat. Spacing inconsistencies, no accent, generic widgets.
- **4 or below** — Missing items, unreadable controls, or
  unnavigable groups. Triggers an immediate fix before re-scoring.

## How to Report

Reply with one section per backend, in this order: web, tui, gpui,
freya, cocoa, android, ios. Each section must include:

- **Score** (1-10).
- **Required-content check** — ✓ / ✗ for each of the 4 items in the
  checklist, plus a note on how the other (non-active) groups are
  reachable.
- **Findings** — bulleted list of concrete issues with location
  hints. Concrete: "the Font size number widget has no visible
  spinner buttons; users can't tell it's editable".
- **Quickest path to 10** — one or two targeted edits the fix
  agent should make (file:line if you can guess it, otherwise
  component name).
