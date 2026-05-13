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

const __dirname = dirname(fileURLToPath(import.meta.url));
const projectRoot = join(__dirname, "..");
const editorDir = join(projectRoot, "build", "editor");
const screenshotDir = join(editorDir, "screenshots");

export const sizes = {
  wide: { width: 1920, height: 1080 },
  laptop: { width: 1440, height: 900 },
  medium: { width: 1280, height: 800 },
  tablet: { width: 1024, height: 768 },
  narrow: { width: 768, height: 1024 },
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

export const views = {
  shell: {
    description:
      "Editor shell — sidebar + preview + inspector (default state, no story selected)",
    setup: async (_page) => {
      // No navigation; capture the shell on its initial mount.
    },
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
};

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
  let selectedSizes = Object.keys(sizes);
  let isFiltered = false;
  let skipBuild = false;
  let port = 8091;
  let listOnly = false;

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
  for (const s of selectedSizes) {
    if (!sizes[s]) {
      console.error(`Unknown size: ${s}`);
      process.exit(1);
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

  if (!isFiltered && existsSync(screenshotDir)) {
    rmSync(screenshotDir, { recursive: true });
  }
  mkdirSync(screenshotDir, { recursive: true });

  const { chromium } = await import("playwright");
  const browser = await chromium.launch({ headless: true });

  let count = 0;
  let failure = null;
  try {
    for (const viewName of selectedViews) {
      const view = views[viewName];
      for (const sizeName of selectedSizes) {
        const vp = sizes[sizeName];
        const context = await browser.newContext({
          viewport: { width: vp.width, height: vp.height },
          deviceScaleFactor: 2,
        });
        const page = await context.newPage();
        await page.goto(`http://127.0.0.1:${port}/`);
        await page.waitForTimeout(400);
        await view.setup(page);
        await page.waitForTimeout(200);
        // M-EVP-2: verify expected state BEFORE writing the PNG so
        // the captured screenshot can never be silently stale.
        await verifyExpectedState(page, viewName, view);
        const p = join(screenshotDir, `${viewName}-${sizeName}.png`);
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
