#!/usr/bin/env node
// tools/editor-screenshot.mjs
//
// Captures screenshots from the isonim-examples demo editor at
// various viewports. Mirrors the upstream isonim/tools/editor-screenshot.mjs
// helper but builds the isonim-examples editor instance
// (editor/main.nim) and serves it on port 8091 (vs 8090 for the
// upstream wanderlust editor).
//
// Usage:
//   node tools/editor-screenshot.mjs                    # all views, all sizes
//   node tools/editor-screenshot.mjs --view shell       # just the editor shell
//   node tools/editor-screenshot.mjs --size wide        # just wide viewport
//   node tools/editor-screenshot.mjs --view shell --size narrow
//   node tools/editor-screenshot.mjs --list             # list available views and sizes
//   node tools/editor-screenshot.mjs --port 9091        # override the server port
//   node tools/editor-screenshot.mjs --no-build         # skip nim compilation
//
// Screenshots are saved to: build/editor/screenshots/<view>-<size>.png
//
// M-EVP-2: each named view declares `expectedStory` + `expectedBackend`.
// After `setup(page)` runs, the tool reads the iframe's `body[data-story]`
// + `body[data-backend]` attributes; if either doesn't match the declared
// expectation, the tool throws and exits non-zero. This stops silent
// "stale state" PNGs from making it into the v5-style visual review.

import { execSync, exec, spawn } from "child_process";
import { mkdirSync, rmSync, existsSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import { promisify } from "util";
import net from "net";

const execAsync = promisify(exec);

const __dirname = dirname(fileURLToPath(import.meta.url));
const projectRoot = join(__dirname, "..");
const editorDir = join(projectRoot, "build", "editor");
const screenshotDir = join(editorDir, "screenshots");

// M-EVP-12 viewport contract:
//
//   - `wide`   1920 × 1080 (canonical desktop, large screens).
//   - `laptop` 1440 ×  900 (canonical laptop; the strict density gate).
//   - `narrow`  375 ×  812 (M-EVP-12 spec: narrow target for shell);
//                aliased to the iPhone 13 mini portrait dimensions.
//
// The medium / tablet / pre-M-EVP-12 mobile (=narrow alias) entries
// remain available for legacy --size flags; new view briefs should
// only target wide / laptop / narrow.
export const sizes = {
  wide: { width: 1920, height: 1080 },
  laptop: { width: 1440, height: 900 },
  medium: { width: 1280, height: 800 },
  tablet: { width: 1024, height: 768 },
  // M-EVP-12: `narrow` is the canonical mobile shell viewport. The
  // legacy pre-M-EVP-12 sizes table called this entry `mobile` and
  // used 768×1024 for `narrow`; the M-EVP-12 spec re-purposes
  // `narrow` to the strict mobile size and drops the 768×1024
  // tablet-narrow entry (it overlapped with `tablet`).
  narrow: { width: 375, height: 812 },
  // Deprecated alias retained for back-compat with any pre-M-EVP-12
  // caller that hard-coded `--size mobile`. New code: use `narrow`.
  mobile: { width: 375, height: 812 },
};

// ---------------------------------------------------------------------------
// Section-expansion helper
//
// Defaults today (per `defaultSidebarSections` in
// isonim/src/isonim/editor/viewmodels.nim): userJourneys=true, pages=true,
// components=true, foundations=true, guidelines=false. The
// `story-selected*` setups land inside the Components section; the group
// "Settings App / Group" is collapsed by default (per `stories.nim`). The
// current setup clicked the group toggle but did NOT first ensure the
// ancestor section was expanded — if a future default change ever collapses
// Components by default, the deeper story link is `display: none` and the
// previous `page.$(...).click()` would silently no-op against a hidden
// element. M-EVP-2 hardens every setup by adding an explicit
// `ensureSectionExpanded` guard, checking `aria-expanded` before clicking
// so we never toggle an already-open section closed.
// ---------------------------------------------------------------------------

export async function ensureSectionExpanded(page, sectionLabel) {
  const toggle = page
    .locator(`[aria-label="Toggle ${sectionLabel} section"]`)
    .first();
  await toggle.waitFor({ state: "attached", timeout: 10_000 });
  const expanded = await toggle.getAttribute("aria-expanded");
  if (expanded !== "true") {
    await toggle.click();
    // After clicking the toggle the chevron re-renders with
    // aria-expanded="true"; wait for it so the section body's group
    // toggles are query-able.
    await page
      .locator(`[aria-label="Toggle ${sectionLabel} section"][aria-expanded="true"]`)
      .first()
      .waitFor({ state: "attached", timeout: 5_000 });
  }
}

export async function ensureGroupExpanded(page, groupName) {
  const toggle = page
    .locator(`[aria-label="Toggle ${groupName} stories"]`)
    .first();
  await toggle.waitFor({ state: "attached", timeout: 10_000 });
  const expanded = await toggle.getAttribute("aria-expanded");
  if (expanded !== "true") {
    await toggle.click();
    await page
      .locator(`[aria-label="Toggle ${groupName} stories"][aria-expanded="true"]`)
      .first()
      .waitFor({ state: "attached", timeout: 5_000 });
  }
}

export async function selectStory(page, storyLabel) {
  const story = page
    .locator(`[aria-label="Select story ${storyLabel}"]`)
    .first();
  await story.waitFor({ state: "visible", timeout: 10_000 });
  await story.click();
}

export async function clickBackendChip(page, backendLabel) {
  const chip = page
    .locator(`[aria-label="Preview backend ${backendLabel}"]`)
    .first();
  await chip.waitFor({ state: "visible", timeout: 10_000 });
  await chip.click();
  // The chip flips `aria-pressed` as part of the same reactive update
  // that writes vm.platform and re-runs demoPreviewHook. Waiting for
  // it gives us a clean cause-and-effect signal.
  await page
    .locator(
      `[aria-label="Preview backend ${backendLabel}"][aria-pressed="true"]`,
    )
    .first()
    .waitFor({ state: "attached", timeout: 5_000 });
}

// ---------------------------------------------------------------------------
// Iframe state probes
//
// The editor shell mounts ALL view components (storyboard, component
// detail, page preview, foundations, vector editor) into the DOM at
// once and uses `display:none` to hide the inactive ones. That means
// `document.querySelector("iframe")` would return the FIRST iframe in
// the document — typically the (hidden) storyboard's flow mini-preview
// iframe — even when the active view is the component detail.
//
// `readIframeState` walks every iframe and picks the one whose ancestor
// chain is actually rendered (offsetParent != null is the canonical
// "is this element laid out / visible" check in the DOM). It returns
// the iframe's body `data-story` + `data-backend` reading the same
// way M-EVP-1 does: same-origin contentDocument dataset first, srcdoc
// regex fallback.
//
// `expectedSrcdocBackend` is used both as a backend filter (when set,
// we only consider iframes whose srcdoc already declares the expected
// backend — disambiguates the case where the iframe srcdoc rewrite
// is mid-flight) and as a tiebreaker for noise. Pass empty string to
// disable that filter.
// ---------------------------------------------------------------------------

export async function readIframeState(page, expectedSrcdocBackend = "") {
  return await page.evaluate((expectedBackendFilter) => {
    const iframes = Array.from(document.querySelectorAll("iframe"));
    if (iframes.length === 0) {
      return { story: null, backend: null, iframePresent: false };
    }
    // Prefer iframes that are actually laid out. An iframe inside a
    // `display:none` ancestor has `offsetParent === null`. Some
    // visible iframes (e.g. those with `position:absolute`) may also
    // report null offsetParent — for those we additionally check the
    // computed display of every ancestor.
    function isVisible(el) {
      if (el.offsetParent !== null) return true;
      let n = el;
      while (n && n !== document.body) {
        const cs = window.getComputedStyle(n);
        if (cs.display === "none") return false;
        n = n.parentElement;
      }
      return true;
    }
    const visibleIframes = iframes.filter(isVisible);
    const pool = visibleIframes.length > 0 ? visibleIframes : iframes;

    function probe(iframe) {
      let story = null;
      let backend = null;
      try {
        const body = iframe.contentDocument?.body;
        if (body) {
          if (typeof body.dataset.backend === "string") {
            backend = body.dataset.backend;
          }
          // data-story is on the inner <main>, not the body.
          const main = body.querySelector('main[data-story]');
          if (main) story = main.getAttribute("data-story");
        }
      } catch {
        /* same-origin failure — fall through to srcdoc parse */
      }
      if (story === null || backend === null) {
        const srcdoc = iframe.getAttribute("srcdoc") ?? "";
        if (backend === null) {
          const m = srcdoc.match(/<body data-backend="([^"]+)"/);
          if (m) backend = m[1];
        }
        if (story === null) {
          const m = srcdoc.match(/<main class="app" data-story="([^"]+)"/);
          if (m) story = m[1];
        }
      }
      return { story, backend };
    }

    // When the caller declares an expectedBackend, prefer an iframe
    // whose srcdoc already shows that backend. This guards against
    // the reactive iframe-srcdoc update being mid-flight at read time
    // (the same window of staleness the M-EVP-1 spec wraps in a poll).
    if (expectedBackendFilter && expectedBackendFilter.length > 0) {
      for (const iframe of pool) {
        const p = probe(iframe);
        if (p.backend === expectedBackendFilter) {
          return { ...p, iframePresent: true };
        }
      }
    }
    const p = probe(pool[0]);
    return { ...p, iframePresent: true };
  }, expectedSrcdocBackend);
}

