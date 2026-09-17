import { expect, test } from '@playwright/test';
import { pull, commits, success, failure, gate, setup, reviews, authored, row, selectTab, noLanding } from './home-fixture.mjs';

test('tabs support keyboard selection, cache both groups and retain the selected tab when opening a PR in a new tab', async ({ page }) => {
  const state = await setup(page);
  await page.goto('/');
  const reviewTab = page.getByRole('tab', { name: 'Review requests 2', exact: true });
  const authoredTab = page.getByRole('tab', { name: 'Pull requests authored by me 1', exact: true });
  await expect(authoredTab).toHaveAttribute('aria-selected', 'true');
  await expect(reviewTab).toHaveAttribute('tabindex', '-1');
  await expect(page.getByRole('tabpanel')).toHaveCount(1);
  await expect(authored(page).locator('.home-count')).toHaveText('Showing 1 of 1 pull requests');
  await selectTab(page, 'ReviewRequested');
  await expect(reviews(page).locator('.home-count')).toHaveText('Showing 2 of 2 pull requests');
  const one = row(page, 'Pull request 1');
  await expect(one.getByRole('button', { name: /Expand commits/ })).toHaveText('▸Commits');
  await one.getByRole('button', { name: /Expand commits/ }).click();
  await expect(one.getByRole('button', { name: /Collapse commits/ })).toContainText('Commits (1)');
  await reviewTab.focus();
  for (const [key, selected] of [['ArrowRight', authoredTab], ['ArrowRight', reviewTab], ['Home', authoredTab], ['End', reviewTab], ['ArrowLeft', authoredTab]]) {
    await page.keyboard.press(key);
    await expect(selected).toBeFocused();
    await expect(selected).toHaveAttribute('aria-selected', 'true');
  }
  const popupReady = page.waitForEvent('popup');
  await row(page, 'Pull request 3').getByRole('link', { name: 'Pull request 3', exact: true }).press('Enter');
  const popup = await popupReady;
  await expect(popup).toHaveURL(/\/upstream\/repo\/pull\/3$/);
  await expect(popup.getByText('Loaded PR', { exact: true })).toBeVisible();
  await popup.close();
  await expect(page).toHaveURL(/\/$/);
  await expect(authoredTab).toHaveAttribute('aria-selected', 'true');
  await selectTab(page, 'ReviewRequested');
  await expect(one.getByRole('link', { name: /Commit 1/ })).toBeVisible();
  expect(state.calls.filter(c => c.kind === 'ViewerPullsGet')).toHaveLength(2);
  expect(state.calls.filter(c => c.kind === 'PullCommitsGet')).toHaveLength(1);
  await page.reload();
  await expect(authoredTab).toHaveAttribute('aria-selected', 'true');
  await noLanding(page);
});

for (const path of ['/']) test(`account popover supports authorization, keyboard and focus return on ${path}`, async ({ page }) => {
  const state = await setup(page); state.installUrl = 'https://github.com/apps/moondiff/installations/new';
  await page.goto(path);
  const trigger = page.getByRole('button', { name: 'Account: alice' });
  const menu = page.getByRole('menu', { name: 'Account', exact: true });
  await expect(trigger).toHaveCount(1);
  if (path !== '/') {
    await expect(page.locator('.hero-workspace').getByRole('button', { name: 'Account: alice' })).toBeVisible();
    await expect(page.locator('.comments-toolbar').getByRole('button', { name: 'Refresh', exact: true })).toBeVisible();
    await expect(page.locator('.comments-toolbar .account-control')).toHaveCount(0);
  }
  await expect(menu).toBeHidden();
  await trigger.focus(); await page.keyboard.press('ArrowDown');
  await expect(trigger).toHaveAttribute('aria-expanded', 'true');
  await expect(menu.getByText('Signed in as alice')).toBeVisible();
  const authorize = menu.getByRole('menuitem', { name: 'Install Moondiff Github App ↗' });
  await expect(authorize).toHaveAttribute('href', state.installUrl);
  await expect(authorize).toBeFocused();
  await expect(menu.getByText('Choose which repositories this app can access on GitHub.')).toBeVisible();
  await page.keyboard.press('End'); await expect(menu.getByRole('menuitem', { name: 'Sign out' })).toBeFocused();
  await page.keyboard.press('Home'); await expect(authorize).toBeFocused();
  await page.keyboard.press('Escape'); await expect(menu).toBeHidden(); await expect(trigger).toBeFocused();
  await trigger.click(); await page.locator('.home-identity, .hero-workspace .brand').click();
  await expect(menu).toBeHidden(); await expect(trigger).toHaveAttribute('aria-expanded', 'false');
  await trigger.focus(); await page.keyboard.press('ArrowUp');
  await expect(menu.getByRole('menuitem', { name: 'Sign out' })).toBeFocused();
  await page.keyboard.press('Tab'); await expect(menu).toBeHidden();
});

