---
campaignId: task-app-to-9
schemaVersion: 1
briefRefs:
  - render.task-app
targetScore: 9.0
scopeBackends: [web, tui, gpui, freya, cocoa, android, ios]
maxIterations: 30
status: escalated
startedAt: null
finishedAt: 2026-05-21T09:20:38Z
notesToOrchestrator: |
  **DO NOT COMPRESS THESE NOTES.** Earlier turns rewrote
  notesToOrchestrator and stripped guidance, breaking the next
  turn's context. If you need to record observations, append to
  `## Current state` / `## History` — do not edit this field.

  Drive the task-app brief from baseline up to 9+ across the
  backends listed in scopeBackends in this single long-running turn.
  You have shell tools, file edits, all of codex's agentic toolkit.

  Working corpus: /Users/zahary/metacraft/isonim-examples/screenshots/render/task-app-*.png
  represents the current rendering state.

  Typical work pattern:
    1. Seed a run: `build/bin/isonim-review seed-run --brief render.task-app --capture <be>=<path>...`
       (run from /Users/zahary/metacraft/isonim, where the binary lives).
    2. Run reviewer: `build/bin/isonim-review run-review --run <run_id> --acp-backend codex`.
    3. Read the report, pick the highest-priority defect.
    4. Implement the fix in the relevant file.
    5. Re-seed-run with the modified outputs.
    6. Re-run-review to verify the defect is resolved.
    7. Update `## Current state` with progress.
    8. Continue with next defect, OR set frontmatter
       `status: converged|escalated|stopped|needs_human` when done.

  Per-backend blockers: document in `## Current state`, drop the
  backend from this turn, **keep iterating on the others**. Don't
  escalate the whole campaign for one blocked cell.

  Dev-shell mapping for THIS project — MUST follow:
    * `isonim-review` CLI: `direnv exec ~/metacraft/isonim build/bin/isonim-review ...`
    * Screenshot launchers, `node tools/editor-screenshot.mjs`, and
      per-backend `nim c -r tests/test_<backend>_*.nim`:
          direnv exec ~/metacraft/isonim-examples ...
      Only the isonim-examples shell has `LD_LIBRARY_PATH` set to
      `../isonim-gpui/rust/target/debug` and `../isonim-freya/rust/target/debug`.
      If `could not load: libgpui_nim_shim.dylib` or
      `libfreya_nim_shim.dylib`: ALWAYS the wrong dev shell. Switch.

  Cross-repo edits are explicitly authorised (per §D3b of the
  orchestrator prompt). When a prescription needs a change in
  `isonim-render-serve/src/.../<backend>_adapter.nim`, in a
  launcher, in the editor preview-frame, or in the bridge: take
  the change. Do not exit citing "this needs a renderer change".

  Prescription discipline (§D3a):
  - If a cell's open defect is qualitative (e.g. "soft", "cramped",
    "not native enough") and has NO `prescription:` line with
    concrete pixel/hex/spacing values, your FIRST action is to bump
    the reviewer prompt template version, require `prescription:`,
    re-run review against the SAME captures. THEN implement the
    fresh prescription.
  - Prescriptions are setup, not the deliverable. The score lift
    on the recaptured PNG IS the deliverable. A campaign with
    prescriptions on file but unchanged scores has not advanced.

  **No-regression rule** (read carefully — last turn regressed 3
  cells while lifting 1): when you edit a cell that is already at
  target or near-target, the edit MUST be scoped to a named open
  defect. Do not propagate stylistic changes (e.g. summary-copy
  rewordings, removed icons) into cells that did not flag that
  exact defect. If you intend to make a cross-cell change for
  consistency, re-review the affected cells in the SAME turn and
  revert the change in any cell whose score drops as a result.

  Prior-turn carry: the previous turn lifted GPUI 6→7 (good) but
  reported regressions on web (9→8), tui (8→7), and ios (8→7).
  This may reflect (a) real regressions from the agent's web
  summary-copy change + ios checkmark removal, (b) reviewer
  calibration drift, or (c) both. THIS turn: recapture every
  cell, re-review, identify which dropped because of code vs.
  drift, revert the regression-causing edits where the code
  change is the cause.

  Do NOT commit code edits. The operator commits each fix in its
  own commit. Leave the working tree dirty.
---

# Drive task-app brief to 9+ across the in-scope backends

