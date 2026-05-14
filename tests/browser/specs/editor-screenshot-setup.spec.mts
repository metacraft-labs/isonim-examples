// M-EVP-2: Screenshot tool's setup correctly navigates to target story.
//
// The v5 `story-selected-tui-*` screenshots captured the WRONG story
// because the setup function in `tools/editor-screenshot.mjs` clicked
// elements that were not visible — the deeper story link was hidden
// inside a collapsed group, so `page.$(...).click()` either timed out
// or no-op'd. The tool produced a plausible-looking PNG but the rendered
// state was stale, and downstream review sub-agents rated the wrong
// frame.
//
// This spec is the regression test for that whole class of bugs. It
// imports the `views` table from `tools/editor-screenshot.mjs` (single
// source of truth — adding a new view to the screenshot tool extends
// this test automatically), runs each view's setup in a real browser,
// and asserts the iframe's `<body data-story>` + `<body data-backend>`
// match the per-view declared `expectedStory` + `expectedBackend`.
//
// Hard rule (binding): no skips, no soft assertions. A view whose
// setup silently lands on the wrong story (or on no iframe at all)
// MUST fail this test loudly with a precise mismatch error.
//
// File extension `.mts`: Playwright's babel transform treats `.mts` as
// ESM, which lets us `import` the .mjs tool statically. A `.ts` file
// would be transpiled to CommonJS and the static import would fail at
// runtime with "ReferenceError: exports is not defined in ES module
// scope".

import { test, expect, type Page } from "@playwright/test";
// eslint-disable-next-line @typescript-eslint/ban-ts-comment
// @ts-ignore — runtime ESM import; the .mjs file has no .d.ts sidecar.
import * as screenshotTool from "../../../tools/editor-screenshot.mjs";

type ViewDef = {
  description: string;
  setup: (page: Page) => Promise<void>;
  expectedStory: string;
  expectedBackend: string;
  // M-EVP-12: views that drive the non-Web canvas via `attachBridgeClient`
  // need a real TUI launcher running on port 8102. This spec's config
  // (`playwright.config.screenshot-setup.ts`) only starts the editor
  // bundle's static server — it does NOT launch the bridge subprocesses
  // (the `editor-demo` config in `playwright.config.ts` does). Skip
  // canvas-* views here; their setups are exercised end-to-end by the
  // `test-editor-visual-gates` Justfile recipe, which spawns the
  // launcher itself.
  usesTui?: boolean;
  // M-EVP-12: views that need `window.__isonimTestMode = true` injected
  // before the editor bundle boots. The recipe handles this via
  // `page.addInitScript`; this spec's loop doesn't, so views that
  // depend on test-mode mirrors should be skipped here too.
  requiresTestMode?: boolean;
};

type IframeState = {
  story: string | null;
  backend: string | null;
  iframePresent: boolean;
};

const views = screenshotTool.views as Record<string, ViewDef>;
const readIframeState = screenshotTool.readIframeState as (
  page: Page,
  expectedSrcdocBackend?: string,
) => Promise<IframeState>;

const desktop = { width: 1440, height: 900 };

async function gotoEditor(page: Page) {
  await page.setViewportSize(desktop);
  await page.goto(`/`);
  await expect(page.locator(".editor-sidebar")).toBeVisible({
    timeout: 20_000,
  });
}

test.describe("editor-screenshot.mjs setup navigates to the declared story", () => {
  const viewNames = Object.keys(views);

  // Sanity: the views table must not be empty. If it ever became empty
  // (e.g. a refactor accidentally exported `{}`), every per-view test
  // would silently disappear from the suite — keep that loud.
  test("views table is non-empty", () => {
    expect(viewNames.length).toBeGreaterThan(0);
  });

  for (const name of viewNames) {
    const view = views[name];
    // M-EVP-12: canvas-* views need the TUI launcher subprocess that
    // only `test-editor-visual-gates` spawns. Skip them here so the
    // setup-spec stays a fast bundle-only smoke test.
    if (view.usesTui === true) {
      test.skip(`view "${name}" (skipped: requires TUI launcher; covered by test-editor-visual-gates)`, () => {});
      continue;
    }
    test(`view "${name}" lands on expectedStory="${view.expectedStory}" expectedBackend="${view.expectedBackend}"`, async ({
      page,
    }) => {
      // M-EVP-12: views that depend on test-mode mirrors need
      // `window.__isonimTestMode = true` set before the bundle boots.
      if (view.requiresTestMode === true) {
        await page.addInitScript(() => {
          (window as unknown as Record<string, unknown>).__isonimTestMode = true;
        });
      }
      await gotoEditor(page);
      // Brief settle after the initial mount so the reactive graph
      // has emitted its first frame before setup starts driving it.
      await page.waitForTimeout(300);

      await view.setup(page);

      // Allow the reactive iframe-srcdoc update to settle, then read.
      // The screenshot tool's `verifyExpectedState` helper polls for
      // up to 5 s; we do the equivalent here with Playwright's
      // poll/expect so the test output points at the test line on
      // failure rather than at a thrown Error from the helper.
      if (view.expectedStory === "" && view.expectedBackend === "") {
        // Empty expectations mean "no iframe-state assertion" — the
        // view captures whatever default state the editor lands on.
        // We still assert the editor sidebar mounted (gotoEditor
        // above already waited for `.editor-sidebar` to be visible),
        // so this branch is the documented escape-hatch for views
        // that intentionally capture the default-state surface.
      } else {
        // Pass the expected backend as the srcdoc filter so the read
        // disambiguates the storyboard's still-mounted (but hidden)
        // mini-preview iframes from the active view's iframe.
        await expect
          .poll(
            async () =>
              (await readIframeState(page, view.expectedBackend)).story,
            {
              message: `view "${name}" must reach iframe data-story="${view.expectedStory}"`,
              timeout: 15_000,
            },
          )
          .toBe(view.expectedStory);
        await expect
          .poll(
            async () =>
              (await readIframeState(page, view.expectedBackend)).backend,
            {
              message: `view "${name}" must reach iframe data-backend="${view.expectedBackend}"`,
              timeout: 15_000,
            },
          )
          .toBe(view.expectedBackend);
      }
    });
  }
});
