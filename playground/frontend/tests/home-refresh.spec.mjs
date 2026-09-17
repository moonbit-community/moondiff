import { expect, test } from '@playwright/test';
import { pull, commits, success, failure, gate, setup, reviews, authored, row, selectTab } from './home-fixture.mjs';

test('multi-page refresh retains the old lists and expanded commits until each replacement is ready', async ({ page }) => {
  let refreshing = false, commitAttempts = 0;
  const pullsGate = gate(), commitsGate = gate();
  await page.clock.setFixedTime(new Date('2026-09-18T12:00:00Z'));
  const state = await setup(page, async ({ route, kind, args }) => {
    if (kind === 'ViewerPullsGet') {
      let items, next_cursor, total_count = 100;
      if (args.kind.$tag === 'Authored') { items = [pull(refreshing ? 501 : 500)]; total_count = 1; }
      else if (!refreshing) {
        items = Array.from({ length: args.cursor ? 26 : 50 }, (_, i) => pull(i + (args.cursor ? 51 : 1)));
        next_cursor = args.cursor ? 'old-more' : 'old-page2';
      } else if (!args.cursor) {
        items = Array.from({ length: 50 }, (_, i) => pull(100 + i, { updated_at: '2026-09-18T12:00:00Z' })); next_cursor = 'new-page2';
      } else if (args.cursor === 'new-page2') {
        await pullsGate.promise;
        items = [pull(1), ...Array.from({ length: 25 }, (_, i) => pull(150 + i))]; next_cursor = 'new-more';
      } else { expect(args.cursor).toBe('new-more'); items = [pull(999)]; }
      await route.fulfill({ json: success('ViewerPulls', { items, total_count, ...(next_cursor ? { next_cursor } : {}) }) }); return true;
    }
    if (kind !== 'PullCommitsGet') return false;
    if (refreshing && args.cursor) {
      expect(args.cursor).toBe('new-commits2'); commitAttempts++;
      if (commitAttempts === 1) { await commitsGate.promise; await route.fulfill(failure('github_timeout', 'GitHub did not respond in time.', 504)); return true; }
    }
    const start = (refreshing ? 101 : 1) + (args.cursor ? 2 : 0);
    await route.fulfill({ json: success('PullCommits', commits(start, 2, { total_count: 4, head_sha: (refreshing ? 'c' : 'b').repeat(40), ...(args.cursor ? {} : { next_cursor: refreshing ? 'new-commits2' : 'old-commits2' }) })) }); return true;
  });
  await page.goto('/'); await selectTab(page, 'ReviewRequested');
  const more = reviews(page).locator(':scope > .home-page-actions').getByRole('button', { name: 'Load more' });
  await more.click(); await expect(reviews(page).locator('.home-pull')).toHaveCount(76);
  const one = row(page, 'Pull request 1');
  await one.getByRole('button', { name: /Expand commits/ }).click();
  await one.getByRole('button', { name: 'Load more' }).click(); await expect(one.locator('.home-commit')).toHaveCount(4);
  const originalTime = await page.locator('.home-updated time').getAttribute('datetime');
  refreshing = true; await page.clock.setFixedTime(new Date('2026-09-18T12:05:00Z'));
  await page.getByRole('button', { name: 'Refresh lists' }).click();
  await expect.poll(() => state.calls.some(c => c.args.cursor === 'new-page2')).toBe(true);
  await expect.poll(() => commitAttempts).toBe(1);
  await expect(page.getByRole('button', { name: 'Refreshing…', exact: true })).toBeDisabled();
  await expect(reviews(page).locator('.home-pull')).toHaveCount(76);
  await expect(row(page, 'Pull request 2')).toBeVisible();
  await expect(one.locator('.home-commit')).toHaveCount(4);
  await expect(one.getByRole('link', { name: /Commit 1$/ })).toBeVisible();
  await expect(one.getByRole('status')).toHaveText('Refreshing…');
  await expect(page.locator('.home-updated time')).toHaveAttribute('datetime', originalTime);
  await selectTab(page, 'Authored'); await expect(row(page, 'Pull request 501')).toBeVisible();
  await expect(page.locator('.home-updated time')).toHaveAttribute('datetime', '2026-09-18T12:05:00.000Z');
  await selectTab(page, 'ReviewRequested');
  commitsGate.release();
  await expect(one.getByRole('alert')).toHaveText('Refresh failed. GitHub did not respond in time.');
  await expect(one.getByRole('link', { name: /Commit 1$/ })).toBeVisible();
  await one.getByRole('button', { name: 'Retry' }).click();
  await expect(one.getByRole('link', { name: /Commit 104$/ })).toBeVisible();
  await expect(one.getByRole('link', { name: /Commit 1$/ })).toHaveCount(0);
  pullsGate.release();
  await expect(page.getByRole('button', { name: 'Refresh lists' })).toBeEnabled();
  await expect(reviews(page).locator('.home-pull')).toHaveCount(76);
  await expect(reviews(page).locator('.home-title-link').first()).toHaveText('Pull request 100');
  await expect(row(page, 'Pull request 2')).toHaveCount(0);
  await expect(one.getByRole('button', { name: /Collapse commits/ })).toHaveAttribute('aria-expanded', 'true');
  await expect(one.locator('.home-commit')).toHaveCount(4);
  await expect(page.locator('.home-updated time')).toHaveAttribute('datetime', '2026-09-18T12:05:00.000Z');
  await page.clock.setFixedTime(new Date('2026-09-18T12:10:00Z'));
  await more.click(); await expect(row(page, 'Pull request 999')).toBeVisible();
  await expect(page.locator('.home-updated time')).toHaveAttribute('datetime', '2026-09-18T12:05:00.000Z');
  expect(state.calls.filter(c => c.kind === 'ViewerPullsGet' && c.args.kind.$tag === 'ReviewRequested').map(c => c.args.cursor)).toEqual([undefined, 'old-page2', undefined, 'new-page2', 'new-more']);
});