for (const configured of [false, true]) test(`empty PR lists show no extra actions${configured ? ' with an installation URL' : ' without an installation URL'}`, async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 900 });
  const state = await setup(page, async ({ route, kind }) => {
    if (kind !== 'ViewerPullsGet') return false;
    await route.fulfill({ json: success('ViewerPulls', { items: [], total_count: 0 }) }); return true;
  });
  if (configured) state.installUrl = 'https://github.com/apps/moondiff/installations/new';
  await page.goto('/');
  await selectTab(page, 'ReviewRequested');
  await expect(reviews(page).getByText('Open pull requests that request your review appear here.')).toBeVisible();
  await expect(page.getByRole('tab', { name: 'Review requests 0', exact: true })).toBeVisible();
  await expect(reviews(page).locator('.home-count')).toHaveText('Showing 0 of 0 pull requests');
  await expect(reviews(page).getByRole('button')).toHaveCount(0);
  await expect(reviews(page).getByRole('link')).toHaveCount(0);
  await expect(reviews(page).getByText('Choose which repositories this app can access on GitHub.')).toHaveCount(0);
  await selectTab(page, 'Authored');
  await expect(page.getByRole('tab', { name: 'Pull requests authored by me 0', exact: true })).toBeFocused();
  await expect(authored(page)).toContainText('Closed and merged pull requests are not included.');
  await expect(authored(page).getByText('You have no open pull requests.', { exact: true })).toBeVisible();
  await expect(authored(page).locator('.home-count')).toHaveText('Showing 0 of 0 pull requests');
  await expect(authored(page).getByRole('button')).toHaveCount(0);
  await expect(authored(page).getByRole('link')).toHaveCount(0);
  await expect(authored(page).getByText('Choose which repositories this app can access on GitHub.')).toHaveCount(0);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await selectTab(page, 'ReviewRequested');
  await expect(reviews(page)).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  expect(state.calls.filter(c => c.kind === 'ViewerPullsGet')).toHaveLength(2);
  await page.getByRole('button', { name: /^Account:/ }).click();
  await expect(page.getByRole('menuitem', { name: 'Install Moondiff Github App ↗' })).toHaveCount(configured ? 1 : 0);
});

test('initial pending and failed lists never report zero and successful lists have independent local times', async ({ page }) => {
  const pending = gate(); let fail = true;
  await page.clock.setFixedTime(new Date('2026-09-18T12:00:00Z'));
  await setup(page, async ({ route, kind, args }) => {
    if (kind !== 'ViewerPullsGet' || args.kind.$tag !== 'Authored') return false;
    await pending.promise;
    if (fail) await route.fulfill(failure('rate_limit', 'Sign in to increase your rate limit.', 429));
    else await route.fulfill({ json: success('ViewerPulls', { items: [], total_count: 0 }) });
    return true;
  });
  await page.goto('/');
  await expect(page.getByRole('tab', { name: /Pull requests authored by me Loading count/ })).toHaveText('Pull requests authored by me…');
  await expect(page.getByRole('button', { name: 'Loading…', exact: true })).toBeDisabled();
  await selectTab(page, 'ReviewRequested');
  const firstTime = await page.locator('.home-updated time').getAttribute('datetime');
  expect(firstTime).toBe('2026-09-18T12:00:00.000Z');
  await selectTab(page, 'Authored');
  await expect(page.locator('.home-updated time')).toHaveCount(0);
  pending.release();
  await expect(authored(page).getByRole('alert')).toHaveText('GitHub is temporarily limiting requests. Please try again later.');
  await expect(page.getByRole('tab', { name: /Pull requests authored by me Count unavailable/ })).toHaveText('Pull requests authored by me—');
  await expect(authored(page).locator('.home-count')).toHaveCount(0);
  fail = false; await page.clock.setFixedTime(new Date('2026-09-18T12:05:00Z'));
  await authored(page).getByRole('button', { name: 'Retry' }).click();
  await expect(page.locator('.home-updated time')).toHaveAttribute('datetime', '2026-09-18T12:05:00.000Z');
  await selectTab(page, 'ReviewRequested');
  await expect(page.locator('.home-updated time')).toHaveAttribute('datetime', firstTime);
});

