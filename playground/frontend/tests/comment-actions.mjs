import { expect } from "@playwright/test";

export async function clickLineCommentButton(button) {
  await expect(async () => {
    await button.scrollIntoViewIfNeeded({ timeout: 1_000 });
    await button.locator("xpath=..").hover({ timeout: 1_000 });
    await button.click({ timeout: 1_000 });
  }).toPass({ timeout: 5_000, intervals: [100, 250, 500] });
}