## Objectives

- Lift every evaluable cell to >=7 and at least five of them to >=8.
- Address every blocker-severity defect before tackling warn-level.
- Make edits aligned with the brief's cross-backend consistency
  contract.
- If a backend is unevaluable in this environment, document it as a
  per-backend blocker and continue with the rest.

## Scope

- Brief: `render.task-app`
- Corpus: existing PNGs at
  `isonim-examples/screenshots/render/task-app-*.png`.
- Implementation: `isonim-examples/task_app/core/{vm,views,story_ids}.nim`
  and per-backend leaves at
  `isonim-examples/task_app/<backend>/leaves.nim`.

## Success criteria

- All evaluable cells >=7.
- At least five evaluable cells >=8.
- Blockers from earlier turns either resolved or escalated with a
  documented reason.
- Blocked cells explicitly listed in the exit summary.

## Current state

Terminal state for this turn: **escalated**. The current corpus was
recaptured/reseeded and reviewed after focused TUI/Freya/Cocoa work,
but the campaign gates were not met.

Final review: run `a977765b-0374-45b5-a1e2-52e4d0f947a1`, report
`5d92879d-d0be-43de-863e-505633e529c5`, reviewer
`review-prompt@v2+gpt-5`.

Final rendering scores:
- web: 9, open nit `web-preview-underfilled`.
- tui: 7, open warn `tui-preview-underuses-canvas`.
- gpui: 7, open warn `gpui-soft-downscaled-text`.
- freya: 7, open warn `freya-composition-too-wide-and-top-heavy`.
- cocoa: 7, open warn `cocoa-not-native-enough`.
- android: 4, blocked/stale seeded PNG; open blocker
  `android-missing-remove-controls` and warn
  `android-stretched-and-jagged-render`. Source has a remove chip, but
  this turn did not have a fresh real-device `adb` framebuffer proof.
- ios: 6, stale/device carry-over; open warns
  `ios-overscaled-content` and `ios-filter-inactive-contrast`.

Hard-rule explanation for below-target evaluable cells: TUI was
investigated and a concrete 80x24 centering attempt was tested against
the real screenshot path, but it produced a blank terminal frame and
was reverted; the restored 120x36 path remains visible but still
top-left-pinned. Freya received the prescribed 12px shell gaps and
8px row gaps, but review changed the defect to overwide/top-heavy
composition and stayed at 7. Cocoa received prescribed text/padding
improvements and recovered to 7, but still needs a deeper native
AppKit treatment rather than more row metric tweaks. GPUI and iOS were
not edited this turn; their latest score movement is reviewer/carry-over
drift on unchanged seeded PNGs. Android remains unevaluable as a
fresh capture in this environment.

## History

- 2026-05-20T22:12:15Z baseline seeded run
  `720876bc-6f07-4bfe-b629-4971c0a5baed`, review
  `d39da687-a892-46ad-9c5b-ad810f427abb`.
  - baseline rendering scores: web 9, tui 4, gpui 6, freya 5,
    cocoa 6, android 4, ios 8.
- 2026-05-20T22:21:03Z resolved `tui-missing-add-submit-control`.
  - patch: `task_app/tui/leaves.nim` adds a visible `Add Task`
    `ButtonWidget` below the TUI input, wired to `vm.addTask`
    and input clearing.
  - verification: review `5e25a5c0-e5bd-4bc3-b5bd-1b7708b2bb62`.
  - score delta on `Task App / Pages/Inbox:page#0@tui`
    rendering: 4 → 7.
- 2026-05-20T22:22:58Z attempted `android-remove-controls-missing`.
  - patch: `task_app/android/leaves.nim` restores a visible
    trailing `×` remove chip on each row and lets the task label
    flex-grow so the chip sits at the row's trailing edge.
  - verification: code-level only (`nim check -d:mockJni`,
    rebuilt with `-d:mockJni`). Real Android visual capture
    requires `adb` + connected device, unavailable in the prior
    turn's environment.
- 2026-05-21T03:47:29Z baseline seeded run
  `fe2acd1a-d872-4512-8e0b-70c37bcba7bf`, review
  `ffa62cb4-8554-468f-85ff-607036bb9a2f`.
  - baseline rendering scores: web 9, tui 4, gpui 6, freya 6,
    cocoa 6, android 4, ios 7.
  - blocker defects: `tui-remove-control-missing`,
    `android-remove-control-missing`.
