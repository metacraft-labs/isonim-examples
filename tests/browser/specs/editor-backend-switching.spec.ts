// M-EVP-1: Backend switching works for every story kind.
//
// The reactive chain `backend chip click → vm.platform → demoPreviewHook
// → iframe srcdoc` must repaint the in-iframe preview document for every
// story kind exposed in the demo workspace, not just the two component
// kinds the old `showProject` gate let through.
//
// This spec exercises the (story kind × backend) matrix end-to-end
// against the real editor JS bundle running in Chromium. For each story
// kind we navigate to a representative story, then click each of the 6
// backend chips (Web / TUI / GPUI / Freya / Cocoa / Android) and assert
// the iframe's `<body data-backend>` attribute matches the clicked
// backend identifier (`pbWeb`, `pbTui`, ...).
//
// Hard rule (binding): no skips, no conditional gates. Cocoa and
// Android surface as `unavailable` on Linux but the chip click STILL
// flips `vm.platform.val` and `demoPreviewHook` STILL returns
// per-backend HTML for those targets — the part of the chain we're
// testing here. A regression that silently retains the previous
// srcdoc for any (kind, backend) combination must produce a loud,
// specific failure.

import { test, expect, type Page, type Locator } from "@playwright/test";

const desktop = { width: 1440, height: 900 };

// All six PreviewBackend enum values. The `id` is the wire identifier
// used by the chip's `data-preview-backend` attribute; the `dataBackend`
// is the value the demoPreviewHook bakes into `<body data-backend>` via
// `$platform` (the Nim enum's repr, e.g. `pbWeb`).
const backends = [
  { id: "web", dataBackend: "pbWeb" },
  { id: "tui", dataBackend: "pbTui" },
  { id: "gpui", dataBackend: "pbGpui" },
  { id: "freya", dataBackend: "pbFreya" },
  { id: "cocoa", dataBackend: "pbCocoa" },
  { id: "android", dataBackend: "pbAndroid" },
] as const;

// Story kinds exposed in the isonim-examples demo workspace. The
// `buildDemoStoryGroups` proc in `editor/stories.nim` declares groups
// of every StoryKind: skFlow, skPage, skComponent, skPattern,
// skFoundation, skGuideline. Each entry below pins ONE representative
// story plus the per-kind iframe selector (`data-*-project-frame` or
// `data-flow-mini-preview`).
//
// `setup` performs the click path that lands the editor on the target
// story's view. The expansion clicks are explicit (no fragile defaults)
// so a future change to `defaultSidebarSections` doesn't silently
// degrade this test.
//
// `iframeSelector` is the CSS selector for the iframe whose
// `<body data-backend>` we will read after every chip click.

type StoryKindCase = {
  kind: string;
  setup: (page: Page) => Promise<void>;
  iframeSelector: string;
  // The iframe's `<body>` carries `data-story="<group>/<name>"`. We
  // read it after `setup` to assert the navigation landed on the
  // expected story before exercising the chip matrix.
  expectedStory: string;
};

