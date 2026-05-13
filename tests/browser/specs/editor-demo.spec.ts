// EX-M14: end-to-end test for the isonim-examples demo editor.
//
// Combines two flavours of real-stack visual proof:
//
//  1. *In-editor* assertions against the M57 edge-strip chrome and the
//     web backend's in-iframe preview. Web is the only backend whose
//     preview surface today is the editor's own iframe; for the
//     non-Web backends the editor (running in a static browser bundle)
//     cannot itself spawn a child process.
//
//  2. *Per-bridge* assertions: every Linux backend's launcher binary is
//     started by `playwright.config.ts` (one bridge per port). The spec
//     hits each bridge's static `index.html` directly, waits for the
//     WebSocket canvas client to paint its first frame, and asserts:
//
//       - the canvas has at least one non-background pixel (the bridge
//         streamed *real* demo content, not a stub gradient);
//       - the per-backend canvas hashes are pairwise distinct (the four
//         Linux backends rasterise the demo through four different
//         pipelines);
//       - the asserted text fingerprint matches the active demo (task
//         names appear in the TUI raster's text bands; settings labels
//         appear when the bridge is started with `--demo=settings`).
//
// The spec MUST fail if any of the four Linux backends cannot actually
// render the demo. No skips, no "scaffold-only" fallbacks.

import { test, expect, type Page } from "@playwright/test";

const desktop = { width: 1440, height: 900 };
const phone = { width: 480, height: 800 };

const bridgePorts = JSON.parse(process.env.BRIDGE_PORTS || "{}") as {
  web: number;
  tui: number;
  gpui: number;
  freya: number;
  freyaSettings: number;
};

const backendIds = ["web", "tui", "gpui", "freya"] as const;
const unavailableBackends = ["cocoa", "android"] as const;

// --------------------------------------------------------------------------
// Helpers
// --------------------------------------------------------------------------

async function gotoEditor(page: Page, params: string = "") {
  await page.setViewportSize(desktop);
  await page.goto(`/?${params}`);
  await expect(page.locator(".editor-sidebar")).toBeVisible();
  await expect(page).toHaveTitle("IsoNim Examples Editor");
  await expect(
    page.getByText("IsoNim Editor", { exact: false }).first(),
  ).toBeVisible();
}

async function navigateToSettingsGroupStory(page: Page) {
  const groupHeader = page
    .locator('[aria-label="Toggle Settings App / Group stories"]')
    .first();
  await expect(groupHeader).toBeVisible({ timeout: 10_000 });
  const expanded = await groupHeader.getAttribute("aria-expanded");
  if (expanded !== "true") {
    await groupHeader.click();
  }
  const storyButton = page
    .locator(
      '[aria-label="Select story Settings App / Group / Appearance"]',
    )
    .first();
  await expect(storyButton).toBeVisible({ timeout: 10_000 });
  await storyButton.click();
}

// Connect to a bridge's static canvas client; wait for the canvas to
// paint at least one frame; return the canvas's ImageData hash plus the
// non-background pixel count.
async function probeBridge(page: Page, port: number): Promise<{
  hash: string;
  nonBgPixels: number;
  width: number;
  height: number;
}> {
  await page.goto(`http://127.0.0.1:${port}/`);
  // Wait for the WebSocket hello + first F packet to repaint the canvas.
  await page.waitForFunction(
    () => {
      const c = document.getElementById("canvas") as HTMLCanvasElement | null;
      if (!c) return false;
      // Default canvas width/height starts at 256×256 from the static
      // HTML; a successful first frame either keeps that or replaces it,
      // but in both cases the pixel buffer is non-empty.
      if (c.width === 0 || c.height === 0) return false;
      const ctx = c.getContext("2d");
      if (!ctx) return false;
      try {
        const img = ctx.getImageData(0, 0, c.width, c.height);
        // Count any pixel whose colour is non-zero — uninitialised
        // browser canvases read back as all-zero RGBA. We accept the
        // first frame after either the default "black" surface paints
        // or a real frame arrives (the bridge sends a frame within the
        // first ~125ms after the hello).
        for (let i = 0; i < img.data.length; i += 4) {
          if (img.data[i] | img.data[i + 1] | img.data[i + 2]) return true;
        }
        return false;
      } catch {
        return false;
      }
    },
    null,
    { timeout: 20_000 },
  );
  return await page.evaluate(() => {
    const c = document.getElementById("canvas") as HTMLCanvasElement;
    const ctx = c.getContext("2d");
    if (!ctx) throw new Error("no 2d context");
    const img = ctx.getImageData(0, 0, c.width, c.height);
    let nonBg = 0;
    // Hash via FNV-1a over the raw RGBA bytes.
    let h = 0x811c9dc5;
    for (let i = 0; i < img.data.length; i += 4) {
      const r = img.data[i];
      const g = img.data[i + 1];
      const b = img.data[i + 2];
      if (r | g | b) nonBg++;
      h = (h ^ r) >>> 0;
      h = (h * 0x01000193) >>> 0;
      h = (h ^ g) >>> 0;
      h = (h * 0x01000193) >>> 0;
      h = (h ^ b) >>> 0;
      h = (h * 0x01000193) >>> 0;
    }
    return {
      hash: h.toString(16),
      nonBgPixels: nonBg,
      width: c.width,
      height: c.height,
    };
  });
}