- 2026-05-21T03:55:07Z resolved `tui-remove-control-missing`
  without committing, per `notesToOrchestrator`.
  - patch:
    `task_app/tui/leaves.nim` adds a trailing `×` marker to each
    task row and wires row click to `vm.removeTask`;
    `tests/test_tui_leaves_end_to_end.nim` asserts the visible
    marker and removal behavior.
  - supporting patch: narrowed TUI imports in
    `task_app/tui/leaves.nim`, `task_app/main_tui.nim`,
    `settings_app/main_tui.nim`, `editor/backends/tui_term.nim`,
    and the focused TUI test so this path no longer links the
    top-level `isonim_tui` tree-sitter surface.
  - verification: `nim c -r tests/test_tui_leaves_end_to_end.nim`
    passed; `nim c ... editor/backends/tui_term.nim` passed;
    screenshot refreshed at
    `screenshots/render/task-app-tui.png`; review
    `37cbaa66-e220-42c3-aefb-ed56f001721a` confirms the required
    remove affordance is present and raises TUI rendering 4 → 7.
- 2026-05-21T03:56:40Z investigated
  `android-remove-controls-missing`.
  - source evidence: `task_app/android/leaves.nim` lines 388-402
    already create a visible trailing `×` remove button.
  - environment blocker: `adb` is unavailable in this shell, so a
    real Android framebuffer capture cannot be produced; the seeded
    Android PNG remains stale/uncapturable for this turn.
- 2026-05-21T03:56:58Z attempted Freya row-layout improvement but
  could not verify visually.
  - patch: `task_app/freya/leaves.nim` pins the task label span's
    main-axis width so the remove action should land at the row
    trailing edge.
  - verification: Freya backend binary compiles, but the focused
    Freya test and screenshot launcher fail at runtime with
    `could not load: libfreya_nim_shim.dylib`; no visual review was
    run against this patch.
- 2026-05-21T04:24:53Z attempted GPUI hierarchy/width polish and
  reverted it before exit.
  - patch attempted: `task_app/gpui/leaves.nim` centered the app shell,
    clamped input/summary width, brightened labels, and enlarged
    checkboxes.
  - verification: GPUI launcher compiled, but screenshot capture failed
    because `libgpui_nim_shim.dylib` could not be loaded. The source
    patch was reverted because no visual proof was possible.
- 2026-05-21T04:28:37Z resolved part of the Cocoa composition defect.
  - patch: `isonim-render-serve/src/isonim_render_serve/adapters/cocoa_adapter.nim`
    adds opt-in `data-cross-align="center"` support for fixed-width
    vertical children; `task_app/cocoa/leaves.nim` marks Task App bands
    and rows with that attribute.
  - verification: Cocoa launcher rebuilt; screenshot refreshed at
    `screenshots/render/task-app-cocoa.png`; seeded run
    `3fd47848-66fe-4d26-a51f-1f736670b9af`, review
    `6369f4bf-2733-49b4-8b59-88aa8152cf4a` kept Cocoa rendering at 6
    while replacing the overstretched/right-aligned finding with
    native-idiom and contrast warnings.
- 2026-05-21T04:30:44Z improved Cocoa preview-scale contrast.
  - patch: `task_app/cocoa/leaves.nim` brightens the input text,
    row surfaces, toggle fill, and remove glyph/chip.
  - verification: Cocoa launcher rebuilt; screenshot refreshed at
    `screenshots/render/task-app-cocoa.png`; seeded run
    `465f9b7f-54f5-4357-b988-a90ffcfb60d5`, review
    `236ce2ec-018a-41c3-a95a-06b42d8b8752` leaves Cocoa rendering at
    6 with remaining `cocoa-generic-web-like-rendering` and
    `cocoa-vertical-composition-unbalanced` warnings.