const storyKindCases: StoryKindCase[] = [
  {
    // skFlow: flow groups don't surface individual stories in the
    // sidebar (the flow group's `aria-label` is "Open ... journey",
    // not "Toggle ... stories"). Opening a journey switches the
    // editor to the storyboard view, which renders one
    // mini-preview iframe per flow step. Each iframe uses the
    // per-backend documentHtml via demoPreviewHook, so clicking a
    // backend chip while on the storyboard must repaint every
    // flow-step iframe. We assert on the first such iframe.
    kind: "skFlow",
    setup: async (page) => {
      const journey = page
        .locator('[aria-label="Open Add Task Flow journey"]')
        .first();
      await expect(journey).toBeVisible({ timeout: 10_000 });
      await journey.click();
    },
    iframeSelector: 'iframe[data-flow-mini-preview="true"]',
    // The first flow step in "Add Task Flow" resolves to the Inbox
    // page story (see `demoFlowSteps` in stories.nim). The iframe's
    // <main data-story> reflects the resolved page story.
    expectedStory: "Task App / Pages/Inbox",
  },
  {
    kind: "skPage",
    setup: async (page) => {
      // Pages section is expanded by default per
      // `defaultSidebarSections`, but expand explicitly to guard
      // against a future default change.
      await ensureSectionExpanded(page, "Pages");
      const group = page
        .locator('[aria-label="Toggle Task App / Pages stories"]')
        .first();
      const groupExpanded = await group.getAttribute("aria-expanded");
      if (groupExpanded !== "true") {
        await group.click();
      }
      const story = page
        .locator('[aria-label="Select story Task App / Pages / Inbox"]')
        .first();
      await expect(story).toBeVisible({ timeout: 10_000 });
      await story.click();
    },
    iframeSelector: 'iframe[data-page-project-frame="true"]',
    expectedStory: "Task App / Pages/Inbox",
  },
  {
    kind: "skComponent",
    setup: async (page) => {
      await ensureSectionExpanded(page, "Components");
      const group = page
        .locator('[aria-label="Toggle Settings App / Group stories"]')
        .first();
      const groupExpanded = await group.getAttribute("aria-expanded");
      if (groupExpanded !== "true") {
        await group.click();
      }
      const story = page
        .locator(
          '[aria-label="Select story Settings App / Group / Appearance"]',
        )
        .first();
      await expect(story).toBeVisible({ timeout: 10_000 });
      await story.click();
    },
    iframeSelector: 'iframe[data-component-project-frame="true"]',
    expectedStory: "Settings App / Group/Appearance",
  },
  {
    kind: "skPattern",
    setup: async (page) => {
      // The Patterns group lives inside the Components section
      // (per `groupInSection(_, ssComponents)`).
      await ensureSectionExpanded(page, "Components");
      const group = page
        .locator('[aria-label="Toggle Patterns stories"]')
        .first();
      const groupExpanded = await group.getAttribute("aria-expanded");
      if (groupExpanded !== "true") {
        await group.click();
      }
      const story = page
        .locator(
          '[aria-label="Select story Patterns / Form With Inline Error"]',
        )
        .first();
      await expect(story).toBeVisible({ timeout: 10_000 });
      await story.click();
    },
    iframeSelector: 'iframe[data-component-project-frame="true"]',
    expectedStory: "Patterns/Form With Inline Error",
  },
  {
    kind: "skFoundation",
    setup: async (page) => {
      await ensureSectionExpanded(page, "Foundations");
      const group = page
        .locator(
          '[aria-label="Toggle Task App / Foundations stories"]',
        )
        .first();
      const groupExpanded = await group.getAttribute("aria-expanded");
      if (groupExpanded !== "true") {
        await group.click();
      }
      const story = page
        .locator(
          '[aria-label="Select story Task App / Foundations / Spacing"]',
        )
        .first();
      await expect(story).toBeVisible({ timeout: 10_000 });
      await story.click();
    },
    iframeSelector: 'iframe[data-foundation-project-frame="true"]',
    expectedStory: "Task App / Foundations/Spacing",
  },
  {
    kind: "skGuideline",
    setup: async (page) => {
      // Guidelines section is collapsed by default.
      await ensureSectionExpanded(page, "Guidelines");
      const group = page
        .locator('[aria-label="Toggle Guidelines stories"]')
        .first();
      const groupExpanded = await group.getAttribute("aria-expanded");
      if (groupExpanded !== "true") {
        await group.click();
      }
      const story = page
        .locator(
          '[aria-label="Select story Guidelines / Cross-renderer parity"]',
        )
        .first();
      await expect(story).toBeVisible({ timeout: 10_000 });
      await story.click();
    },
    iframeSelector: 'iframe[data-component-project-frame="true"]',
    expectedStory: "Guidelines/Cross-renderer parity",
  },
];

// --------------------------------------------------------------------------
// Helpers
// --------------------------------------------------------------------------

async function gotoEditor(page: Page) {
  await page.setViewportSize(desktop);
  await page.goto(`/`);
  await expect(page.locator(".editor-sidebar")).toBeVisible({
    timeout: 20_000,
  });
}

async function ensureSectionExpanded(page: Page, label: string) {
  const sectionToggle = page
    .locator(`[aria-label="Toggle ${label} section"]`)
    .first();
  await expect(sectionToggle).toBeVisible({ timeout: 10_000 });
  const expanded = await sectionToggle.getAttribute("aria-expanded");
  if (expanded !== "true") {
    await sectionToggle.click();
  }
  // Wait until the toggle reports expanded so the section body's
  // story buttons are query-able.
  await expect(sectionToggle).toHaveAttribute("aria-expanded", "true");
}

// Read `<body data-backend>` from the iframe matched by `selector`.
// Tries a same-origin contentDocument read first; falls back to
// parsing the iframe's `srcdoc` attribute when same-origin is blocked
// (the editor serves the iframe inline so same-origin usually
// succeeds, but the fallback is the canonical path documented in
// M-EVP-1 and is also robust against transient timing where the
// inner document hasn't finished loading yet).
async function readIframeBackend(
  page: Page,
  selector: string,
): Promise<string | null> {
  return await page.evaluate((sel) => {
    const iframe = document.querySelector(sel) as HTMLIFrameElement | null;
    if (!iframe) return null;
    try {
      const body = iframe.contentDocument?.body;
      if (body && typeof body.dataset.backend === "string") {
        return body.dataset.backend;
      }
    } catch {
      /* fall through to srcdoc parse */
    }
    const srcdoc = iframe.getAttribute("srcdoc") ?? "";
    const match = srcdoc.match(/<body data-backend="([^"]+)"/);
    return match ? match[1] : null;
  }, selector);
}

