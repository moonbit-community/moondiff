import { expect } from '@playwright/test';

export async function ensureFileExpanded(file) {
  const table = file.locator('table.review-diff').first();
  const expand = file.getByRole('button', { name: /^Expand / }).first();
  await expect.poll(async () => await table.isVisible() || await expand.isVisible()).toBe(true);
  if (!await table.isVisible()) await expand.click();
  await expect(table).toBeVisible();
}