test('the tab bar stays available while scrolling long lists', async ({ page }) => {
  await setup(page, async ({ route, kind }) => {
    if (kind !== 'ViewerPullsGet') return false;
    await route.fulfill({ json: success('ViewerPulls', { items: Array.from({ length: 50 }, (_, i) => pull(i + 1)), total_count: 76, next_cursor: 'next' }) }); return true;
  });
  await page.goto('/');
  await selectTab(page, 'ReviewRequested');
  await expect(reviews(page).locator('.home-count')).toHaveText('Showing 50 of 76 pull requests');
  await page.evaluate(() => scrollTo(0, 2000));
  await expect.poll(() => page.getByRole('tablist').evaluate(el => Math.round(el.getBoundingClientRect().top))).toBe(0);
  await selectTab(page, 'Authored');
  await expect(page.getByRole('tab', { name: 'Pull requests authored by me 76', exact: true })).toHaveAttribute('aria-selected', 'true');
  await expect(page.getByRole('tablist')).toBeInViewport();
});

for (const width of [1280, 375, 320]) for (const colorScheme of ['light', 'dark']) test(`${width}px ${colorScheme} dashboard fits long titles, accounts and large counts`, async ({ page }) => {
  await page.setViewportSize({ width, height: 900 }); await page.emulateMedia({ colorScheme });
  const state = await setup(page, async ({ route, kind }) => {
    if (kind === 'ViewerPullsGet') await route.fulfill({ json: success('ViewerPulls', { items: [pull(1, { title: 'Title'.repeat(32), repo: 'repository'.repeat(10), author: 'author'.repeat(10), draft: true })], total_count: 2147483647 }) });
    else if (kind === 'PullCommitsGet') await route.fulfill({ json: success('PullCommits', commits(1, 1, { total_count: 2147483647 })) });
    else return false;
    return true;
  });
  state.user = 'long-username'.repeat(8); state.installUrl = 'https://github.com/apps/moondiff/installations/new';
  await page.goto('/');
  await selectTab(page, 'ReviewRequested');
  await reviews(page).getByRole('button', { name: /Expand commits/ }).click();
  await expect(reviews(page).getByRole('link', { name: /Commit 1/ })).toBeVisible();
  const title = reviews(page).locator('.home-title-link');
  await reviews(page).getByRole('button', { name: /Collapse commits/ }).focus();
  await page.keyboard.press('Shift+Tab');
  await expect(title).toBeFocused();
  await expect(title).toHaveCSS('text-decoration-line', 'underline');
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  expect(await page.locator('.home-header, .home-tabs, .home-toolbar, #home-panel-review, .home-expand:visible').evaluateAll(elements => elements.every(el => { const r = el.getBoundingClientRect(); return r.left >= 0 && r.right <= innerWidth; }))).toBe(true);
  const [info, expand] = await Promise.all([reviews(page).locator('.home-pull-info').boundingBox(), reviews(page).locator('.home-expand').boundingBox()]);
  if (width < 600) expect(expand.y).toBeGreaterThanOrEqual(info.y + info.height);
  else expect(expand.x).toBeGreaterThan(info.x + info.width);
  await page.getByRole('button', { name: /^Account:/ }).click();
  const menu = page.getByRole('menu', { name: 'Account', exact: true }); await expect(menu).toBeVisible();
  const box = await menu.boundingBox(); expect(box.x).toBeGreaterThanOrEqual(0); expect(box.x + box.width).toBeLessThanOrEqual(width);
  await page.keyboard.press('Escape');
  await page.screenshot({ path: `/tmp/moondiff-home-${width}-${colorScheme}.png`, fullPage: true });
});
