import { expect, test } from '@playwright/test';
import { head, pull, commits, success, failure, gate, setup, reviews, authored, row, noLanding, selectTab, signOut } from './home-fixture.mjs';

// A gate makes the session check visible and catches even a single frame of the old homepage.
test('signed-in root replaces the entire landing DOM before and after refresh and reload', async ({ page }) => {
  const state = await setup(page); state.statusGate = gate();
  await page.goto('/');
  await expect(page.getByRole('status')).toHaveText('Checking GitHub session…');
  await noLanding(page); expect(state.calls).toHaveLength(0);
  state.statusGate.release(); state.statusGate = null;
  await expect(authored(page).getByText('Draft', { exact: true })).toBeVisible();
  await selectTab(page, 'ReviewRequested');
  await expect(reviews(page).getByRole('link')).toHaveCount(2);
  await noLanding(page); expect(await page.evaluate(() => window.oldLandingSeen)).toBe(false);
  await page.getByRole('button', { name: 'Refresh lists', exact: true }).click();
  await expect.poll(() => state.calls.filter(c => c.kind === 'ViewerPullsGet').length).toBe(4);
  await page.reload(); await expect(page.getByRole('button', { name: 'Account: alice' })).toBeVisible();
  await noLanding(page); expect(await page.evaluate(() => window.oldLandingSeen)).toBe(false);
});

test('signed-in invalid routes keep the input visible while typing a valid GitHub URL', async ({ page }) => {
  const state = await setup(page);
  await page.goto('/#/invalid');
  await expect(page.getByRole('button', { name: 'Account: alice', exact: true }).first()).toBeVisible();
  const input = page.locator('#commit-url');
  await expect(input).toBeVisible();
  await expect(page.locator('.empty-state.error')).toBeVisible();
  let entered = '';
  for (const character of 'https://github.com/upstream/repo/pull/1') {
    await input.pressSequentially(character); entered += character;
    await expect(input).toBeVisible();
    await expect(input).toHaveValue(entered);
    await expect(page.locator('.empty-state.error')).toBeVisible();
  }
  expect(state.calls).toHaveLength(0);
  await page.getByRole('button', { name: 'View diff' }).click();
  await expect(page).toHaveURL(/\/upstream\/repo\/pull\/1$/);
  await expect(page.getByText('Loaded PR', { exact: true })).toBeVisible();
});

