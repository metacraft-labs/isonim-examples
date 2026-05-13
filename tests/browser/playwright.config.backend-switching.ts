// M-EVP-1: standalone Playwright config for the backend-switching spec.
//
// This spec only needs the editor's static JS bundle (port 8091); it
// does NOT need the four Linux bridge launchers that `editor-demo`
// uses for per-backend canvas hashing. Splitting the config out lets
// the spec run on macOS where the GPUI bridge's `libgpui_nim_shim.dylib`
// is unavailable (the Linux launcher uses a shim that isn't built on
// macOS today; M-EVP-1's scope is the iframe-srcdoc chain, which is
// purely the editor JS and doesn't depend on any bridge process).
//
// Run via:
//   cd tests/browser && \
//     npx playwright test \
//       --config=playwright.config.backend-switching.ts

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
      name: "editor-backend-switching",
      testMatch: "editor-backend-switching.spec.ts",
      use: {
        baseURL: "http://localhost:8091",
      },
    },
  ],
});