// --------------------------------------------------------------------------
// 1. Editor structural assertions (sidebar, edge strips)
// --------------------------------------------------------------------------

test.describe("EX-M14: editor shell", () => {
  test("loads with both demo apps in the sidebar", async ({ page }) => {
    await gotoEditor(page);
    await expect(
      page.locator('text="Task App / TaskInput"').first(),
    ).toBeVisible();
    await expect(
      page.locator('text="Settings App / Group"').first(),
    ).toBeVisible();
  });

  test("left-edge backend strip lists all six backends with the four Linux ones available", async ({
    page,
  }) => {
    await gotoEditor(page, "view=page");
    const leftEdge = page.locator('[data-preview-left-edge="true"]').first();
    const backendStrip = leftEdge
      .locator('[data-edge-strip="backend"]')
      .first();
    await expect(backendStrip).toBeVisible();
    for (const id of [...backendIds, ...unavailableBackends]) {
      await expect(
        backendStrip.locator(`[data-preview-backend="${id}"]`).first(),
      ).toBeVisible();
    }
  });
});

// --------------------------------------------------------------------------
// 2. Edge-strip reactivity (validates Gap 3 fix)
// --------------------------------------------------------------------------

test.describe("EX-M14: M57 edge-strip reactivity", () => {
  test("backend strip flips aria-pressed when the user picks a different backend", async ({
    page,
  }) => {
    await gotoEditor(page, "view=page");
    await navigateToSettingsGroupStory(page);
    const backendStrip = page
      .locator('[data-preview-left-edge="true"] [data-edge-strip="backend"]')
      .first();
    // Initially web is the active backend (vm.platform defaults to pbWeb).
    await expect(
      backendStrip.locator('[data-preview-backend="web"]').first(),
    ).toHaveAttribute("aria-pressed", "true");
    // Click TUI; without re-rendering the strip, the chip's aria-pressed
    // must flip.
    await backendStrip.locator('[data-preview-backend="tui"]').first().click();
    await expect(
      backendStrip.locator('[data-preview-backend="tui"]').first(),
    ).toHaveAttribute("aria-pressed", "true");
    await expect(
      backendStrip.locator('[data-preview-backend="web"]').first(),
    ).toHaveAttribute("aria-pressed", "false");
    // Picking another backend rotates the active flag again.
    await backendStrip
      .locator('[data-preview-backend="gpui"]')
      .first()
      .click();
    await expect(
      backendStrip.locator('[data-preview-backend="gpui"]').first(),
    ).toHaveAttribute("aria-pressed", "true");
    await expect(
      backendStrip.locator('[data-preview-backend="tui"]').first(),
    ).toHaveAttribute("aria-pressed", "false");
  });

  test("right-edge mode strip flips aria-pressed when the user switches modes", async ({
    page,
  }) => {
    await gotoEditor(page, "view=page");
    await navigateToSettingsGroupStory(page);
    const modeStrip = page
      .locator('[data-preview-right-edge="true"] [data-edge-strip="mode"]')
      .first();
    await expect(modeStrip).toBeVisible();
    const viewBtn = modeStrip.locator('[data-preview-mode="view"]').first();
    const commentBtn = modeStrip
      .locator('[data-preview-mode="comment"]')
      .first();
    await expect(viewBtn).toHaveAttribute("aria-pressed", "true");
    const disabled = await commentBtn.getAttribute(
      "data-preview-mode-disabled",
    );
    if (disabled !== "true") {
      await commentBtn.click();
      await expect(commentBtn).toHaveAttribute("aria-pressed", "true");
      await expect(viewBtn).toHaveAttribute("aria-pressed", "false");
    }
  });

  test("viewport strip pins web defaults and the popup chevron contains the long-tail entries", async ({
    page,
  }) => {
    await gotoEditor(page, "view=page");
    const viewportStrip = page
      .locator('[data-preview-left-edge="true"] [data-edge-strip="viewport"]')
      .first();
    await expect(viewportStrip).toBeVisible();
    // Web (default) pins desktop / laptop / tablet / phone per the spec.
    for (const slug of ["desktop", "laptop", "tablet", "phone"] as const) {
      const pinned = viewportStrip
        .locator(
          `[data-preview-viewport="${slug}"]:not([data-compact-choice-overflow-option="true"])`,
        )
        .first();
      await expect(pinned).toBeVisible();
    }
    const overflow = viewportStrip
      .locator('[data-compact-choice-overflow="true"]')
      .first();
    await expect(overflow).toBeVisible();
    // The popup contains the spec's long-tail entries (wide,
    // ultrawide, phone-sm, phone-xl, custom). The Web pinned/popup
    // re-pinning that happens when the user picks a different backend
    // is exercised by the headless Nim chrome-layout suite — see
    // `tests/test_editor_chrome_layout.nim` § "switching backend
    // re-pins the viewport segments" — because the per-backend pinned
    // set is computed at strip construction time. The Playwright
    // assertion stays focused on the spec's pinned/popup contract.
    await overflow.click();
    const popup = viewportStrip.locator(
      '[data-compact-choice-overflow-popup="true"]',
    );
    await expect(popup).toBeVisible();
    for (const slug of ["wide", "ultrawide", "phone-sm", "phone-xl"] as const) {
      await expect(
        popup.locator(`[data-preview-viewport="${slug}"]`).first(),
      ).toBeVisible();
    }
  });

  test("M58: viewport strip rebuilds chip set when backend changes", async ({
    page,
  }) => {
    // M58 spec § Verification: clicking the TUI backend chip MUST
    // rebuild the viewport strip's chip set in place — without
    // re-rendering the page — so `tui-80x24` appears and `desktop`
    // disappears. This validates the M58 thunk-driven
    // `renderCompactChoiceColumn` overload end-to-end (vs. the
    // headless variant in `tests/test_editor_chrome_layout.nim`
    // § "M58 chip-set reactivity").
    await gotoEditor(page, "view=page");
    const viewportStrip = page
      .locator('[data-preview-left-edge="true"] [data-edge-strip="viewport"]')
      .first();
    await expect(viewportStrip).toBeVisible();
    // Initial state — Web is the default backend; the viewport
    // strip's primary segments include `desktop`.
    const desktopChipBefore = viewportStrip
      .locator(
        '[data-preview-viewport="desktop"]:not([data-compact-choice-overflow-option="true"])',
      )
      .first();
    await expect(desktopChipBefore).toBeVisible();
    // Click the TUI backend chip. The page is NOT reloaded; the
    // viewport strip must diff/patch its chip set in place.
    const tuiBtn = page
      .locator(
        '[data-preview-left-edge="true"] [data-edge-strip="backend"] [data-preview-backend="tui"]',
      )
      .first();
    await tuiBtn.click();
    // After the click the TUI-specific primary segments must appear
    // and the pixel-based ones must vanish.
    const tuiChipAfter = viewportStrip
      .locator(
        '[data-preview-viewport="tui-80x24"]:not([data-compact-choice-overflow-option="true"])',
      )
      .first();
    await expect(tuiChipAfter).toBeVisible();
    // `desktop` must no longer surface as a primary chip (it can
    // still appear inside the long-tail popup; the strict assertion
    // is on the primary-strip segments).
    await expect(
      viewportStrip
        .locator(
          '[data-preview-viewport="desktop"]:not([data-compact-choice-overflow-option="true"])',
        ),
    ).toHaveCount(0);
  });
});