test('commit expansion is lazy and cached while PR and fork commit links open in new tabs', async ({ page }) => {
  const state = await setup(page);
  await page.goto('/');
  await selectTab(page, 'ReviewRequested');
  const one = row(page, 'Pull request 1'), two = row(page, 'Pull request 2');
  await expect(one).toBeVisible();
  expect(state.calls.filter(c => c.kind === 'PullCommitsGet')).toHaveLength(0);
  await one.getByRole('button', { name: /Expand commits/ }).focus(); await page.keyboard.press('Enter');
  await expect(one.getByRole('link', { name: /Commit 1/ })).toBeVisible();
  await expect(one.locator('.home-count')).toHaveCount(0);
  await two.getByRole('button', { name: /Expand commits/ }).click();
  await expect(two.getByRole('link', { name: /Commit 1/ })).toBeVisible();
  await one.getByRole('button', { name: /Collapse commits/ }).click();
  await one.getByRole('button', { name: /Expand commits/ }).click();
  expect(state.calls.filter(c => c.kind === 'PullCommitsGet')).toHaveLength(2);
  const link = one.getByRole('link', { name: /Commit 1/ });
  await expect(link).toHaveAttribute('href', `/upstream/repo/pull/1/commits/${'1'.padStart(40, '0')}`);
  await expect(link).toHaveAttribute('target', '_blank');
  await expect(link).toHaveAttribute('rel', 'noopener noreferrer');
  // Observe modifier handling, then prevent navigation in this test listener.
  // Exercise actual native new-tab navigation separately with a middle click.
  expect(await link.evaluate(el => ['ctrlKey', 'metaKey', 'shiftKey', 'altKey'].map(key => {
    let prevented;
    el.addEventListener('click', event => { prevented = event.defaultPrevented; event.preventDefault(); }, { once: true });
    el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, button: 0, [key]: true }));
    return prevented;
  }))).toEqual([false, false, false, false]);
  const popupReady = page.context().waitForEvent('page'); await link.click({ button: 'middle' });
  const popup = await popupReady; await expect(popup).toHaveURL(/\/pull\/1\/commits\//); await popup.close();
  const documentId = await page.evaluate(() => window.dashboardDocumentId);
  const homepageUrl = page.url();
  const prLink = one.getByRole('link', { name: 'Pull request 1', exact: true });
  await expect(prLink).toHaveAttribute('target', '_blank');
  await expect(prLink).toHaveAttribute('rel', 'noopener noreferrer');
  const prReady = page.waitForEvent('popup'); await prLink.click();
  const pr = await prReady;
  await expect(pr).toHaveURL(/\/upstream\/repo\/pull\/1$/);
  await expect(pr.getByText('Loaded PR', { exact: true })).toBeVisible();
  await expect(pr.getByRole('button', { name: 'Account: alice', exact: true })).toBeVisible();
  expect(await pr.evaluate(() => window.opener)).toBeNull();
  await pr.close();
  const commitReady = page.waitForEvent('popup'); await link.click();
  const commit = await commitReady;
  await expect(commit).toHaveURL(/\/upstream\/repo\/pull\/1\/commits\/0+1$/);
  await expect(commit.getByText('Loaded commit', { exact: true })).toBeVisible();
  await expect(commit.locator('.hero-workspace').getByRole('button', { name: 'Account: alice' })).toBeVisible();
  expect(await commit.evaluate(() => window.opener)).toBeNull();
  expect(state.calls.some(c => c.kind === 'CommitGet' && c.args.owner === 'fork')).toBe(true);
  await commit.close();
  const keyboardReady = page.waitForEvent('popup'); await link.press('Enter');
  const keyboardCommit = await keyboardReady;
  await expect(keyboardCommit.getByText('Loaded commit', { exact: true })).toBeVisible();
  await keyboardCommit.close();
  await expect(page).toHaveURL(homepageUrl);
  expect(await page.evaluate(() => window.dashboardDocumentId)).toBe(documentId);
  await expect(one.getByRole('link', { name: /Commit 1/ })).toBeVisible();
  await expect(two.getByRole('link', { name: /Commit 1/ })).toBeVisible();
  expect(state.calls.filter(c => c.kind === 'ViewerPullsGet')).toHaveLength(2);
  expect(state.calls.filter(c => c.kind === 'PullCommitsGet')).toHaveLength(2);
});

test('list pagination preserves rows, deduplicates and retries independently, including incomplete search', async ({ page }) => {
  let attempts = 0;
  await setup(page, async ({ route, kind, args }) => {
    if (kind !== 'ViewerPullsGet') return false;
    if (args.kind.$tag === 'Authored') { await route.fulfill(failure('permission_denied', 'Repository access denied.', 403)); return true; }
    if (!args.cursor) { await route.fulfill({ json: success('ViewerPulls', { items: Array.from({ length: 50 }, (_, i) => pull(i + 1)), total_count: 51, next_cursor: 'page2' }) }); return true; }
    expect(args.cursor).toBe('page2'); attempts++;
    if (attempts === 1) await route.fulfill(failure('rate_limit', 'Rate limit. Try again.', 429));
    else if (attempts === 2) await route.fulfill({ json: success('ViewerPulls', { items: [], total_count: 51, next_cursor: 'page2', incomplete: 'Search is incomplete. Retry to continue.' }) });
    else await route.fulfill({ json: success('ViewerPulls', { items: [pull(50), pull(51, { updated_at: '2026-09-02T00:00:00Z' })], total_count: 51 }) });
    return true;
  });
  await page.goto('/');
  await expect(reviews(page).locator('.home-pull')).toHaveCount(50);
  await selectTab(page, 'Authored');
  await expect(authored(page).getByRole('alert')).toContainText('GitHub denied');
  await selectTab(page, 'ReviewRequested');
  await reviews(page).getByRole('button', { name: 'Load more' }).click();
  await expect(reviews(page).getByRole('alert')).toContainText('temporarily limiting requests');
  await expect(reviews(page).locator('.home-pull')).toHaveCount(50);
  await reviews(page).getByRole('button', { name: 'Retry' }).click();
  await expect(reviews(page).getByRole('alert')).toContainText('incomplete');
  await reviews(page).getByRole('button', { name: 'Retry' }).click();
  await expect(reviews(page).locator('.home-pull')).toHaveCount(51);
  await expect(reviews(page).locator('.home-title-link').first()).toHaveText('Pull request 51');
  await expect(reviews(page).getByRole('button', { name: 'Load more' })).toHaveCount(0);
});

