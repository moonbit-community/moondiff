import { expect, test } from '@playwright/test';
import { writeFile } from 'node:fs/promises';
import { setup, pull, success, gate, failure, row, selectTab, signOut, base, head } from './home-fixture.mjs';
import { successFixture } from '../../tests/protocol-fixtures.mjs';
import { navigate } from './rendering-fixture.mjs';
import { clickLineCommentButton } from './comment-actions.mjs';
import { settleRegions } from '../../tests/render-probe.mjs';

const file = { filename: 'src/renamed.mbt', previous_filename: 'old/exact name.mbt', status: 'renamed', additions: 1, deletions: 1, changes: 2, patch: '@@ -1 +1 @@\n-pub fn answer() { 1 }\n+pub fn answer() { 2 }' };
const mergeBase = 'c'.repeat(40);

async function fixture(page, handler) {
  await page.addInitScript(() => { window.__moondiffMetrics = { files: {}, active: {} }; });
  const state = await setup(page, async ({ route, kind, args, state }) => {
    if (handler && await handler({ route, kind, args, state })) return true;
    let json;
    if (kind === 'ViewerPullsGet') json = success('ViewerPulls', {
      items: (args.kind.$tag === 'Authored' ? [1, 2, 3, 4, 5, 6, 7, 8, 9] : [4, 5, 8, 9, 10, 11]).map(number => pull(number)), total_count: 7,
    });
    else if (kind === 'PullGet') json = successFixture('github.pull.get', {
      title: `Ready PR ${args.number}`, html_url: `https://github.com/upstream/repo/pull/${args.number}`,
      base: { sha: base, repo: { full_name: 'upstream/repo' } }, head: { sha: state.latestHead || head, repo: { full_name: 'fork/repo' } }, additions: 1, deletions: 1, changed_files: 1, commits: 0,
    });
    else if (kind === 'CompareGet') json = successFixture('github.compare.get', { merge_base_commit: { sha: mergeBase } });
    else if (kind === 'PullFiles') json = successFixture('github.pull.files', [file]);
    else if (kind === 'ContentGet') {
      const source = args.revision === mergeBase ? 'pub fn answer() { 1 }\n' : 'pub fn answer() { 2 }\n';
      json = successFixture('github.content.get', { base64: Buffer.from(source).toString('base64'), size: Buffer.byteLength(source), content_type: 'text/plain' });
    } else return false;
    await route.fulfill({ json });
    return true;
  });
  return state;
}

const kindCalls = (state, kind) => state.calls.filter(call => call.kind === kind);
const prepared = page => expect.poll(() => page.evaluate(() => window.__moondiffMetrics?.prefetch?.cache_bytes || 0)).toBeGreaterThan(0);

async function controlPrefetchDelay(page) {
  await page.addInitScript(() => {
    const schedule = window.setTimeout, cancel = window.clearTimeout;
    const jobs = new Map();
    let sequence = 0;
    window.setTimeout = (callback, delay, ...args) => {
      if (delay !== 250) return schedule(callback, delay, ...args);
      const id = --sequence;
      jobs.set(id, () => callback(...args));
      return id;
    };
    window.clearTimeout = id => { if (!jobs.delete(id)) cancel(id); };
    window.prefetchDelayCount = () => jobs.size;
    window.tickPrefetchDelay = () => {
      const pending = [...jobs.values()];
      jobs.clear();
      for (const run of pending) run();
    };
  });
}

async function tickPrefetchDelay(page) {
  await expect.poll(() => page.evaluate(() => window.prefetchDelayCount())).toBe(1);
  await page.evaluate(() => window.tickPrefetchDelay());
}

