// Playwright config for the conversation app's editor stories alone.
//
// Those stories are mounted live in the web preview, so they need only the
// editor server — none of the per-backend launchers the default config
// starts. Port 8191 keeps it clear of a running `just editor-serve` (8091).
//
//   cd tests/browser && npx playwright test -c playwright.config.conversation.ts
import { existsSync } from "node:fs";
import { defineConfig } from "@playwright/test";

const chromiumExecutable =
  process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ??
  ["/run/current-system/sw/bin/chromium", "/usr/bin/chromium"].find((p) =>
    existsSync(p),
  );

const port = Number(process.env.CONVERSATION_EDITOR_PORT ?? "8191");

export default defineConfig({
  testDir: "./specs",
  testMatch: /conversation-story\.spec\.ts$/,
  timeout: 120_000,
  expect: { timeout: 20_000 },
  use: {
    baseURL: `http://localhost:${port}`,
    headless: true,
    browserName: "chromium",
    launchOptions: chromiumExecutable
      ? { executablePath: chromiumExecutable }
      : undefined,
  },
  webServer: [
    {
      command: "node ../../tools/editor-server.mjs",
      cwd: "../../build/editor",
      env: { PORT: String(port) },
      port,
      reuseExistingServer: false,
      timeout: 30_000,
    },
  ],
});