test('commit pages keep GitHub order past 250 and restart on snapshot changes; refresh revalidates expanded pages', async ({ page }) => {
  let changed = false, starts = 0;
  await setup(page, async ({ route, kind, args }) => {
    if (kind !== 'PullCommitsGet') return false;
    if (!args.cursor) starts++;
    if (args.cursor === '100' && !changed) { changed = true; await route.fulfill(failure('pull_commits_changed', 'PR changed', 409)); return true; }
    const start = Number(args.cursor || 0), end = Math.min(start + 100, 301);
    await route.fulfill({ json: success('PullCommits', commits(start + 1, end - start, { total_count: 301, head_sha: changed ? 'c'.repeat(40) : head, ...(end < 301 ? { next_cursor: String(end) } : {}) })) }); return true;
  });
  await page.goto('/'); await selectTab(page, 'ReviewRequested'); const one = row(page, 'Pull request 1');
  await one.getByRole('button', { name: /Expand/ }).click();
  await expect(one.locator('.home-commit')).toHaveCount(100);
  await expect(one.locator('.home-count')).toHaveText('Showing 100 of 301 commits');
  await one.getByRole('button', { name: 'Load more' }).click();
  await expect.poll(() => starts).toBe(2); await expect(one.locator('.home-commit')).toHaveCount(100);
  for (const count of [200, 300, 301]) {
    await one.getByRole('button', { name: 'Load more' }).click();
    await expect(one.locator('.home-commit')).toHaveCount(count);
    if (count < 301) await expect(one.locator('.home-count')).toHaveText(`Showing ${count} of 301 commits`);
    else await expect(one.locator('.home-count')).toHaveCount(0);
  }
  await expect(one.locator('.home-commit-link').last()).toContainText('Commit 301');
  await page.getByRole('button', { name: 'Refresh lists', exact: true }).click();
  await expect(one.getByRole('button', { name: /Collapse/ })).toBeVisible();
  await expect.poll(() => starts).toBe(3);
  await expect(page.getByRole('button', { name: 'Refresh lists' })).toBeEnabled();
  await expect(one.locator('.home-commit')).toHaveCount(301);
  await expect(one.locator('.home-count')).toHaveCount(0);
});

test('logout and account changes clear data and discard delayed pages', async ({ page }) => {
  const pending = gate(); let entered = 0;
  const state = await setup(page, async ({ route, kind, args, state }) => {
    if (kind !== 'ViewerPullsGet' || args.kind.$tag !== 'ReviewRequested') return false;
    const owner = state.user;
    if (owner === 'alice') { entered++; await pending.promise; }
    await route.fulfill({ json: success('ViewerPulls', { items: [pull(1, { title: `${owner} private PR` })], total_count: 1 }) }).catch(() => {}); return true;
  });
  await page.goto('/'); await expect.poll(() => entered).toBe(1);
  state.user = 'bob';
  await page.evaluate(() => { dispatchEvent(new PageTransitionEvent('pagehide', { persisted: true })); dispatchEvent(new PageTransitionEvent('pageshow', { persisted: true })); dispatchEvent(new Event('focus')); });
  await expect(page.getByRole('button', { name: 'Account: bob' })).toBeVisible();
  await selectTab(page, 'ReviewRequested');
  await expect(page.getByRole('link', { name: 'bob private PR' })).toBeVisible();
  pending.release(); await expect(page.getByRole('link', { name: 'alice private PR' })).toHaveCount(0);
  await signOut(page);
  await expect(page.getByRole('button', { name: 'Sign in with GitHub' })).toBeVisible();
  await expect(page.locator('.pr-dashboard')).toHaveCount(0); await expect(page.locator('#commit-url')).toBeVisible();
});