test('refresh failures and incomplete search retain the old list and resume staging on Retry', async ({ page }) => {
  let refreshing = false, retries = 0;
  const state = await setup(page, async ({ route, kind, args }) => {
    if (kind !== 'ViewerPullsGet' || args.kind.$tag !== 'ReviewRequested' || !refreshing) return false;
    if (!args.cursor) await route.fulfill({ json: success('ViewerPulls', { items: [pull(9)], total_count: 3, next_cursor: 'next' }) });
    else if (++retries === 1) await route.abort('failed');
    else if (retries === 2) await route.fulfill({ json: success('ViewerPulls', { items: [], total_count: 3, next_cursor: 'retry-window', incomplete: 'Search is incomplete. Retry to continue.' }) });
    else { expect(args.cursor).toBe('retry-window'); await route.fulfill({ json: success('ViewerPulls', { items: [pull(10)], total_count: 2 }) }); }
    return true;
  });
  await page.goto('/'); await selectTab(page, 'ReviewRequested'); await expect(page.getByRole('button', { name: 'Refresh lists' })).toBeEnabled();
  refreshing = true; await page.getByRole('button', { name: 'Refresh lists' }).click();
  await expect(reviews(page).getByRole('alert')).toContainText('Refresh failed.');
  await expect(row(page, 'Pull request 1')).toBeVisible();
  await reviews(page).getByRole('button', { name: 'Retry' }).click();
  await expect(reviews(page).getByRole('alert')).toContainText('incomplete');
  await expect(row(page, 'Pull request 1')).toBeVisible();
  await expect(reviews(page).getByRole('button', { name: 'Load more' })).toHaveCount(0);
  await reviews(page).getByRole('button', { name: 'Retry' }).click();
  await expect(row(page, 'Pull request 10')).toBeVisible();
  await expect(row(page, 'Pull request 1')).toHaveCount(0);
  expect(state.calls.filter(c => c.kind === 'ViewerPullsGet' && c.args.kind.$tag === 'ReviewRequested').map(c => c.args.cursor)).toEqual([undefined, undefined, 'next', 'next', 'retry-window']);
});