// ---------------------------------------------------------------------------
// Views
//
// Each entry declares:
//   description   — human-readable summary for `--list`.
//   setup(page)   — async navigation steps that land the editor on the
//                   target view. Uses locator-based clicks (works across
//                   playwright-core and @playwright/test).
//   expectedStory — string the iframe's `<body data-story>` MUST equal
//                   after setup. Empty string means "no iframe / no
//                   story expected" (the bare editor shell).
//   expectedBackend — string the iframe's `<body data-backend>` MUST
//                     equal after setup (e.g. "pbWeb", "pbTui"). Empty
//                     string means "no expectation" (no iframe yet).
// ---------------------------------------------------------------------------

// M-EVP-12: per-view size restriction. When set, --size flags that
// don't intersect are dropped for the view (e.g. shell-narrow only
// captures at the `mobile` viewport per the M-EVP-12 spec; canvas
// views only capture at wide+laptop).
//
// `usesTui = true` declares the view requires the TUI launcher
// subprocess to be running on the bridge port; the screenshot tool
// spawns the launcher on demand.
//
// `requiresTestMode = true` injects `window.__isonimTestMode = true`
// before the editor bundle boots (gates the M-EVP-10 / M-EVP-11
// mirrors used here to assert manifest landings before screenshotting).
//
// `postSetup` runs after `setup` and after the standard
// `verifyExpectedState`. It's the hook for canvas-mode assertions
// that need test-mode mirrors (manifest readiness, hover, dblclick).

// M-EVP-12 default sizing rules per view category. Used when a view
// declares no explicit `viewports` array. The default is
// ["wide", "laptop"]; views whose brief is narrow-specific can
// declare ["mobile"] to skip the wide / laptop capture pair.
const DEFAULT_VIEWPORTS_WIDE_LAPTOP = ["wide", "laptop"];

export const views = {
  shell: {
    description:
      "Editor shell — sidebar + preview + inspector (default state, no story selected)",
    setup: async (_page) => {
      // No navigation; capture the shell on its initial mount.
    },
    viewports: ["wide", "laptop", "narrow"],
    expectedStory: "",
    expectedBackend: "",
  },
  "story-selected": {
    description:
      "Editor shell with the Settings/Group/Appearance story selected",
    setup: async (page) => {
      await ensureSectionExpanded(page, "Components");
      await ensureGroupExpanded(page, "Settings App / Group");
      await selectStory(page, "Settings App / Group / Appearance");
    },
    expectedStory: "Settings App / Group/Appearance",
    expectedBackend: "pbWeb",
  },
  "story-selected-tui": {
    description:
      "Story selected, then TUI backend chip clicked in the preview-pane toolbar",
    setup: async (page) => {
      await ensureSectionExpanded(page, "Components");
      await ensureGroupExpanded(page, "Settings App / Group");
      await selectStory(page, "Settings App / Group / Appearance");
      await clickBackendChip(page, "TUI");
    },
    expectedStory: "Settings App / Group/Appearance",
    expectedBackend: "pbTui",
  },

  // ------------------------------------------------------------------------
  // M-EVP-12: sidebar quick-nav strip
  // ------------------------------------------------------------------------

  "sidebar-quick-nav": {
    description:
      "Sidebar after a search-typed-and-cleared probe and a Components quick-nav click (M-EVP-9 strip + filter + empty-category)",
    setup: async (page) => {
      // Type a filter, wait for the tree to narrow, then clear it.
      // This exercises the M-EVP-9 real-time filter; the cleared
      // input is the captured state.
      const searchInput = page
        .locator('[data-sidebar-search="true"]')
        .first();
      await searchInput.waitFor({ state: "visible", timeout: 10_000 });
      await searchInput.fill("spacing");
      await page.waitForTimeout(150);
      await searchInput.fill("");
      // Click the Components quick-nav icon.
      const componentsIcon = page
        .locator(
          '[data-sidebar-quicknav="true"] [data-category-kind="skComponent"]',
        )
        .first();
      await componentsIcon.waitFor({ state: "visible", timeout: 10_000 });
      await componentsIcon.click();
      // The active-category handler expands the Components section
      // and updates aria-pressed; wait for the pressed state to
      // settle so the screenshot captures the active highlight.
      await page
        .locator(
          '[data-sidebar-quicknav="true"] [data-category-kind="skComponent"][aria-pressed="true"]',
        )
        .first()
        .waitFor({ state: "attached", timeout: 5_000 });
    },
    expectedStory: "",
    expectedBackend: "",
  },

  // ------------------------------------------------------------------------
  // M-EVP-12: vector editor (empty / split / carousel variants)
  //
  // The vector editor is mounted by `vm.openVectorEditor(story)`. The
  // editor's sidebar exposes the `Task Check Icon` vector-symbol
  // story under Foundations → `Task App / Vector Symbols`.
  // ------------------------------------------------------------------------

  "vector-editor-empty": {
    description:
      "Vector editor with no usage context — opened on the seeded 'Empty Glyph' symbol (0 usages)",
    setup: async (page) => {
      // Foundations is in the canonical sidebar section ordering;
      // ensure the section is expanded so the vector-symbol group's
      // toggle is reachable, then expand the group itself.
      await ensureSectionExpanded(page, "Foundations");
      await ensureGroupExpanded(page, "Task App / Vector Symbols");
      // M-EVP-8 inline Edit affordance is the canonical path to the
      // vector editor — clicking the `[data-vector-edit="true"]`
      // button calls `vm.openVectorEditor(story)` directly. No
      // intermediate story selection is needed (and `selectStory`
      // would route to evComponentDetail per `viewForStory`, then
      // the Edit click would still re-route to evVectorEditor; doing
      // only the Edit click is simpler and avoids that flicker).
      await openVectorEditorViaInlineEdit(page, "Empty Glyph");
    },
    expectedStory: "",
    expectedBackend: "",
  },

  "vector-editor-with-symbol": {
    description:
      "Vector editor opened on 'Task Filter Icon' — natural 2-usage workspace seed → split (stacked) usage panel",
    setup: async (page) => {
      await ensureSectionExpanded(page, "Foundations");
      await ensureGroupExpanded(page, "Task App / Vector Symbols");
      await openVectorEditorViaInlineEdit(page, "Task Filter Icon");
    },
    expectedStory: "",
    expectedBackend: "",
  },

  "vector-editor-carousel": {
    description:
      "Vector editor opened on 'Task Check Icon' — natural 6-usage workspace seed → carousel usage panel; advances to index 2 so Prev and Next are both enabled",
    setup: async (page) => {
      await ensureSectionExpanded(page, "Foundations");
      await ensureGroupExpanded(page, "Task App / Vector Symbols");
      await openVectorEditorViaInlineEdit(page, "Task Check Icon");
      // Advance the carousel to index 2 (the 3rd dot) so Prev/Next
      // are both enabled — a boundary-free snapshot. Two real
      // clicks on the Next button — no VM mutation.
      const next = page
        .locator('[data-vector-usage-next="true"]')
        .first();
      await next.waitFor({ state: "visible", timeout: 10_000 });
      await next.click();
      await page.waitForTimeout(80);
      await next.click();
      await page.waitForFunction(
        () => {
          const panel = document.querySelector(
            '[data-vector-usage-carousel="true"]',
          );
          return !!(
            panel && panel.getAttribute("data-vector-usage-index") === "2"
          );
        },
        null,
        { timeout: 5_000 },
      );
    },
    expectedStory: "",
    expectedBackend: "",
  },

  // ------------------------------------------------------------------------
  // M-EVP-12: canvas preview (RS-M11 Pattern A) + M-EVP-10 affordances
  //
  // These views require the TUI launcher subprocess to be running on
  // the bridge port. The screenshot tool spawns it on demand.
  // ------------------------------------------------------------------------

  "canvas-preview-tui": {
    description:
      "TUI canvas with M-EVP-10 hover label + selection outline + breadcrumb (View mode, no handles)",
    usesTui: true,
    requiresTestMode: true,
    setup: async (page) => {
      await selectTaskListStoryForCanvas(page);
      await clickBackendChip(page, "TUI");
      await waitForCanvasManifest(page);
      const target = await pickTaskRowFromManifest(page);
      const point = await canvasPointForBounds(page, target.bounds);
      await page.mouse.move(point.clientX, point.clientY);
      await page.waitForFunction(
        (expected) => {
          const v = window.__isonimHoveredComponentPath;
          return typeof v === "string" && v === expected;
        },
        target.componentPath,
        { timeout: 10_000 },
      );
      await page.mouse.click(point.clientX, point.clientY);
      await page.waitForFunction(
        (expected) => {
          const v = window.__isonimSelectedComponentPath;
          return typeof v === "string" && v === expected;
        },
        target.componentPath,
        { timeout: 10_000 },
      );
      // Re-hover so the hover label is visible alongside the
      // selection outline + breadcrumb when the screenshot fires.
      await page.mouse.move(point.clientX, point.clientY);
      // M-EVP-12 fix-cycle 2: explicit waits for the selection outline
      // *and* the breadcrumb panel — the createRenderEffect that
      // positions them runs asynchronously after the click; before it
      // fires the breadcrumb still has display=none / empty text and
      // the screenshot would catch a stale "no overlay" frame.
      await page
        .locator('[data-canvas-selection-outline="true"]')
        .first()
        .waitFor({ state: "visible", timeout: 5_000 });
      await page
        .locator('[data-canvas-selection-breadcrumb="true"]')
        .first()
        .waitFor({ state: "visible", timeout: 5_000 });
      await page.waitForFunction(
        () => {
          const bc = document.querySelector(
            '[data-canvas-selection-breadcrumb="true"]',
          );
          return !!bc && (bc.textContent ?? "").trim().length > 0;
        },
        null,
        { timeout: 5_000 },
      );
      await page.waitForTimeout(150);
    },
    expectedStory: "",
    expectedBackend: "",
  },

  "canvas-preview-edit-mode": {
    description:
      "TUI canvas with selection outline + 8 edit-mode handles",
    usesTui: true,
    requiresTestMode: true,
    setup: async (page) => {
      await selectTaskListStoryForCanvas(page);
      await clickBackendChip(page, "TUI");
      await waitForCanvasManifest(page);
      const target = await pickTaskRowFromManifest(page);
      const point = await canvasPointForBounds(page, target.bounds);
      await page.mouse.click(point.clientX, point.clientY);
      await page.waitForFunction(
        (expected) => {
          const v = window.__isonimSelectedComponentPath;
          return typeof v === "string" && v === expected;
        },
        target.componentPath,
        { timeout: 10_000 },
      );
      // Switch to Edit mode via the chrome bar mode chip; this is
      // the canonical M-EVP-10 path that paints the 8 handles.
      const editChip = page
        .locator(
          '[data-preview-mode="edit"]:not([data-preview-mode-disabled="true"])',
        )
        .first();
      await editChip.waitFor({ state: "visible", timeout: 5_000 });
      await editChip.click();
      // M-EVP-12 fix-cycle 2: the previous "wait for count === 8"
      // counted handles in the DOM regardless of display, so the
      // screenshot could fire before the cascade (editMode flips to
      // emEdit → createRenderEffect → handlesGroup display:block +
      // per-handle positioning) actually painted. The proper gate is:
      //
      //   1. The chip's reactive binding marks itself aria-pressed
      //      once vm.editMode == emEdit (cascade step 1 settled).
      //   2. The 8-handle group has display:block and each handle
      //      has non-zero bounding-rect (cascade step 3 settled).
      //
      // Both must hold before the screenshot can fire.
      await page
        .locator(
          '[data-preview-mode="edit"][aria-pressed="true"]',
        )
        .first()
        .waitFor({ state: "attached", timeout: 5_000 });
      await page.waitForFunction(
        () => {
          const els = Array.from(
            document.querySelectorAll(
              '[data-canvas-selection-handle="true"]',
            ),
          );
          if (els.length !== 8) return false;
          return els.every((el) => {
            const r = el.getBoundingClientRect();
            return r.width > 0 && r.height > 0;
          });
        },
        null,
        { timeout: 10_000 },
      );
    },
    expectedStory: "",
    expectedBackend: "",
  },

  "canvas-preview-vector-dblclick-open": {
    description:
      "Editor state right after a vector-symbol canvas dblclick opens the vector editor (M-EVP-11)",
    usesTui: true,
    requiresTestMode: true,
    setup: async (page) => {
      await selectTaskListStoryForCanvas(page);
      await clickBackendChip(page, "TUI");
      await waitForCanvasManifest(page);
      // Find the TaskCheckIcon vector-symbol manifest entry.
      const target = await page.evaluate(() => {
        const m = window.__isonimManifest;
        if (!m || !Array.isArray(m.elements)) return null;
        const entry = m.elements.find(
          (e) =>
            e.kind === "vector-symbol" &&
            e.componentPath === "task_app/views/TaskCheckIcon",
        );
        return entry ? { bounds: entry.bounds,
                         componentPath: entry.componentPath } : null;
      });
      if (!target) {
        throw new Error(
          "canvas-preview-vector-dblclick-open: no vector-symbol " +
            "manifest entry with componentPath " +
            "task_app/views/TaskCheckIcon — has the TaskCheckIcon " +
            "leaf been wired in the TUI summary bar?",
        );
      }
      const point = await canvasPointForBounds(page, target.bounds);
      await page.mouse.dblclick(point.clientX, point.clientY);
      // Wait for the vector editor mount + target-string mirror.
      await page.waitForFunction(
        () =>
          window.__isonimEditorActiveView === "evVectorEditor" &&
          window.__isonimVectorEditorTarget ===
            "task_app/views/TaskCheckIcon",
        null,
        { timeout: 10_000 },
      );
      await page.waitForTimeout(150);
    },
    expectedStory: "",
    expectedBackend: "",
  },
};