test('page restoration resumes aborted commit pages without losing loaded lists and expanded state', async ({ page }) => {
  const pending = gate(); let commitCalls = 0;
  const state = await setup(page, async ({ route, kind }) => {
    if (kind !== 'PullCommitsGet') return false;
    commitCalls++;
    if (commitCalls === 1) await pending.promise;
    await route.fulfill({ json: success('PullCommits', commits(1, 1)) }).catch(() => {}); return true;
  });
  await page.goto('/'); await selectTab(page, 'ReviewRequested'); const one = row(page, 'Pull request 1');
  await one.getByRole('button', { name: /Expand/ }).click(); await expect.poll(() => commitCalls).toBe(1);
  await page.evaluate(() => { dispatchEvent(new PageTransitionEvent('pagehide', { persisted: true })); dispatchEvent(new PageTransitionEvent('pageshow', { persisted: true })); dispatchEvent(new Event('focus')); });
  await expect(one.getByRole('link', { name: /Commit 1/ })).toBeVisible();
  expect(commitCalls).toBe(2); expect(state.calls.filter(c => c.kind === 'ViewerPullsGet')).toHaveLength(2);
  pending.release(); await expect(one.locator('.home-commit')).toHaveCount(1);
});

test('mobile dashboard wraps long titles and repositories with working keyboard controls', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 812 });
  await setup(page, async ({ route, kind }) => {
    if (kind !== 'ViewerPullsGet') return false;
    await route.fulfill({ json: success('ViewerPulls', { items: [pull(1, { title: 'A'.repeat(160), repo: 'repository'.repeat(10), draft: true })], total_count: 1 }) }); return true;
  });
  await page.goto('/'); await selectTab(page, 'ReviewRequested'); const expand = reviews(page).getByRole('button', { name: /Expand/ });
  await expand.focus(); await page.keyboard.press('Space');
  await expect(reviews(page).getByRole('button', { name: /Collapse/ })).toHaveAttribute('aria-expanded', 'true');
  await expect(reviews(page).getByRole('link', { name: /Commit 1/ })).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await page.screenshot({ path: '/tmp/moondiff-home-mobile.png', fullPage: true });
});

for (const invalidInput of [false, true]) test(`finishing real device sign-in on the anonymous homepage immediately shows the dashboard${invalidInput ? ' after an invalid landing URL' : ''}`, async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('#commit-url')).toBeVisible();
  if (invalidInput) {
    await page.locator('#commit-url').fill('https://example.com/not-github');
    await page.getByRole('button', { name: 'View diff' }).click();
    await expect(page.locator('.empty-state.error')).toBeVisible();
  }
  await page.getByRole('button', { name: 'Sign in with GitHub' }).first().click();
  await expect(page.locator('.device-code').first()).toBeVisible();
  const code = await page.locator('.device-code').first().textContent();
  const opened = page.waitForEvent('popup'); await page.getByRole('button', { name: 'Open GitHub' }).first().click();
  const verification = await opened;
  await verification.getByRole('textbox', { name: 'Verification code' }).fill(code);
  await verification.getByRole('button', { name: 'Authorize device' }).click();
  await verification.close();
  await expect(page.getByRole('button', { name: 'Account: alice' })).toBeVisible();
  await expect(authored(page).getByText('You have no open pull requests.')).toBeVisible();
  await selectTab(page, 'ReviewRequested');
  await expect(reviews(page).getByText('No pull requests awaiting your review.')).toBeVisible();
  await noLanding(page);
});

test('signing out while PR lists load immediately clears the dashboard and ignores late responses', async ({ page }) => {
  const pending = gate(); let entered = 0;
  await setup(page, async ({ route, kind }) => {
    if (kind !== 'ViewerPullsGet') return false;
    entered++; await pending.promise;
    await route.fulfill({ json: success('ViewerPulls', { items: [pull(1, { title: 'Late private PR' })], total_count: 1 }) }).catch(() => {}); return true;
  });
  await page.goto('/'); await expect.poll(() => entered).toBe(2);
  await signOut(page);
  await expect(page.locator('.pr-dashboard')).toHaveCount(0);
  pending.release();
  await expect(page.getByRole('button', { name: 'Sign in with GitHub' })).toBeVisible();
  await expect(page.getByText('Late private PR')).toHaveCount(0);
});