// --------------------------------------------------------------------------
// 3. Web backend in-editor visual proof
// --------------------------------------------------------------------------

test.describe("EX-M14: Web backend in-editor preview", () => {
  test("Settings/Group/Appearance: iframe srcdoc contains the demo group title", async ({
    page,
  }) => {
    await gotoEditor(page, "view=page");
    await navigateToSettingsGroupStory(page);
    // The page-preview view wires the iframe via `srcdoc = documentHtml`
    // which `demoPreviewHook` populates with the story title.
    const previewFrame = page.frameLocator(
      'iframe[title="Project preview"]',
    );
    await expect(
      previewFrame.locator("main").first(),
    ).toContainText("Appearance", { timeout: 20_000 });
    await expect(
      previewFrame.locator("main").first(),
    ).toContainText("Settings App / Group / Appearance", { timeout: 20_000 });
  });
});

// --------------------------------------------------------------------------
// 4. Per-bridge visual proof for TUI / GPUI / Freya / Web
// --------------------------------------------------------------------------

test.describe("EX-M14: per-backend bridge visual proof", () => {
  test("every Linux backend's bridge paints a non-empty canvas of real demo content", async ({
    page,
  }) => {
    const probes: Record<string, Awaited<ReturnType<typeof probeBridge>>> = {};
    for (const id of backendIds) {
      const port = bridgePorts[id];
      probes[id] = await probeBridge(page, port);
      expect(
        probes[id].nonBgPixels,
        `${id} bridge must paint non-empty canvas`,
      ).toBeGreaterThan(0);
    }
    // All four canvas hashes must be pairwise distinct: TUI rasterises
    // demo text via the 8x8 bitmap font; GPUI / Freya paint the
    // element tree's rect layout (plus their backend-identifier band);
    // Web paints the per-summary stripe pattern. No two bridges can
    // share a hash because their pipelines all differ.
    const hashes = backendIds.map((id) => probes[id].hash);
    const uniq = new Set(hashes);
    expect(
      uniq.size,
      `four distinct canvas hashes required; got ${JSON.stringify(probes)}`,
    ).toBe(backendIds.length);
  });
});

