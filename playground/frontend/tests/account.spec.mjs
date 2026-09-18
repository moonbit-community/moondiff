import { expect, test } from '@playwright/test';
import { setup, gate, failure, row, signOut, selectTab } from './home-fixture.mjs';

const routes = ['/upstream/repo/pull/1', `/fork/repo/commit/${'b'.repeat(40)}`];
const account = page => page.getByRole('button', { name: /^Account:/ });

async function reactivate(page) {
  await page.bringToFront();
  // Headless tabs can all report focus, so explicitly model leaving and returning.
  await page.evaluate(() => {
    Object.defineProperty(document, 'hidden', { configurable: true, value: false });
    document.hasFocus = () => false;
    dispatchEvent(new Event('blur'));
    document.hasFocus = () => true;
    dispatchEvent(new Event('focus'));
    delete document.hasFocus;
    delete document.hidden;
  });
}

for (const path of routes) {
  test(`account stays at the right of the toolbar with long names in both themes on ${path}`, async ({ page }) => {
    const state = await setup(page);
    state.user = 'long-username'.repeat(8);
    state.installUrl = 'https://github.com/apps/moondiff/installations/new';
    await page.goto(path);
    await expect(page.locator('.comments-toolbar')).toBeVisible();
    const toolbar = page.locator('.hero-workspace');
    for (const colorScheme of ['light', 'dark']) {
      await page.emulateMedia({ colorScheme });
      for (const width of [320, 375, 680, 681, 980, 981, 1280]) {
        await page.setViewportSize({ width, height: 900 });
        await expect(account(page)).toHaveAttribute('title', state.user);
        const geometry = await toolbar.evaluate(el => {
          const trigger = el.querySelector('.account-button').getBoundingClientRect();
          const brand = el.querySelector('.brand').getBoundingClientRect();
          const url = el.querySelector('.workspace-url').getBoundingClientRect();
          const header = el.getBoundingClientRect();
          return {
            overflow: document.documentElement.scrollWidth > innerWidth || el.scrollWidth > el.clientWidth,
            rightGap: header.right - trigger.right,
            sameRow: trigger.top < brand.bottom && brand.top < trigger.bottom,
            followsUrl: trigger.left >= url.right,
          };
        });
        expect(geometry, `${colorScheme} ${width}px`).toMatchObject({ overflow: false, sameRow: true, followsUrl: true });
        expect(geometry.rightGap).toBeLessThanOrEqual(12);
        await account(page).click();
        const menu = page.getByRole('menu', { name: 'Account', exact: true });
        await expect(menu).toBeVisible();
        const bounds = await menu.boundingBox();
        expect(bounds.x).toBeGreaterThanOrEqual(0);
        expect(bounds.x + bounds.width).toBeLessThanOrEqual(width);
        await page.keyboard.press('Escape');
        await expect(account(page)).toBeFocused();
      }
    }
  });

  test(`account remains available during loading, failure and retry on ${path}`, async ({ page }) => {
    const pending = gate(); let fail = true;
    await setup(page, async ({ route, kind }) => {
      if (!fail || !['PullGet', 'CommitGet'].includes(kind)) return false;
      await pending.promise;
      await route.fulfill(failure('unavailable', 'Repository temporarily unavailable.', 503));
      return true;
    });
    await page.goto(path);
    await expect(page.locator('.loading')).toBeVisible();
    await expect(account(page)).toBeVisible();
    pending.release();
    await expect(page.locator('.empty-state.error')).toBeVisible();
    await expect(account(page)).toHaveCount(1);
    await account(page).click();
    await expect(page.getByRole('menuitem', { name: 'Sign out' })).toBeVisible();
    await expect(page.getByRole('menuitem', { name: 'Install Moondiff Github App ↗' })).toHaveCount(0);
    await page.keyboard.press('Escape');
    fail = false;
    await page.getByRole('button', { name: 'Try again', exact: true }).click();
    await expect(page.locator('.comments-toolbar')).toBeVisible();
    await expect(account(page)).toBeVisible();
  });
}

test('homepage, PR and commit tabs share account changes and sign-out', async ({ page }) => {
  const state = await setup(page);
  await page.goto('/');
  await selectTab(page, 'ReviewRequested');
  const one = row(page, 'Pull request 1');
  const prReady = page.waitForEvent('popup');
  await one.getByRole('link', { name: 'Pull request 1', exact: true }).click();
  const pr = await prReady;
  await one.getByRole('button', { name: /Expand commits/ }).click();
  const commitReady = page.waitForEvent('popup');
  await one.getByRole('link', { name: /Commit 1/ }).click();
  const commit = await commitReady;
  const pages = [page, pr, commit];
  for (const current of pages) await expect(account(current)).toHaveAccessibleName('Account: alice');
  state.user = 'bob';
  for (const current of pages) {
    await reactivate(current);
    await expect(account(current)).toHaveAccessibleName('Account: bob');
  }
  await signOut(commit);
  for (const current of pages) {
    await reactivate(current);
    await expect(account(current)).toHaveCount(0);
    await expect(current.getByRole('button', { name: 'Sign in with GitHub' })).toBeVisible();
  }
  await expect(page.locator('.pr-dashboard')).toHaveCount(0);
  await pr.close(); await commit.close();
});