- 2026-05-21T07:05:44Z resolved
  `tui-summary-copy-not-brief-equivalent`.
  - patch: `task_app/{web,tui,gpui,freya,cocoa,android}/leaves.nim`
    now render the summary as `N active · M completed` (or the same
    byte sequence for native targets) instead of `N of M remaining`;
    focused tests were updated for TUI, GPUI, Freya, Cocoa, and
    Android.
  - verification: `nim c -r tests/test_tui_leaves_end_to_end.nim`,
    `nim c -r tests/test_gpui_leaves_end_to_end.nim`,
    `nim c -r tests/test_freya_leaves_end_to_end.nim`,
    `nim c -r tests/test_cocoa_leaves_macos_only.nim`,
    `nim c -r -d:mockJni tests/test_android_leaves_android_only.nim`,
    and `nim c -r tests/test_views_compile_cross_renderer.nim` passed.
    Local screenshots for web/tui/gpui/freya/cocoa were refreshed.
    Seeded run `98edc82a-9a59-48dc-a309-75dd2e88c3ec`, report
    `a540d463-2ec3-44d9-902b-21eb9f9f3d4b` confirmed the refreshed
    cells show `3 active · 0 completed`; TUI rendering moved to 7 and
    the summary-copy defect did not recur.
- 2026-05-21T07:10:15Z investigated GPUI/Freya row-layout polish.
  - patch attempted: GPUI label flex/summary width and Freya label
    style width. It did not materially change the captured composition;
    the ineffective GPUI changes were reverted before exit, and the
    existing Freya `data-fixed-width` hint remains.
  - verification: `nim c -r tests/test_gpui_leaves_end_to_end.nim` and
    `nim c -r tests/test_freya_leaves_end_to_end.nim` passed; GPUI and
    Freya launchers rebuilt and captured through the `isonim-examples`
    dev shell. Seeded run `89cb691c-16ad-45c7-98e8-665594997b15`,
    report `74c7337c-10f6-455c-b899-da96b68aec5a` kept GPUI at 6 and
    Freya at 5/6 depending reviewer calibration, proving the row
    composition issue needs a deeper renderer/layout fix rather than
    another leaf-level width hint.
- 2026-05-21T07:14:00Z removed decorative summary checkmark artifact and
  escalated at iteration cap.
  - patch: `task_app/{tui,gpui,freya,cocoa,android,ios}/leaves.nim`
    keeps the `TaskCheckIconPath` vector-symbol node for editor
    integration but clears its visible text so it no longer reads as a
    stray footer glyph.
  - verification: `nim c -r tests/test_tui_leaves_end_to_end.nim`,
    `nim c -r tests/test_gpui_leaves_end_to_end.nim`,
    `nim c -r tests/test_freya_leaves_end_to_end.nim`, and
    `nim c -r tests/test_cocoa_leaves_macos_only.nim` passed. Local
    web/tui/gpui/freya/cocoa launchers rebuilt and screenshots
    refreshed. Seeded run `15dbf1ce-29bb-4e18-b99d-abb559819984`,
    report `3944e309-8f99-4b73-bd64-46999cb088c4` scored web 9,
    tui 7, gpui 6, freya 6, cocoa 6, android 4 stale/blocked, ios 8
    stale/carry-over.
- 2026-05-21T07:53:35Z refreshed the baseline and tightened reviewer
  calibration for qualitative defects.
  - baseline: seeded run `48809efd-dc63-458c-b36d-2e4bc264cb39`,
    report `91164525-211e-4d6b-a150-78a1deb281b4`; scores were web 8,
    tui 7, gpui 6, freya 5, cocoa 5, android 4 stale/blocked, ios 7.
    The report still emitted qualitative `warn` findings without
    actionable prescriptions.
  - patch:
    `/Users/zahary/metacraft/isonim/prompts/design_review/reviewer_prompt.template`
    now declares `review-prompt@v2` and requires every non-nit defect
    to include a concrete `prescription:` using pixels, colors,
    spacing, typography, scaling, or node-tree/layout changes.
  - verification: re-seeded the same current PNG corpus as
    `77b854e8-9bfd-4242-b0b3-1f7c30c68d49` and reviewed with
    `--agent-version review-prompt@v2`; report
    `718353b5-863b-40dd-b052-a04e364178ab` produced concrete
    prescriptions for web, tui, gpui, freya, cocoa, android, and ios
    non-nit defects. Scores were web 8, tui 7, gpui 6, freya 6,
    cocoa 6, android 4 stale/blocked, ios 8.
  - attempted Freya prescription implementation:
    `task_app/freya/leaves.nim` was temporarily changed to add
    row `justify-content: space-between` and then a fixed-width label
    host. `direnv exec /Users/zahary/metacraft/isonim-examples nim c -r
    tests/test_freya_leaves_end_to_end.nim` passed, and
    `direnv exec /Users/zahary/metacraft/isonim-examples node
    tools/editor-screenshot.mjs --view render --component task-app
    --backend freya --no-build` refreshed the screenshot, but the
    remove glyph remained clustered next to the label. The temporary
    edits were reverted; the final refreshed Freya screenshot matches
    the current source. Root cause remains in the Freya live
    renderer/layout bridge rather than another leaf-level width hint.
  - terminal status: escalated because target scores were not reached
    within the campaign's iteration budget, but every non-blocked
    below-target cell now has a concrete reviewer prescription for the
    next implementation pass.