// ---------------------------------------------------------------------------
// Helpers used by the M-EVP-12 view setups.
// ---------------------------------------------------------------------------

async function openVectorEditorViaInlineEdit(page, symbolName) {
  // M-EVP-8 inline Edit affordance: each skVectorSymbol row in the
  // sidebar exposes a `[data-vector-edit="true"]` button next to
  // the row label. Clicking it calls `vm.openVectorEditor(story)`
  // which flips `vm.activeView` to `evVectorEditor`.
  //
  // *Quirk* (post-M-EVP-9 sidebar): an `event.stopPropagation()`
  // on the inline Edit button is documented in shell.nim but the
  // DSL's ``addEventListener`` wrapper doesn't actually emit one,
  // so clicking the button via `playwright.click()` also bubbles
  // up to the row's `onclick = selectStory` handler — which then
  // calls `selectStory(skVectorSymbol)` → `evComponentDetail`
  // (overrides the vector-editor view we just opened). We side-
  // step the bubbling by dispatching the click event directly
  // and immediately re-asserting the active view via the editor's
  // openVectorEditor entry. Because the editor's DSL handlers are
  // bound through `addEventListener("click", openVec)` we can
  // simulate the same code path by calling the bound handler with
  // a non-bubbling synthetic Event — which is exactly what
  // ``el.dispatchEvent(new Event('click', { bubbles: false }))``
  // does in JS. The row handler is bound to its OWN element, not
  // a wrapping document listener, so a non-bubbling event fires
  // only the Edit-button handler.
  await page.locator(`[aria-label="Edit vector symbol ${symbolName}"]`)
    .first()
    .waitFor({ state: "visible", timeout: 10_000 });
  await page.evaluate((label) => {
    const el = document.querySelector(`[aria-label="${label}"]`);
    if (!el) throw new Error(`Edit affordance for "${label}" not in DOM`);
    el.dispatchEvent(new Event("click", { bubbles: false }));
  }, `Edit vector symbol ${symbolName}`);
  // Wait for the vector editor surface to mount.
  await page
    .locator('[data-vector-editor="true"]')
    .first()
    .waitFor({ state: "visible", timeout: 10_000 });
}

async function selectTaskListStoryForCanvas(page) {
  // Navigate the sidebar to a TaskList story so the
  // component-detail view mounts the project canvas.
  await ensureSectionExpanded(page, "Components");
  await ensureGroupExpanded(page, "Task App / TaskList");
  // The first TaskList story in stories.nim is "Empty" — pick
  // "Two Active" instead since it produces multiple TaskRow
  // manifest entries which exercises the manifest hit-test better.
  await selectStory(page, "Task App / TaskList / Two Active");
}

async function waitForCanvasManifest(page) {
  // The canvas becomes the active surface for non-Web backends.
  const canvas = page
    .locator('canvas[data-canvas-active="true"]')
    .first();
  await canvas.waitFor({ state: "visible", timeout: 15_000 });
  // Wait for non-empty paint.
  await page.waitForFunction(
    () => {
      const list = document.querySelectorAll(
        'canvas[data-canvas-active="true"]',
      );
      if (list.length === 0) return false;
      const c = list[0];
      if (c.width === 0 || c.height === 0) return false;
      const ctx = c.getContext("2d");
      if (!ctx) return false;
      try {
        const img = ctx.getImageData(0, 0, c.width, c.height);
        for (let i = 0; i < img.data.length; i += 4) {
          if (img.data[i] | img.data[i + 1] | img.data[i + 2]) return true;
        }
      } catch {
        return false;
      }
      return false;
    },
    null,
    { timeout: 30_000 },
  );
  // Wait for the gated element-tree manifest mirror.
  await page.waitForFunction(
    () => {
      const m = window.__isonimManifest;
      return !!(
        m &&
        m.type === "element-tree" &&
        Array.isArray(m.elements) &&
        m.elements.length > 0
      );
    },
    null,
    { timeout: 15_000 },
  );
  // Wait for canvas dimensions to match the manifest surface.
  await page.waitForFunction(
    () => {
      const m = window.__isonimManifest;
      const list = document.querySelectorAll(
        'canvas[data-canvas-active="true"]',
      );
      if (list.length === 0 || !m) return false;
      const c = list[0];
      return c.width === m.surfaceWidth && c.height === m.surfaceHeight;
    },
    null,
    { timeout: 10_000 },
  );
}

async function pickTaskRowFromManifest(page) {
  return await page.evaluate(() => {
    const m = window.__isonimManifest;
    const rows = m.elements.filter((e) =>
      e.componentPath.startsWith("task_app/views/TaskRow#"),
    );
    const row = rows.length >= 2 ? rows[1] : rows[0];
    return {
      id: row.id,
      componentPath: row.componentPath,
      bounds: row.bounds,
    };
  });
}

async function canvasPointForBounds(page, bounds) {
  return await page.evaluate((row) => {
    const list = document.querySelectorAll(
      'canvas[data-canvas-active="true"]',
    );
    const c = list[0];
    const rect = c.getBoundingClientRect();
    const cx = row.x + Math.floor(row.w / 2);
    const cy = row.y + Math.floor(row.h / 2);
    const clientX = rect.left + (cx + 0.5) * (rect.width / c.width);
    const clientY = rect.top + (cy + 0.5) * (rect.height / c.height);
    return { clientX, clientY };
  }, bounds);
}