test('commit retry keeps earlier pages while other expanded PRs remain usable', async ({ page }) => {
  let attempts = 0;
  await setup(page, async ({ route, kind, args }) => {
    if (kind !== 'PullCommitsGet' || args.number !== '1') return false;
    if (!args.cursor) await route.fulfill({ json: success('PullCommits', commits(1, 1, { total_count: 2, next_cursor: 'second' })) });
    else if (++attempts === 1) await route.fulfill(failure('github_timeout', 'GitHub did not respond in time.', 504));
    else { expect(args.cursor).toBe('second'); await route.fulfill({ json: success('PullCommits', commits(2, 1)) }); }
    return true;
  });
  await page.goto('/'); await selectTab(page, 'ReviewRequested'); const one = row(page, 'Pull request 1'), two = row(page, 'Pull request 2');
  await one.getByRole('button', { name: /Expand/ }).click();
  await one.getByRole('button', { name: 'Load more' }).click();
  await expect(one.getByRole('alert')).toHaveText('GitHub did not respond in time.');
  await expect(one.locator('.home-count')).toHaveText('Showing 1 of 2 commits');
  await expect(one.getByRole('link', { name: /Commit 1/ })).toBeVisible();
  await two.getByRole('button', { name: /Expand/ }).click();
  await expect(two.getByRole('link', { name: /Commit 1/ })).toBeVisible();
  await one.getByRole('button', { name: 'Retry' }).click();
  await expect(one.locator('.home-commit')).toHaveCount(2);
  await expect(one.locator('.home-count')).toHaveCount(0);
});

for (const target of ['ReviewRequested', 'Authored', 'Commits']) test(`${target} invalid cursor recovery stops on a failed first page and Retry starts fresh`, async ({ page }) => {
  let starts = 0;
  const state = await setup(page, async ({ route, kind, args }) => {
    const match = target === 'Commits'
      ? kind === 'PullCommitsGet' && args.number === '1'
      : kind === 'ViewerPullsGet' && args.kind.$tag === target;
    if (!match) return false;
    if (args.cursor || ++starts === 2) {
      await route.fulfill(failure('invalid_cursor', 'Cursor expired. Retry this list.', 400));
    } else if (target === 'Commits') {
      await route.fulfill({ json: success('PullCommits', commits(starts === 1 ? 1 : 3, 1, starts === 1 ? { total_count: 2, next_cursor: 'expired' } : {})) });
    } else {
      await route.fulfill({ json: success('ViewerPulls', { items: [pull(starts === 1 ? 1 : 4)], total_count: starts === 1 ? 2 : 1,
        ...(starts === 1 ? { next_cursor: 'expired' } : {}) }) });
    }
    return true;
  });
  await page.goto('/');
  await selectTab(page, target === 'Authored' ? 'Authored' : 'ReviewRequested');
  if (target === 'Commits') await row(page, 'Pull request 1').getByRole('button', { name: /Expand commits/ }).click();
  const affected = target === 'Commits' ? row(page, 'Pull request 1') : target === 'Authored' ? authored(page) : reviews(page);
  await affected.getByRole('button', { name: 'Load more', exact: true }).click();
  await expect(affected.getByRole('alert')).toHaveText('Cursor expired. Retry this list.');
  await expect(affected.locator(target === 'Commits' ? '.home-commit' : '.home-pull')).toHaveCount(0);
  expect(starts).toBe(2);
  const calls = () => state.calls.filter(c => target === 'Commits'
    ? c.kind === 'PullCommitsGet' && c.args.number === '1'
    : c.kind === 'ViewerPullsGet' && c.args.kind.$tag === target);
  expect(calls().map(c => c.args.cursor)).toEqual([undefined, 'expired', undefined]);
  // Another list stays interactive while the failed first page waits for Retry.
  await selectTab(page, target === 'Authored' ? 'ReviewRequested' : 'Authored');
  const unaffected = target === 'Authored' ? row(page, 'Pull request 2') : row(page, 'Pull request 3');
  await unaffected.getByRole('button', { name: /Expand commits/ }).click();
  await expect(unaffected.getByRole('link', { name: /Commit 1/ })).toBeVisible();
  expect(starts).toBe(2);
  await selectTab(page, target === 'Authored' ? 'Authored' : 'ReviewRequested');
  await affected.getByRole('button', { name: 'Retry', exact: true }).click();
  await expect(affected.getByRole('link', { name: target === 'Commits' ? /Commit 3/ : 'Pull request 4' })).toBeVisible();
  expect(calls().map(c => c.args.cursor)).toEqual([undefined, 'expired', undefined, undefined]);
});