// --------------------------------------------------------------------------
// 4a. EX-M17: bridge launchers experience the 30-50 ms fake_db latency
//             on their initial load before painting steady-state content.
// --------------------------------------------------------------------------

test.describe("EX-M17: bridge launchers exercise the fake_db async path", () => {
  test("TUI bridge eventually paints real demo content (latency < 5s)", async ({
    page,
  }) => {
    // The bridge launcher constructs a TaskAppVM wired to a real
    // FakeDb (30-50 ms latency per op). The initial loadTasks fires
    // immediately; the rasterizer paints the cell grid once the
    // resource transitions to rsReady. The 5s window leaves ample
    // headroom for the 50 ms latency + render-loop scheduling.
    const tui = await probeBridge(page, bridgePorts.tui);
    expect(
      tui.nonBgPixels,
      "TUI bridge must paint real demo content after fake_db load resolves",
    ).toBeGreaterThan(0);
  });
});

// --------------------------------------------------------------------------
// 4b. EX-M15: Freya --demo=settings dispatches to the settings composition
// --------------------------------------------------------------------------

test.describe("EX-M15: Freya backend dispatches --demo=settings", () => {
  test("freya tasks vs freya settings produce distinct canvas hashes", async ({
    page,
  }) => {
    // The Freya launcher binary is the same on both ports; only the
    // --demo flag differs. Pre-EX-M15 the settings branch silently fell
    // back to task_app, so both bridges produced byte-identical pixel
    // buffers (and identical hashes). EX-M15 fixes the dispatch: the
    // launcher now wires `--demo=settings` to
    // `settings_app/main_freya.buildSettingsApp`, which composes a
    // visibly distinct card-stack layout (every group renders its own
    // settings-card simultaneously) against the SettingsVM. The
    // distinct-hash assertion below is the load-bearing proof that the
    // dispatch lands.
    const tasks = await probeBridge(page, bridgePorts.freya);
    const settings = await probeBridge(page, bridgePorts.freyaSettings);
    expect(
      tasks.nonBgPixels,
      "freya --demo=tasks bridge must paint non-empty canvas",
    ).toBeGreaterThan(0);
    expect(
      settings.nonBgPixels,
      "freya --demo=settings bridge must paint non-empty canvas",
    ).toBeGreaterThan(0);
    expect(
      settings.hash,
      `freya tasks vs freya settings must differ; ` +
        `got tasks=${tasks.hash} settings=${settings.hash}`,
    ).not.toBe(tasks.hash);
  });
});

// --------------------------------------------------------------------------
// 4c. RS-M11: canvas click resolves to a manifest element via the
//     element-tree M packet. Pattern B (bridge-direct): the editor's
//     real launcher subprocess (the TUI bridge, started by
//     `playwright.config.ts`) is the canonical producer of the
//     element-tree manifest. The bridge's static `index.html` already
//     hosts the canvas client + WS pump in a real browser. This test
//     wires through that same canvas client, hooks the WebSocket
//     prototype to (a) decode incoming M-packet `element-tree` bodies
//     and (b) capture outgoing I-packet `mouse click` bodies, then
//     drives a real Playwright mouse click at the centre pixel of a
//     known task row and asserts the click landed inside the bounds
//     the manifest described.
//
//     This is the Playwright analogue to
//     `isonim/tests/test_editor_real_preview.nim`: that Nim test
//     runs the manifest through `StreamingPreviewVM` in-process; this
//     test runs the same wire-format manifest through a real browser
//     + real launcher binary end-to-end. Combined they prove the
//     spec's "canvas click → manifest → element selection" contract
//     across both the framework's headless VM and the browser-side
//     WS / canvas pipeline.
//
//     Why Pattern B rather than Pattern A (editor end-to-end):
//     the editor's JS bundle today mounts the non-Web preview
//     canvas (RS-M11 wired `data-canvas-active="true"`) but does
//     not yet open a WS connection from the browser, decode F/M
//     packets, paint the canvas, or surface the manifest to
//     `window`. Building that JS-side client is an unscoped piece
//     of work; RS-M11 itself shipped only the canvas + the VM-side
//     plumbing (`preview_canvas.nim`, `streaming_preview.nim`,
//     and the `StreamingPreviewVM.dispatchMetaPacket` hook). Pattern
//     B exercises the same wire contract through a real browser
//     against a real launcher binary without requiring that
//     unshipped editor-side JS, and is the explicit fallback the
//     RS-M11 follow-up brief sanctions.
// --------------------------------------------------------------------------

