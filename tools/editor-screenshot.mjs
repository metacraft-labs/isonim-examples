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

import { execSync, spawn } from "child_process";
import { mkdirSync, rmSync, existsSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import net from "net";

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
      // Wait for the 8-handle group to render.
      await page.waitForFunction(
        () => document.querySelectorAll(
          '[data-canvas-selection-handle="true"]',
        ).length === 8,
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
// TUI launcher subprocess management.
//
// The canvas-* views need a real TUI bridge process running on a
// well-known port so `attachBridgeClient` can connect. We start a
// single launcher process for the lifetime of the screenshot run,
// then poll the bridge HTTP root before driving the editor.
// ---------------------------------------------------------------------------

// Must match `bridgePortForBackend(pbTui)` in
// isonim/src/isonim/editor/streaming_preview.nim — the JS editor
// bundle hard-codes this port when attaching its bridge client.
const TUI_BRIDGE_PORT = 8102;

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

async function startTuiLauncher(projectRoot) {
  const launcherBin = join(
    projectRoot, "build", "backends", "isonim-examples-tui",
  );
  if (!existsSync(launcherBin)) {
    throw new Error(
      `TUI launcher binary missing: ${launcherBin}. ` +
        "Run `just build-backends` (or `direnv exec . just build-backends`) first.",
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
    `==> Starting TUI launcher on port ${TUI_BRIDGE_PORT}: ${launcherBin} ${args.join(" ")}`,
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
  let outDir = screenshotDir;

  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case "--view":
        selectedViews = [args[++i]];
        isFiltered = true;
        break;
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
    process.exit(0);
  }

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

  console.log(`==> Starting server on port ${port}...`);
  const server = spawn(
    "python3",
    ["-m", "http.server", String(port), "--bind", "127.0.0.1"],
    { cwd: editorDir, stdio: "ignore", detached: true },
  );
  await new Promise((r) => setTimeout(r, 1000));

  // M-EVP-12: if any selected view requires the TUI launcher, spawn
  // it once for the lifetime of the screenshot run. The launcher
  // listens on port 8102 — the editor's `bridgePortForBackend(pbTui)`
  // contract. We only spawn once per screenshot run so back-to-back
  // canvas views share the same WebSocket-ready bridge.
  const needsTui = selectedViews.some((v) => views[v].usesTui);
  let tuiLauncher = null;
  if (needsTui) {
    tuiLauncher = await startTuiLauncher(projectRoot);
  }

  if (!isFiltered && existsSync(outDir)) {
    rmSync(outDir, { recursive: true });
  }
  mkdirSync(outDir, { recursive: true });

  const { chromium } = await import("playwright");
  const browser = await chromium.launch({ headless: true });

  let count = 0;
  let failure = null;
  try {
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
  } catch (e) {
    failure = e;
  }

  await browser.close();
  try {
    process.kill(-server.pid);
  } catch {
    /* ignore */
  }
  if (tuiLauncher) {
    try {
      process.kill(-tuiLauncher.pid);
    } catch {
      /* ignore */
    }
  }
  if (failure) {
    console.error(`==> FAILED after ${count} screenshot(s):`);
    console.error(failure.message ?? failure);
    process.exit(1);
  }
  console.log(`==> Done. ${count} screenshot(s) written.`);
}

if (isMainModule()) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