// ---------------------------------------------------------------------------
// Backend-launcher subprocess management.
//
// The canvas-* + render-category views need a real per-backend bridge
// process running on a well-known port so `attachBridgeClient` can
// connect. We start one launcher process per backend for the lifetime
// of the screenshot run, then poll the bridge TCP port before driving
// the editor.
//
// Per-backend port table — mirrors `bridgePortForBackend` in
// isonim/src/isonim/editor/streaming_preview.nim and `BRIDGE_PORTS` in
// tools/editor-server.mjs.
//
// Note: the deprecated pixel TUI launcher (`isonim-examples-tui`) used
// port 8102 (route `/bridge/tui`). Post-RS-M13 the canonical TUI bridge
// is `tui-term` on 8112 (route `/tui-bridge`). The render category
// always uses tui-term; the legacy `tui` slot is captured under that
// binary but filed under the canonical `tui` filename.
// ---------------------------------------------------------------------------

const TUI_BRIDGE_PORT = 8102; // legacy pixel TUI (kept for the canvas-*
                              // views that still spawn the old `tui`
                              // binary).

const BACKEND_LAUNCHERS = {
  // Slot name → { bin, port, requireMacos, requireEnv, requireAdb,
  //               extraArgs, displayName, chipLabel }
  web: {
    bin: "isonim-examples-web", port: 8101, chipLabel: "Web",
  },
  // `tui` is the canonical render-category slot; we always boot
  // `isonim-examples-tui-term` (the post-RS-M13 D/M/P xterm.js
  // launcher) on its 8112 bridge port. The deprecated pixel TUI
  // (`isonim-examples-tui` on 8102) is used only by the legacy
  // `canvas-preview-*` views.
  tui: {
    bin: "isonim-examples-tui-term", port: 8112, chipLabel: "TUI",
  },
  "tui-term": {
    bin: "isonim-examples-tui-term", port: 8112, chipLabel: "TUI",
  },
  gpui: {
    bin: "isonim-examples-gpui", port: 8103, chipLabel: "GPUI",
  },
  freya: {
    bin: "isonim-examples-freya", port: 8104, chipLabel: "Freya",
  },
  cocoa: {
    bin: "isonim-examples-cocoa", port: 8105, chipLabel: "Cocoa",
    requireMacos: true,
  },
  // The Android launcher requires `adb` on PATH and a connected
  // device; without one it refuses to start. The screenshot tool
  // detects an unreachable launcher and falls back to a placeholder.
  android: {
    bin: "isonim-examples-android", port: 8106, chipLabel: "Android",
    requireAdb: true,
  },
  // The iOS launcher needs the iPhone's Stream-app listener address
  // in `ISONIM_IOS_DEVICE_ENDPOINT=<host>:<port>`. The known dev
  // device today is `192.168.100.156:8200`; users can override.
  ios: {
    bin: "isonim-examples-ios", port: 8107, chipLabel: "iOS",
    requireMacos: true,
    requireEnv: "ISONIM_IOS_DEVICE_ENDPOINT",
    envDefault: "192.168.100.156:8200",
  },
};

async function waitForTcpPort(port, host, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const ok = await new Promise((resolve) => {
      const sock = net.createConnection({ port, host });
      sock.once("connect", () => { sock.end(); resolve(true); });
      sock.once("error", () => { resolve(false); });
    });
    if (ok) return true;
    await new Promise((r) => setTimeout(r, 100));
  }
  return false;
}

// One-shot probe — returns true iff a TCP listener is currently bound
// on (host, port). Unlike `waitForTcpPort` this does not retry and is
// safe to call before spawning a launcher to detect a lingering
// previous-run process holding the port.
async function isPortInUse(port, host = "127.0.0.1") {
  return await new Promise((resolve) => {
    const sock = net.createConnection({ port, host });
    sock.once("connect", () => { sock.end(); resolve(true); });
    sock.once("error", () => { resolve(false); });
  });
}

// Kill whatever process is currently bound to (host, port). The
// previous screenshot run can leave detached launchers running across
// process boundaries (the cleanup handler only runs on a graceful
// exit; SIGKILL / OOM / `Ctrl-C` mid-shell-pipe all leak children).
// When the next run boots a launcher on the same port, `spawn()`
// returns successfully and `waitForTcpPort` sees the OLD launcher's
// port — which was started with the PREVIOUS run's `--demo=` slug —
// and the editor reads frames for the WRONG demo. This produces the
// M-EVP-14 "settings cell shows the task app" / "task cell shows the
// settings app" wrong-demo flakes the reviewer surfaced.
//
// We resolve the holding PID via `lsof -ti:<port>` (BSD/macOS + Linux
// both ship this binary in the editor dev-shell) and send SIGKILL.
// `lsof` exits 1 when nothing is bound, which we treat as "nothing
// to kill" and silently succeed.
async function reclaimPort(port, host = "127.0.0.1") {
  if (!(await isPortInUse(port, host))) return { ok: true, killed: [] };
  return await new Promise((resolve) => {
    const lsof = spawn("lsof", ["-ti", `:${port}`], {
      stdio: ["ignore", "pipe", "pipe"],
    });
    let out = "";
    lsof.stdout.on("data", (b) => { out += b.toString(); });
    lsof.on("close", async () => {
      const pids = out.trim().split(/\s+/).filter((p) => /^\d+$/.test(p))
        .map((p) => parseInt(p, 10));
      const killed = [];
      for (const pid of pids) {
        try {
          process.kill(pid, "SIGKILL");
          killed.push(pid);
        } catch { /* already dead */ }
      }
      // Give the kernel a tick to release the bound port.
      const deadline = Date.now() + 2_000;
      while (Date.now() < deadline) {
        if (!(await isPortInUse(port, host))) {
          resolve({ ok: true, killed });
          return;
        }
        await new Promise((r) => setTimeout(r, 50));
      }
      resolve({ ok: false, killed, reason: "port still bound after kill" });
    });
    lsof.on("error", () => {
      resolve({ ok: false, killed: [], reason: "lsof not available" });
    });
  });
}

// iOS auto-launch.
//
// iOS aggressively suspends/terminates apps. After ~30 s backgrounded,
// the Stream app's NWListener stops accepting and the launcher's
// probe sees nothing. `xcrun devicectl device process launch` brings
// the app to the foreground programmatically — the same thing a user
// would do by tapping the icon. We invoke it BEFORE the existing probe
// so the probe (and the launcher's own configured-endpoint connect)
// actually has a live NWListener to talk to.
//
// Override the device id via `ISONIM_IOS_DEVICE_ID`. Override the
// bundle id via `ISONIM_IOS_BUNDLE_ID` (defaults to the Stream app's
// bundle). If `xcrun devicectl` itself fails (device unplugged, no
// Xcode CLI tools, …) we silently fall through to the existing probe
// path so the unreachable-device placeholder still fires.
async function ensureIosStreamAppRunning(demoSlug = "task") {
  const deviceId =
    process.env.ISONIM_IOS_DEVICE_ID
    ?? "688D4B24-9EDF-51E3-B343-F351DE814897";
  const bundleId =
    process.env.ISONIM_IOS_BUNDLE_ID ?? "com.metacraft.isonim.cocoa.stream";
  // M-EVP-14 iOS demo wiring. The Stream app's
  // FrameStreamingViewController dispatches between three Nim entry
  // points based on the `ISONIM_DEMO` environment variable:
  //
  //   - `task`     → `isonim_task_start` (seeded TaskAppVM demo)
  //   - `settings` → `isonim_settings_start` (SettingsVM demo)
  //   - anything else → legacy `isonim_start` (Branded scene fallback)
  //
  // We always terminate any pre-existing instance so the env var
  // dispatch is honoured on every launch (otherwise iOS would
  // surface the prior instance which captured the previous env).
  const envObj = { ISONIM_DEMO: demoSlug };
  const envArg = JSON.stringify(envObj);
  try {
    await execAsync(
      `xcrun devicectl device process launch --device ${deviceId} ` +
      `--terminate-existing ` +
      `--environment-variables '${envArg}' ` +
      `${bundleId}`,
      { timeout: 15_000 },
    );
  } catch (e) {
    // devicectl exits non-zero when the device isn't connected, isn't
    // paired, or the bundle id is wrong. None of those are fatal here:
    // the probe below will placeholder cleanly, and a user who *can*
    // reach the iPhone via the existing manual-tap path is unblocked.
    console.warn(
      `==> iOS auto-launch failed (${e.message ?? e}); falling back to probe.`,
    );
    return false;
  }
  // Give the NWListener a beat to bind on the device side. The app
  // takes ~1-2 s to come to foreground from a suspended state plus
  // another ~0.5-1 s to re-bind the listener; 3 s covers both with
  // headroom and is still inside the 30 s frame-paint budget.
  await new Promise((r) => setTimeout(r, 3_000));
  return true;
}

