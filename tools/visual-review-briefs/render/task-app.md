# Visual Review Brief — Task App Preview

## What You're Reviewing

The **Task App** demo is one of two showcase apps in IsoNim's editor.
You are reviewing the live-rendered preview of this demo across every
backend the editor supports. The screenshot bundle for this review
contains one PNG per backend, all rendered from the same `TaskAppVM`
state — same data, same demo, different renderers.

The bundle filenames are
`screenshots/render/task-app-<backend>.png` where `<backend>` is one
of: `web`, `tui`, `gpui`, `freya`, `cocoa`, `android`, `ios`.

## Required Content (Information Equivalence)

Every backend's image MUST show all of the following. **If any item is
missing or unreadable, score that backend's cell ≤ 4/10 and report
the missing item as the first finding.**

1. **Three seeded sample tasks**, in this order:
   - "Buy groceries"
   - "Walk the dog"
   - "Ship EX-M14"
2. **A toggle / completion control** beside each task (a checkbox, an
   ASCII `[ ]` marker, an iOS-style switch, an Android Material
   checkbox — whichever idiom the backend uses).
3. **A remove control** beside each task — a button, `×` glyph, or
   delete affordance. (TUI may use a row indicator instead of a per-
   task button if cell budget is tight; document if you accept this.)
4. **A "New task…" text input** with a placeholder hint AND an
   accompanying **"Add Task" submit control**.
5. **A filter selector** with three options: **All / Active /
   Completed**. The active option must be visually distinguishable
   from the inactive options.
6. **A summary bar** showing the active/completed count (e.g. "3
   active · 0 completed" or "3 tasks remaining").

## Design Intent

- **Dark theme** with the IsoNim accent token `#7c7aed` (a vivid
  indigo). Backgrounds in the `#0f0f14` → `#22232e` range; cards one
  step lighter than the canvas; primary text near-white
  (`#e8e9f0`), secondary text muted gray (`#a0a2b0`).
- **Card-style rows**: each task should feel like a discrete row card
  with comfortable inner padding, not a tight HTML `<li>`. The
  three task rows together form a vertically stacked column.
- **Single clear focal point**: the task list should dominate the
  pane. The input and filter chrome live above; the summary lives
  below.
- **Hierarchical typography**: input placeholder and summary use a
  lighter weight than task names. The accent color highlights the
  active filter and primary CTA only — never overused.
- **8-px rhythm**: gaps and padding fall on multiples of 4 px (4 / 8 /
  12 / 16). Nothing cramped (`< 4 px`) or loose (`> 24 px` between
  related items).

## Per-Backend Native-Idiom Expectations

Cross-backend consistency does NOT mean visual identity — each backend
must look natural in its own platform's idiom. Score against the brief
*as expressed through the backend's native conventions*, not against
the Web reference. The information content must match; the look-and-
feel will and should differ.

- **Web** — HTML/CSS in an iframe. Expect: rendered DOM with the dark
  palette, accent buttons, semantic markup. The closest to a "design-
  system reference" baseline.
- **TUI** — monospace cell grid rendered through `xterm.js`. Expect:
  ASCII or Unicode box-drawing for borders, `[ ]` / `[x]` for
  toggles, terminal-native color (256-color or true-color palette
  approximating the brand colors). Information must be readable in
  ~80 cols × ~24 rows.
- **GPUI** — Zed's Rust UI toolkit, headless raster. Expect: flat
  surfaces, sharp pixel edges, rounded corners (`border-radius`),
  the dark palette with `#7c7aed` accent on the active filter and
  Add button. GPUI's renderer ignores `border` / `font-weight` so
  emphasis comes from background + color contrast.
- **Freya** — Skia-rendered, web-inspired layout. Expect: similar to
  Web visually but rasterised; rounded controls; gradients optional
  but discouraged for the showcase.
- **Cocoa** — AppKit running in-process on macOS. Expect: native Mac
  controls (`NSButton`, `NSTextField`, `NSTableView`) honouring the
  system Aqua / dark-mode appearance. Mac users should recognise
  this as a Mac app. The IsoNim accent appears as the tinted
  selection color.
- **Android** — real device framebuffer via `adb exec-out screencap`.
  Expect: Material 3 components (`Material You` palette tuned to the
  IsoNim accent), Material checkboxes, FAB-shaped Add button is
  acceptable. Status bar / system chrome at the top is part of the
  framebuffer — not a defect.
- **iOS** — real iPhone framebuffer via Wi-Fi from the IsoNim Stream
  app. Expect: UIKit controls (`UISwitch` for toggles, `UIButton`
  with `.tinted` style for Add, large title at the top is
  acceptable). System status bar / Dynamic Island visible at the
  top — part of the framebuffer, not a defect.

## Cross-Backend Consistency Contract

- **Information equivalence is non-negotiable.** Every required item
  in the *Required Content* checklist must be present in every
  backend's frame. Information missing in one backend but present in
  others is a hard finding.
- **Visual identity is NOT required.** A reviewer should NOT mark
  down TUI for being ASCII, iOS for using a `UISwitch` instead of a
  CSS checkbox, or Android for showing the system status bar. Each
  backend should look natural in its native idiom.
- **Accent usage should rhyme.** The active filter, the primary Add
  CTA, and the focused-state markers should all use the same accent
  (`#7c7aed` or its closest native-palette analog).
- **The seeded task names must be byte-identical** across all
  backends (they come from the same VM via the same seed function).
- **The order must match**: "Buy groceries" → "Walk the dog" → "Ship
  EX-M14" (the VM is sorted by insertion order).

## Scoring Rubric (Absolute 1-10)

Score each backend's cell INDEPENDENTLY against this rubric. The target
is **10/10 on every cell**. The reviewer's job is to find the gap
between the current capture and 10/10.

- **10** — Production-ready showcase. Every required item present,
  perfectly composed, native-idiomatic, accent usage spot-on,
  typography hierarchy crisp, spacing balanced, no visual mistakes.
  Could ship as a design-system example.
- **9** — Excellent. One minor polish issue (e.g. a slightly off
  padding, a non-fatal accent miss). Information content perfect.
- **7-8** — Solid. Information equivalent and aesthetically pleasant,
  but lacks polish: typography hierarchy is muted, spacing rhythm is
  off, accent is missing or overused.
- **5-6** — Functional but rough. Information present but visually
  flat or noisy. Spacing inconsistencies, missing accent, generic
  default-styles look.
- **4 or below** — One or more required items are missing,
  unreadable, or replaced by a placeholder. Triggers an immediate
  fix before re-scoring.

## How to Report

Reply with one section per backend, in this order: web, tui, gpui,
freya, cocoa, android, ios. Each section must include:

- **Score** (1-10).
- **Required-content check** — ✓ / ✗ for each of the 6 items.
- **Findings** — bulleted list of specific issues with location
  hints. Be concrete: not "spacing feels off" but "the input row's
  bottom margin is roughly 4 px while the row gap between task
  cards is 10 px — pick one rhythm".
- **Quickest path to 10** — one or two targeted edits the fix agent
  should make (file:line if you can guess it, otherwise component
  name).