- 2026-05-21T08:09:33Z resolved the concrete Freya cramped-left row
  defect and escalated with remaining cells below target.
  - patch:
    `/Users/zahary/metacraft/isonim-render-serve/src/isonim_render_serve/adapters/freya_adapter.nim`
    teaches the synthetic Freya layout manifest/raster path to honor
    explicit `data-layout-padding` and `data-layout-gap` attributes;
    `/Users/zahary/metacraft/isonim-render-serve/tests/test_freya_adapter_element_tree.nim`
    adds a deterministic row-geometry test proving checkbox x=16,
    label x=44, trailing remove x=764 for an 800x52 row;
    `/Users/zahary/metacraft/isonim-examples/task_app/freya/leaves.nim`
    applies 16px row padding, 8px row gap, a label host, and a
    trailing remove layout that the real Freya headless renderer
    consumes.
  - verification:
    `direnv exec /Users/zahary/metacraft/isonim-render-serve nim c --styleCheck:usages --styleCheck:error --path:src --path:tests --mm:orc --threads:on -r tests/test_freya_adapter_element_tree.nim`
    passed;
    `direnv exec /Users/zahary/metacraft/isonim-examples nim c -r tests/test_freya_leaves_end_to_end.nim`
    passed; Freya launcher rebuilt with `-d:useFreyaHeadless`;
    `direnv exec /Users/zahary/metacraft/isonim-examples node tools/editor-screenshot.mjs --view render --component task-app --backend freya --no-build`
    refreshed
    `/Users/zahary/metacraft/isonim-examples/screenshots/render/task-app-freya.png`.
  - review: first seeded run
    `62ab15c5-4191-4f2f-97dd-9f86312afad6`, report
    `89568f60-24f4-4596-bb2d-b1b532fa16df`, proved the synthetic
    adapter-only geometry did not affect the real Freya headless
    pixels and kept Freya at 6 with
    `freya-row-content-collapsed-left`.  The follow-up leaf/real-headless
    patch seeded run `ef4c1fec-10e3-4d26-b49a-ede680524428`, report
    `fa3057b6-7d60-4e43-beea-20b85ecfe909`, removed
    `freya-row-content-collapsed-left` and moved Freya rendering
    6 → 7.  Remaining Freya warn is `freya-rows-overwide-and-flat`.
  - commit: not created in this turn because both
    `isonim-examples/task_app/freya/leaves.nim` and sibling campaign
    files already contained pre-existing uncommitted changes from
    earlier turns; staging the verified patch as one clean defect
    commit would have swept unrelated carry-over edits into the same
    commit.

