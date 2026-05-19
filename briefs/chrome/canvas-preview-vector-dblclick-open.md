---
briefId: chrome.canvas-preview-vector-dblclick-open
schemaVersion: 1
kind: chrome
title: Vector Editor Opened via Canvas Dblclick (M-EVP-11)
coversPreviews:
  - storyRef: { group: "Task App / Vector Symbols", name: "Task Check Icon", kind: vectorsymbol, index: 0 }
    backends: [tui]
captureViewports:
  - { width: 1920, height: 1080, label: "wide" }
  - { width: 1440, height: 900, label: "laptop" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: chrome, label: "Editor Chrome", weight: 1.0, scale: { min: 1, max: 10 } }
relatedBriefs: [chrome.canvas-preview-tui, chrome.canvas-preview-edit-mode]
---


## What You're Reviewing

The state of the editor **immediately after** a double-click on a
canvas vector-symbol entry. M-EVP-11 closes the M-EVP-8 TODO: the
canvas JS shim's `dblclick` handler hit-tests the manifest, sees
`kind == "vector-symbol"`, looks up the matching `skVectorSymbol`
story (`task_app/views/TaskCheckIcon` → `Task App / Vector
Symbols / Task Check Icon`), and calls
`vm.openVectorEditor(story)`. The screenshot captures the editor
with the vector editor mounted and the dblclick'd target
identified.

The screenshot tool drives the editor to this state by:

1. Setting `window.__isonimTestMode = true`.
2. Opening the editor; navigating to a Task App / TaskList story
   so the summary bar (containing the seeded `TaskCheckIcon`
   vector-symbol leaf) is rendered.
3. Clicking the `[data-preview-backend="tui"]` chip in the chrome
   bar to mount the canvas + bridge client.
4. Waiting for the first non-empty canvas frame AND for the
   `element-tree` manifest to land at `window.__isonimManifest`.
5. Finding the manifest entry with
   `componentPath == "task_app/views/TaskCheckIcon"` and
   `kind == "vector-symbol"`, computing its centre.
6. Issuing `page.mouse.dblclick(x, y)` at that point.
7. Waiting until `window.__isonimEditorActiveView ===
   "evVectorEditor"` AND
   `window.__isonimVectorEditorTarget === "task_app/views/
   TaskCheckIcon"`.

Captured by `editor-screenshot.mjs` view
`canvas-preview-vector-dblclick-open` at viewports `wide` and
`laptop`: files
`screenshots/canvas-preview-vector-dblclick-open-wide.png` and
`screenshots/canvas-preview-vector-dblclick-open-laptop.png`.

## Design Goals

- The vector editor mounts cleanly — same surface
  `vector-editor-empty.md` / `vector-editor-with-symbol.md` describe.
- The vector editor must show the correct target — the **Task
  Check Icon** symbol, NOT a different vector story.
- Transition feels intentional: no flicker artefact, no leftover
  canvas overlay residue from the previous TUI canvas view.

## Color Expectations

- Same colour palette as the other vector-editor briefs (dark
  panel surfaces, accent for active tool, etc.).

## What is Expected on the Screenshot

### Vector editor mounted

- The shell chrome bar is **hidden** for the `evVectorEditor`
  view (`shell.nim` sets `display: none` on `chromeBarEl`).
- The vector editor's own toolbar is visible:
  - `[data-vector-editor-toolbar="true"]` row at the top.
  - `[data-vector-editor-back="true"]` back button (visible only
    while `evVectorEditor` is active).
  - Title text `Vector Editor`.
  - Boolean op buttons (`union`, `subtract`, `intersect`,
    `exclude`).
  - Save button.

### Correct target

- The target identifier is the **TaskCheckIcon** vector symbol.
  Verify via `window.__isonimVectorEditorTarget` test-mode mirror
  (set to `task_app/views/TaskCheckIcon`).
- In the layers panel below the canvas, the seeded layer rows
  appear (the default `Circle / Rectangle / Line` set may render
  initially if the symbol has not been edited).
- In the properties panel's Accessibility section, the placeholder
  `Title` text reads `Check icon` and `Description` reads
  `Indicates completion` (these are the static placeholders from
  the empty-state brief and confirm the vector editor surface
  mounted cleanly).

### Sidebar selection

- The sidebar's Foundations section is expanded; the
  `Task App / Vector Symbols` group is expanded; the
  `Task Check Icon` story row is selected (accent-tinted
  background + accent left border).

### Negative expectations

- No `<canvas data-canvas-active="true">` visible anywhere — the
  view switched away from the component-detail canvas.
- No iframe visible — `evVectorEditor` does not render the Web
  iframe.
- No `[data-canvas-overlay="true"]` overlay residue.
- The `[data-vector-editor-usage-split="true"]` usage panel may
  or may not be visible depending on whether the dblclicked
  symbol has tracked usages; if visible it should be in **split**
  mode (≤ 3 usages — the seeded workspace exposes only one
  natural usage of TaskCheckIcon).

## What to Evaluate

1. **Correct target mounted** — does the vector editor show the
   Task Check Icon symbol, or a different / placeholder symbol?
2. **Clean transition** — no visual artefacts left over from the
   prior TUI canvas state.
3. **Sidebar selection consistency** — the Foundations section
   expansion + Task Check Icon highlight match the vector editor
   target.
4. **Toolbar polish** — back button + title + boolean ops +
   Save form a clean header without crowding.
5. **Tool palette + properties + layers all rendered** — same
   visual baseline as `vector-editor-empty.md`.
6. **Usage panel** — if visible, it shows the natural usage
   (`Task App / TaskList / *`); should not be in carousel mode
   (only one natural usage).

## How to Report

- Keep under 250 words.
- **First line:** `Expected elements: present
  (target=TaskCheckIcon)` OR
  `Expected elements: missing-<X>` / `wrong-target-<Y>`.
- Lead with one-sentence aesthetic impression.
- Quote the target string visible (via `window.__isonim
  VectorEditorTarget` or via sidebar highlight) so the reader can
  verify it equals `task_app/views/TaskCheckIcon` or its sidebar
  display form `Task Check Icon`.
- List specific issues with selectors.
- End with **1–2 highest-priority fixes**.
- Rate 1–10. Wrong target = ≤ 3/10; otherwise normal calibration.
