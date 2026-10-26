import { requestsFor, trackRoute } from '../../tests/browser-control.mjs';
import { expect, test } from '../../tests/browser-test.mjs';
import { setup, gate, base, head } from './home-fixture.mjs';
import { successFixture } from '../../tests/protocol-fixtures.mjs';
import { settleRegions } from '../../tests/render-probe.mjs';

const mergeBase = 'c'.repeat(40), middle = 'd'.repeat(40);
const path = '/upstream/repo/pull/1';
const checking = 'Checking the current PR version…';
const file = {
  filename: 'src/main.mbt', status: 'modified', additions: 1, deletions: 1,
  changes: 2, patch: '@@ -1 +1 @@\n-fn answer() { 1 }\n+fn answer() { 2 }',
};
const commits = [
  { sha: middle, commit: { message: 'First change' }, parents: [{ sha: mergeBase }] },
  { sha: head, commit: { message: 'Last change' }, parents: [{ sha: middle }] },
];

async function reactivate(page) {
  const response = page.waitForResponse('**/api/auth/status');
  await page.evaluate(() => {
    Object.defineProperty(document, 'hasFocus', { configurable: true, value: () => false });
    dispatchEvent(new Event('blur'));
    Object.defineProperty(document, 'hasFocus', { configurable: true, value: () => true });
    dispatchEvent(new Event('focus'));
  });
  await (await response).finished();
  await settleRegions(page);
}

async function cachedAnonymousPull(page, large) {
  await page.addInitScript(() => { window.__moondiffMetrics = { files: {}, active: {} }; });
  const publicValidation = gate(), privateValidation = gate();
  let blockPublic = false, publicHeld = false, privateHeld = false, publicRequest, privateRequest;
  const metadata = {
    title: 'Anonymous cached PR', html_url: 'https://github.com/upstream/repo/pull/1',
    base: { sha: base, repo: { full_name: 'upstream/repo' } },
    head: { sha: head, repo: { full_name: 'fork/repo' } },
    additions: 1, deletions: 1, changed_files: large ? 3_001 : 1, commits: 2,
  };
  const state = await setup(page, async ({ route, kind, args }) => {
    let op, value;
    switch (kind) {
      case 'ViewerPullsGet': op = 'github.viewer.pulls.get'; value = { items: [], total_count: 0 }; break;
      case 'PullGet':
        if (!privateHeld) { privateRequest = requestsFor(page).enter(route.request()); privateHeld = true; await privateValidation.promise; }
        op = 'github.pull.get'; value = metadata; break;
      case 'CompareGet': op = 'github.compare.get'; value = { merge_base_commit: { sha: mergeBase } }; break;
      case 'PullFiles': op = 'github.pull.files'; value = [file]; break;
      case 'PullCommitPageGet': op = 'github.pull.commit.page.get'; value = commits; break;
      case 'ContentGet': {
        const source = args.revision === mergeBase ? 'fn answer() { 1 }\n' : 'fn answer() { 2 }\n';
        op = 'github.content.get'; value = { base64: Buffer.from(source).toString('base64'), size: Buffer.byteLength(source) };
        break;
      }
      case 'PullViewedGet':
        op = 'github.pull.viewed.get'; value = { base_sha: base, head_sha: head, files: [{ path: file.filename, state: { $tag: 'Unviewed' } }] };
        break;
      case 'IssueCommentCreate':
        op = 'github.issue.comment.create';
        value = { id: 1, body: args.body, html_url: 'https://github.com/comment/1', created_at: '2026-09-01T00:00:00Z', user: { login: 'alice' } };
        break;
      default: return false;
    }
    await route.fulfill({ json: successFixture(op, value) });
    return true;
  });
  state.user = null;
  await page.context().route('**/api/auth/device/start', route => {
    const id = route.request().postDataJSON().attempt_id;
    state.user = 'alice';
    return route.fulfill({ json: successFixture('auth.device.start', {
      attempt_id: id, authenticated: true, login: 'alice', user_id: 'alice', csrf_token: 'fixture',
      device_flow: { id, phase: 'completed', user_code: '', verification_uri: '', expires_at: 2_000_000_000, retry_after: 5, message: '' },
    }) });
  });
  await page.route('https://api.github.com/**', async route => {
    route = trackRoute(route);
    const url = new URL(route.request().url()), pathname = url.pathname;
    const headers = { 'Access-Control-Allow-Origin': '*' };
    let value;
    if (pathname.endsWith('/pulls/1')) {
      if (blockPublic && !publicHeld) { publicRequest = requestsFor(page).enter(route.request()); publicHeld = true; await publicValidation.promise; }
      value = metadata;
    } else if (pathname.includes('/compare/')) value = { merge_base_commit: { sha: mergeBase } };
    else if (pathname.endsWith('/pulls/1/files')) value = [file];
    else if (pathname.endsWith('/pulls/1/commits')) value = commits;
    else if (pathname.endsWith('/comments')) value = [];
    else if (pathname.includes('/contents/')) {
      return route.fulfill({ body: url.searchParams.get('ref') === mergeBase ? 'fn answer() { 1 }\n' : 'fn answer() { 2 }\n', contentType: 'text/plain', headers });
    } else throw new Error(`Unexpected public request ${url}`);
    await route.fulfill({ json: value, headers });
  });
  await page.goto(path);
  await expect(page.locator('.range-selector select').first()).toBeEnabled();
  await expect(page.getByText(checking, { exact: true })).toHaveCount(0);
  await page.locator('.range-selector select').first().selectOption(middle);
  await page.locator('.range-selector select').nth(1).selectOption(head);
  await page.getByRole('link', { name: /Moondiff/ }).click();
  blockPublic = true;
  await page.goBack();
  await expect(page.getByText(checking, { exact: true })).toBeVisible();
  await expect.poll(() => publicHeld).toBe(true);
  expect(await page.evaluate(() => window.__moondiffMetrics.counters.prefetch_cache_hits)).toBe(1);
  return { state, publicValidation, privateValidation, privateHeld: () => privateHeld, publicRequest: () => publicRequest, privateRequest: () => privateRequest };
}