- 2026-05-21T08:29:50Z verified GPUI layout/contrast lift and escalated with Cocoa still below gate.
  - patch:
    `/Users/zahary/metacraft/isonim-examples/task_app/gpui/leaves.nim` restores a full-width GPUI frame, centers the 720px task column with 48px top padding, aligns input/list/summary widths, brightens primary labels to `#e8e9f0`, and raises placeholder/summary text to `#a0a2b0`;
    `/Users/zahary/metacraft/isonim-examples/task_app/cocoa/leaves.nim` applies AppKit-like 28/32/44 control metrics, narrower grouped-list widths, and brighter remove glyphs;
    `/Users/zahary/metacraft/isonim-render-serve/src/isonim_render_serve/adapters/cocoa_adapter.nim` lets horizontal Cocoa children honor `data-fixed-height` on the cross axis so fixed-height controls center inside rows.
  - verification:
    `direnv exec /Users/zahary/metacraft/isonim-examples nim c -r tests/test_gpui_leaves_end_to_end.nim` passed;
    `direnv exec /Users/zahary/metacraft/isonim-examples nim c -r tests/test_cocoa_leaves_macos_only.nim` passed;
    `direnv exec /Users/zahary/metacraft/isonim-render-serve nim c --styleCheck:usages --styleCheck:error --path:src --path:tests --mm:orc --threads:on -r tests/test_cocoa_adapter_macos_only.nim` passed;
    GPUI and Cocoa launchers rebuilt and screenshots refreshed through the `isonim-examples` dev shell.
  - review sequence:
    seeded run `7748a611-d835-4881-b62d-ba1c51d67293`, report `eb0b192d-b74d-4fea-a31c-09fff5b8687d`, exposed the first GPUI root-width attempt as a regression (`gpui-incorrect-letterbox-and-clipped-layout`, rendering 5);
    seeded run `af66527c-fc1c-45fa-b7f0-0a378542cca6`, report `e77d8297-bc18-4de6-aa78-81764f4bf43b`, confirmed the GPUI layout regression was fixed but GPUI was still 6 due to blur/left-heavy composition and Cocoa regressed to 5;
    seeded run `1e149089-a7f3-42fb-b034-ffa9a8c132d4`, report `27d4d5d4-0a3e-4c09-b5b2-fd7ad563c3f7`, scored web 8, tui 7, gpui 7, freya 7, cocoa 6, android 4 stale/blocked, ios 7.
  - score delta from carry-over `fa3057b6-7d60-4e43-beea-20b85ecfe909`: gpui rendering 6 -> 7; cocoa rendering stayed 6 after attempted fixes.
  - terminal status: escalated because the campaign gates are still unmet and Cocoa remains below 7 after repeated prescription-driven leaf/adapter attempts.
- 2026-05-21T08:52:00Z fixed a capture-surface flake and escalated at
  the campaign gate.
  - patch:
    `/Users/zahary/metacraft/isonim/src/isonim/editor/views/preview_pane.nim`
    now hides the Brief tab host unless the Brief tab is active; this
    fixed screenshots that showed the brief document while the Preview
    tab was selected;
    `/Users/zahary/metacraft/isonim/src/isonim/editor/views/canvas_mount.nim`
    changes the active canvas frame to a concrete `#303244` hairline;
    `/Users/zahary/metacraft/isonim-cocoa/src/isonim_cocoa/uikit/views.nim`
    and `.../uikit_renderer.nim` add UISegmentedControl title-colour
    styling;
    `/Users/zahary/metacraft/isonim-examples/task_app/ios/leaves.nim`
    uses legible inactive segmented labels, dark selected labels,
    smaller switch dimensions, and restores the summary `✓` glyph.
  - attempted/reverted:
    `/Users/zahary/metacraft/isonim-examples/task_app/freya/leaves.nim`
    was changed to cap the app shell at 960px and center it, but review
    `5600dfd7-a2b1-45d8-ad14-88998a96d63a` showed a blocker
    regression (`freya-remove-controls-missing`) and a white letterbox
    band, so the width-cap/centering was backed out;
    `/Users/zahary/metacraft/isonim-examples/task_app/cocoa/leaves.nim`
    briefly used taller 44/48px input/row metrics, but review
    `5600dfd7-a2b1-45d8-ad14-88998a96d63a` scored Cocoa 5, so those
    metrics were backed out.
  - verification:
    `direnv exec /Users/zahary/metacraft/isonim nim c --styleCheck:usages --styleCheck:error --path:src --mm:orc --threads:on tests/test_editor_shell_views.nim`
    passed;
    `direnv exec /Users/zahary/metacraft/isonim-examples nim c -r tests/test_freya_leaves_end_to_end.nim`
    passed;
    `direnv exec /Users/zahary/metacraft/isonim-examples nim c -r tests/test_cocoa_leaves_macos_only.nim`
    passed;
    `direnv exec /Users/zahary/metacraft/isonim-examples nim check task_app/ios/leaves.nim`
    passed; `nim c task_app/main_ios.nim` compiled through C generation
    but could not link because `UIKit.framework` is unavailable in this
    shell.
  - build/capture:
    `just build-backends`, `just build-backends-macos`, and explicit
    editor JS build with sibling paths
    (`--path:../nim-agents/src --path:../nim-acp/src --path:../nim-agent-harbor/src`)
    passed; refreshed web/tui/gpui/freya/cocoa screenshots through
    `node tools/editor-screenshot.mjs --view render --component task-app
    --backend <backend> --no-build`.
  - review:
    run `dcaee42c-d379-44a1-b277-dca37a2e598c`, report
    `8bd33ab7-f337-4946-92e9-df2b06d240af`, exposed the invalid
    Brief-pane capture flake; after the tab-host fix, run
    `c429acad-7000-4b15-9d0f-d2a338e6b258`, report
    `5600dfd7-a2b1-45d8-ad14-88998a96d63a`, exposed the Freya/Cocoa
    regressions; final run `a5ab4af3-f12c-44e0-9e23-875a8aa32170`,
    report `9131cf5a-da0a-43fb-a5a1-6b1bfdd070d0`, scored web 9,
    tui 7, gpui 7, freya 6, cocoa 6, android 4 stale/blocked, ios 7
    stale/device carry-over.
