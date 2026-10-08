import { expect, test } from '@playwright/test';

test('repeat visits reuse content-hashed JS and CSS from the browser cache', async ({ page }) => {
  // Request routing disables the browser HTTP cache, so use the local server's
  // anonymous API response without installing any Playwright routes.
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  const assets = () => page.evaluate(() => performance.getEntriesByType('resource')
    .filter(entry => /\/(?:index|styles)\.[0-9a-f]{64}\.(?:js|css)$/.test(new URL(entry.name).pathname))
    .map(entry => ({ url: entry.name, transferred: entry.transferSize, size: entry.encodedBodySize }))
    .sort((a, b) => a.url.localeCompare(b.url)));

  await page.goto('/');
  await expect(page.locator('#commit-url')).toBeVisible();
  const first = await assets();
  expect(first).toHaveLength(2);
  for (const asset of first) {
    expect(asset.transferred).toBeGreaterThan(0);
    expect(asset.size).toBeGreaterThan(0);
  }

  await page.goto('about:blank');
  await page.goto('/');
  await expect(page.locator('#commit-url')).toBeVisible();
  expect(await assets()).toEqual(first.map(asset => ({ ...asset, transferred: 0 })));
  expect(errors).toEqual([]);
});