for (const target of ['ReviewRequested', 'Commits']) test(`${target} refresh cursor recovery preserves old content and retries a failed restart`, async ({ page }) => {
  let refreshing = false, starts = 0;
  const state = await setup(page, async ({ route, kind, args }) => {
    const matches = target === 'Commits' ? kind === 'PullCommitsGet' : kind === 'ViewerPullsGet' && args.kind.$tag === target;
    if (!matches) return false;
    if (!refreshing) {
      if (target !== 'Commits') return false;
      await route.fulfill({ json: success('PullCommits', commits(1, 2)) }); return true;
    }
    if (args.cursor || ++starts === 2) await route.fulfill(failure('invalid_cursor', 'Cursor expired. Retry this list.', 400));
    else if (target === 'Commits') await route.fulfill({ json: success('PullCommits', commits(starts === 1 ? 10 : 20, 1, starts === 1 ? { next_cursor: 'expired' } : {})) });
    else await route.fulfill({ json: success('ViewerPulls', { items: [pull(starts === 1 ? 10 : 20)], total_count: 1, ...(starts === 1 ? { next_cursor: 'expired' } : {}) }) });
    return true;
  });
  await page.goto('/'); await selectTab(page, 'ReviewRequested'); await expect(page.getByRole('button', { name: 'Refresh lists' })).toBeEnabled();
  if (target === 'Commits') {
    await row(page, 'Pull request 1').getByRole('button', { name: /Expand commits/ }).click();
    await expect(row(page, 'Pull request 1').locator('.home-commit')).toHaveCount(2);
  }
  refreshing = true; await page.getByRole('button', { name: 'Refresh lists' }).click();
  const affected = target === 'Commits' ? row(page, 'Pull request 1') : reviews(page);
  await expect(affected.getByRole('alert')).toHaveText('Refresh failed. Cursor expired. Retry this list.');
  await expect(affected.getByRole('link', { name: target === 'Commits' ? /Commit 1$/ : 'Pull request 1', exact: target !== 'Commits' })).toBeVisible();
  expect(starts).toBe(2);
  await affected.getByRole('button', { name: 'Retry' }).click();
  await expect(affected.getByRole('link', { name: target === 'Commits' ? /Commit 20$/ : 'Pull request 20', exact: target !== 'Commits' })).toBeVisible();
  expect(state.calls.filter(c => target === 'Commits' ? c.kind === 'PullCommitsGet' : c.kind === 'ViewerPullsGet' && c.args.kind.$tag === target).map(c => c.args.cursor)).toEqual([undefined, undefined, 'expired', undefined, undefined]);
});

test('page restoration resumes a refresh from its staged cursor and discards the interrupted response', async ({ page }) => {
  let refreshing = false, seconds = 0;
  const pending = gate();
  const state = await setup(page, async ({ route, kind, args }) => {
    if (kind !== 'ViewerPullsGet' || args.kind.$tag !== 'ReviewRequested' || !refreshing) return false;
    if (!args.cursor) await route.fulfill({ json: success('ViewerPulls', { items: [pull(8)], total_count: 2, next_cursor: 'second' }) });
    else {
      const interrupted = ++seconds === 1;
      if (interrupted) await pending.promise;
      await route.fulfill({ json: success('ViewerPulls', { items: [pull(interrupted ? 99 : 9)], total_count: 2 }) }).catch(() => {});
    }
    return true;
  });
  await page.goto('/'); await selectTab(page, 'ReviewRequested'); await expect(page.getByRole('button', { name: 'Refresh lists' })).toBeEnabled();
  refreshing = true; await page.getByRole('button', { name: 'Refresh lists' }).click();
  await expect.poll(() => seconds).toBe(1);
  await expect(row(page, 'Pull request 1')).toBeVisible();
  await page.evaluate(() => { dispatchEvent(new PageTransitionEvent('pagehide', { persisted: true })); dispatchEvent(new PageTransitionEvent('pageshow', { persisted: true })); dispatchEvent(new Event('focus')); });
  await expect(row(page, 'Pull request 9')).toBeVisible();
  pending.release(); await expect(row(page, 'Pull request 99')).toHaveCount(0);
  expect(state.calls.filter(c => c.kind === 'ViewerPullsGet' && c.args.kind.$tag === 'ReviewRequested').map(c => c.args.cursor)).toEqual([undefined, undefined, 'second', 'second']);
});

test('session expiry during refresh clears visible and staged private data before a late response', async ({ page }) => {
  let refreshing = false; const pending = gate();
  await setup(page, async ({ route, kind, args }) => {
    if (kind !== 'ViewerPullsGet' || !refreshing) return false;
    if (args.kind.$tag === 'ReviewRequested') await route.fulfill(failure('authentication_required', 'Sign in again.', 401));
    else { await pending.promise; await route.fulfill({ json: success('ViewerPulls', { items: [pull(99)], total_count: 1 }) }).catch(() => {}); }
    return true;
  });
  await page.goto('/'); await selectTab(page, 'ReviewRequested'); await expect(page.getByRole('button', { name: 'Refresh lists' })).toBeEnabled();
  refreshing = true; await page.getByRole('button', { name: 'Refresh lists' }).click();
  await expect(page.locator('.pr-dashboard')).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Try sign-in' })).toBeVisible();
  pending.release(); await expect(page.getByText('Pull request 99')).toHaveCount(0);
});