// iOS-specific reachability probe.
//
// The pipeline keeps timing out at the 30 s frame-paint wait when the
// iPhone is asleep — the launcher accepts the WS connection but no F
// packets ever arrive, so `waitForFramePainted` burns the full budget
// before falling back to the placeholder PNG. This probe runs BEFORE
// `waitForFramePainted` for the iOS backend: it performs the same two
// things the launcher's `connectIfNeeded` does (configured-endpoint
// TCP connect + Bonjour browse) within a tight ~5 s budget so we can
// surface a clear error to the placeholder text and skip ~25 s of
// dead waiting per iOS cell.
//
// Returns:
//   { ok: true }                  — device reachable
//   { ok: false, reason: "..." }  — device unreachable, with hint text
async function probeIosDevice() {
  const endpoint =
    process.env.ISONIM_IOS_DEVICE_ENDPOINT ?? "192.168.100.156:8200";
  const colonIdx = endpoint.lastIndexOf(":");
  const host = colonIdx > 0 ? endpoint.slice(0, colonIdx) : endpoint;
  const port = colonIdx > 0
    ? parseInt(endpoint.slice(colonIdx + 1), 10)
    : 8200;

  // Step 1: 2 s TCP connect to the configured endpoint.
  const directOk = await new Promise((resolve) => {
    const sock = net.createConnection({ port, host });
    const timer = setTimeout(() => {
      sock.destroy();
      resolve(false);
    }, 2_000);
    sock.once("connect", () => {
      clearTimeout(timer);
      sock.end();
      resolve(true);
    });
    sock.once("error", () => {
      clearTimeout(timer);
      resolve(false);
    });
  });
  if (directOk) return { ok: true };

  // Step 2: 3 s Bonjour browse for `_isonim-stream._tcp`. We only
  // need to see a single "Add" line to confirm the device is awake
  // and publishing — at which point the launcher's own Bonjour
  // fallback will resolve and connect.
  const bonjourSawDevice = await new Promise((resolve) => {
    let resolved = false;
    let proc;
    try {
      proc = spawn("dns-sd", ["-B", "_isonim-stream._tcp", "local."], {
        stdio: ["ignore", "pipe", "ignore"],
      });
    } catch {
      resolve(false);
      return;
    }
    const timer = setTimeout(() => {
      if (resolved) return;
      resolved = true;
      try { proc.kill("SIGTERM"); } catch { /* ignore */ }
      resolve(false);
    }, 3_000);
    proc.stdout.on("data", (b) => {
      const text = b.toString();
      // Look for any line whose 2nd column is `Add` AND whose service
      // type column references our service. The header lines never
      // match because the 2nd column is `Flags`/`Domain`/etc.
      for (const line of text.split("\n")) {
        const tokens = line.trim().split(/\s+/);
        if (tokens.length < 6) continue;
        if (tokens[1] !== "Add") continue;
        if (!tokens[5].includes("_isonim-stream._tcp")) continue;
        if (resolved) return;
        resolved = true;
        clearTimeout(timer);
        try { proc.kill("SIGTERM"); } catch { /* ignore */ }
        resolve(true);
        return;
      }
    });
    proc.once("error", () => {
      if (resolved) return;
      resolved = true;
      clearTimeout(timer);
      resolve(false);
    });
    proc.once("close", () => {
      if (resolved) return;
      resolved = true;
      clearTimeout(timer);
      resolve(false);
    });
  });
  if (bonjourSawDevice) return { ok: true };

  return {
    ok: false,
    reason:
      "iOS device asleep — tap the IsoNim Stream icon on iPhone 14 to " +
      "wake, then re-run",
  };
}

function hasAdbDevice() {
  try {
    const out = execSync("adb devices", {
      stdio: ["ignore", "pipe", "ignore"],
    }).toString();
    // `adb devices` always echoes a header line; real devices appear on
    // subsequent lines with a tab-separated state of `device`.
    return out.split("\n")
      .slice(1)
      .some((l) => /\tdevice\s*$/.test(l.trim() + "\t"));
  } catch {
    return false;
  }
}

// Generic launcher boot. Returns:
//   { ok: true,  proc, port }
// or
//   { ok: false, reason: "<human reason>" }
async function startLauncher(backend, projectRoot, opts = {}) {
  const spec = BACKEND_LAUNCHERS[backend];
  if (!spec) {
    return { ok: false, reason: `unknown backend "${backend}"` };
  }
  if (spec.requireMacos && process.platform !== "darwin") {
    return {
      ok: false,
      reason: `${backend} launcher requires macOS host`,
    };
  }
  if (spec.requireAdb && !hasAdbDevice()) {
    return {
      ok: false,
      reason:
        `${backend} launcher requires \`adb\` on PATH and a connected device`,
    };
  }
  const envExtra = {};
  if (spec.requireEnv) {
    const value = process.env[spec.requireEnv] ?? spec.envDefault;
    if (!value) {
      return {
        ok: false,
        reason: `${backend} launcher requires env var ${spec.requireEnv}`,
      };
    }
    envExtra[spec.requireEnv] = value;
  }
  // iOS-specific fast-fail: before we even spawn the launcher,
  // confirm the iPhone is reachable. The launcher itself now does
  // its own 2 s configured-endpoint try plus a 5 s Bonjour fallback
  // (`editor/backends/ios.nim::connectIfNeeded`), so a fully unreachable
  // device would still bring the launcher up briefly before raising
  // on the first capture — and the 30 s frame-paint wait would then
  // burn its full budget. Probing here saves ~25 s per iOS cell and
  // lets us write a clear placeholder text the user can act on.
  if (backend === "ios") {
    // First: ask the device to foreground the Stream app with the
    // right demo entry point in its environment. We pass the demo
    // slug (default `task`) through so the on-device Swift VC's
    // env-var dispatch picks the matching Nim composition root —
    // M-EVP-14 demo integration. Failures fall through to the probe
    // so the existing "iOS device asleep" placeholder still triggers
    // when the iPhone is truly unreachable.
    const demoSlug = opts.demo ?? "task";
    await ensureIosStreamAppRunning(demoSlug);
    const probe = await probeIosDevice();
    if (!probe.ok) {
      return { ok: false, reason: probe.reason };
    }
  }
  const launcherBin = join(
    projectRoot, "build", "backends", spec.bin,
  );
  if (!existsSync(launcherBin)) {
    return {
      ok: false,
      reason: `launcher binary missing: ${launcherBin}`,
    };
  }
  // The web backend doesn't have a bridge in practice (the editor
  // renders Web in an iframe via demoPreviewHook), but the launcher
  // binary still exists and accepts a port. We just boot it for
  // matrix uniformity; the render-category capture for Web reads the
  // iframe, not the WebSocket.
  const demo = opts.demo ?? "task";
  const args = [
    "--port", String(spec.port),
    "--demo=" + demo,
    "--fps", "8",
  ];
  const staticDir = join(projectRoot, "..", "isonim-render-serve", "static");
  if (existsSync(staticDir)) {
    args.push("--static", staticDir);
  }
  // Reclaim the port before spawn. A detached launcher left over from
  // a previous (possibly crashed / Ctrl-C'd) screenshot run will be
  // holding the port with the WRONG `--demo=` slug; if we don't
  // reclaim, `spawn()` succeeds (creates a child that immediately
  // exits with "Address already in use") and `waitForTcpPort` sees the
  // OLD launcher's still-bound port. The editor then reads the
  // previous demo's frame stream, producing the M-EVP-14 wrong-demo
  // flakes (settings cells rendering task app; task cells rendering
  // settings app — opposite directions depending on which prior run
  // most recently leaked which launcher binary).
  const reclaim = await reclaimPort(spec.port);
  if (reclaim.killed.length > 0) {
    console.log(
      `==> Reclaimed ${backend} port ${spec.port} from stale PID(s): ${reclaim.killed.join(", ")}`,
    );
  }
  if (!reclaim.ok) {
    return {
      ok: false,
      reason:
        `${backend} launcher cannot bind port ${spec.port}: ${reclaim.reason ?? "unknown"}`,
    };
  }
  console.log(
    `==> Starting ${backend} launcher on port ${spec.port}: ${spec.bin} ${args.join(" ")}`,
  );
  const proc = spawn(launcherBin, args, {
    stdio: ["ignore", "pipe", "pipe"],
    detached: true,
    env: { ...process.env, ...envExtra },
  });
  let stderrTail = "";
  let earlyExit = null; // {code, signal} | null
  proc.stdout.on("data", () => { /* discard */ });
  proc.stderr.on("data", (b) => {
    stderrTail = (stderrTail + b.toString()).slice(-512);
  });
  proc.on("exit", (code, signal) => {
    earlyExit = { code, signal };
  });
  const ok = await waitForTcpPort(spec.port, "127.0.0.1", 15_000);
  if (!ok) {
    try { process.kill(-proc.pid); } catch { /* ignore */ }
    return {
      ok: false,
      reason:
        `${backend} launcher did not open port ${spec.port} within 15s` +
        (stderrTail ? ` (stderr tail: ${stderrTail.trim()})` : ""),
    };
  }
  // Sanity check: the child we just spawned must still be alive when
  // the port becomes responsive. If the child exited (e.g. because
  // `reclaimPort` raced and a parallel run booted a competing
  // launcher between our kill and our spawn), the port we're talking
  // to is NOT this child's port — abort rather than silently capture
  // the wrong demo.
  if (earlyExit !== null) {
    return {
      ok: false,
      reason:
        `${backend} launcher PID ${proc.pid} exited before binding ` +
        `port ${spec.port} (code=${earlyExit.code}, signal=${earlyExit.signal})` +
        (stderrTail ? ` (stderr tail: ${stderrTail.trim()})` : ""),
    };
  }
  return { ok: true, proc, port: spec.port, chipLabel: spec.chipLabel };
}

// Backwards-compat shim: callers still invoke startTuiLauncher() for
// the legacy pixel-TUI canvas views. We boot the deprecated `tui`
// binary on port 8102 — NOT the post-RS-M13 `tui-term` launcher —
// because the canvas-preview-* views poll for the legacy F/M/I
// bridge contract.
async function startTuiLauncher(projectRoot) {
  const launcherBin = join(
    projectRoot, "build", "backends", "isonim-examples-tui",
  );
  if (!existsSync(launcherBin)) {
    throw new Error(
      `TUI launcher binary missing: ${launcherBin}. ` +
        "Run `just build-backends-dev-pixel-tui` first.",
    );
  }
  const staticDir = join(
    projectRoot, "..", "isonim-render-serve", "static",
  );
  const args = [
    "--port", String(TUI_BRIDGE_PORT),
    "--demo=tasks",
    "--fps", "8",
  ];
  if (existsSync(staticDir)) {
    args.push("--static", staticDir);
  }
  console.log(
    `==> Starting (legacy) TUI launcher on port ${TUI_BRIDGE_PORT}: ${launcherBin} ${args.join(" ")}`,
  );
  const proc = spawn(launcherBin, args, {
    stdio: ["ignore", "pipe", "pipe"],
    detached: true,
  });
  proc.stdout.on("data", () => { /* discard */ });
  proc.stderr.on("data", () => { /* discard */ });
  const ok = await waitForTcpPort(
    TUI_BRIDGE_PORT, "127.0.0.1", 15_000,
  );
  if (!ok) {
    try { process.kill(-proc.pid); } catch { /* ignore */ }
    throw new Error(
      `TUI launcher did not open port ${TUI_BRIDGE_PORT} within 15s`,
    );
  }
  return proc;
}

