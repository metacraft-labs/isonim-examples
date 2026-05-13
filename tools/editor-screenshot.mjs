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

import { execSync, spawn } from "child_process";
import { mkdirSync, rmSync, existsSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const projectRoot = join(__dirname, "..");
const editorDir = join(projectRoot, "build", "editor");
const screenshotDir = join(editorDir, "screenshots");

const sizes = {
  wide: { width: 1920, height: 1080 },
  laptop: { width: 1440, height: 900 },
  medium: { width: 1280, height: 800 },
  tablet: { width: 1024, height: 768 },
  narrow: { width: 768, height: 1024 },
  mobile: { width: 375, height: 812 },
};

const views = {
  shell: {
    description: "Editor shell — sidebar + preview + inspector (default state)",
    setup: async () => {},
  },
  "story-selected": {
    description: "Editor shell with the Settings/Group/Appearance story selected",
    setup: async (page) => {
      const groupHeader = await page.$(
        '[aria-label="Toggle Settings App / Group stories"]',
      );
      if (groupHeader) {
        await groupHeader.click();
        await page.waitForTimeout(150);
      }
      const story = await page.$(
        '[aria-label="Select story Settings App / Group / Appearance"]',
      );
      if (story) {
        await story.click();
        await page.waitForTimeout(200);
      }
    },
  },
  "story-selected-tui": {
    description: "Story selected, then TUI backend chip clicked in the preview-pane toolbar",
    setup: async (page) => {
      const groupHeader = await page.$(
        '[aria-label="Toggle Settings App / Group stories"]',
      );
      if (groupHeader) {
        await groupHeader.click();
        await page.waitForTimeout(150);
      }
      const story = await page.$(
        '[aria-label="Select story Settings App / Group / Appearance"]',
      );
      if (story) {
        await story.click();
        await page.waitForTimeout(200);
      }
      const tuiChip = await page.$(
        '[aria-label="Preview backend TUI"]',
      );
      if (tuiChip) {
        await tuiChip.click();
        await page.waitForTimeout(250);
      }
    },
  },
};

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
  for (const [k, v] of Object.entries(views)) console.log(`  ${k}: ${v.description}`);
  console.log("Sizes:");
  for (const [k, v] of Object.entries(sizes)) console.log(`  ${k}: ${v.width}x${v.height}`);
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

async function main() {
  if (!skipBuild) {
    console.log("==> Building isonim-examples editor...");
    mkdirSync(editorDir, { recursive: true });
    execSync(
      `nim js --path:. --path:../isonim/src --path:../nim-everywhere/src --hints:off -o:${editorDir}/editor.js editor/main.nim`,
      { cwd: projectRoot, stdio: "pipe" },
    );
    execSync(`cp editor/index.html ${editorDir}/index.html`, { cwd: projectRoot });
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
      const p = join(screenshotDir, `${viewName}-${sizeName}.png`);
      await page.screenshot({ path: p });
      console.log(`    ${viewName}-${sizeName} (${vp.width}x${vp.height}): ${p}`);
      count++;
      await context.close();
    }
  }

  await browser.close();
  try {
    process.kill(-server.pid);
  } catch {
    /* ignore */
  }
  console.log(`==> Done. ${count} screenshot(s) written.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