for (const large of [false, true]) test(`first sign-in resumes an anonymous cached ${large ? 'large PR selector' : 'PR'} without losing its selection`, async ({ page }) => {
  const cached = await cachedAnonymousPull(page, large);
  const content = large ? '.range-selector' : '.file-card';
  await page.evaluate(selector => { window.identityContent = document.querySelector(selector); }, content);
  if (large) {
    const signInPage = await page.context().newPage();
    await signInPage.goto('/');
    await signInPage.getByRole('button', { name: 'Sign in with GitHub' }).click();
    await expect(signInPage.getByRole('button', { name: 'Account: alice' })).toBeVisible();
    await signInPage.close();
    await reactivate(page);
  } else {
    await page.getByRole('button', { name: 'Sign in with GitHub' }).click();
  }
  await expect(page.getByRole('button', { name: 'Account: alice' })).toBeVisible();
  await expect.poll(cached.privateHeld).toBe(true);
  await expect(page.getByText(checking, { exact: true })).toBeVisible();
  await expect(page.locator('.range-selector select').first()).toHaveValue(middle);
  await expect(page.locator('.range-selector select').nth(1)).toHaveValue(head);
  expect(await page.evaluate(selector => document.querySelector(selector) === window.identityContent, content)).toBe(true);
  if (!large) {
    await page.getByRole('button', { name: 'Add overall comment' }).click();
    await page.locator('.comment-editor textarea').fill('Comment after validation');
    await expect(page.getByRole('button', { name: 'Post comment' })).toBeDisabled();
    await expect(page.locator('.viewed-control input')).toBeDisabled();
    await expect(page.getByRole('button', { name: 'Rebase and merge', exact: true })).toBeDisabled();
  }
  const counters = await page.evaluate(() => ({ ...window.__moondiffMetrics.counters }));
  await reactivate(page);
  await expect(page.getByText(checking, { exact: true })).toBeVisible();
  cached.publicValidation.release();
  await requestsFor(page).wait({ phase: 'cancelled', predicate: request => request.id === cached.publicRequest().id });
  await settleRegions(page);
  await expect(page.getByText(checking, { exact: true })).toBeVisible();
  cached.privateValidation.release();
  await requestsFor(page).wait({ phase: 'received', predicate: request => request.id === cached.privateRequest().id });
  await expect(page.getByText(checking, { exact: true })).toHaveCount(0);
  const confirmedCounters = await page.evaluate(() => window.__moondiffMetrics.counters);
  for (const key of ['snapshot_misses', 'prefetch_cache_hits', 'prefetch_inflight_hits']) {
    expect(confirmedCounters[key] || 0, key).toBe(counters[key] || 0);
  }
  await expect(page.locator('.range-selector select').first()).toHaveValue(middle);
  await expect(page.locator('.range-selector select').nth(1)).toHaveValue(head);
  expect(await page.evaluate(selector => document.querySelector(selector) === window.identityContent, content)).toBe(true);
  if (large) {
    await expect(page.locator('.range-limit')).toBeVisible();
    await expect(page.locator('.file-card')).toHaveCount(0);
    expect(cached.state.calls.filter(call => call.kind === 'PullFiles')).toHaveLength(0);
  } else {
    await expect(page.getByRole('button', { name: 'Post comment' })).toBeEnabled();
    await expect(page.locator('.viewed-control input')).toBeEnabled();
    await expect(page.getByRole('button', { name: 'Rebase and merge', exact: true })).toBeEnabled();
    await page.getByRole('button', { name: 'Post comment' }).click();
    await expect(page.getByRole('article').filter({ hasText: 'Comment after validation' })).toBeVisible();
    expect(cached.state.calls.filter(call => call.kind === 'IssueCommentCreate')).toHaveLength(1);
  }
});