async function cachedVerification(page, { large = false } = {}) {
  let stage = 'warm', failRestored = false;
  const gates = { initial: gate(), restored: gate() };
  const held = {}, completed = {};
  const state = await fixture(page, async ({ route, kind, args }) => {
    if (kind === 'PullViewedGet') {
      await route.fulfill({ json: successFixture('github.pull.viewed.get', {
        base_sha: base, head_sha: head,
        files: [{ path: file.filename, state: { $tag: 'Unviewed' } }],
      }) });
      return true;
    }
    if (kind !== 'PullGet') return false;
    const current = stage;
    // Comments and snapshot validation can request the same metadata concurrently.
    // Hold every read for this PR in the selected phase, regardless of ordering.
    const blocked = current !== 'warm' && args.number === '1';
    if (blocked) {
      held[current] = true;
      await gates[current].promise;
    }
    const response = blocked && current === 'restored' && failRestored
      ? failure('github_http_503', 'Restored verification failed', 503)
      : { json: successFixture('github.pull.get', {
        title: `Ready PR ${args.number}`, html_url: `https://github.com/upstream/repo/pull/${args.number}`,
        base: { sha: base, repo: { full_name: 'upstream/repo' } },
        head: { sha: head, repo: { full_name: 'fork/repo' } },
        additions: 1, deletions: 1, changed_files: large ? 3_001 : 1, commits: 0,
      }) };
    await route.fulfill(response).catch(() => {});
    if (blocked) completed[current] = true;
    return true;
  });
  if (large) {
    await page.goto('/upstream/repo/pull/1');
    await expect(page.locator('.range-limit')).toBeVisible();
    await expect(page.getByText('Checking the current PR version…', { exact: true })).toHaveCount(0);
    await page.getByRole('link', { name: /Moondiff/ }).click();
  } else {
    await page.goto('/');
    await expect.poll(() => kindCalls(state, 'ContentGet').length).toBe(2);
  }
  stage = 'initial';
  await row(page, 'Pull request 1').getByRole('link').click();
  await expect(page.getByText('Checking the current PR version…', { exact: true })).toBeVisible();
  await expect.poll(() => held.initial).toBe(true);
  return { state, gates, held, completed, setStage: value => { stage = value; }, fail: () => { failRestored = true; } };
}

async function restoreVerification(page, cached) {
  cached.setStage('restored');
  await page.evaluate(() => {
    dispatchEvent(new PageTransitionEvent('pagehide', { persisted: true }));
    dispatchEvent(new PageTransitionEvent('pageshow', { persisted: true }));
    dispatchEvent(new Event('focus'));
  });
}

test('prefetch selects only the current tab first five, keeps one background request and warms exact fork/rename source pairs without rendering diffs', async ({ page }) => {
  let active = 0, maxActive = 0;
  const state = await fixture(page, async ({ kind }) => {
    if (['PullGet', 'CompareGet', 'PullFiles', 'ContentGet'].includes(kind)) {
      active++; maxActive = Math.max(active, maxActive);
      await new Promise(resolve => setTimeout(resolve, 8));
      active--;
    }
    return false;
  });
  await page.goto('/');
  await expect.poll(() => kindCalls(state, 'PullFiles').length).toBe(2);
  await expect.poll(() => kindCalls(state, 'ContentGet').length).toBe(2);
  expect(maxActive).toBe(1);
  expect([...new Set(kindCalls(state, 'PullGet').map(call => call.args.number))]).toEqual(['1', '2', '3', '4', '5']);
  expect(kindCalls(state, 'ContentGet').map(call => call.args)).toEqual([
    { owner: 'upstream', repo: 'repo', path: 'old/exact name.mbt', revision: mergeBase },
    { owner: 'fork', repo: 'repo', path: 'src/renamed.mbt', revision: head },
  ]);
  expect(state.calls.findIndex(call => call.kind === 'ContentGet')).toBeLessThan(state.calls.findLastIndex(call => call.kind === 'PullFiles'));
  await expect(page.locator('.diff-scroll')).toHaveCount(0);
  const metrics = await page.evaluate(() => window.__moondiffMetrics);
  expect(Object.keys(metrics.files || {})).toHaveLength(0);
  await selectTab(page, 'ReviewRequested');
  await expect.poll(() => kindCalls(state, 'PullFiles').length).toBe(4);
  expect([...new Set(kindCalls(state, 'PullGet').map(call => call.args.number))]).toEqual(['1', '2', '3', '4', '5', '8', '9', '10']);
  await page.getByRole('button', { name: 'Refresh lists', exact: true }).click();
  await expect.poll(() => kindCalls(state, 'ViewerPullsGet').length).toBe(4);
  await page.waitForTimeout(350);
  expect(kindCalls(state, 'PullFiles')).toHaveLength(4);
});

