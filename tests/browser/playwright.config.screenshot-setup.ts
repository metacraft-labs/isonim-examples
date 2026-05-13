// M-EVP-2: standalone Playwright config for the
// editor-screenshot-setup spec.
//
// This spec only needs the editor's static JS bundle (port 8091); it
// does NOT need the per-backend bridge launchers that `editor-demo`
// requires. Splitting the config out lets the spec run on macOS where
// the GPUI bridge's `libgpui_nim_shim.dylib` is unavailable. The spec
// imports the `views` table from `tools/editor-screenshot.mjs` directly
// and exercises each setup against the real editor JS bundle.
//
// Run via:
//   cd tests/browser && \
//     npx playwright test \
//       --config=playwright.config.screenshot-setup.ts

import { existsSync } from "node:fs";
import { defineConfig } from "@playwright/test";

const chromiumExecutable =
  process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ??
  (existsSync("/run/current-system/sw/bin/chromium")
    ? "/run/current-system/sw/bin/chromium"
    : undefined);

export default defineConfig({
  testDir: "./specs",
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
  ],
  projects: [
    {
      name: "editor-screenshot-setup",
      testMatch: "editor-screenshot-setup.spec.mts",
      use: {
        baseURL: "http://localhost:8091",
      },
    },
  ],
});