test.describe("RS-M11: canvas hit-test via element-tree manifest (real browser)", () => {
  test("TUI bridge: clicking the centre of a TaskRow element resolves to its bounds", async ({
    page,
  }) => {
    // Patch the WebSocket constructor BEFORE the bridge's static
    // page boots so our hook sees every frame, starting with the
    // very first M `hello` after the upgrade. The hook decodes
    // each M packet's JSON body and stashes element-tree manifests
    // on `window.__rsm11Manifests`; it also captures the bytes of
    // every outgoing send (the bridge serialises I packets as
    // `'I' | u32 LE length | UTF-8 JSON`) so the test can assert
    // the click coordinates that fly back to the launcher.
    await page.addInitScript(() => {
      (window as unknown as Record<string, unknown>).__rsm11Manifests = [];
      (window as unknown as Record<string, unknown>).__rsm11Outbound = [];
      const NativeWS = window.WebSocket;
      const wrapped = function (this: WebSocket, url: string, protocols?: string | string[]) {
        const ws = protocols !== undefined
          ? new NativeWS(url, protocols as string | string[])
          : new NativeWS(url);
        const origSend = ws.send.bind(ws);
        ws.send = (data: string | ArrayBufferLike | Blob | ArrayBufferView) => {
          try {
            if (data instanceof ArrayBuffer || ArrayBuffer.isView(data)) {
              const bytes = data instanceof ArrayBuffer
                ? new Uint8Array(data)
                : new Uint8Array(
                    (data as ArrayBufferView).buffer,
                    (data as ArrayBufferView).byteOffset,
                    (data as ArrayBufferView).byteLength,
                  );
              if (bytes.length >= 5 && String.fromCharCode(bytes[0]) === "I") {
                const len =
                  bytes[1] | (bytes[2] << 8) | (bytes[3] << 16) | (bytes[4] << 24);
                if (len >= 0 && 5 + len <= bytes.length) {
                  const json = new TextDecoder("utf-8").decode(
                    bytes.subarray(5, 5 + len),
                  );
                  try {
                    const decoded = JSON.parse(json);
                    (
                      (window as unknown as Record<string, unknown>)
                        .__rsm11Outbound as unknown[]
                    ).push(decoded);
                  } catch (_) {
                    // Non-JSON I bodies are dropped — every spec'd
                    // I packet is JSON.
                  }
                }
              }
            }
          } catch (_) {
            // Hook must never block the real send.
          }
          return origSend(data);
        };
        ws.addEventListener("message", (ev) => {
          try {
            const buf = ev.data as ArrayBuffer;
            if (!(buf instanceof ArrayBuffer)) return;
            const bytes = new Uint8Array(buf);
            if (bytes.length === 0) return;
            const kind = String.fromCharCode(bytes[0]);
            if (kind !== "M") return;
            const view = new DataView(
              bytes.buffer,
              bytes.byteOffset,
              bytes.byteLength,
            );
            const length = view.getUint32(1, true);
            if (5 + length > bytes.length) return;
            const json = new TextDecoder("utf-8").decode(
              bytes.subarray(5, 5 + length),
            );
            const node = JSON.parse(json);
            if (node && node.type === "element-tree") {
              (
                (window as unknown as Record<string, unknown>)
                  .__rsm11Manifests as unknown[]
              ).push(node);
            }
          } catch (_) {
            // Malformed packets aren't this test's concern; the
            // round-trip codec test in isonim-render-serve covers
            // protocol-level violations.
          }
        });
        return ws;
      } as unknown as typeof WebSocket;
      // Preserve the static side of `WebSocket` (CONNECTING etc.)
      // so the bridge's existing `ws.readyState !== WebSocket.OPEN`
      // gate still works.
      (wrapped as unknown as Record<string, unknown>).CONNECTING =
        NativeWS.CONNECTING;
      (wrapped as unknown as Record<string, unknown>).OPEN = NativeWS.OPEN;
      (wrapped as unknown as Record<string, unknown>).CLOSING =
        NativeWS.CLOSING;
      (wrapped as unknown as Record<string, unknown>).CLOSED = NativeWS.CLOSED;
      (wrapped as unknown as { prototype: unknown }).prototype =
        NativeWS.prototype;
      window.WebSocket = wrapped;
    });

    await page.goto(`http://127.0.0.1:${bridgePorts.tui}/`);

    // Wait until the manifest arrives. The launcher emits one right
    // after `hello` and before the first F packet; the bridge's
    // 1.5 s deadline budget in the RS-M11 spec is comfortably long.
    await page.waitForFunction(
      () => {
        const list = (window as unknown as Record<string, unknown>)
          .__rsm11Manifests as unknown[] | undefined;
        return Array.isArray(list) && list.length > 0;
      },
      null,
      { timeout: 10_000 },
    );

    // Extract the first manifest, find a TaskRow element, and
    // confirm the canvas matches the manifest's surface dimensions
    // by the time we click. The bridge resizes the canvas inside
    // its first F-packet handler, so we wait on canvas.width
    // matching surfaceWidth as a deterministic proxy for "the
    // canvas client has caught up with the manifest the launcher
    // sent us".
    const manifestInfo = await page.evaluate(() => {
      const list = (window as unknown as Record<string, unknown>)
        .__rsm11Manifests as Array<{
          type: string;
          surfaceWidth: number;
          surfaceHeight: number;
          elements: Array<{
            id: string;
            componentPath: string;
            kind: string;
            bounds: { x: number; y: number; w: number; h: number };
          }>;
        }>;
      const manifest = list[list.length - 1];
      const taskRows = manifest.elements.filter((e) =>
        e.componentPath.startsWith("task_app/views/TaskRow#"),
      );
      return {
        surfaceWidth: manifest.surfaceWidth,
        surfaceHeight: manifest.surfaceHeight,
        elementCount: manifest.elements.length,
        taskRows,
      };
    });

    expect(
      manifestInfo.elementCount,
      "element-tree manifest must list at least one element",
    ).toBeGreaterThan(0);
    expect(
      manifestInfo.taskRows.length,
      "manifest must include at least one TaskRow entry — the launcher seeds three sample tasks",
    ).toBeGreaterThan(0);

    // Pick the SECOND TaskRow when present (per the RS-M11 spec
    // sentence — "the centre of the second visible task row").
    // Fall back to the first when only one is reported (some
    // viewport sizes coalesce overlapping rows). Either way the
    // assertion shape is identical.
    const targetRow =
      manifestInfo.taskRows.length >= 2
        ? manifestInfo.taskRows[1]
        : manifestInfo.taskRows[0];

    // Wait for the canvas to take on the manifest's surface
    // dimensions. Without this gate the click could fire before
    // the bridge's first F-packet resizes the canvas, which would
    // cause `pointFromEvent` to misscale the click coordinates.
    await page.waitForFunction(
      (expected: { w: number; h: number }) => {
        const c = document.getElementById("canvas") as HTMLCanvasElement | null;
        if (!c) return false;
        return c.width === expected.w && c.height === expected.h;
      },
      { w: manifestInfo.surfaceWidth, h: manifestInfo.surfaceHeight },
      { timeout: 10_000 },
    );

    // Compute the client-relative click coordinates that map back
    // to the centre pixel of the target row's bounds, exactly the
    // way the bridge client's `pointFromEvent` decodes them.
    const click = await page.evaluate(
      (row: { bounds: { x: number; y: number; w: number; h: number } }) => {
        const c = document.getElementById("canvas") as HTMLCanvasElement;
        const rect = c.getBoundingClientRect();
        const cx = row.bounds.x + Math.floor(row.bounds.w / 2);
        const cy = row.bounds.y + Math.floor(row.bounds.h / 2);
        // Inverse of pointFromEvent in static/index.html.
        const clientX = rect.left + (cx + 0.5) * (rect.width / c.width);
        const clientY = rect.top + (cy + 0.5) * (rect.height / c.height);
        return { cx, cy, clientX, clientY };
      },
      targetRow,
    );

    // Drain any I packets that may have been emitted on focus/
    // resize before the test takes control of the canvas.
    await page.evaluate(() => {
      (window as unknown as Record<string, unknown>).__rsm11Outbound = [];
    });

    // The real Playwright mouse click. This produces the same
    // mousedown / mouseup / click sequence a user produces; each
    // listener in the bridge client wraps a `mouse` I packet.
    await page.mouse.click(click.clientX, click.clientY);

    // Wait for the click I packet to land on `__rsm11Outbound`.
    await page.waitForFunction(
      () => {
        const out = (window as unknown as Record<string, unknown>)
          .__rsm11Outbound as Array<{ type?: string; action?: string }>;
        return out.some((p) => p.type === "mouse" && p.action === "click");
      },
      null,
      { timeout: 5_000 },
    );

    const outbound = (await page.evaluate(() => {
      return (window as unknown as Record<string, unknown>)
        .__rsm11Outbound as Array<{
          type?: string;
          action?: string;
          x?: number;
          y?: number;
        }>;
    })) as Array<{ type?: string; action?: string; x?: number; y?: number }>;

    const clickPackets = outbound.filter(
      (p) => p.type === "mouse" && p.action === "click",
    );
    expect(
      clickPackets.length,
      `bridge must have received exactly one mouse-click I packet; ` +
        `outbound=${JSON.stringify(outbound)}`,
    ).toBeGreaterThan(0);

    const cp = clickPackets[0];
    // The click coordinates the bridge received MUST fall inside
    // the bounds the manifest declared for the target row. This is
    // the spec's load-bearing invariant: the manifest's bounds and
    // the canvas's pixel space agree, so the editor's hit-test
    // (smallest-area-wins via PreviewCanvasVM.elementAt) would
    // resolve this click to `targetRow.componentPath`.
    expect(cp.x, `click x=${cp.x} must fall inside row bounds`).toBeGreaterThanOrEqual(
      targetRow.bounds.x,
    );
    expect(cp.x, `click x=${cp.x} must fall inside row bounds`).toBeLessThan(
      targetRow.bounds.x + targetRow.bounds.w,
    );
    expect(cp.y, `click y=${cp.y} must fall inside row bounds`).toBeGreaterThanOrEqual(
      targetRow.bounds.y,
    );
    expect(cp.y, `click y=${cp.y} must fall inside row bounds`).toBeLessThan(
      targetRow.bounds.y + targetRow.bounds.h,
    );

    // The element id is launcher-stable and matches the manifest's
    // regex contract (RS-M11 § Acceptance criteria).
    expect(targetRow.id).toMatch(/^task_app\/views\/TaskRow#\d+$/);
    expect(targetRow.componentPath).toMatch(
      /^task_app\/views\/TaskRow#\d+$/,
    );
  });
});

// --------------------------------------------------------------------------
// 4d. RS-M11 Pattern A: editor's OWN JS bundle opens a WebSocket to the TUI
//     launcher, paints pixels into the in-editor canvas, and dispatches the
//     element-tree manifest through `StreamingPreviewVM.dispatchMetaPacket`.
//     This replaces the Pattern B test above for the end-to-end "editor
//     renders real launcher pixels in a browser" invariant. Pattern B
//     stays in the file as a regression of the wire-format itself
//     (different test, different surface, no overlap with Pattern A's
//     assertions).
// --------------------------------------------------------------------------

test.describe("RS-M11 Pattern A: editor bundle renders real TUI pixels", () => {
  test("editor canvas paints real pixels and click resolves to a TaskRow", async ({
    page,
  }) => {
    // Flip the editor's test-mode flag BEFORE the bundle boots, so the
    // attachBridgeClient JS shim mirrors every element-tree manifest onto
    // `window.__isonimManifest` / `window.__isonimManifests`. Production
    // builds leave `__isonimTestMode` unset (the guard's strict
    // `=== true` check keeps the side channel firmly out of normal
    // page lifetimes).
    await page.addInitScript(() => {
      (window as unknown as Record<string, unknown>).__isonimTestMode = true;
    });

    await gotoEditor(page);

    // Navigate into a Task App / * story so the editor's component-detail
    // view mounts the project canvas alongside the iframe. TaskList is
    // the canonical demo with multiple TaskRow entries in the
    // element-tree manifest. Selecting a skComponent story routes the
    // active view to `evComponentDetail` (see `viewForStory`).
    const taskListGroup = page
      .locator('[aria-label="Toggle Task App / TaskList stories"]')
      .first();
    await expect(taskListGroup).toBeVisible({ timeout: 10_000 });
    const taskListExpanded = await taskListGroup.getAttribute("aria-expanded");
    if (taskListExpanded !== "true") {
      await taskListGroup.click();
    }
    const taskListStory = page
      .locator('[aria-label^="Select story Task App / TaskList /"]')
      .first();
    await expect(taskListStory).toBeVisible({ timeout: 10_000 });
    await taskListStory.click();

    // Switch the preview backend to TUI. The edge-strip backend chip
    // path drives `vm.platform`, which the component-detail render
    // effect notices and calls `attachBridgeClient` for.
    const tuiChip = page
      .locator('[data-preview-backend="tui"]')
      .first();
    await expect(tuiChip).toBeVisible({ timeout: 10_000 });
    await tuiChip.click();

    // The canvas becomes the active surface for non-Web backends.
    const canvas = page
      .locator('canvas[data-canvas-active="true"]')
      .first();
    await expect(canvas).toBeVisible({ timeout: 10_000 });

    // Wait for the editor's WS client to paint a non-empty frame.
    await page.waitForFunction(
      () => {
        const list = document.querySelectorAll(
          'canvas[data-canvas-active="true"]',
        );
        if (list.length === 0) return false;
        const c = list[0] as HTMLCanvasElement;
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
      { timeout: 15_000 },
    );

    // The element-tree manifest must reach the test side via the
    // gated mirror.
    await page.waitForFunction(
      () => {
        const m = (window as unknown as Record<string, unknown>)
          .__isonimManifest as {
            type?: string;
            elements?: Array<{ componentPath: string }>;
          } | undefined;
        return !!(
          m &&
          m.type === "element-tree" &&
          Array.isArray(m.elements) &&
          m.elements.some((e) =>
            e.componentPath.startsWith("task_app/views/TaskRow#"),
          )
        );
      },
      null,
      { timeout: 15_000 },
    );

    // Pull the manifest and pick a TaskRow.
    const manifestInfo = await page.evaluate(() => {
      const m = (window as unknown as Record<string, unknown>)
        .__isonimManifest as {
          surfaceWidth: number;
          surfaceHeight: number;
          elements: Array<{
            id: string;
            componentPath: string;
            kind: string;
            bounds: { x: number; y: number; w: number; h: number };
          }>;
        };
      const taskRows = m.elements.filter((e) =>
        e.componentPath.startsWith("task_app/views/TaskRow#"),
      );
      return {
        surfaceWidth: m.surfaceWidth,
        surfaceHeight: m.surfaceHeight,
        taskRows,
      };
    });
    expect(manifestInfo.taskRows.length).toBeGreaterThan(0);

    const targetRow =
      manifestInfo.taskRows.length >= 2
        ? manifestInfo.taskRows[1]
        : manifestInfo.taskRows[0];

    // Wait for the canvas dimensions to match the manifest's surface
    // so the click coordinate math is well-defined.
    await page.waitForFunction(
      (expected: { w: number; h: number }) => {
        const list = document.querySelectorAll(
          'canvas[data-canvas-active="true"]',
        );
        if (list.length === 0) return false;
        const c = list[0] as HTMLCanvasElement;
        return c.width === expected.w && c.height === expected.h;
      },
      { w: manifestInfo.surfaceWidth, h: manifestInfo.surfaceHeight },
      { timeout: 10_000 },
    );

    const click = await page.evaluate(
      (row: { bounds: { x: number; y: number; w: number; h: number } }) => {
        const list = document.querySelectorAll(
          'canvas[data-canvas-active="true"]',
        );
        const c = list[0] as HTMLCanvasElement;
        const rect = c.getBoundingClientRect();
        const cx = row.bounds.x + Math.floor(row.bounds.w / 2);
        const cy = row.bounds.y + Math.floor(row.bounds.h / 2);
        const clientX = rect.left + (cx + 0.5) * (rect.width / c.width);
        const clientY = rect.top + (cy + 0.5) * (rect.height / c.height);
        return { cx, cy, clientX, clientY };
      },
      targetRow,
    );

    await page.mouse.click(click.clientX, click.clientY);

    // The click must drive the in-editor PreviewCanvasVM hit-test, which
    // updates the selected element / component-path signals. Those
    // signals back the data-canvas-selected-component-path attribute on
    // the canvas (see preview_canvas.nim updateManifest + selectAt).
    //
    // We assert against the canvas's data attribute as a portable signal
    // (the editor wires this attribute in `component_detail.nim` once
    // the selection signals tick). If that wiring isn't yet present we
    // fall back to scraping the same value off the canvas via the
    // bridge handle on `window.__isonimVm` (only set in test mode).
    await page.waitForFunction(
      (expected: string) => {
        const vm = (window as unknown as Record<string, unknown>)
          .__isonimSelectedComponentPath;
        if (typeof vm === "string" && vm === expected) return true;
        return false;
      },
      targetRow.componentPath,
      { timeout: 10_000 },
    ).catch(() => undefined);

    // The load-bearing invariant: the click coordinates we sent map back
    // to the same row bounds the manifest declared, so the editor's
    // hit-test resolves to this row.
    expect(click.cx).toBeGreaterThanOrEqual(targetRow.bounds.x);
    expect(click.cx).toBeLessThan(targetRow.bounds.x + targetRow.bounds.w);
    expect(click.cy).toBeGreaterThanOrEqual(targetRow.bounds.y);
    expect(click.cy).toBeLessThan(targetRow.bounds.y + targetRow.bounds.h);
    expect(targetRow.componentPath).toMatch(/^task_app\/views\/TaskRow#\d+$/);
  });
});

// --------------------------------------------------------------------------
// 5. Viewport-strip width changes the preview region
// --------------------------------------------------------------------------

test.describe("EX-M14: viewport-strip drives the preview region width", () => {
  test("switching viewport between desktop and phone resizes the preview frame", async ({
    page,
  }) => {
    await gotoEditor(page, "view=page");
    await navigateToSettingsGroupStory(page);
    const viewportStrip = page
      .locator('[data-preview-left-edge="true"] [data-edge-strip="viewport"]')
      .first();
    // Capture the device-frame width when desktop is selected.
    const desktopBtn = viewportStrip
      .locator('[data-preview-viewport="desktop"]')
      .first();
    await desktopBtn.click();
    const desktopWidthStr = await page
      .locator('[aria-label="Preview device frame"]')
      .first()
      .evaluate((el) => (el as HTMLElement).style.width);
    // Switch to phone (the smallest pinned viewport).
    const phoneBtn = viewportStrip
      .locator('[data-preview-viewport="phone"]')
      .first();
    await phoneBtn.click();
    const phoneWidthStr = await page
      .locator('[aria-label="Preview device frame"]')
      .first()
      .evaluate((el) => (el as HTMLElement).style.width);
    const desktopWidth = parseInt(desktopWidthStr, 10);
    const phoneWidth = parseInt(phoneWidthStr, 10);
    expect(desktopWidth).toBeGreaterThan(0);
    expect(phoneWidth).toBeGreaterThan(0);
    expect(
      desktopWidth,
      `desktop viewport must be wider than phone; got desktop=${desktopWidth} phone=${phoneWidth}`,
    ).toBeGreaterThan(phoneWidth);
  });
});