test('opening an in-progress prefetch reuses its metadata chain and cancels the remaining background work', async ({ page }) => {
  const blocked = gate();
  let first = true;
  const state = await fixture(page, async ({ kind, args }) => {
    if (kind === 'PullGet' && args.number === '1' && first) { first = false; await blocked.promise; }
    return false;
  });
  await page.goto('/');
  await expect.poll(() => kindCalls(state, 'PullGet').length).toBe(1);
  await row(page, 'Pull request 1').getByRole('link').click();
  await expect(page).toHaveURL(/\/pull\/1$/);
  blocked.release();
  await expect(page.locator('.diff-scroll table').first()).toBeVisible();
  expect(kindCalls(state, 'PullFiles')).toHaveLength(1);
  expect(kindCalls(state, 'CompareGet')).toHaveLength(1);
  expect(kindCalls(state, 'PullGet').every(call => call.args.number === '1')).toBe(true);
  expect(await page.evaluate(() => window.__moondiffMetrics.counters.prefetch_inflight_hits)).toBe(1);
});

for (const intent of ['hover', 'keyboard focus']) test(`stable ${intent} promotes an eligible candidate within the two-snapshot budget`, async ({ page }) => {
  const blocked = gate(); let first = true;
  const state = await fixture(page, async ({ kind, args }) => {
    if (kind === 'PullGet' && args.number === '1' && first) { first = false; await blocked.promise; }
    return false;
  });
  await page.goto('/');
  await expect.poll(() => kindCalls(state, 'PullGet').length).toBe(1);
  const target = row(page, 'Pull request 5').getByRole('link');
  if (intent === 'hover') await target.hover();
  else await target.focus();
  await page.waitForTimeout(120);
  blocked.release();
  await expect.poll(() => kindCalls(state, 'PullFiles').length).toBe(2);
  await expect.poll(() => new Set(kindCalls(state, 'PullGet').map(call => call.args.number)).size).toBe(5);
  expect(kindCalls(state, 'PullFiles').map(call => call.args.number)).toEqual(['1', '5']);
  expect(kindCalls(state, 'CompareGet')).toHaveLength(2);
});

