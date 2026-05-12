// Playwright config for the isonim-examples demo editor.
//
// EX-M14: drives the editor through the M57 edge-strip chrome and the
// RS-M7 streaming-preview backends. Boots:
//
//   * the editor's static bundle on port 8091 (`python3 -m http.server`),
//   * the TUI / GPUI / Freya / Web bridge launchers on ports 8101–8104
//     so the per-backend visual-proof tests can hit each canvas client
//     directly (the in-browser editor itself cannot spawn subprocesses).
//
// Run via:
//   cd tests/browser && npx playwright test
//
// Pre-reqs (handled by Justfile + nix shell):
//   - `just build-backends`  builds the four Linux launcher binaries.
//   - `just editor-build`    builds the Nim → JS editor bundle.

import { existsSync } from "node:fs";
import { defineConfig } from "@playwright/test";

const chromiumExecutable =
  process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ??
  (existsSync("/run/current-system/sw/bin/chromium")
    ? "/run/current-system/sw/bin/chromium"
    : undefined);

// Per-backend bridge ports. Exposed to the specs via the BRIDGE_PORTS
// env var so a single source of truth lives here. The `freyaSettings`
// entry (EX-M15) is the same launcher binary as `freya` started with
// `--demo=settings` so the spec can prove the Freya backend dispatches
// to the settings composition rather than falling back to task_app.
const bridgePorts = {
  web: 8101,
  tui: 8102,
  gpui: 8103,
  freya: 8104,
  freyaSettings: 8105,
};
process.env.BRIDGE_PORTS = JSON.stringify(bridgePorts);

const buildBackendsDir = "../../build/backends";
const staticDir = "../../../isonim-render-serve/static";

export default defineConfig({
  testDir: "./specs",
  // First-frame bridge spawn can take a few seconds on a cold start;
  // the per-backend visual-proof tests then each consume up to a few
  // seconds of WebSocket handshake + first-frame paint.
  timeout: 180_000,
  expect: {
    timeout: 20_000,
  },
  use: {
    baseURL: "http://localhost:8091",
    headless: true,
    browserName: "chromium",
    launchOptions: chromiumExecutable
      ? { executablePath: chromiumExecutable }
      : undefined,
  },
  webServer: [
    {
      command: "python3 -m http.server 8091 --bind 127.0.0.1",
      cwd: "../../build/editor",
      port: 8091,
      reuseExistingServer: true,
      timeout: 30_000,
    },
    {
      command: `${buildBackendsDir}/isonim-examples-web --port ${bridgePorts.web} --demo=tasks --static ${staticDir} --width 320 --height 200 --fps 8`,
      url: `http://127.0.0.1:${bridgePorts.web}/`,
      reuseExistingServer: true,
      timeout: 30_000,
    },
    {
      command: `${buildBackendsDir}/isonim-examples-tui --port ${bridgePorts.tui} --demo=tasks --static ${staticDir} --fps 8`,
      url: `http://127.0.0.1:${bridgePorts.tui}/`,
      reuseExistingServer: true,
      timeout: 30_000,
    },
    {
      command: `${buildBackendsDir}/isonim-examples-gpui --port ${bridgePorts.gpui} --demo=tasks --static ${staticDir} --width 320 --height 200 --fps 8`,
      url: `http://127.0.0.1:${bridgePorts.gpui}/`,
      reuseExistingServer: true,
      timeout: 30_000,
    },
    {
      command: `${buildBackendsDir}/isonim-examples-freya --port ${bridgePorts.freya} --demo=tasks --static ${staticDir} --width 320 --height 200 --fps 8`,
      url: `http://127.0.0.1:${bridgePorts.freya}/`,
      reuseExistingServer: true,
      timeout: 30_000,
    },
    // EX-M15: a second Freya launcher instance, started with
    // --demo=settings. The spec probes this bridge and asserts the
    // canvas hash is *distinct* from the `freya --demo=tasks` bridge
    // above, proving the Freya backend's --demo dispatch now lands
    // (no fallback to task_app).
    {
      command: `${buildBackendsDir}/isonim-examples-freya --port ${bridgePorts.freyaSettings} --demo=settings --static ${staticDir} --width 320 --height 200 --fps 8`,
      url: `http://127.0.0.1:${bridgePorts.freyaSettings}/`,
      reuseExistingServer: true,
      timeout: 30_000,
    },
  ],
  projects: [
    {
      name: "editor-demo",
      testMatch: "editor-demo.spec.ts",
      use: {
        baseURL: "http://localhost:8091",
      },
    },
  ],
});