// ---------------------------------------------------------------------------
// Render-category matrix (M-EVP-14)
//
// One PNG per (component × backend) cell: every cell captures the
// preview-pane rectangle (`[data-preview-canvas="true"]`) after the
// editor has been navigated to the component's story and the chrome
// bar's backend chip has been clicked for the target backend. The
// per-backend launcher binaries stream real demo frames through the
// editor-server.mjs WebSocket proxy.
//
// Output: `<outDir>/<component>-<backend>.png` (default outDir for
// `--view render` is `screenshots/render/` at the repo root).
// ---------------------------------------------------------------------------

// M-EVP-14: each render component navigates to its top-level "full
// app" Pages story so the editor mounts the demo's Layer-4
// composition with the same default seed the per-backend launchers
// produce when invoked with `--demo=<slug>`:
//
//   - Task App → "Task App / Pages / Inbox" pairs with
//     `seedTaskInboxDefaults` ("Buy groceries", "Walk the dog",
//     "Ship EX-M14"). The brief in tools/visual-review-briefs/render/
//     task-app.md references exactly these three tasks.
//   - Settings App → "Settings App / Pages / Preferences" pairs with
//     `buildDemoSettingsCatalog()` (Appearance, Editor, Notifications
//     each with three items).
//
// Both top-level Pages groups have `expanded: true` in stories.nim so
// no group toggle is required, but we still call ensureSection/
// GroupExpanded as a guard against future default changes.
//
// `demoSlug` is passed through to the per-backend launcher's `--demo=`
// CLI flag so the streamed canvas frames carry the matching demo. The
// editor-side sidebar selection (set up via `setup`) and the
// launcher-side `--demo` must agree, otherwise the canvas backends
// render one demo while the iframe / editor chrome show another.
export const renderComponents = {
  "task-app": {
    description:
      "Task App — full-app Pages/Inbox (3 seeded tasks: Buy groceries / Walk the dog / Ship EX-M14)",
    demoSlug: "task",
    setup: async (page) => {
      await ensureSectionExpanded(page, "Pages");
      await ensureGroupExpanded(page, "Task App / Pages");
      await selectStory(page, "Task App / Pages / Inbox");
    },
  },
  "settings-app": {
    description:
      "Settings App — full-app Pages/Preferences (Appearance / Editor / Notifications, three items each)",
    demoSlug: "settings",
    setup: async (page) => {
      await ensureSectionExpanded(page, "Pages");
      await ensureGroupExpanded(page, "Settings App / Pages");
      await selectStory(page, "Settings App / Pages / Preferences");
    },
  },
};

// The render-category backend list. `tui` always boots the post-RS-M13
// tui-term binary on port 8112; we still record the cell under the
// canonical `tui` filename so consumers don't have to special-case the
// legacy F/M/I slot.
export const renderBackends = [
  "web", "tui", "gpui", "freya", "cocoa", "android", "ios",
];

export function renderCells() {
  const out = [];
  for (const c of Object.keys(renderComponents)) {
    for (const b of renderBackends) {
      out.push({ component: c, backend: b });
    }
  }
  return out;
}

// Wait until the in-editor preview surface for `backend` has painted a
// real frame from the launcher. Per-backend signals:
//   - web        — iframe body[data-backend="pbWeb"] with non-empty
//                  children (covered by verifyExpectedState).
//   - tui        — `[data-tui-terminal="true"]` host with a
//                  non-empty `.xterm-screen` descendant.
//   - canvas backends (gpui/freya/cocoa/android/ios) — the existing
//                  `waitForCanvasManifest` helper (gates on non-zero
//                  pixel diversity + a populated __isonimManifest).
async function waitForFramePainted(page, backend) {
  if (backend === "web") {
    await page.waitForFunction(() => {
      const iframes = Array.from(document.querySelectorAll("iframe"));
      for (const f of iframes) {
        try {
          const b = f.contentDocument?.body;
          if (!b) continue;
          if (b.dataset.backend !== "pbWeb") continue;
          if (b.children && b.children.length > 0) return true;
        } catch { /* cross-origin guard; try srcdoc */ }
        const srcdoc = f.getAttribute("srcdoc") ?? "";
        if (/<body data-backend="pbWeb"/.test(srcdoc) &&
            /<main class="app"[^>]*>[\s\S]*<\/main>/.test(srcdoc)) {
          return true;
        }
      }
      return false;
    }, null, { timeout: 20_000 });
    return;
  }
  if (backend === "tui" || backend === "tui-term") {
    await page.waitForFunction(() => {
      const host = document.querySelector('[data-tui-terminal="true"]');
      if (!host) return false;
      const screen = host.querySelector(".xterm-screen, .xterm-rows");
      if (!screen) return false;
      const t = (screen.textContent ?? "").trim();
      return t.length > 0;
    }, null, { timeout: 25_000 });
    return;
  }
  // Canvas backends.
  await waitForCanvasManifest(page);
}

// Wait until the preview chrome bar's active backend chip matches
// `backend`. The chrome bar's `bindBackendChip` reactive effect writes
// `aria-pressed="true"` + the unified accent fill onto the chip that
// corresponds to `vm.platform.val`. Without this gate the render-cell
// screenshot can race the chip's reactive cascade — the launcher frame
// can paint before the chip's effect has flushed — which produces the
// settings-cell "active-chip misfires" the round-3 reviewer flagged
// (the settings cell visibly highlights the wrong backend because the
// chrome bar still reflects the previous click). The selector matches
// the chip's `aria-pressed="true"` AND its `data-preview-backend` data
// attribute scoped to the chrome bar's `data-toolbar-cluster="backend"`
// cluster so we never pick up a stale duplicate sitting in the legacy
// edge-strip locations.
async function waitForChromeBarActiveBackend(page, backend) {
  // `data-preview-backend` uses the lowercase wire id (see
  // streaming_preview.nim `backendId`): pbWeb -> "web", etc. The render
  // backend keys in this file already mirror those ids 1:1.
  await page.waitForFunction(
    (expectedId) => {
      const candidates = Array.from(document.querySelectorAll(
        `[data-preview-backend="${expectedId}"][aria-pressed="true"]`,
      ));
      // Prefer a chip inside the chrome bar's backend cluster so we
      // never satisfy on a hidden legacy/edge-strip mirror.
      for (const el of candidates) {
        if (el.closest('[data-toolbar-cluster="backend"]')) return true;
      }
      // Fallback: any visible aria-pressed chip with the right backend
      // id — covers earlier chrome layouts that did not tag the cluster.
      return candidates.length > 0;
    },
    backend,
    { timeout: 5000 },
  );
}

// Click the chrome-bar backend chip for `backend`. The chrome bar's
// backend strip is a compact-choice column with `visibleLimit = 6`, so
// the 7th option (iOS today) lives inside a `<details>` overflow
// popup and isn't `visible` until the overflow trigger is opened. We
// inspect the chip's attributes before clicking and open the overflow
// trigger first when the chip is marked as an overflow-option.
async function clickRenderBackendChip(page, backend) {
  const label = BACKEND_LAUNCHERS[backend]?.chipLabel;
  if (!label) {
    throw new Error(`render: unknown backend "${backend}"`);
  }
  const chip = page
    .locator(`[aria-label="Preview backend ${label}"]`)
    .first();
  await chip.waitFor({ state: "attached", timeout: 10_000 });
  const isOverflow = await chip.getAttribute(
    "data-compact-choice-overflow-option",
  );
  if (isOverflow === "true") {
    // Open the backend strip's overflow popup so the chip becomes
    // visible. The overflow trigger sits in the same column.
    const stripTrigger = page
      .locator(
        '[data-edge-strip="backend"] [data-compact-choice-overflow="true"]',
      )
      .first();
    const clusterTrigger = page
      .locator(
        '[data-toolbar-cluster="backend"] [data-compact-choice-overflow="true"]',
      )
      .first();
    if (await stripTrigger.count() > 0) {
      await stripTrigger.click();
    } else {
      await clusterTrigger.click();
    }
    await chip.waitFor({ state: "visible", timeout: 5_000 });
  }
  await clickBackendChip(page, label);
}