test('a completed hit paints while real verification is blocked and disables every write until confirmed', async ({ page }) => {
  const validation = gate();
  let block = false;
  const state = await fixture(page, async ({ kind }) => { if (kind === 'PullGet' && block) await validation.promise; return false; });
  await page.goto('/');
  await expect.poll(() => kindCalls(state, 'ContentGet').length).toBe(2);
  block = true;
  await row(page, 'Pull request 1').getByRole('link').click();
  await expect(page.locator('.diff-scroll table').first()).toBeVisible();
  await expect(page.getByText('Checking the current PR version…', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Add overall comment' }).click();
  await page.locator('.comment-editor textarea').fill('Wait for verification');
  await expect(page.getByRole('button', { name: 'Post comment' })).toBeDisabled();
  await expect(page.getByRole('button', { name: 'Rebase and merge', exact: true })).toBeDisabled();
  await expect(page.locator('.viewed-control input')).toBeDisabled();
  validation.release(); block = false;
  await expect(page.getByRole('button', { name: 'Post comment' })).toBeEnabled();
  await expect(page.getByText('Checking the current PR version…', { exact: true })).toHaveCount(0);
  expect(kindCalls(state, 'PullFiles')).toHaveLength(2);
  expect(kindCalls(state, 'ContentGet')).toHaveLength(2);
});

test('page restoration restarts cached PR validation and keeps every write locked until confirmation', async ({ page }) => {
  const cached = await cachedVerification(page);
  await expect(page.locator('.diff-scroll table')).toBeVisible();
  await page.getByRole('button', { name: 'Add overall comment' }).click();
  await page.locator('.comment-editor textarea').fill('Draft retained through restoration');
  const hits = await page.evaluate(() => window.__moondiffMetrics.counters.prefetch_cache_hits);
  cached.state.statusGate = gate();
  await restoreVerification(page, cached);
  await expect(page.locator('.discussion-auth')).toHaveText('Checking GitHub session…');
  await expect(page.getByRole('button', { name: 'Post comment' })).toBeDisabled();
  expect(cached.held.restored).toBeUndefined();
  cached.state.statusGate.release();
  await expect.poll(() => cached.held.restored).toBe(true);
  cached.gates.initial.release();
  await expect.poll(() => cached.completed.initial).toBe(true);
  await expect(page.getByText('Checking the current PR version…', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Post comment' })).toBeDisabled();
  await expect(page.locator('.viewed-control input')).toBeDisabled();
  await expect(page.getByRole('button', { name: 'Rebase and merge', exact: true })).toBeDisabled();
  cached.gates.restored.release();
  await expect(page.getByText('Checking the current PR version…', { exact: true })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Post comment' })).toBeEnabled();
  await expect(page.locator('.viewed-control input')).toBeEnabled();
  await expect(page.getByRole('button', { name: 'Rebase and merge', exact: true })).toBeEnabled();
  await expect(page.locator('.comment-editor textarea')).toHaveValue('Draft retained through restoration');
  expect(await page.evaluate(() => window.__moondiffMetrics.counters.prefetch_cache_hits)).toBe(hits + 1);
  expect(kindCalls(cached.state, 'ContentGet')).toHaveLength(2);
  expect(kindCalls(cached.state, 'PullFiles')).toHaveLength(2);
});

test('restored PR validation errors preserve the diff and offer a working retry', async ({ page }) => {
  const cached = await cachedVerification(page);
  cached.fail();
  await restoreVerification(page, cached);
  await expect.poll(() => cached.held.restored).toBe(true);
  cached.gates.initial.release();
  cached.gates.restored.release();
  await expect(page.locator('[data-region="status"]').getByText(/Restored verification failed/)).toBeVisible();
  await expect(page.locator('.diff-scroll table')).toBeVisible();
  await expect(page.locator('.viewed-control input')).toBeDisabled();
  cached.setStage('warm');
  await page.getByRole('button', { name: 'Try again', exact: true }).click();
  await expect(page.locator('[data-region="status"]').getByText(/Restored verification failed/)).toHaveCount(0);
  await expect(page.getByText('Checking the current PR version…', { exact: true })).toHaveCount(0);
  await expect(page.locator('.viewed-control input')).toBeEnabled();
});

for (const large of [false, true]) test(`cached ${large ? 'large selector' : 'diff'} survives repeated 503 validation retries with a stable Status host and selection`, async ({ page }) => {
  let pending = null, response = null, lastHeld = null, held = 0;
  const middle = 'd'.repeat(40);
  const metadata = {
    title: 'Retry fixture', html_url: 'https://github.com/upstream/repo/pull/1',
    base: { sha: base, repo: { full_name: 'upstream/repo' } },
    head: { sha: head, repo: { full_name: 'fork/repo' } },
    additions: 1, deletions: 1, changed_files: large ? 3_001 : 1, commits: 2,
  };
  const state = await fixture(page, async ({ route, kind }) => {
    let json;
    if (kind === 'ViewerPullsGet') json = success('ViewerPulls', { items: [pull(1)], total_count: 1 });
    else if (kind === 'PullGet') {
      const barrier = pending, failureResponse = response;
      const blocked = barrier && barrier !== lastHeld;
      if (blocked) { lastHeld = barrier; held++; await barrier.promise; }
      await route.fulfill(blocked && failureResponse || { json: successFixture('github.pull.get', metadata) }).catch(() => {});
      return true;
    } else if (kind === 'PullCommitPageGet') json = successFixture('github.pull.commit.page.get', [
      { sha: middle, commit: { message: 'First change' }, parents: [{ sha: mergeBase }] },
      { sha: head, commit: { message: 'Second change' }, parents: [{ sha: middle }] },
    ]);
    else if (kind === 'PullViewedGet') json = successFixture('github.pull.viewed.get', {
      base_sha: base, head_sha: head, files: [{ path: file.filename, state: { $tag: 'Unviewed' } }],
    });
    else return false;
    await route.fulfill({ json });
    return true;
  });
  await page.goto('/upstream/repo/pull/1');
  await expect(page.locator('.range-selector select').first()).toBeEnabled();
  await expect(page.getByText('Checking the current PR version…', { exact: true })).toHaveCount(0);
  await page.locator('.range-selector select').first().selectOption(middle);
  await expect(page.locator('.range-selector select').first()).toHaveValue(middle);
  if (!large) {
    await page.getByRole('button', { name: 'Add overall comment' }).click();
    await page.locator('.comment-editor textarea').fill('Keep this draft during retries');
  }
  await page.getByRole('link', { name: /Moondiff/ }).click();
  await expect(page.getByRole('tab').first()).toBeVisible();
  pending = gate(); response = failure('github_http_503', 'Validation temporarily unavailable', 503);
  await page.goBack();
  await expect.poll(() => held).toBe(1);
  await expect(page.locator('[data-region="status"]')).toHaveCount(1);
  const status = await page.locator('[data-region="status"]').elementHandle();
  const from = page.locator('.range-selector select').first();
  const generation = await page.locator('main').evaluate(root => root.querySelector('[data-navigation-generation]')?.dataset.navigationGeneration ?? null);
  for (let attempt = 0; attempt < 2; attempt++) {
    pending.release();
    await expect(page.getByText(/Validation temporarily unavailable/)).toBeVisible();
    await expect(from).toHaveValue(middle);
    await expect(page.locator(large ? '.range-limit' : '.diff-scroll table')).toBeVisible();
    if (!large) {
      await expect(page.locator('.comment-editor textarea')).toHaveValue('Keep this draft during retries');
      await expect(page.getByRole('button', { name: 'Post comment' })).toBeDisabled();
      await expect(page.locator('.viewed-control input')).toBeDisabled();
    }
    pending = gate();
    if (attempt === 1) response = null;
    const count = kindCalls(state, 'PullGet').length;
    await page.getByRole('button', { name: 'Try again', exact: true }).click();
    await expect(page.getByText('Checking the current PR version…', { exact: true })).toBeVisible();
    await expect.poll(() => held).toBe(attempt + 2);
    expect(kindCalls(state, 'PullGet')).toHaveLength(count + 1);
    await expect(from).toHaveValue(middle);
    expect(await status.evaluate(node => node === document.querySelector('[data-region="status"]') && node.previousElementSibling?.dataset.region === 'toolbar')).toBe(true);
  }
  pending.release();
  await expect(page.getByText('Checking the current PR version…', { exact: true })).toHaveCount(0);
  await expect(from).toHaveValue(middle);
  expect(await status.evaluate(node => node === document.querySelector('[data-region="status"]'))).toBe(true);
  expect(await page.locator('main').evaluate(root => root.querySelector('[data-navigation-generation]')?.dataset.navigationGeneration ?? null)).toBe(generation);
  if (!large) await expect(page.getByRole('button', { name: 'Post comment' })).toBeEnabled();
});

for (const expired of [false, true]) test(`display metadata changes keep restored inline drafts submittable with ${expired ? 'expired' : 'valid'} snapshot cache`, async ({ page }) => {
  let changed = false, held = false;
  const validation = gate();
  const state = await fixture(page, async ({ route, kind }) => {
    if (kind === 'ViewerPullsGet') {
      await route.fulfill({ json: success('ViewerPulls', { items: [pull(1)], total_count: 1 }) });
      return true;
    }
    if (kind !== 'PullGet' || !changed) return false;
    if (!held) { held = true; await validation.promise; }
    await route.fulfill({ json: successFixture('github.pull.get', {
      title: 'Updated display title', html_url: 'https://github.com/upstream/repo/pull/1?updated',
      base: { sha: base, repo: { full_name: 'upstream/repo' } },
      head: { sha: head, repo: { full_name: 'fork/repo' } },
      additions: 30, deletions: 20, changed_files: 1, commits: 0,
    }) });
    return true;
  });
  await page.goto('/upstream/repo/pull/1');
  await expect(page.locator('.diff-scroll table')).toBeVisible();
  const gutter = page.locator('.review-gutter.new-line-number').filter({ has: page.locator('.line-number-value', { hasText: /^1$/ }) });
  await clickLineCommentButton(gutter.getByRole('button', { name: 'Comment on line 1', exact: true }));
  await page.locator('.comment-editor textarea').fill('Keep original inline anchor');
  await page.getByRole('link', { name: /Moondiff/ }).click();
  await expect(page.getByRole('tab').first()).toBeVisible();
  if (expired) await page.clock.setFixedTime(new Date(Date.now() + 31_000));
  changed = true;
  const filesBefore = kindCalls(state, 'PullFiles').length;
  await page.goBack();
  await expect.poll(() => held).toBe(true);
  if (!expired) await expect(page.getByRole('button', { name: 'Post comment' })).toBeDisabled();
  validation.release();
  await expect(page.getByText('Updated display title', { exact: true })).toBeVisible();
  await expect(page.locator('.comment-editor textarea')).toHaveValue('Keep original inline anchor');
  await expect(page.getByRole('button', { name: 'Post comment' })).toBeEnabled();
  await expect(page.getByText(/PR updated\. Copy or cancel/)).toHaveCount(0);
  expect(kindCalls(state, 'PullFiles')).toHaveLength(filesBefore);
});

for (const stage of ['metadata', 'compare', 'files', 'validation', 'source']) test(`hiding cancels pure prefetch during ${stage} and visibility resumes completed cache after 250ms`, async ({ page }) => {
  await controlPrefetchDelay(page);
  const blocked = gate();
  let held = null, metadataReads = 0, stopped = false;
  const state = await fixture(page, async ({ route, kind }) => {
    if (kind === 'ViewerPullsGet') {
      await route.fulfill({ json: success('ViewerPulls', { items: [pull(1)], total_count: 1 }) });
      return true;
    }
    if (kind === 'PullGet') metadataReads++;
    const match = stage === 'metadata' && kind === 'PullGet' && metadataReads === 1
      || stage === 'compare' && kind === 'CompareGet'
      || stage === 'files' && kind === 'PullFiles'
      || stage === 'validation' && kind === 'PullGet' && metadataReads === 2
      || stage === 'source' && kind === 'ContentGet';
    if (!held && match) {
      held = route.request();
      await blocked.promise;
      stopped = true;
      // The request was aborted while the barrier held its response.
      await route.fulfill(failure('unavailable', 'Late response', 503)).catch(() => {});
      return true;
    }
    return false;
  });
  const aborted = [];
  page.on('requestfailed', request => aborted.push(request));
  await page.goto('/');
  await expect(row(page, 'Pull request 1')).toBeVisible();
  await settleRegions(page);
  await tickPrefetchDelay(page);
  await expect.poll(() => Boolean(held)).toBe(true);
  const count = state.calls.length;
  const bytes = await page.evaluate(() => window.__moondiffMetrics.prefetch?.cache_bytes || 0);
  await page.evaluate(() => {
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => true });
    document.dispatchEvent(new Event('visibilitychange'));
  });
  await expect.poll(() => aborted.includes(held)).toBe(true);
  blocked.release();
  await expect.poll(() => stopped).toBe(true);
  await settleRegions(page);
  expect(state.calls).toHaveLength(count);
  expect(await page.evaluate(() => window.__moondiffMetrics.prefetch?.cache_bytes || 0)).toBe(bytes);
  await page.evaluate(() => {
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });
    document.dispatchEvent(new Event('visibilitychange'));
  });
  await expect.poll(() => page.evaluate(() => window.prefetchDelayCount())).toBe(1);
  expect(state.calls).toHaveLength(count);
  await page.evaluate(() => window.tickPrefetchDelay());
  await expect.poll(() => kindCalls(state, 'ContentGet').length).toBe(stage === 'source' ? 3 : 2);
  expect(kindCalls(state, 'PullFiles')).toHaveLength(stage === 'source' ? 1 : stage === 'metadata' || stage === 'compare' ? 1 : 2);
});

test('late restored validation cannot replace a newly navigated PR', async ({ page }) => {
  const cached = await cachedVerification(page);
  await restoreVerification(page, cached);
  await expect.poll(() => cached.held.restored).toBe(true);
  cached.setStage('warm');
  await navigate(page, '/upstream/repo/pull/7');
  await expect(page.getByText('Ready PR 7', { exact: true })).toBeVisible();
  cached.gates.initial.release();
  cached.gates.restored.release();
  await expect.poll(() => cached.completed.restored).toBe(true);
  await expect(page).toHaveURL(/\/pull\/7$/);
  await expect(page.getByText('Ready PR 7', { exact: true })).toBeVisible();
  await expect(page.getByText('Ready PR 1', { exact: true })).toHaveCount(0);
  await expect(page.getByText('Checking the current PR version…', { exact: true })).toHaveCount(0);
});

test('restoring cached large PR validation retains the selector and finishes confirmation', async ({ page }) => {
  const cached = await cachedVerification(page, { large: true });
  await expect(page.locator('.range-limit')).toBeVisible();
  await expect(page.locator('.range-selector select')).toHaveCount(2);
  await restoreVerification(page, cached);
  await expect.poll(() => cached.held.restored).toBe(true);
  cached.gates.initial.release();
  cached.gates.restored.release();
  await expect(page.getByText('Checking the current PR version…', { exact: true })).toHaveCount(0);
  await expect(page.locator('.range-limit')).toBeVisible();
  await expect(page.locator('.range-selector select')).toHaveCount(2);
  await expect(page.locator('.file-card')).toHaveCount(0);
  expect(kindCalls(cached.state, 'PullFiles')).toHaveLength(0);
});

test('large PRs remain metadata-only and rate limits stop their round', async ({ page }) => {
  const state = await fixture(page, async ({ route, kind, args }) => {
    if (kind !== 'PullGet') return false;
    if (args.number === '2') { await route.fulfill(failure('rate_limit', 'Fixture rate limit', 429)); return true; }
    await route.fulfill({ json: successFixture('github.pull.get', { title: 'Large PR', html_url: 'https://github.com/upstream/repo/pull/1', base: { sha: base }, head: { sha: head }, additions: 301, deletions: 0, changed_files: 301, commits: 0 }) });
    return true;
  });
  await page.goto('/');
  await expect.poll(() => kindCalls(state, 'PullGet').length).toBe(2);
  await page.waitForTimeout(350);
  expect(kindCalls(state, 'PullFiles')).toHaveLength(0);
  expect(kindCalls(state, 'CompareGet')).toHaveLength(0);
  expect(kindCalls(state, 'ContentGet')).toHaveLength(0);
});

test('hidden homepages do not start background reads and sign-out rejects late responses', async ({ page }) => {
  const blocked = gate();
  await page.addInitScript(() => { Object.defineProperty(document, 'hidden', { configurable: true, get: () => true }); });
  const state = await fixture(page, async ({ kind }) => { if (kind === 'PullGet') await blocked.promise; return false; });
  await page.goto('/');
  await expect(page.getByRole('tab').first()).toBeVisible();
  await page.waitForTimeout(350);
  expect(kindCalls(state, 'PullGet')).toHaveLength(0);
  await page.evaluate(() => { Object.defineProperty(document, 'hidden', { configurable: true, get: () => false }); document.dispatchEvent(new Event('visibilitychange')); });
  await expect.poll(() => kindCalls(state, 'PullGet').length).toBe(1);
  await signOut(page);
  blocked.release();
  await expect(page.locator('.hero-landing')).toBeVisible();
  await expect.poll(() => page.evaluate(() => window.__moondiffMetrics.prefetch.cache_bytes)).toBe(0);
  expect(kindCalls(state, 'PullFiles')).toHaveLength(0);
});

test('fixed-fixture cold and prefetched navigation report readable diff latency, restoration and hit metrics', async ({ page }, testInfo) => {
  const state = await fixture(page, async ({ kind }) => {
    if (['PullGet', 'CompareGet', 'PullFiles', 'ContentGet'].includes(kind)) await new Promise(resolve => setTimeout(resolve, 25));
    return false;
  });
  await page.goto('/');
  for (const [index, number] of [7, 8, 9].entries()) {
    await row(page, `Pull request ${number}`).getByRole('link').click();
    await expect(page.locator('.diff-scroll table').first()).toBeVisible();
    await expect.poll(() => page.evaluate(() => window.__moondiffMetrics.timings?.click_to_diff_cold?.samples?.length || 0)).toBe(index + 1);
    await page.getByRole('link', { name: /Moondiff/ }).click();
    // Complete two snapshots and both shared source blobs before visiting.
    await expect.poll(() => kindCalls(state, 'PullFiles').filter(call => Number(call.args.number) <= 5).length).toBe(2);
    await prepared(page);
  }
  for (const [index, number] of [1, 2, 3].entries()) {
    await row(page, `Pull request ${number}`).getByRole('link').click();
    await expect(page.locator('.diff-scroll table').first()).toBeVisible();
    await expect.poll(() => page.evaluate(() => window.__moondiffMetrics.timings?.click_to_diff_prefetch?.samples?.length || 0)).toBe(index + 1);
    await page.goBack();
    await expect(page.getByRole('tab').first()).toBeVisible();
  }
  await expect.poll(() => page.evaluate(() => window.__moondiffMetrics.timings?.back_restore?.samples?.length || 0)).toBeGreaterThan(0);
  const metrics = await page.evaluate(() => ({ ...window.__moondiffMetrics, sources: undefined }));
  expect(metrics.prefetch.hits).toBeGreaterThan(0);
  expect(metrics.prefetch.hit_rate).toBeGreaterThan(0);
  expect(metrics.counters.prefetch_requests).toBeGreaterThan(0);
  expect(metrics.counters.prefetch_bytes).toBeGreaterThan(0);
  const report = testInfo.outputPath('navigation-performance.json');
  await writeFile(report, JSON.stringify(metrics, null, 2));
  await testInfo.attach('navigation-performance.json', { path: report, contentType: 'application/json' });
});