async function readIframeStory(
  page: Page,
  selector: string,
): Promise<string | null> {
  return await page.evaluate((sel) => {
    const iframe = document.querySelector(sel) as HTMLIFrameElement | null;
    if (!iframe) return null;
    const srcdoc = iframe.getAttribute("srcdoc") ?? "";
    const match = srcdoc.match(/<main class="app" data-story="([^"]+)"/);
    return match ? match[1] : null;
  }, selector);
}

// Wait until the iframe's data-backend matches `expected`. The chip
// click triggers a reactive effect that re-runs the demoPreviewHook
// and writes the new srcdoc; the browser then re-parses the
// document. We poll with a short timeout because the test must FAIL
// LOUDLY if the srcdoc silently retains the previous backend.
async function expectIframeBackend(
  page: Page,
  selector: string,
  expected: string,
  context: string,
) {
  await expect
    .poll(async () => readIframeBackend(page, selector), {
      message: `iframe ${selector} body[data-backend] must become ${expected} ${context}`,
      timeout: 10_000,
    })
    .toBe(expected);
}

async function clickBackend(page: Page, backendId: string) {
  // The backend chip strip lives in the preview-pane top toolbar
  // (`data-preview-chrome-bar="true"`), not the legacy left-edge
  // column. The chrome bar is the single source of truth for chip
  // groups since the M57 chrome consolidation.
  const chip = page
    .locator(
      `[data-preview-chrome-bar="true"] [data-edge-strip="backend"] [data-preview-backend="${backendId}"]`,
    )
    .first();
  await expect(chip).toBeVisible({ timeout: 10_000 });
  await chip.click();
  // Confirm the chip flipped aria-pressed; the per-backend iframe
  // srcdoc update is gated by the reactive `vm.platform` write that
  // also flips this attribute, so checking it gives a clear cause-
  // and-effect signal in the test log.
  await expect(chip).toHaveAttribute("aria-pressed", "true");
}

// --------------------------------------------------------------------------
// Spec
// --------------------------------------------------------------------------

test.describe("editor backend switching", () => {
  for (const sc of storyKindCases) {
    test(`${sc.kind}: every backend chip repaints the iframe with the matching <body data-backend>`, async ({
      page,
    }) => {
      await gotoEditor(page);
      await sc.setup(page);

      // After setup, the iframe must exist and the inner document
      // must carry the expected story marker. This catches the
      // upstream class of failures where setup landed on the wrong
      // view or no story at all — the (kind, backend) loop below
      // would otherwise rubber-stamp a fixed, wrong document.
      const iframe = page.locator(sc.iframeSelector).first();
      await expect(iframe).toBeVisible({ timeout: 15_000 });
      await expect
        .poll(async () => readIframeStory(page, sc.iframeSelector), {
          message: `after setup, iframe ${sc.iframeSelector} must show story "${sc.expectedStory}"`,
          timeout: 15_000,
        })
        .toBe(sc.expectedStory);

      // Iterate the 6 backends. The chain we are validating end-to-end:
      //
      //   chip click → vm.platform.val := pbX
      //              → vm.preview.current re-runs demoPreviewHook(_, pbX)
      //              → createRenderEffect rewrites iframe srcdoc
      //              → <body data-backend="pbX"> in the inner document
      //
      // If ANY backend silently retains the previous srcdoc, the
      // `expectIframeBackend` poll fails with a backend-specific
      // error message.
      for (const b of backends) {
        await clickBackend(page, b.id);
        await expectIframeBackend(
          page,
          sc.iframeSelector,
          b.dataBackend,
          `(kind=${sc.kind}, backend=${b.id})`,
        );
      }
    });
  }

  // Sanity assertion: the test above exercises (#story kinds × #backends)
  // = 6 × 6 = 36 (kind, backend) assertions. Keep this explicit so a
  // future change that removes a kind or a backend trips this check.
  test("matrix covers 6 story kinds × 6 backends = 36 combinations", () => {
    expect(storyKindCases).toHaveLength(6);
    expect(backends).toHaveLength(6);
    expect(storyKindCases.length * backends.length).toBe(36);
  });
});