// Resolve the preview-pane clip rectangle from the running editor.
//
// The empty-state shell exposes a wrapper element directly tagged
// `[data-preview-canvas="true"]` (shell.nim line 1384). After a story
// is selected the active view's body inside `[data-preview-view-stack]`
// replaces that empty-state element; we pick the visible child of the
// view stack instead so the clip rectangle is always the preview
// surface, never the editor chrome.
async function previewCanvasClip(page) {
  return await page.evaluate(() => {
    const isVisible = (el) => {
      if (!el) return false;
      const r = el.getBoundingClientRect();
      if (r.width <= 0 || r.height <= 0) return false;
      const cs = window.getComputedStyle(el);
      return cs.display !== "none" && cs.visibility !== "hidden";
    };
    const direct = document.querySelector('[data-preview-canvas="true"]');
    if (isVisible(direct)) {
      const r = direct.getBoundingClientRect();
      return {
        x: Math.max(0, Math.floor(r.left)),
        y: Math.max(0, Math.floor(r.top)),
        width: Math.max(1, Math.floor(r.width)),
        height: Math.max(1, Math.floor(r.height)),
      };
    }
    // Fallback: the active child inside the view stack — i.e. the
    // current evComponentDetail / evPagePreview / evFoundationsPage
    // element. There's exactly one visible child after the reactive
    // view switch runs.
    const stack = document.querySelector('[data-preview-view-stack="true"]');
    if (stack) {
      const kids = Array.from(stack.children).filter(isVisible);
      if (kids.length > 0) {
        // Pick the LARGEST visible child to be robust if a tiny aux
        // element happens to sit alongside the active view.
        kids.sort((a, b) => {
          const ra = a.getBoundingClientRect();
          const rb = b.getBoundingClientRect();
          return rb.width * rb.height - ra.width * ra.height;
        });
        const r = kids[0].getBoundingClientRect();
        return {
          x: Math.max(0, Math.floor(r.left)),
          y: Math.max(0, Math.floor(r.top)),
          width: Math.max(1, Math.floor(r.width)),
          height: Math.max(1, Math.floor(r.height)),
        };
      }
    }
    return null;
  });
}

// Render a placeholder PNG to `outPath` reading the message text via a
// throwaway Playwright page. Using the same headless Chromium we
// already drive avoids pulling in a separate image-encoding dep.
//
// M-EVP-14: the placeholder matches the editor's 1920×1080 capture
// extent so a `<component>-<backend>-unavailable.png` file can be
// dropped into the same review-grid cell without resizing.
async function writeUnavailablePlaceholder(browser, outPath, message) {
  const safe = message
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const html =
    `<!doctype html><meta charset="utf-8">` +
    `<style>html,body{margin:0;padding:0;width:100%;height:100%;` +
    `background:#3a3f48;` +
    `color:#e6e6e6;font:600 28px/1.4 system-ui,sans-serif;` +
    `display:flex;align-items:center;justify-content:center;` +
    `text-align:center;}` +
    `.box{padding:48px;max-width:1200px;}</style>` +
    `<div class="box">${safe}</div>`;
  const ctx = await browser.newContext({
    viewport: { width: 1920, height: 1080 },
    deviceScaleFactor: 1,
  });
  const page = await ctx.newPage();
  await page.setContent(html);
  await page.screenshot({ path: outPath });
  await ctx.close();
}

// ---------------------------------------------------------------------------
// Expected-state verification
//
// After setup runs, verify the iframe carries the declared story +
// backend. Polls briefly (the iframe srcdoc update is reactive and
// usually settles in <100 ms; we allow up to 5 s for slow CI nodes).
// Throws a precise error if the post-setup state does not match.
// ---------------------------------------------------------------------------

export async function verifyExpectedState(page, viewName, view) {
  // Empty expectations mean "no iframe-state assertion" — the view
  // captures whatever default state the editor lands on. For the
  // bare shell view this is the storyboard view's flow mini-previews;
  // there's no single "expected story" because the storyboard renders
  // one iframe per flow step. We still verify the editor sidebar is
  // mounted (the screenshot tool's caller polls for that separately
  // via gotoEditor in the test spec).
  if (view.expectedStory === "" && view.expectedBackend === "") return;

  // Poll for the expected state up to 5 s. The reactive chain
  // (chip click → vm.platform → demoPreviewHook → iframe srcdoc)
  // usually settles in <100 ms but Chromium's iframe re-parse can add
  // a few hundred ms of latency on a busy CI worker.
  const deadline = Date.now() + 5_000;
  let last = { story: null, backend: null, iframePresent: false };
  while (Date.now() < deadline) {
    last = await readIframeState(page, view.expectedBackend);
    const storyOk =
      view.expectedStory === "" || last.story === view.expectedStory;
    const backendOk =
      view.expectedBackend === "" || last.backend === view.expectedBackend;
    if (storyOk && backendOk) return;
    await page.waitForTimeout(100);
  }

  if (!last.iframePresent) {
    throw new Error(
      `view "${viewName}": expected iframe with story="${view.expectedStory}" backend="${view.expectedBackend}", but no iframe was found`,
    );
  }
  throw new Error(
    `view "${viewName}": expected story="${view.expectedStory}" backend="${view.expectedBackend}", got story="${last.story}" backend="${last.backend}"`,
  );
}

// ---------------------------------------------------------------------------
// CLI entry point
//
// `import` is a no-op at the top level; only `main()` runs the
// screenshot tool. The test spec can `import { views, ... } from
// ".../tools/editor-screenshot.mjs"` without spawning a browser.
// ---------------------------------------------------------------------------

function isMainModule() {
  // Compare the resolved current module URL with `process.argv[1]`.
  // When run via `node tools/editor-screenshot.mjs`, argv[1] is the
  // file path; when imported, this won't match.
  return process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];
}

