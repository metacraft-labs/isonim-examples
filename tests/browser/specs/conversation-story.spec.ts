// The conversation app's stories in the examples editor: each is the
// ViewModel over the stand-in services, mounted live in the page preview,
// so every control works there as in the product.
import { expect, type FrameLocator, type Page, test } from "@playwright/test";

const group = "Conversation App / Pages";

async function openStory(page: Page, story: string): Promise<FrameLocator> {
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto("/");
  await expect(page.locator(".editor-sidebar")).toBeVisible();
  const section = page.locator('[aria-label="Toggle Pages section"]').first();
  if ((await section.getAttribute("aria-expanded")) !== "true") {
    await section.click();
  }
  const toggle = page.locator(`[aria-label="Toggle ${group} stories"]`).first();
  if ((await toggle.getAttribute("aria-expanded")) !== "true") {
    await toggle.click();
  }
  await page
    .locator(`[aria-label="Select story ${group} / ${story}"]`)
    .first()
    .click();
  const frame = page.frameLocator('iframe[data-page-project-frame="true"]');
  await expect(frame.locator('[data-testid="conversation-app"]')).toHaveAttribute(
    "data-editor-state",
    story,
  );
  return frame;
}

test("typical: the list and transcript; a prompt streams a reply", async ({
  page,
}) => {
  const app = await openStory(page, "Typical (4G)");
  await expect(app.locator('[data-testid="conversation-app"]')).toHaveAttribute(
    "data-network-profile",
    "4g",
  );
  await expect(app.locator('[data-testid="conversation-row"]')).toHaveCount(12);
  await expect(app.locator('[data-testid="message"]')).toHaveCount(6);

  await app.locator('[data-testid="draft"]').fill("What should I pack?");
  await app.locator('[data-testid="send"]').click();
  // The reply grows on screen before it is complete.
  const partial = app.locator('[data-testid="reply-text"]');
  await expect(partial).toBeVisible();
  const early = (await partial.textContent()) ?? "";
  await expect
    .poll(async () => ((await partial.textContent()) ?? "").length, {
      timeout: 10_000,
    })
    .toBeGreaterThan(early.length);
  // Then it joins the transcript, after the prompt.
  await expect(app.locator('[data-testid="message"]')).toHaveCount(8, {
    timeout: 20_000,
  });
  await expect(app.locator('[data-testid="message"]').nth(6)).toHaveText(
    "What should I pack?",
  );
  await expect(app.locator('[data-testid="message"]').nth(7)).toContainText(
    "Here is a short plan.",
  );
  await expect(app.locator('[data-testid="streaming-reply"]')).toBeHidden();

  // The stand-in kept the exchange: reopening the conversation reads it back.
  await app.locator('[data-testid="conversation-row"]').nth(1).click();
  await expect(app.locator('[data-testid="message"]')).toHaveCount(6);
  await app.locator('[data-testid="conversation-row"]').nth(0).click();
  await expect(app.locator('[data-testid="message"]')).toHaveCount(8);
});

test("large: the list is backfilled after the first screen", async ({ page }) => {
  const app = await openStory(page, "Large (4G)");
  await expect(app.locator('[data-testid="backfill-status"]')).toContainText(
    "more conversation",
  );
  await expect(app.locator('[data-testid="conversation-row"]')).toHaveCount(500, {
    timeout: 30_000,
  });
  await expect(app.locator('[data-testid="backfill-status"]')).toBeHidden();
});

test("error: the first screen fails and Retry tries again", async ({ page }) => {
  const app = await openStory(page, "Error (4G)");
  await expect(app.locator('[data-testid="load-error"]')).toContainText(
    "unavailable",
  );
  await app.locator('[data-testid="retry"]').click();
  // The stand-in still fails, so the retried load ends in the error again.
  await expect(app.locator('[data-testid="load-error"]')).toBeVisible();
});

test("empty: New conversation starts one", async ({ page }) => {
  const app = await openStory(page, "Empty (4G)");
  await expect(app.locator('[data-testid="conversation-list-empty"]')).toBeVisible();
  await app.locator('[data-testid="new-conversation"]').click();
  await expect(app.locator('[data-testid="conversation-row"]')).toHaveCount(1);
  await expect(app.locator('[data-testid="transcript-empty"]')).toHaveCount(0);
});

test("slow 3G: placeholders first, then the data", async ({ page }) => {
  const app = await openStory(page, "Typical (slow 3G)");
  // About two seconds of latency: the skeleton is what the user sees first.
  await expect(app.locator('[data-testid="conversation-skeleton"]')).toHaveCount(6);
  await expect(app.locator('[data-testid="message-skeleton"]')).toHaveCount(3);
  await page.screenshot({
    path: process.env.CONVERSATION_SCREENSHOT_DIR
      ? `${process.env.CONVERSATION_SCREENSHOT_DIR}/slow-3g-placeholders.png`
      : undefined,
  });
  await expect(app.locator('[data-testid="conversation-row"]')).toHaveCount(12, {
    timeout: 15_000,
  });
  await expect(app.locator('[data-testid="conversation-skeleton"]')).toHaveCount(0);
  await page.screenshot({
    path: process.env.CONVERSATION_SCREENSHOT_DIR
      ? `${process.env.CONVERSATION_SCREENSHOT_DIR}/slow-3g-loaded.png`
      : undefined,
  });
});