- 2026-05-21T09:06:19Z verified Cocoa layout-gap adapter lift and
  escalated with remaining campaign gates unmet.
  - patch:
    `/Users/zahary/metacraft/isonim-render-serve/src/isonim_render_serve/adapters/cocoa_adapter.nim`
    now honors `data-layout-padding` and `data-layout-gap` in the
    AppKit capture layout pass and in the element-tree manifest
    geometry;
    `/Users/zahary/metacraft/isonim-render-serve/tests/test_cocoa_adapter_macos_only.nim`
    adds a deterministic manifest geometry test for padding/gap;
    `/Users/zahary/metacraft/isonim-examples/task_app/cocoa/leaves.nim`
    emits explicit layout padding/gap attributes for the Task App
    shell, input row, filter row, task rows, list, and summary.
  - verification:
    `direnv exec /Users/zahary/metacraft/isonim-render-serve nim c --styleCheck:usages --styleCheck:error --path:src --path:tests --mm:orc --threads:on -r tests/test_cocoa_adapter_macos_only.nim`
    passed;
    `direnv exec /Users/zahary/metacraft/isonim-examples nim c -r tests/test_cocoa_leaves_macos_only.nim`
    passed;
    `direnv exec /Users/zahary/metacraft/isonim-examples just build-backends-macos`
    passed;
    `direnv exec /Users/zahary/metacraft/isonim-examples node tools/editor-screenshot.mjs --view render --component task-app --backend cocoa --no-build`
    refreshed
    `/Users/zahary/metacraft/isonim-examples/screenshots/render/task-app-cocoa.png`.
  - review:
    seeded run `b312aa73-d024-4580-8267-b12cc9eee8e0`, report
    `02e18bea-cce5-4fbb-97cf-c396594416a6`, scored web 9, tui 7,
    gpui 8, freya 7, cocoa 7, android 4 stale/blocked, ios 8.
    Cocoa rendering moved 6 -> 7; web/tui/ios did not regress.
  - commit: not created, per `notesToOrchestrator`.
- 2026-05-21T09:20:38Z attempted TUI/Freya/Cocoa prescription pass and
  escalated with campaign gates unmet.
  - patch:
    `/Users/zahary/metacraft/isonim/src/isonim/editor/views/canvas_mount.nim`
    keeps the TUI terminal host's visibility helper from discarding
    centering styles;
    `/Users/zahary/metacraft/isonim-examples/task_app/freya/leaves.nim`
    changes Freya shell/list rhythm to 12px between header/list bands
    and 8px between task rows;
    `/Users/zahary/metacraft/isonim-examples/task_app/cocoa/leaves.nim`
    raises Cocoa row label/summary font sizes and row padding.
  - attempted/reverted:
    TUI was briefly changed to attach an 80x24 xterm surface and force
    the xterm host itself to flex-center. The real screenshot rendered
    a blank/near-empty TUI frame, so the grid-size and xterm-host flex
    changes were reverted before final review. The restored 120x36
    xterm path remains visible but reviewer still flags it as
    underusing the canvas.
  - verification:
    `direnv exec /Users/zahary/metacraft/isonim nim c --styleCheck:usages --styleCheck:error --path:src --mm:orc --threads:on tests/test_editor_shell_views.nim`
    passed;
    `direnv exec /Users/zahary/metacraft/isonim-examples nim c -r tests/test_freya_leaves_end_to_end.nim`
    passed;
    `direnv exec /Users/zahary/metacraft/isonim-examples nim c -r tests/test_cocoa_leaves_macos_only.nim`
    passed;
    editor JS was rebuilt with explicit sibling agent paths;
    `just build-backends` passed for web/tui/gpui/freya and
    `just build-backends-macos` passed for Cocoa; refreshed TUI,
    Freya, and Cocoa screenshots through
    `node tools/editor-screenshot.mjs --view render --component task-app --backend <backend> --no-build`.
  - review:
    intermediate run `bac8e083-85d3-4ab8-b9db-058913a59deb`, report
    `35ce066c-24a9-440c-8dbe-28c6cfa0f298`, scored web 9, tui 7,
    gpui 8, freya 7, cocoa 6, android 4 stale/blocked, ios 7 stale.
    Final run `a977765b-0374-45b5-a1e2-52e4d0f947a1`, report
    `5d92879d-d0be-43de-863e-505633e529c5`, scored web 9, tui 7,
    gpui 7, freya 7, cocoa 7, android 4 stale/blocked, ios 6 stale.
    No two-cell lift to >=8 was verified; campaign escalated.
  - commit: not created, per `notesToOrchestrator`.