async function main() {
  // Parse args.
  const args = process.argv.slice(2);
  let selectedViews = Object.keys(views);
  let selectedSizes = null; // null means "honour each view's `viewports`"
  let isFiltered = false;
  let skipBuild = false;
  let port = 8091;
  let listOnly = false;
  let outDir = null; // resolved per-category below
  let isRender = false;
  let selectedComponents = null; // null means "all"
  let selectedBackends = null;   // null means "all"

  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case "--view": {
        const v = args[++i];
        if (v === "render") {
          isRender = true;
        } else {
          selectedViews = [v];
        }
        isFiltered = true;
        break;
      }
      case "--size":
        selectedSizes = [args[++i]];
        isFiltered = true;
        break;
      case "--out-dir":
        outDir = args[++i];
        isFiltered = true;
        break;
      case "--port":
        port = parseInt(args[++i], 10);
        break;
      case "--no-build":
        skipBuild = true;
        break;
      case "--list":
        listOnly = true;
        break;
      case "--component":
        selectedComponents = [args[++i]];
        isFiltered = true;
        break;
      case "--backend":
        selectedBackends = [args[++i]];
        isFiltered = true;
        break;
      default:
        console.error(`Unknown arg: ${args[i]}`);
        process.exit(1);
    }
  }

  if (listOnly) {
    console.log("Views:");
    for (const [k, v] of Object.entries(views)) {
      console.log(`  ${k}: ${v.description}`);
    }
    console.log("Sizes:");
    for (const [k, v] of Object.entries(sizes)) {
      console.log(`  ${k}: ${v.width}x${v.height}`);
    }
    console.log("Render cells (--view render):");
    for (const cell of renderCells()) {
      const p = `screenshots/render/${cell.component}-${cell.backend}.png`;
      console.log(`  ${cell.component} × ${cell.backend} -> ${p}`);
    }
    process.exit(0);
  }

  // Validate selections.
  if (isRender) {
    if (selectedComponents !== null) {
      for (const c of selectedComponents) {
        if (!renderComponents[c]) {
          console.error(`Unknown component: ${c}`);
          process.exit(1);
        }
      }
    }
    if (selectedBackends !== null) {
      for (const b of selectedBackends) {
        if (!renderBackends.includes(b)) {
          console.error(`Unknown backend: ${b}`);
          process.exit(1);
        }
      }
    }
  } else {
    for (const v of selectedViews) {
      if (!views[v]) {
        console.error(`Unknown view: ${v}`);
        process.exit(1);
      }
    }
    if (selectedSizes !== null) {
      for (const s of selectedSizes) {
        if (!sizes[s]) {
          console.error(`Unknown size: ${s}`);
          process.exit(1);
        }
      }
    }
  }

  if (outDir === null) {
    outDir = isRender
      ? join(projectRoot, "screenshots", "render")
      : screenshotDir;
  }

  if (!skipBuild) {
    console.log("==> Building isonim-examples editor...");
    mkdirSync(editorDir, { recursive: true });
    execSync(
      `nim js --path:. --path:../isonim/src --path:../nim-everywhere/src --hints:off -o:${editorDir}/editor.js editor/main.nim`,
      { cwd: projectRoot, stdio: "pipe" },
    );
    execSync(`cp editor/index.html ${editorDir}/index.html`, {
      cwd: projectRoot,
    });
    console.log("    Built.");
  }

  // The render category needs the editor-server.mjs proxy so each
  // backend's `/bridge/<slug>` (or `/tui-bridge`) WebSocket reaches the
  // matching launcher. The non-render legacy categories run fine
  // against the simpler python3 -m http.server.
  console.log(`==> Starting server on port ${port}...`);
  const server = isRender
    ? spawn(
        "node",
        [join(__dirname, "editor-server.mjs")],
        {
          cwd: projectRoot,
          stdio: "ignore",
          detached: true,
          env: { ...process.env, PORT: String(port),
                 EDITOR_STATIC_ROOT: editorDir },
        },
      )
    : spawn(
        "python3",
        ["-m", "http.server", String(port), "--bind", "127.0.0.1"],
        { cwd: editorDir, stdio: "ignore", detached: true },
      );
  await new Promise((r) => setTimeout(r, 1000));

  // Per-backend launcher processes. The cleanup loop below kills all
  // of them on tool exit (success, failure, and SIGINT).
  const launcherProcs = [];
  let tuiLauncher = null;

  // M-EVP-12: if any non-render view needs the legacy pixel-TUI
  // launcher, spawn it once for the lifetime of the screenshot run.
  if (!isRender) {
    const needsTui = selectedViews.some((v) => views[v].usesTui);
    if (needsTui) {
      tuiLauncher = await startTuiLauncher(projectRoot);
    }
  }

  // Register cleanup early so a Ctrl-C tears every child down. We
  // kill both the process group (-pid) and the direct pid — the
  // process-group kill is the canonical path for `detached: true`
  // children, but some launchers (notably the Freya bridge on macOS)
  // detach themselves from the spawned group, so the negative-pid
  // signal misses them. Trying both is harmless when one succeeds.
  let cleanedUp = false;
  const killOne = (pid) => {
    if (!pid) return;
    // Two-phase kill: SIGTERM first (gives the launcher a chance to
    // flush stdio + drop its bridge socket), then SIGKILL as the
    // hard backstop. Without the SIGKILL, the Nim `waitFor
    // s.serve()` blocking call in the bridge can ignore SIGTERM if
    // the dispatcher is mid-await, leaving the launcher alive past
    // this run's cleanup and holding the port for the NEXT run's
    // launcher boot. That's the failure mode that produced the
    // M-EVP-14 wrong-demo flakes (see `reclaimPort` for the spawn-
    // time defense; this is the matching teardown-time fix).
    try { process.kill(-pid); } catch { /* group kill missed */ }
    try { process.kill(pid); } catch { /* already dead */ }
    try { process.kill(-pid, "SIGKILL"); } catch { /* group SIGKILL */ }
    try { process.kill(pid, "SIGKILL"); } catch { /* already dead */ }
  };
  const cleanup = () => {
    if (cleanedUp) return;
    cleanedUp = true;
    killOne(server.pid);
    if (tuiLauncher) killOne(tuiLauncher.pid);
    for (const p of launcherProcs) killOne(p.pid);
  };
  process.on("SIGINT", () => { cleanup(); process.exit(130); });
  process.on("SIGTERM", () => { cleanup(); process.exit(143); });
  // SIGHUP fires when the controlling terminal closes (e.g. CI step
  // teardown). Without this, the SIGINT handler above never runs and
  // the launcher children survive into the next run. This was the
  // path that left 5-hour-old `--demo=task` launchers holding ports
  // 8104/8105 and producing the M-EVP-14 wrong-demo flakes.
  process.on("SIGHUP", () => { cleanup(); process.exit(129); });
  // Last-chance synchronous cleanup. `process.on("exit")` runs even
  // when main() throws and bubbles unhandled, but it cannot use
  // async APIs — `killOne` is fully synchronous so this is safe.
  process.on("exit", () => { cleanup(); });

  if (!isFiltered && existsSync(outDir)) {
    rmSync(outDir, { recursive: true });
  }
  mkdirSync(outDir, { recursive: true });

  const { chromium } = await import("playwright");
  const browser = await chromium.launch({ headless: true });

  let count = 0;
  let failure = null;
  try {
    if (isRender) {
      const cells = renderCells().filter((cell) =>
        (selectedComponents === null ||
          selectedComponents.includes(cell.component)) &&
        (selectedBackends === null ||
          selectedBackends.includes(cell.backend)),
      );
      // Group by component so we can boot per-backend launchers with
      // the matching `--demo=<slug>` once per component. Booting
      // launchers up-front for the whole matrix would force every
      // backend to stream the same demo, which would make the canvas
      // pixels disagree with the editor's sidebar selection for one
      // of the two components.
      const componentsInOrder = [];
      const cellsByComponent = new Map();
      for (const cell of cells) {
        if (!cellsByComponent.has(cell.component)) {
          componentsInOrder.push(cell.component);
          cellsByComponent.set(cell.component, []);
        }
        cellsByComponent.get(cell.component).push(cell);
      }

      for (const componentName of componentsInOrder) {
        const componentCells = cellsByComponent.get(componentName);
        const comp = renderComponents[componentName];
        const demoSlug = comp?.demoSlug ?? "task";
        const backendsNeeded = Array.from(
          new Set(componentCells.map((c) => c.backend)),
        );
        const launcherState = {}; // backend -> { ok, proc?, reason? }
        const groupProcs = [];
        for (const b of backendsNeeded) {
          const r = await startLauncher(b, projectRoot, { demo: demoSlug });
          launcherState[b] = r;
          if (r.ok) {
            launcherProcs.push(r.proc);
            groupProcs.push(r.proc);
          }
        }

        for (const cell of componentCells) {
          const baseName = `${cell.component}-${cell.backend}`;
          const outPath = join(outDir, `${baseName}.png`);
          const unavailablePath = join(outDir, `${baseName}-unavailable.png`);
          const state = launcherState[cell.backend];
          if (!state.ok) {
            await writeUnavailablePlaceholder(
              browser, unavailablePath,
              `${cell.backend} unavailable: ${state.reason}`,
            );
            console.log(
              `    ${baseName}: PLACEHOLDER (${state.reason})`,
            );
            count++;
            continue;
          }
          try {
            await captureRenderCell(browser, port, cell, outPath);
            console.log(`    ${baseName}: ${outPath}`);
            count++;
          } catch (e) {
            await writeUnavailablePlaceholder(
              browser, unavailablePath,
              `${cell.backend} unavailable: capture failed: ${e.message ?? e}`,
            );
            console.log(
              `    ${baseName}: PLACEHOLDER (capture error: ${e.message ?? e})`,
            );
            count++;
          }
        }

        // Teardown the per-component launcher group before moving on
        // — otherwise the next component's launcher would clash on
        // the same per-backend bridge port.
        for (const p of groupProcs) killOne(p.pid);
        // Brief pause so the kernel releases the bridge ports before
        // the next group boots launchers on the same ports.
        await new Promise((r) => setTimeout(r, 250));
      }
    } else {
      for (const viewName of selectedViews) {
        const view = views[viewName];
        // Resolve the effective per-view viewport list:
        //   - explicit --size flag wins (overrides view's `viewports`).
        //   - else view.viewports if declared.
        //   - else DEFAULT_VIEWPORTS_WIDE_LAPTOP.
        const effectiveSizes = (selectedSizes !== null)
          ? selectedSizes
          : (Array.isArray(view.viewports) && view.viewports.length > 0
              ? view.viewports
              : DEFAULT_VIEWPORTS_WIDE_LAPTOP);
        for (const sizeName of effectiveSizes) {
          const vp = sizes[sizeName];
          if (!vp) {
            throw new Error(
              `view "${viewName}": viewport "${sizeName}" not in the sizes table`,
            );
          }
          const context = await browser.newContext({
            viewport: { width: vp.width, height: vp.height },
            deviceScaleFactor: 2,
          });
          const page = await context.newPage();
          // M-EVP-12: views that drive M-EVP-10 / M-EVP-11 mirrors must
          // see `window.__isonimTestMode === true` BEFORE the editor
          // bundle boots, so the gated `window.__isonim*` write paths
          // fire on the first event after attachBridgeClient mounts.
          if (view.requiresTestMode === true) {
            await page.addInitScript(() => {
              window.__isonimTestMode = true;
            });
          }
          await page.goto(`http://127.0.0.1:${port}/`);
          await page.waitForTimeout(400);
          await view.setup(page);
          await page.waitForTimeout(200);
          // M-EVP-2: verify expected state BEFORE writing the PNG so
          // the captured screenshot can never be silently stale.
          await verifyExpectedState(page, viewName, view);
          const p = join(outDir, `${viewName}-${sizeName}.png`);
          await page.screenshot({ path: p });
          console.log(
            `    ${viewName}-${sizeName} (${vp.width}x${vp.height}): ${p}`,
          );
          count++;
          await context.close();
        }
      }
    }
  } catch (e) {
    failure = e;
  }

  await browser.close();
  cleanup();
  if (failure) {
    console.error(`==> FAILED after ${count} screenshot(s):`);
    console.error(failure.message ?? failure);
    process.exit(1);
  }
  console.log(`==> Done. ${count} screenshot(s) written.`);
}

// Drive one render cell: navigate to the component story, click the
// backend chip, wait for a real painted frame, then screenshot the
// FULL editor viewport (1920×1080).
//
// M-EVP-14 capture extent: per the visual-review brief, the reviewer
// compares the editor *as a whole* (sidebar + preview pane + inspector
// + chrome bar with the backend chip selected) across backends — not
// just the raw preview-pane rectangle. We use Playwright's default
// `page.screenshot()` (no `clip`) so the entire 1920×1080 viewport
// lands in the PNG.
async function captureRenderCell(browser, port, cell, outPath) {
  const comp = renderComponents[cell.component];
  if (!comp) throw new Error(`unknown render component "${cell.component}"`);
  // Canvas backends drive the M-EVP-10 / M-EVP-11 mirrors which gate on
  // __isonimTestMode; the iframe + xterm backends don't need it but
  // setting it is harmless. We set it unconditionally for render cells.
  const context = await browser.newContext({
    viewport: { width: 1920, height: 1080 },
    deviceScaleFactor: 1,
  });
  const page = await context.newPage();
  await page.addInitScript(() => { window.__isonimTestMode = true; });
  try {
    await page.goto(`http://127.0.0.1:${port}/`);
    await page.waitForTimeout(400);
    await comp.setup(page);
    await page.waitForTimeout(200);
    await clickRenderBackendChip(page, cell.backend);
    await waitForFramePainted(page, cell.backend);
    // Before snapping, gate on the chrome bar's reactive
    // `aria-pressed="true"` cascade for this backend. The launcher's
    // first painted frame and the chip's reactive effect run on
    // independent code paths, and on the settings-app cell the chip
    // path was visibly losing the race (round-3 reviewer: "settings
    // cell highlights the wrong backend"). Waiting here makes the
    // capture deterministic — the chrome bar always reflects the chip
    // we just clicked.
    await waitForChromeBarActiveBackend(page, cell.backend);
    // Small settle delay so the chip's accent fill and per-backend
    // overlay re-flow finish painting (browser-side compositor flush).
    await page.waitForTimeout(200);
    await page.screenshot({ path: outPath });
  } finally {
    await context.close();
  }
}

if (isMainModule()) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
