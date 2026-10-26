import { expect } from "../../tests/browser-test.mjs";

export async function clickLineCommentButton(button, { afterHover } = {}) {
  const retry = { timeout: 5_000, intervals: [100, 250, 500] };
  const hover = async () => {
    await button.scrollIntoViewIfNeeded({ timeout: 1_000 });
    await button.locator("xpath=..").hover({ timeout: 1_000 });
  };
  let needsHover = true;
  if (afterHover) {
    await expect(hover).toPass(retry);
    // Run once, outside click retries, so callback failures propagate directly.
    await afterHover();
    needsHover = false;
  }
  await expect(async () => {
    if (needsHover) await hover();
    needsHover = true;
    await button.click({ timeout: 1_000 });
  }).toPass(retry);
}