## Notes to next campaign

- GPUI's remaining gap after the centered-column fix is not content
  completeness; report `27d4d5d4-0a3e-4c09-b5b2-fd7ad563c3f7` points
  at `gpui-scaling-softness` and `gpui-letterbox-ambiguous`, so next work
  should inspect the GPUI raster scale / preview frame path rather than
  another task-row leaf tweak.
- Cocoa stayed at 6 after AppKit metric and cross-axis control-height
  changes. The next pass likely needs real native grouped-list /
  NSSegmentedControl treatment in the Cocoa renderer or adapter, not just
  narrower `data-fixed-width` constants in `task_app/cocoa/leaves.nim`.
- Do not trust stale Android seeded PNGs for
  `android-remove-controls-missing`; the source currently contains
  the visible remove chip, but proof requires a real `adb` capture.
- The TUI examples should avoid broad `import isonim_tui` in launcher
  and focused test paths unless tree-sitter is intentionally needed;
  the broad import adds `-ltree-sitter` and can break otherwise
  unrelated TUI builds.
- GPUI and Freya are evaluable when tests, screenshot launchers, and
  `node tools/editor-screenshot.mjs` run through the `isonim-examples`
  dev shell. Do not mark shim dylib loading as a blocker until that
  shell has been tried.
- Freya's cramped row-content defect did not respond to another
  `data-fixed-width` hint on the label. Next work should inspect the
  Freya renderer/layout bridge for a real flexible spacer or trailing
  alignment mechanism before adding more leaf width constants.
- `review-prompt@v2` successfully forced concrete `prescription:`
  lines in the raw reviewer report, but the current parser drops that
  field from `agent_reports.parsed_scores`. If campaigns need to make
  prescription-driven decisions from structured JSON rather than the
  raw markdown, extend `ReviewerDefect` / `toParsedScoresJsonb` to
  preserve `prescription`.
- The Preview/Brief tab hosts need real `display` hiding, not only
  active-tab metadata. Run `dcaee42c-d379-44a1-b277-dca37a2e598c`,
  report `8bd33ab7-f337-4946-92e9-df2b06d240af`, proved that leaving
  the Brief host visible can make all refreshed cells review as the
  wrong surface even when the Preview tab is selected.
- Freya should not be fixed by capping the whole app shell at 960px:
  that creates a white right-side band and can hide trailing remove
  controls. Constrain inner content or fix the renderer/background path
  instead.
- UIKit segmented-control colour support now exists in `isonim-cocoa`
  via `color` and `selected-color`; the next real iOS stream capture
  should verify inactive label contrast, then address the remaining
  `Add` vs `Add Task` CTA label if the brief author requires exact
  wording.
- TUI 80x24 xterm attach is not a drop-in fix for
  `tui-preview-underuses-canvas`: this turn's real screenshot went
  blank after switching from 120x36 to 80x24. Investigate the
  terminal bridge/grid handshake before changing the grid dimensions
  again.
- Freya's remaining `freya-composition-too-wide-and-top-heavy` defect
  is not solved by row/header gap tweaks. The next pass needs a real
  content-column max-width/centering mechanism in the Freya adapter or
  renderer path; previous whole-shell capping caused a white band, so
  constrain the inner content/background together.
