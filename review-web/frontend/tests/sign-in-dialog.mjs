import { expect } from '@playwright/test';

export const signInDialog = page => page.locator('#sign-in-dialog');
export const pagePosition = page => page.evaluate(() => ({ x: scrollX, y: scrollY, url: location.href }));
export const expectPagePosition = (page, before) => expect.poll(() => pagePosition(page)).toEqual(before);

export async function expectSignInDialog(page, title, pending = false) {
  const dialog = signInDialog(page);
  await expect(dialog).toBeVisible();
  await expect(dialog).toHaveAccessibleName(title);
  await expect(pending ? dialog.locator('#sign-in-dialog-status') :
    dialog.locator('.review-sign-in-button')).toBeFocused();
  await expect(dialog).toBeInViewport();
  const { x, y, width, height } = await dialog.boundingBox();
  const viewport = page.viewportSize();
  expect(x).toBeGreaterThanOrEqual(15);
  expect(y).toBeGreaterThanOrEqual(15);
  expect(width).toBeLessThanOrEqual(448);
  expect(Math.abs(x + width / 2 - viewport.width / 2)).toBeLessThanOrEqual(10);
  expect(Math.abs(y + height / 2 - viewport.height / 2)).toBeLessThanOrEqual(1);
}

export async function closeSignInDialog(page, method = 'button') {
  if (method === 'escape') await page.keyboard.press('Escape');
  else if (method === 'backdrop') await page.mouse.click(5, 5);
  else await signInDialog(page).getByRole('button', { name: 'Close sign-in dialog' }).click();
  await expect(signInDialog(page)).toBeHidden();
}
