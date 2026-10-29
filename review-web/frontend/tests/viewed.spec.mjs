import { createGate, installClock, clockFor, requestsFor } from '../../tests/browser-control.mjs';
import { cancelledRoute } from '../../tests/browser-control.mjs';
import { expect, test } from '../../tests/browser-test.mjs';
import { fixtureRequest, successFixture, metadataFallbackRoute } from '../../tests/protocol-fixtures.mjs';
import { clickLineCommentButton } from './comment-actions.mjs';
import { signInDialog, pagePosition, expectPagePosition, expectSignInDialog, closeSignInDialog } from './sign-in-dialog.mjs';
import { settleRegions, waitForState } from '../../tests/render-probe.mjs';

const base = '1'.repeat(40), head = 'a'.repeat(40), merge = '2'.repeat(40);
const path = '/alice/repo/pull/42';
const files = ['src/a.txt', 'src/new name.txt', 'README.md'].map((filename, i) => ({
  filename, ...(i === 1 ? { previous_filename: 'src/old.txt' } : {}),
  status: i === 1 ? 'renamed' : 'modified', additions: 1, deletions: 1, changes: 2,
  patch: '@@ -1,3 +1,3 @@\n context\n-old\n+new\n tail',
}));
const gate = createGate;
async function install(page, options = {}) {
  const state = {
    user: 'alice', authenticated: true, base, head, calls: [], states: {},
    readGate: null, writeGate: null, readFailure: null, writeFailure: null, applyOnFailure: false,
    page, files, reviewComments: [], contentFailure: null,
    ...options,
  };
  const states = () => state.states[state.user] ??= {};
  await page.addInitScript(() => {
    let active = true;
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => !active });
    document.hasFocus = () => active;
    window.reactivate = () => {
      active = false; dispatchEvent(new Event('blur')); document.dispatchEvent(new Event('visibilitychange'));
      active = true; document.dispatchEvent(new Event('visibilitychange')); dispatchEvent(new Event('focus'));
    };
  });
  await page.route('https://api.github.com/repos/alice/repo/**', async route => {
    const url = new URL(route.request().url());
    const resource = url.pathname.replace('/repos/alice/repo/', '');
    let op, args, value, source = false;
    if (resource.startsWith('contents/')) {
      source = true; op = 'github.content.get';
      args = { path: resource.slice('contents/'.length).split('/').map(decodeURIComponent).join('/'), ref: url.searchParams.get('ref') };
      const text = state.source ? state.source(args.ref) : `context\n${args.ref === head ? 'new' : 'old'}\ntail`;
      value = Buffer.from(text);
    } else if (/^pulls\/\d+\/files$/.test(resource)) {
      op = 'github.pull.files'; args = { number: '42', page: Number(url.searchParams.get('page') || 1) }; value = state.files;
    } else if (/^pulls\/\d+\/comments$/.test(resource)) {
      op = 'github.comments.list'; args = { number: '42' }; value = state.reviewComments;
    } else if (/^issues\/\d+\/comments$/.test(resource) || /^commits\/[^/]+\/comments$/.test(resource)) {
      op = 'github.comments.list'; args = {}; value = [];
    } else if (/^pulls\/\d+$/.test(resource)) {
      op = 'github.pull.get'; args = { number: '42' };
      value = { title: state.title ?? 'Viewed fixture', html_url: 'https://github.com/alice/repo/pull/42',
        base: { sha: state.base, repo: { full_name: 'alice/repo' } }, head: { sha: state.head, repo: { full_name: 'alice/repo' } },
        additions: state.files.length, deletions: state.files.length, changed_files: state.files.length, commits: 0 };
    } else if (/^commits\/[^/]+$/.test(resource)) {
      op = 'github.commit.get'; args = { sha: resource.split('/')[1] };
      value = { sha: args.sha, html_url: `https://github.com/alice/repo/commit/${args.sha}`,
        commit: { message: 'Commit fixture' }, parents: [{ sha: base }],
        stats: { additions: 3, deletions: 3, total: 6 }, files: state.files };
    } else if (resource.startsWith('compare/')) {
      op = 'github.compare.get'; args = {}; value = { merge_base_commit: { sha: merge } };
    } else {
      throw new Error(`Unhandled Viewed fixture GitHub URL ${url}`);
    }
    state.calls.push({ op, args });
    const headers = { 'Access-Control-Allow-Origin': '*' };
    await route.fulfill(source
      ? { body: value, contentType: 'text/plain', headers }
      : { json: value, headers }).catch(error => cancelledRoute(route, error));
  });
  await page.route('**/api/**', async route => {
    route = metadataFallbackRoute(route);
    const request = route.request();
    if (new URL(request.url()).pathname === '/api/auth/status') {
      state.calls.push({ op: 'auth.status' });
      const pending = state.authGate; state.authGate = null;
      if (pending) await pending.promise;
      return route.fulfill({ json: successFixture('auth.status', { authenticated: state.authenticated, csrf_token: 'fixture', ...(state.authenticated ? { login: state.user, user_id: state.user === 'alice' ? '1' : '2' } : {}) }) });
    }
    const { op, args } = fixtureRequest(request.postDataJSON());
    state.calls.push({ op, args });
    let value, failure;
    if (op === 'github.viewer.pulls.get') value = { items: [], total_count: 0 };
    else if (op === 'github.pull.get') {
      value = { title: state.title ?? 'Viewed fixture', html_url: 'https://github.com/alice/repo/pull/42', base: { sha: state.base, repo: { full_name: 'alice/repo' } }, head: { sha: state.head, repo: { full_name: 'alice/repo' } }, additions: state.files.length, deletions: state.files.length, changed_files: state.files.length, commits: 0 };
      const pending = state.metadataGate; state.metadataGate = null;
      if (pending) await pending.promise;
    }
    else if (op === 'github.compare.get') value = { merge_base_commit: { sha: merge } };
    else if (op === 'github.pull.files') value = state.files;
    else if (op === 'github.commit.get') value = { sha: args.sha, html_url: `https://github.com/alice/repo/commit/${args.sha}`, commit: { message: 'Commit fixture' }, parents: [{ sha: base }], stats: { additions: 3, deletions: 3, total: 6 }, files };
    else if (op === 'github.content.get') {
      const text = state.source ? state.source(args.ref) : `context\n${args.ref === head ? 'new' : 'old'}\ntail`;
      value = { base64: Buffer.from(text).toString('base64'), size: Buffer.byteLength(text) };
      failure = state.contentFailure; state.contentFailure = null;
    }
    else if (op === 'github.comments.list') value = { issue_comments: [], review_comments: state.reviewComments, commit_comments: [] };
    else if (op === 'github.pull.merge.status') {
      value = { base_sha: state.base, head_sha: state.head, open: true, draft: false, merged: false, mergeable: true, rebaseable: true, mergeable_state: 'clean', ci_checks: [], ci_warnings: [] };
      const pending = state.mergeGate; state.mergeGate = null;
      if (pending) await pending.promise;
    }
    else if (op === 'github.review.comment.create' || op === 'github.review.reply.create') {
      value = {
        id: '22', body: args.body, html_url: 'https://github.com/comment/22', created_at: '2026-09-11T09:00:00Z',
        user: { login: state.user }, path: args.path ?? state.files[0].filename, line: 2, side: 'RIGHT', position: 3,
        commit_id: state.head, ...(op === 'github.review.reply.create' ? { in_reply_to_id: args.comment_id } : {}),
      };
      state.reviewComments.push(value);
    }
    else if (op === 'github.pull.viewed.get') {
      const version = state.readVersion ?? { base_sha: state.base, head_sha: state.head }; state.readVersion = null;
      value = { ...version, files: state.files.map(file => ({ path: file.filename, state: { $tag: states()[file.filename] || 'Unviewed' } })) };
      failure = state.readFailure; state.readFailure = null;
      const pending = state.readGate; state.readGate = null;
      if (pending) await pending.promise;
    } else if (op === 'github.pull.file.viewed.set') {
      const userStates = states();
      failure = state.writeFailure; state.writeFailure = null;
      if (!failure || state.applyOnFailure) userStates[args.path] = args.viewed ? 'Viewed' : 'Unviewed';
      value = { base_sha: state.base, head_sha: state.head, file: { path: args.path, state: { $tag: args.viewed ? 'Viewed' : 'Unviewed' } } };
      const pending = state.writeGate; state.writeGate = null;
      if (pending) await pending.promise;
    } else throw new Error(`Unhandled ${op}`);
    await route.fulfill({ status: failure?.status || 200, json: failure ? { $tag: 'Failure', error: failure } : successFixture(op, value) }).catch(error => cancelledRoute(route, error));
  });
  return state;
}
const box = (page, index = 0) => page.getByRole('checkbox', { name: `Viewed ${files[index].filename}`, exact: true });
const card = (page, index = 0) => page.locator(`#moondiff-file-${index}`);
const calls = (state, op) => state.calls.filter(call => call.op === op);
async function expectViewedWrite(state, path, viewed, action) {
  const before = calls(state, 'github.pull.file.viewed.set').length;
  const expected = { path, base_sha: state.base, head_sha: state.head, viewed };
  await action();
  if (clockFor(state.page)) await clockFor(state.page).until(
    () => calls(state, 'github.pull.file.viewed.set').length === before + 1, 'Viewed write dispatched');
  // Native checkbox state and enabled controls can precede the render that sends the write.
  await expect.poll(() => calls(state, 'github.pull.file.viewed.set').length).toBe(before + 1);
  expect(calls(state, 'github.pull.file.viewed.set')[before].args).toMatchObject(expected);
}
const refresh = page => page.evaluate(() => window.reactivate());

for (const width of [1280, 390]) {
  test(`Viewed restores, marks, expands, preserves cache and supports keyboard at ${width}px`, async ({ page }, testInfo) => {
    await page.setViewportSize({ width, height: 850 });
    const waiting = gate();
    const state = await install(page, { readGate: waiting, states: { alice: { 'src/a.txt': 'Viewed', 'src/new name.txt': 'Dismissed' } } });
    await page.goto(path);
    await expect(page.getByText('Loading Viewed status…', { exact: true })).toBeVisible();
    await expect(box(page)).toBeDisabled();
    await expect(page.getByRole('progressbar', { name: 'Files viewed' })).toHaveCount(0);
    await expect.poll(() => calls(state, 'github.pull.viewed.get').length).toBe(1);
    waiting.resolve();
    await expect(box(page)).toBeChecked();
    await expect(box(page, 1)).not.toBeChecked();
    await expect(card(page)).not.toHaveClass(/expanded/);
    await expect(page.getByText('1 / 3 files viewed', { exact: true })).toBeVisible();
    await expect(card(page, 1).locator('.viewed-label')).toHaveAttribute('title', 'New changes since last viewed');
    await expect(page.locator('.tree-viewed')).toHaveCount(1);
    await card(page).getByRole('button', { name: 'Expand src/a.txt', exact: true }).click();
    await expect(card(page)).toHaveClass(/expanded/);
    await expect(card(page).locator('table')).toBeVisible();
    const contentCount = calls(state, 'github.content.get').length;
    await refresh(page);
    await expect.poll(() => calls(state, 'github.pull.viewed.get').length).toBe(2);
    await expect(box(page)).toBeChecked();
    await expect(card(page)).toHaveClass(/expanded/);
    await box(page).focus();
    await expectViewedWrite(state, files[0].filename, false, () => page.keyboard.press('Space'));
    await expect(box(page)).toBeEnabled();
    await expect(box(page)).not.toBeChecked();
    expect(state.states.alice[files[0].filename]).toBe('Unviewed');
    await expect(card(page)).toHaveClass(/expanded/);
    await expectViewedWrite(state, files[0].filename, true, () => box(page).check());
    await expect(box(page)).toBeEnabled();
    await expect(box(page)).toBeChecked();
    expect(state.states.alice[files[0].filename]).toBe('Viewed');
    await expect(card(page)).not.toHaveClass(/expanded/);
    await expectViewedWrite(state, files[1].filename, true, () => box(page, 1).check());
    await expect(box(page, 1)).toBeEnabled();
    await expect(box(page, 1)).toBeChecked();
    expect(state.states.alice[files[1].filename]).toBe('Viewed');
    await expect(card(page, 1)).not.toHaveClass(/expanded/);
    expect(calls(state, 'github.content.get').length).toBe(contentCount);
    await expect(page.getByText('2 / 3 files viewed', { exact: true })).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    const bounds = await box(page, 1).boundingBox(); expect(bounds.x + bounds.width).toBeLessThan(width);
    await page.screenshot({ path: testInfo.outputPath(`viewed-${width}.png`), fullPage: true });
    await page.reload();
    await expect(box(page, 1)).toBeChecked();
    await expect(card(page, 1)).not.toHaveClass(/expanded/);
  });
}

test('Viewed rejects repeated operations, rolls back clear failure and keeps a comment draft', async ({ page }) => {
  const state = await install(page);
  await page.goto(path); await viewedReady(page); await expect(box(page)).toBeEnabled();
  await card(page).getByRole('button', { name: 'Expand src/a.txt', exact: true }).click();
  await page.getByRole('button', { name: 'Add overall comment', exact: true }).click();
  const editor = page.locator('textarea'); await editor.fill('Keep this comment draft');
  const waiting = gate(); state.writeGate = waiting;
  state.writeFailure = { status: 403, code: 'permission_denied', message: 'Viewed access denied' };
  await expectViewedWrite(state, files[0].filename, true, () => box(page).check());
  await expect(box(page)).toBeDisabled();
  await box(page).evaluate(input => input.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true })));
  expect(calls(state, 'github.pull.file.viewed.set')).toHaveLength(1);
  await expect(page.getByText('1 / 3 files viewed', { exact: true })).toBeVisible();
  waiting.resolve();
  await expect(box(page)).not.toBeChecked();
  await expect(card(page)).toHaveClass(/expanded/);
  await expect(editor).toHaveValue('Keep this comment draft');
  await expectViewedWrite(state, files[0].filename, true, () => card(page).getByRole('button', { name: 'Retry Viewed', exact: true }).click());
  await expect(box(page)).toBeEnabled(); await expect(box(page)).toBeChecked();
  expect(state.states.alice[files[0].filename]).toBe('Viewed');
  await expect(editor).toHaveValue('Keep this comment draft');
});

for (const applied of [true, false]) {
  test(`Viewed reconciles an uncertain write that ${applied ? 'was' : 'was not'} applied`, async ({ page }) => {
    const state = await install(page);
    await page.goto(path); await viewedReady(page); await expect(box(page)).toBeEnabled();
    await card(page).getByRole('button', { name: 'Expand src/a.txt', exact: true }).click();
    const waiting = gate(); state.readGate = waiting;
    state.writeFailure = { status: 504, code: 'github_timeout', message: 'Timed out' }; state.applyOnFailure = applied;
    await expectViewedWrite(state, files[0].filename, true, () => box(page).check());
    await expect.poll(() => calls(state, 'github.pull.viewed.get').length).toBe(2);
    await expect(box(page)).toBeDisabled();
    waiting.resolve();
    if (applied) await expect(box(page)).toBeEnabled();
    else {
      await expect(card(page).getByText('Waiting for GitHub confirmation', { exact: true })).toBeVisible();
      await expect(box(page)).toBeDisabled();
      await expect(card(page).getByRole('button', { name: 'Retry Viewed', exact: true })).toHaveCount(0);
    }
    await expect(box(page)).toBeChecked();
    await expect(card(page)).not.toHaveClass(/expanded/);
    expect(calls(state, 'github.pull.file.viewed.set')).toHaveLength(1);
    expect(state.states.alice[files[0].filename] ?? 'Unviewed').toBe(applied ? 'Viewed' : 'Unviewed');
  });
}

test('Viewed read errors preserve diff; retry restores status and snapshot changes use Load latest', async ({ page }) => {
  const state = await install(page, { readFailure: { status: 429, code: 'rate_limit', message: 'Try later' } });
  await page.goto(path);
  await expect(page.getByText('Viewed status unavailable', { exact: true })).toBeVisible();
  await card(page).getByRole('button', { name: 'Expand src/a.txt', exact: true }).click();
  await expect(card(page).locator('table')).toBeVisible();
  await page.getByRole('button', { name: 'Retry Viewed sync', exact: true }).click();
  await expect(box(page)).toBeEnabled();
  state.head = 'b'.repeat(40);
  await refresh(page);
  await expect(box(page)).toBeDisabled();
  await expect(page.getByRole('button', { name: 'Load latest', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Load latest', exact: true }).click();
  await expect(box(page)).toBeEnabled();
  await expectViewedWrite(state, files[0].filename, true, () => box(page).check());
  await expect(box(page)).toBeEnabled();
  await expect(box(page)).toBeChecked();
  expect(state.states.alice[files[0].filename]).toBe('Viewed');
});

test('a stale read cannot overwrite a newer write or another account', async ({ page }) => {
  const state = await install(page);
  await page.goto(path); await viewedReady(page); await expect(box(page)).toBeEnabled();
  const staleRead = gate(); state.readGate = staleRead;
  await refresh(page);
  await expect.poll(() => calls(state, 'github.pull.viewed.get').length).toBe(2);
  await expectViewedWrite(state, files[0].filename, true, () => box(page).check()); await expect(box(page)).toBeEnabled();
  await expect(box(page)).toBeChecked();
  expect(state.states.alice[files[0].filename]).toBe('Viewed');
  expect(calls(state, 'github.pull.viewed.get')).toHaveLength(2);
  staleRead.resolve();
  await expect.poll(() => calls(state, 'github.pull.viewed.get').length).toBe(3);
  await expect(box(page)).toBeChecked();
  const oldAccount = gate(); state.readGate = oldAccount;
  await refresh(page); await expect.poll(() => calls(state, 'github.pull.viewed.get').length).toBe(4);
  state.user = 'bob';
  await page.evaluate(() => { dispatchEvent(new Event('pagehide')); dispatchEvent(new Event('pageshow')); });
  await expect.poll(() => calls(state, 'github.pull.viewed.get').length).toBe(5);
  await expect(box(page)).not.toBeChecked();
  oldAccount.resolve();
  await expect(box(page)).not.toBeChecked();
  await expect(page.getByText('0 / 3 files viewed', { exact: true })).toBeVisible();
});

test('anonymous PR exposes sign-in and restores Viewed after login; commits do not show it', async ({ page }) => {
  const state = await install(page, { authenticated: false, states: { alice: { 'src/a.txt': 'Viewed' } } });
  await page.goto(path); await viewedReady(page); await expect(box(page)).toBeEnabled();
  await expect(page.getByRole('button', { name: 'Sign in to sync Viewed' })).toBeVisible();
  expect(calls(state, 'github.pull.viewed.get')).toHaveLength(0);
  state.authenticated = true; await refresh(page);
  await expect(box(page)).toBeChecked();
  for (const route of [`/alice/repo/commit/${head}`, `/alice/repo/pull/42/commits/${head}`]) {
    await page.goto(route);
    await expect(page.getByText('Commit fixture', { exact: true })).toBeVisible();
    await expect(page.locator('.viewed-control')).toHaveCount(0);
    await expect(page.locator('.viewed-progress')).toHaveCount(0);
  }
});

for (const width of [1280, 390]) {
  test(`anonymous Viewed checkbox, label and keyboard open a sign-in dialog without toggling at ${width}px`, async ({ page }) => {
    const state = await install(page, { authenticated: false });
    await page.setViewportSize({ width, height: 650 });
    await page.goto(path);
    await expect(box(page)).toBeEnabled();
    const initialClass = await card(page).getAttribute('class');
    for (const activate of [
      () => box(page).click(),
      () => card(page).locator('.viewed-label > span').first().click(),
      async () => { await box(page).focus(); await page.keyboard.press('Space'); },
    ]) {
      await box(page).scrollIntoViewIfNeeded();
      const position = await pagePosition(page);
      const records = await pendingRecords(page);
      await activate();
      await expectSignInDialog(page, 'Sign in to track viewed files');
      await expectPagePosition(page, position);
      await expect(box(page)).not.toBeChecked();
      await expect(card(page)).toHaveClass(initialClass);
      expect(calls(state, 'github.pull.file.viewed.set')).toHaveLength(0);
      expect(calls(state, 'github.pull.viewed.get')).toHaveLength(0);
      expect(new URL(page.url()).pathname).toBe(path);
      expect(new URL(page.url()).hash).toBe('');
      expect(await pendingRecords(page)).toEqual(records);
      await closeSignInDialog(page);
      await expect(box(page)).toBeFocused();
      await expectPagePosition(page, position);
    }
    state.authenticated = true;
    await refresh(page);
    await expect(page.getByText('0 / 3 files viewed', { exact: true })).toBeVisible();
    await expect(box(page)).not.toBeChecked();
    expect(calls(state, 'github.pull.file.viewed.set')).toHaveLength(0);
  });
}

test('anonymous PR entry points focus the dialog status during a session check', async ({ page }) => {
  const state = await install(page, { authenticated: false });
  await page.goto(path);
  await expect(box(page)).toBeEnabled();
  await card(page).getByRole('button', { name: 'Expand src/a.txt', exact: true }).click();
  await expect(card(page).locator('.line-comment-button').first()).toBeAttached();
  const pending = gate(); state.authGate = pending;
  try {
    await page.evaluate(() => { dispatchEvent(new Event('pagehide')); dispatchEvent(new Event('pageshow')); });
    await expect(page.locator('.discussion-auth')).toHaveText('Checking GitHub session…');
    await box(page).click();
    await expectSignInDialog(page, 'Sign in to track viewed files', true);
    await expect(box(page)).not.toBeChecked();
    await closeSignInDialog(page);
    const button = card(page).locator('.new-line-number .line-comment-button').first();
    await button.focus();
    await page.keyboard.press('Enter');
    await expectSignInDialog(page, 'Sign in to comment', true);
  } finally { pending.resolve(); }
  await expect(signInDialog(page).locator('.review-sign-in-button')).toBeFocused();
  await closeSignInDialog(page);
  expect(calls(state, 'github.pull.file.viewed.set')).toHaveLength(0);
});

test('manual refresh and page restoration retain an expanded viewed file and its inline draft', async ({ page }) => {
  const state = await install(page, { states: { alice: { 'src/a.txt': 'Viewed' } } });
  await page.goto(path); await viewedReady(page); await expect(box(page)).toBeChecked();
  await card(page).getByRole('button', { name: 'Expand src/a.txt', exact: true }).click();
  const gutter = card(page).locator('.review-gutter.new-line-number').filter({ has: page.locator('.line-number-value', { hasText: /^2$/ }) });
  await clickLineCommentButton(gutter.getByRole('button', { name: 'Comment on line 2', exact: true }));
  await page.locator('textarea').fill('Inline Viewed draft');
  await page.getByRole('button', { name: 'Refresh', exact: true }).click();
  await expect.poll(() => calls(state, 'github.pull.viewed.get').length).toBe(2);
  await expect(card(page)).toHaveClass(/expanded/);
  await expect(page.locator('textarea')).toHaveValue('Inline Viewed draft');
  await page.evaluate(() => { dispatchEvent(new Event('pagehide')); dispatchEvent(new Event('pageshow')); });
  await expect.poll(() => calls(state, 'github.pull.viewed.get').length).toBe(3);
  await expect(card(page)).toHaveClass(/expanded/);
  await expect(box(page)).toBeChecked();
  await expectViewedWrite(state, files[0].filename, false, () => box(page).uncheck());
  await expect(box(page)).toBeEnabled(); await expect(box(page)).not.toBeChecked();
  expect(state.states.alice[files[0].filename]).toBe('Unviewed');
  await expectViewedWrite(state, files[0].filename, true, () => box(page).check());
  await expect(box(page)).toBeEnabled(); await expect(box(page)).toBeChecked();
  expect(state.states.alice[files[0].filename]).toBe('Viewed');
  await expect(card(page)).not.toHaveClass(/expanded/);
  await expect(page.locator('textarea')).toHaveValue('Inline Viewed draft');
  await card(page).getByRole('button', { name: 'Expand src/a.txt', exact: true }).click();
  await expect(page.locator('textarea')).toHaveValue('Inline Viewed draft');
});

const mbtFiles = ['src/main.mbt', 'src/second.mbt'].map(filename => ({
  ...files[0], filename,
  patch: '@@ -1,3 +1,3 @@\n fn answer() -> Int {\n-  1\n+  2\n }',
}));
const mbtSource = ref => `fn answer() -> Int {\n  ${ref === head ? 2 : 1}\n}\n`;
const mbtBox = (page, index = 0) => page.getByRole('checkbox', { name: `Viewed ${mbtFiles[index].filename}`, exact: true });
const viewedMbtStates = () => ({ alice: Object.fromEntries(mbtFiles.map(file => [file.filename, 'Viewed'])) });
async function installMbt(page, options = {}) {
  return install(page, {
    files: mbtFiles, source: mbtSource, states: viewedMbtStates(),
    reviewComments: [{
      id: '20', body: 'Existing inline comment', html_url: 'https://github.com/comment/20',
      created_at: '2026-09-11T08:00:00Z', user: { login: 'alice' },
      path: mbtFiles[0].filename, line: 2, original_line: 2, side: 'RIGHT', position: 3, commit_id: head,
    }],
    ...options,
  });
}

for (const anonymous of [false, true]) test(`SPA restores user layout before delayed Viewed sync${anonymous ? ' and first sign-in' : ''}`, async ({ page }) => {
  const state = await installMbt(page, { authenticated: !anonymous });
  await page.goto(path);
  if (anonymous) {
    await expect(card(page).locator('.diff-scroll table')).toBeVisible();
    await card(page, 1).locator('.file-toggle').click();
  } else {
    await expect(mbtBox(page)).toBeChecked();
    await card(page).locator('.file-toggle').click();
  }
  await expect(card(page)).toHaveClass(/expanded/);
  await expect(card(page, 1)).not.toHaveClass(/expanded/);
  await settleRegions(page);
  const position = await page.evaluate(() => {
    document.querySelector('#moondiff-file-0 .file-toggle').focus({ preventScroll: true });
    scrollTo(0, 50);
    return scrollY;
  });
  const waiting = gate(); state.readGate = waiting;
  await page.locator('a.workspace-home').evaluate(link => link.click());
  await expect(page).toHaveURL(/\/$/);
  await page.goBack();
  await expect(card(page)).toHaveClass(/expanded/);
  await expect(card(page, 1)).not.toHaveClass(/expanded/);
  await settleRegions(page);
  await expect(card(page).locator('.file-toggle')).toBeFocused();
  await expect.poll(() => page.evaluate(() => scrollY)).toBe(position);
  if (anonymous) { state.authenticated = true; await refresh(page); }
  await expect(page.getByText('Loading Viewed status…', { exact: true })).toBeVisible();
  waiting.resolve();
  await expect(mbtBox(page)).toBeChecked();
  await expect(page.getByText('Loading Viewed status…', { exact: true })).toHaveCount(0);
  await expect(card(page)).toHaveClass(/expanded/);
  await expect(card(page, 1)).not.toHaveClass(/expanded/);
  expect(calls(state, 'github.pull.file.viewed.set')).toHaveLength(0);
});
async function openMbtDraft(page, kind) {
  if (kind === 'reply') {
    await card(page).getByRole('button', { name: 'Reply', exact: true }).click();
  } else {
    const gutter = card(page).locator('.review-gutter.new-line-number').filter({ has: page.locator('.line-number-value', { hasText: /^2$/ }) });
    await clickLineCommentButton(gutter.getByRole('button', { name: 'Comment on line 2', exact: true }));
  }
  return card(page).locator('textarea');
}
async function captureDraft(editor, body) {
  await expect(editor).toBeVisible();
  if (body) await editor.fill(body);
  await editor.focus();
  const selection = await editor.evaluate((el, filled) => {
    el.setSelectionRange(filled ? 2 : 0, filled ? 7 : 0, 'backward');
    return [el.selectionStart, el.selectionEnd, el.selectionDirection];
  }, !!body);
  const original = await editor.elementHandle();
  const placement = await editor.evaluate(el => {
    const bounds = el.getBoundingClientRect(), table = el.closest('table').getBoundingClientRect();
    return [bounds.x - table.x, bounds.y - table.y];
  });
  return async () => {
    await expect(editor).toBeVisible();
    await expect(editor).toHaveValue(body);
    await expect(editor).toBeFocused();
    expect(await original.evaluate(el => el.isConnected && el === document.activeElement)).toBe(true);
    expect(await editor.evaluate(el => [el.selectionStart, el.selectionEnd, el.selectionDirection])).toEqual(selection);
    expect(await editor.evaluate(el => {
      const bounds = el.getBoundingClientRect(), table = el.closest('table').getBoundingClientRect();
      return [bounds.x - table.x, bounds.y - table.y];
    })).toEqual(placement);
  };
}

for (const layout of ['Split', 'Unified']) {
  for (const kind of ['empty inline', 'inline', 'reply']) {
    test(`delayed first Viewed sync preserves ${kind} editor and code in ${layout}`, async ({ page }) => {
      const waiting = gate();
      const state = await installMbt(page, { readGate: waiting });
      await page.goto(path);
      await expect(page.getByText('Loading Viewed status…', { exact: true })).toBeVisible();
      await page.getByRole('button', { name: layout, exact: true }).click();
      // Both .mbt files start expanded, without any file-toggle interaction.
      await expect(card(page).locator('table')).toBeVisible();
      await expect(card(page, 1).locator('table')).toBeVisible();
      const editor = await openMbtDraft(page, kind);
      const checkDraft = await captureDraft(editor, kind === 'empty inline' ? '' : 'Keep this draft');
      const code = await card(page).locator('table').elementHandle();
      await expect.poll(() => calls(state, 'github.pull.viewed.get').length).toBe(1);
      waiting.resolve();
      await expect(mbtBox(page)).toBeChecked();
      await expect(card(page)).toHaveClass(/expanded/);
      await expect(card(page, 1)).not.toHaveClass(/expanded/);
      await expect(page.getByText('2 / 2 files viewed', { exact: true })).toBeVisible();
      expect(await code.evaluate(el => el.isConnected)).toBe(true);
      await checkDraft();
    });
  }
}

for (const kind of ['inline', 'reply']) {
  for (const finish of ['cancel', 'post']) {
    test(`delayed first Viewed sync remembers ${kind} interaction after ${finish}`, async ({ page }) => {
      const waiting = gate();
      const state = await installMbt(page, { readGate: waiting });
      await page.goto(path);
      await expect(page.getByText('Loading Viewed status…', { exact: true })).toBeVisible();
      const editor = await openMbtDraft(page, kind);
      if (finish === 'post') await editor.fill('Completed draft');
      await card(page).getByRole('button', { name: finish === 'post' ? 'Post comment' : 'Cancel', exact: true }).click();
      await expect(page.locator('textarea')).toHaveCount(0);
      if (finish === 'post') await expect(card(page).getByText('Completed draft', { exact: true })).toBeVisible();
      await expect.poll(() => calls(state, 'github.pull.viewed.get').length).toBe(1);
      waiting.resolve();
      await expect(mbtBox(page)).toBeChecked();
      await expect(card(page)).toHaveClass(/expanded/);
      await expect(card(page, 1)).not.toHaveClass(/expanded/);
    });
  }

  test(`retrying the failed first Viewed sync keeps a later ${kind} draft`, async ({ page }) => {
    const state = await installMbt(page, { readFailure: { status: 429, code: 'rate_limit', message: 'Try later' } });
    await page.goto(path);
    await expect(page.getByText('Viewed status unavailable', { exact: true })).toBeVisible();
    const waiting = gate(); state.readGate = waiting;
    await page.getByRole('button', { name: 'Retry Viewed sync', exact: true }).click();
    await expect.poll(() => calls(state, 'github.pull.viewed.get').length).toBe(2);
    const editor = await openMbtDraft(page, kind);
    const checkDraft = await captureDraft(editor, 'Draft after read failed');
    waiting.resolve();
    await expect(mbtBox(page)).toBeChecked();
    await expect(card(page)).toHaveClass(/expanded/);
    await expect(card(page, 1)).not.toHaveClass(/expanded/);
    await checkDraft();
  });

  for (const failure of ['clear', 'uncertain']) {
    test(`unmark Viewed then start ${kind} preserves editor after ${failure} failure`, async ({ page }) => {
      const state = await installMbt(page);
      await page.goto(path); await viewedReady(page); await expect(mbtBox(page)).toBeChecked();
      await expect(card(page)).not.toHaveClass(/expanded/);
      const waiting = gate();
      state.writeFailure = { status: failure === 'clear' ? 403 : 504, code: failure === 'clear' ? 'permission_denied' : 'github_timeout', message: 'Failed' };
      if (failure === 'clear') state.writeGate = waiting;
      else state.readGate = waiting;
      await expectViewedWrite(state, mbtFiles[0].filename, false, () => mbtBox(page).uncheck());
      await expect(mbtBox(page)).toBeDisabled();
      if (failure === 'uncertain') await expect.poll(() => calls(state, 'github.pull.viewed.get').length).toBe(2);
      const editor = await openMbtDraft(page, kind);
      const checkDraft = await captureDraft(editor, 'Keep after unmark failed');
      waiting.resolve();
      if (failure === 'uncertain') {
        await waitingForConfirmation(page);
        await expect(mbtBox(page)).toBeDisabled();
        await expect(mbtBox(page)).not.toBeChecked();
        await expect(card(page).getByRole('button', { name: 'Retry Viewed', exact: true })).toHaveCount(0);
      } else {
        await expect(mbtBox(page)).toBeEnabled();
        await expect(mbtBox(page)).toBeChecked();
        await expect(card(page).getByRole('button', { name: 'Retry Viewed', exact: true })).toBeVisible();
      }
      await expect(card(page)).toHaveClass(/expanded/);
      await checkDraft();
    });
  }
}

test('first Viewed sync preserves section changes and content retries only on the touched file', async ({ page }) => {
  // Comment avatars are incidental to this fixture and must not outlive its reload.
  await page.route('https://github.com/*.png?size=64', route => route.abort());
  for (const action of ['section', 'retry']) {
    const waiting = gate();
    await page.unroute('**/api/**');
    const state = await installMbt(page, { readGate: waiting, ...(action === 'retry' ? { contentFailure: { status: 500, code: 'internal_error', message: 'Content failed' } } : {}) });
    await page.goto(path);
    await expect(page.getByText('Loading Viewed status…', { exact: true })).toBeVisible();
    if (action === 'section') {
      const section = card(page).locator('details.semantic-section');
      await section.locator('summary').click();
      await expect(section).not.toHaveAttribute('open', '');
      await section.locator('summary').click();
      await expect(section).toHaveAttribute('open', '');
    } else {
      await card(page).getByRole('button', { name: 'Retry file', exact: true }).click();
    }
    await expect(card(page).locator('table')).toBeVisible();
    await expect.poll(() => calls(state, 'github.pull.viewed.get').length).toBe(1);
    waiting.resolve();
    await expect(mbtBox(page)).toBeChecked();
    await expect(card(page)).toHaveClass(/expanded/);
    await expect(card(page).locator('table')).toBeVisible();
    await expect(card(page, 1)).not.toHaveClass(/expanded/);
  }
});

test('anonymous section interaction survives first login without protecting other files', async ({ page }) => {
  const state = await installMbt(page, { authenticated: false });
  await page.goto(path);
  const section = card(page).locator('details.semantic-section');
  await section.locator('summary').click();
  await section.locator('summary').click();
  const waiting = gate(); state.readGate = waiting; state.authenticated = true;
  await refresh(page);
  await expect.poll(() => calls(state, 'github.pull.viewed.get').length).toBe(1);
  waiting.resolve();
  await expect(mbtBox(page)).toBeChecked();
  await expect(card(page)).toHaveClass(/expanded/);
  await expect(card(page, 1)).not.toHaveClass(/expanded/);
});

const pendingRecords = page => page.evaluate(() => Object.keys(sessionStorage)
  .filter(key => key.startsWith('moondiff.viewed.pending.v1:'))
  .map(key => JSON.parse(sessionStorage.getItem(key))));
async function viewedReady(page) {
  if (clockFor(page)) await waitForState(page, state =>
    state.application?.viewed.ready && !state.application.viewed.loading, 'initial Viewed state accepted');
}
const waitingForConfirmation = async page => {
  const label = card(page).getByText('Waiting for GitHub confirmation', { exact: true });
  if (clockFor(page)) await clockFor(page).until(() => label.isVisible(), 'Viewed confirmation pending');
  await expect(label).toBeVisible();
};
const readFinished = async page => {
  if (clockFor(page)) await waitForState(page, state =>
    state.application?.viewed.ready && !state.application.viewed.loading, 'Viewed read accepted');
  await expect(page.locator('.viewed-refreshing')).toHaveCount(0);
};
// Cached snapshots revalidate through PullGet rather than PullSnapshotGet.
const snapshotLoads = page => page.evaluate(() => globalThis.__moondiffMetrics.prefetch?.visits ?? 0);
const controlViewedTimers = page => installClock(page);
const viewedTimers = new WeakMap();
async function waitForViewedTimer(page, ms) {
  const current = await page.evaluate(() => __moondiffTestState().application);
  viewedTimers.set(page, await clockFor(page).timer(ms, { predicate: timer =>
    timer.context.generation === current.generation && timer.context.viewedReadSerial === current.viewed.readSerial }));
}
async function advanceViewed(page, ms) {
  const clock = clockFor(page), timer = viewedTimers.get(page);
  if (timer && ms === timer.ms - 1) return clock.before(timer);
  const after = requestsFor(page).checkpoint();
  if (timer && (ms === timer.ms || ms === 1)) {
    await clock.fire(timer);
    await clock.until(() => requestsFor(page).matching({ after, operation: 'PullViewedGet', phase: 'received' }).length,
      'Viewed confirmation response received');
    await readFinished(page);
    viewedTimers.delete(page);
  } else {
    await clock.jump(ms);
    await settleRegions(page);
  }
}

for (const viewed of [true, false]) {
  test(`timed-out ${viewed ? 'mark' : 'unmark'} keeps waiting through old reads and automatically confirms one late mutation`, async ({ page }) => {
    await controlViewedTimers(page);
    if (viewed) await page.setViewportSize({ width: 390, height: 850 });
    const state = await install(page, { states: { alice: { 'src/a.txt': viewed ? 'Unviewed' : 'Viewed' } } });
    await page.goto(path); await viewedReady(page); await expect(box(page)).toBeEnabled();
    state.writeFailure = { status: 504, code: 'github_timeout', message: 'Timed out' };
    await expectViewedWrite(state, files[0].filename, viewed, () => box(page).setChecked(viewed));
    await waitingForConfirmation(page); await readFinished(page);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    const [record] = await pendingRecords(page);
    expect(record).toMatchObject({ user_id: '1', owner: 'alice', repo: 'repo', number: '42', path: files[0].filename, viewed, base_sha: base, head_sha: head });
    expect(Object.keys(record).sort()).toEqual(['id', 'user_id', 'owner', 'repo', 'number', 'path', 'viewed', 'base_sha', 'head_sha'].sort());
    for (const [i, delay] of [2000, 4000].entries()) {
      await waitForViewedTimer(page, delay);
      await advanceViewed(page, delay);
      await expect.poll(() => calls(state, 'github.pull.viewed.get').length).toBe(i + 3);
      await readFinished(page);
      await expect(box(page)).toBeDisabled();
      await expect(box(page)).toBeChecked({ checked: viewed });
      await expect(box(page, 1)).toBeEnabled();
      expect(await pendingRecords(page)).toEqual([record]);
    }
    // GitHub finishes the original write after the timeout and multiple old reads.
    state.states.alice[files[0].filename] = viewed ? 'Viewed' : 'Unviewed';
    await waitForViewedTimer(page, 8000);
    await advanceViewed(page, 8000);
    await expect(box(page)).toBeEnabled();
    await expect(box(page)).toBeChecked({ checked: viewed });
    expect(await pendingRecords(page)).toHaveLength(0);
    expect(calls(state, 'github.pull.file.viewed.set')).toHaveLength(1);
  });
}

test('confirmation retries have a finite schedule, tolerate read errors and restart manually', async ({ page }) => {
  await controlViewedTimers(page);
  const state = await install(page);
  await page.goto(path); await viewedReady(page); await expect(box(page)).toBeEnabled();
  state.writeFailure = { status: 504, code: 'github_timeout', message: 'Timed out' };
  state.readFailure = { status: 503, code: 'unavailable', message: 'Read unavailable' };
  await expectViewedWrite(state, files[0].filename, true, () => box(page).check()); await waitingForConfirmation(page); await readFinished(page);
  let count = 2;
  for (const delay of [2000, 4000, 8000, 16000, 30000, 30000]) {
    await waitForViewedTimer(page, delay);
    await advanceViewed(page, delay - 1);
    expect(calls(state, 'github.pull.viewed.get')).toHaveLength(count);
    await advanceViewed(page, 1);
    await expect.poll(() => calls(state, 'github.pull.viewed.get').length).toBe(++count);
    await readFinished(page);
    await expect(box(page)).toBeDisabled();
  }
  await advanceViewed(page, 86400000);
  expect(calls(state, 'github.pull.viewed.get')).toHaveLength(8);
  expect(await pendingRecords(page)).toHaveLength(1);
  await expect(page.getByText(/^Confirmation is paused/)).toBeVisible();
  await page.getByRole('button', { name: 'Recheck Viewed', exact: true }).click();
  await clockFor(page).until(() => calls(state, 'github.pull.viewed.get').length === 9, 'manual Viewed recheck');
  await expect.poll(() => calls(state, 'github.pull.viewed.get').length).toBe(9);
  await readFinished(page);
  state.states.alice[files[0].filename] = 'Viewed';
  await waitForViewedTimer(page, 2000);
  await advanceViewed(page, 2000);
  await expect.poll(() => calls(state, 'github.pull.viewed.get').length).toBe(10);
  await readFinished(page);
  await expect(box(page)).toBeEnabled();
  await expect(box(page)).toBeChecked();
  expect(state.states.alice[files[0].filename]).toBe('Viewed');
  expect(calls(state, 'github.pull.file.viewed.set')).toHaveLength(1);
});

test('rate limits pause confirmation and page restoration opens a new round', async ({ page }) => {
  await controlViewedTimers(page);
  const state = await install(page);
  await page.goto(path); await viewedReady(page); await expect(box(page)).toBeEnabled();
  state.writeFailure = { status: 504, code: 'github_timeout', message: 'Timed out' };
  state.readFailure = { status: 429, code: 'rate_limit', message: 'Try later' };
  await expectViewedWrite(state, files[0].filename, true, () => box(page).check()); await waitingForConfirmation(page); await readFinished(page);
  await advanceViewed(page, 120000);
  expect(calls(state, 'github.pull.viewed.get')).toHaveLength(2);
  await refresh(page);
  if (clockFor(page)) await clockFor(page).until(() => calls(state, 'github.pull.viewed.get').length === 3, 'restored Viewed recheck');
  await expect.poll(() => calls(state, 'github.pull.viewed.get').length).toBe(3);
  await readFinished(page);
  state.states.alice[files[0].filename] = 'Viewed';
  await waitForViewedTimer(page, 2000);
  await advanceViewed(page, 2000);
  await expect(box(page)).toBeEnabled();
  await expect(box(page)).toBeChecked();
  expect(state.states.alice[files[0].filename]).toBe('Viewed');
  expect(calls(state, 'github.pull.file.viewed.set')).toHaveLength(1);
});

test('reload restores pending changes by path after reordering and isolates login accounts', async ({ page }) => {
  const state = await install(page);
  await page.goto(path); await viewedReady(page); await expect(box(page)).toBeEnabled();
  state.writeFailure = { status: 504, code: 'github_timeout', message: 'Timed out' };
  await expectViewedWrite(state, files[0].filename, true, () => box(page).check()); await waitingForConfirmation(page); await readFinished(page);
  const [record] = await pendingRecords(page);
  state.files = [files[2], files[1], files[0]];
  state.authenticated = false;
  await page.reload();
  await expect(box(page)).toBeEnabled();
  await box(page).click();
  await expectSignInDialog(page, 'Sign in to track viewed files');
  await closeSignInDialog(page);
  await expect(box(page)).not.toBeChecked();
  expect(await pendingRecords(page)).toEqual([record]);
  state.authenticated = true; state.user = 'bob';
  await refresh(page);
  await expect(box(page)).toBeEnabled(); await expect(box(page)).not.toBeChecked();
  expect(await pendingRecords(page)).toEqual([record]);
  state.user = 'alice'; await refresh(page);
  await expect(box(page)).toBeDisabled(); await expect(box(page)).toBeChecked();
  await expect(card(page, 2).getByText('Waiting for GitHub confirmation', { exact: true })).toBeVisible();
  await expect(card(page, 0).getByRole('checkbox')).toBeEnabled();
  expect(await pendingRecords(page)).toEqual([record]);
  state.states.alice[files[0].filename] = 'Viewed';
  await page.getByRole('button', { name: 'Recheck Viewed', exact: true }).click();
  await expect(box(page)).toBeEnabled();
  await expect(box(page)).toBeChecked();
  expect(state.states.alice[files[0].filename]).toBe('Viewed');
  expect(await pendingRecords(page)).toHaveLength(0);
  expect(calls(state, 'github.pull.file.viewed.set')).toHaveLength(1);
});

async function holdUpdatedChecks(page, state) {
  await expect(page.getByRole('button', { name: 'Refresh', exact: true })).toBeEnabled();
  await expect(page.getByRole('button', { name: 'Reload merge status', exact: true })).toBeEnabled();
  const viewed = gate(), merge = gate(), metadata = gate();
  const readCount = calls(state, 'github.pull.viewed.get').length;
  const mergeCount = calls(state, 'github.pull.merge.status').length;
  const metadataCount = calls(state, 'github.pull.get').length;
  // Comments also validate metadata on reactivation. Hold that independent
  // source of staleness so each ordered case proves which reducer ran first.
  state.readGate = viewed; state.mergeGate = merge; state.metadataGate = metadata;
  state.head = 'b'.repeat(40);
  state.title = 'Latest Viewed fixture';
  await refresh(page);
  if (clockFor(page)) await clockFor(page).until(() => calls(state, 'github.pull.viewed.get').length === readCount + 1, 'reactivated Viewed read');
  await expect.poll(() => calls(state, 'github.pull.viewed.get').length).toBe(readCount + 1);
  await expect.poll(() => calls(state, 'github.pull.merge.status').length).toBe(mergeCount + 1);
  await expect.poll(() => calls(state, 'github.pull.get').length).toBe(metadataCount + 1);
  return { viewed, merge, metadata };
}

for (const first of ['Merge', 'Viewed']) {
  test(`Load latest retains an unconfirmed operation without restoring its old expansion: ${first} first`, async ({ page }) => {
    await controlViewedTimers(page);
    const state = await installMbt(page);
    await page.goto(path); await viewedReady(page); await expect(mbtBox(page)).toBeEnabled();
    state.writeFailure = { status: 504, code: 'github_timeout', message: 'Timed out' };
    await expectViewedWrite(state, mbtFiles[0].filename, false, () => mbtBox(page).uncheck()); await waitingForConfirmation(page); await readFinished(page);
    await card(page).getByRole('button', { name: 'Collapse src/main.mbt', exact: true }).click();
    const [record] = await pendingRecords(page);
    const held = await holdUpdatedChecks(page, state);
    try {
      held[first === 'Merge' ? 'merge' : 'viewed'].resolve();
      await clockFor(page).until(() => page.getByRole('button', { name: 'Load latest', exact: true }).isVisible(), 'updated snapshot detected');
      await expect(page.getByRole('button', { name: 'Load latest', exact: true })).toBeVisible();
      // The UI proves the first response has been reduced before releasing the second.
      if (first === 'Merge') await expect(page.getByRole('button', { name: 'Recheck Viewed', exact: true })).toBeDisabled();
      else await expect(page.getByRole('button', { name: 'Recheck Viewed', exact: true })).toHaveCount(0);
      held[first === 'Merge' ? 'viewed' : 'merge'].resolve();
      await readFinished(page);
      const snapshots = await snapshotLoads(page);
      await clockFor(page).until(() => page.getByRole('button', { name: 'Load latest', exact: true }).isVisible(), 'updated snapshot detected');
      await page.getByRole('button', { name: 'Load latest', exact: true }).click();
      await clockFor(page).until(() => page.getByText('Latest Viewed fixture', { exact: true }).isVisible(), 'latest snapshot committed');
      await expect(page.getByText('Latest Viewed fixture', { exact: true })).toBeVisible();
      await waitingForConfirmation(page); await readFinished(page);
      expect(await snapshotLoads(page)).toBe(snapshots + 1);
      await expect(mbtBox(page)).toBeDisabled(); await expect(mbtBox(page)).not.toBeChecked();
      await expect(card(page)).toHaveClass(/expanded/);
      expect(await pendingRecords(page)).toEqual([record]);
      state.states.alice[mbtFiles[0].filename] = 'Unviewed';
      await page.getByRole('button', { name: 'Recheck Viewed', exact: true }).click();
      await clockFor(page).until(() => mbtBox(page).isEnabled(), 'Viewed confirmed');
      await expect(mbtBox(page)).toBeEnabled();
      await expect(mbtBox(page)).not.toBeChecked();
      expect(state.states.alice[mbtFiles[0].filename]).toBe('Unviewed');
      expect(calls(state, 'github.pull.file.viewed.set')).toHaveLength(1);
    } finally { held.merge.resolve(); held.viewed.resolve(); held.metadata.resolve(); }
  });
}

test('one early Load latest click waits for Viewed confirmation and then replaces once', async ({ page }) => {
  await controlViewedTimers(page);
  const state = await installMbt(page);
  await page.goto(path); await viewedReady(page); await expect(mbtBox(page)).toBeEnabled();
  state.writeFailure = { status: 504, code: 'github_timeout', message: 'Timed out' };
  await expectViewedWrite(state, mbtFiles[0].filename, false, () => mbtBox(page).uncheck()); await waitingForConfirmation(page); await readFinished(page);
  await card(page).getByRole('button', { name: 'Collapse src/main.mbt', exact: true }).click();
  const [record] = await pendingRecords(page);
  const held = await holdUpdatedChecks(page, state);
  try {
    held.merge.resolve();
    const latest = page.getByRole('button', { name: 'Load latest', exact: true });
    await clockFor(page).until(() => latest.isVisible(), 'updated snapshot detected');
    await expect(latest).toBeVisible();
    await expect(page.getByRole('button', { name: 'Recheck Viewed', exact: true })).toBeDisabled();
    const snapshots = await snapshotLoads(page);
    const reads = calls(state, 'github.pull.viewed.get').length;
    await latest.click(); await settleRegions(page);
    await expect(page.getByText('Viewed fixture', { exact: true })).toBeVisible();
    await expect(card(page)).not.toHaveClass(/expanded/);
    expect(await pendingRecords(page)).toEqual([record]);
    expect(await snapshotLoads(page)).toBe(snapshots);
    expect(calls(state, 'github.pull.viewed.get')).toHaveLength(reads);
    held.viewed.resolve();
    await clockFor(page).until(() => page.getByText('Latest Viewed fixture', { exact: true }).isVisible(), 'latest snapshot committed');
      await expect(page.getByText('Latest Viewed fixture', { exact: true })).toBeVisible();
    await waitingForConfirmation(page); await readFinished(page);
    await expect(card(page)).toHaveClass(/expanded/);
    expect(await pendingRecords(page)).toEqual([record]);
    expect(await snapshotLoads(page)).toBe(snapshots + 1);
    expect(calls(state, 'github.pull.file.viewed.set')).toHaveLength(1);
  } finally { held.merge.resolve(); held.viewed.resolve(); held.metadata.resolve(); }
});

for (const response of ['old value', 'temporary failure', 'rate limit']) {
  test(`waiting Load latest survives Viewed ${response} and resumes after recheck`, async ({ page }) => {
    await controlViewedTimers(page);
    const state = await installMbt(page);
    await page.goto(path); await viewedReady(page); await expect(mbtBox(page)).toBeEnabled();
    state.writeFailure = { status: 504, code: 'github_timeout', message: 'Timed out' };
    await expectViewedWrite(state, mbtFiles[0].filename, false, () => mbtBox(page).uncheck()); await waitingForConfirmation(page); await readFinished(page);
    const [record] = await pendingRecords(page);
    state.readVersion = { base_sha: base, head_sha: head };
    if (response !== 'old value') state.readFailure = response === 'rate limit'
      ? { status: 429, code: 'rate_limit', message: 'Wait before confirming Viewed' }
      : { status: 503, code: 'unavailable', message: 'Confirmation temporarily unavailable' };
    const held = await holdUpdatedChecks(page, state);
    try {
      held.merge.resolve();
      await clockFor(page).until(() => page.getByRole('button', { name: 'Load latest', exact: true }).isVisible(), 'updated snapshot detected');
      await page.getByRole('button', { name: 'Load latest', exact: true }).click();
      const snapshots = await snapshotLoads(page);
      held.viewed.resolve(); await readFinished(page);
      const recheck = page.getByRole('button', { name: 'Recheck Viewed', exact: true });
      await expect(recheck).toBeEnabled();
      await expect(page.getByText('Viewed fixture', { exact: true })).toBeVisible();
      await expect(mbtBox(page)).toBeDisabled(); await expect(mbtBox(page)).not.toBeChecked();
      await expect(mbtBox(page, 1)).toBeDisabled();
      expect(await pendingRecords(page)).toEqual([record]);
      expect(await snapshotLoads(page)).toBe(snapshots);
      if (response !== 'old value') await expect(page.locator('.viewed-error')).toContainText(
        response === 'rate limit' ? 'GitHub API rate limit exceeded' : 'Confirmation temporarily unavailable',
      );
      const reads = calls(state, 'github.pull.viewed.get').length;
      if (response === 'rate limit') {
        await advanceViewed(page, 120000);
        expect(calls(state, 'github.pull.viewed.get')).toHaveLength(reads);
        await expect(page.getByText(/^Confirmation is paused/)).toBeVisible();
      } else {
        state.readVersion = { base_sha: base, head_sha: head };
        await waitForViewedTimer(page, 2000); await advanceViewed(page, 2000);
        await expect.poll(() => calls(state, 'github.pull.viewed.get').length).toBe(reads + 1);
        await readFinished(page);
        await waitForViewedTimer(page, 4000);
        expect(await pendingRecords(page)).toEqual([record]);
        expect(await snapshotLoads(page)).toBe(snapshots);
      }
      await recheck.click();
      await clockFor(page).until(() => page.getByText('Latest Viewed fixture', { exact: true }).isVisible(), 'latest snapshot committed');
      await expect(page.getByText('Latest Viewed fixture', { exact: true })).toBeVisible();
      await waitingForConfirmation(page); await readFinished(page);
      expect(await snapshotLoads(page)).toBe(snapshots + 1);
      expect(await pendingRecords(page)).toEqual([record]);
      state.states.alice[mbtFiles[0].filename] = 'Unviewed';
      await recheck.click(); await clockFor(page).until(() => mbtBox(page).isEnabled(), 'Viewed confirmed'); await expect(mbtBox(page)).toBeEnabled();
      expect(await pendingRecords(page)).toHaveLength(0);
      expect(calls(state, 'github.pull.file.viewed.set')).toHaveLength(1);
    } finally { held.merge.resolve(); held.viewed.resolve(); held.metadata.resolve(); }
  });
}

test('session storage failure sends no mutation and preserves draft selection and expansion', async ({ page }) => {
  const state = await installMbt(page);
  await page.goto(path); await viewedReady(page); await expect(mbtBox(page)).toBeEnabled();
  await card(page).getByRole('button', { name: 'Expand src/main.mbt', exact: true }).click();
  const editor = await openMbtDraft(page, 'inline');
  const checkDraft = await captureDraft(editor, 'No storage draft');
  await page.evaluate(() => {
    const put = Storage.prototype.setItem;
    Storage.prototype.setItem = function(key, value) {
      if (key.startsWith('moondiff.viewed.pending.v1:')) throw new DOMException('Full', 'QuotaExceededError');
      return put.call(this, key, value);
    };
  });
  // Dispatch without moving focus out of the editor.
  await mbtBox(page).evaluate(el => el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true })));
  await expect(card(page).getByText(/Cannot save this Viewed change/)).toBeVisible();
  await expect(mbtBox(page)).toBeEnabled(); await expect(mbtBox(page)).toBeChecked();
  await expect(card(page)).toHaveClass(/expanded/);
  await checkDraft();
  expect(calls(state, 'github.pull.file.viewed.set')).toHaveLength(0);
  expect(await pendingRecords(page)).toHaveLength(0);
});

test('late completion cannot remove a newer pending operation after reload', async ({ page }) => {
  const state = await install(page);
  await page.goto(path); await viewedReady(page); await expect(box(page)).toBeEnabled();
  const recorder = requestsFor(page), after = recorder.checkpoint();
  const first = gate(); state.writeGate = first;
  await expectViewedWrite(state, files[0].filename, true, () => box(page).check()); await expect(box(page)).toBeDisabled();
  const [oldRecord] = await pendingRecords(page);
  // The mock applies before replying. Reload confirms its target from storage.
  // Observe pagehide's cancellation before destroying the old document;
  // Chromium can otherwise omit requestfailed for its intercepted fetch.
  await page.evaluate(() => dispatchEvent(new Event('pagehide')));
  await recorder.wait({ after, operation: 'PullFileViewedSet', phase: 'cancelled' });
  await page.reload(); await expect(box(page)).toBeEnabled();
  await expect(box(page)).toBeChecked();
  expect(state.states.alice[files[0].filename]).toBe('Viewed');
  expect(await pendingRecords(page)).toHaveLength(0);
  const second = gate(); state.writeGate = second;
  await expectViewedWrite(state, files[0].filename, false, () => box(page).uncheck()); await expect(box(page)).toBeDisabled();
  const [newRecord] = await pendingRecords(page);
  expect(newRecord.id).not.toBe(oldRecord.id);
  first.resolve();
  await readFinished(page);
  expect(await pendingRecords(page)).toEqual([newRecord]);
  second.resolve(); await expect(box(page)).toBeEnabled();
  await expect(box(page)).not.toBeChecked();
  expect(state.states.alice[files[0].filename]).toBe('Unviewed');
  expect(await pendingRecords(page)).toHaveLength(0);
  expect(calls(state, 'github.pull.file.viewed.set')).toHaveLength(2);
});

test('cleanup compares operation IDs before removing a pending record', async ({ page }) => {
  const state = await install(page);
  await page.goto(path); await viewedReady(page); await expect(box(page)).toBeEnabled();
  const waiting = gate(); state.writeGate = waiting;
  await expectViewedWrite(state, files[0].filename, true, () => box(page).check()); await expect(box(page)).toBeDisabled();
  const [record] = await pendingRecords(page);
  const replacement = { ...record, id: record.id + '-new', viewed: false };
  await page.evaluate(replacement => {
    const key = Object.keys(sessionStorage).find(key => key.startsWith('moondiff.viewed.pending.v1:'));
    sessionStorage.setItem(key, JSON.stringify(replacement));
  }, replacement);
  waiting.resolve(); await expect(box(page)).toBeEnabled();
  await expect(box(page)).toBeChecked();
  expect(state.states.alice[files[0].filename]).toBe('Viewed');
  expect(await pendingRecords(page)).toEqual([replacement]);
  expect(calls(state, 'github.pull.file.viewed.set')).toHaveLength(1);
});

test('failed storage cleanup can be retried without sending another write', async ({ page }) => {
  const state = await install(page);
  await page.goto(path); await viewedReady(page); await expect(box(page)).toBeEnabled();
  await page.evaluate(() => {
    const remove = Storage.prototype.removeItem;
    window.blockViewedCleanup = true;
    Storage.prototype.removeItem = function(key) {
      if (window.blockViewedCleanup && key.startsWith('moondiff.viewed.pending.v1:')) throw new DOMException('Blocked', 'SecurityError');
      return remove.call(this, key);
    };
  });
  await expectViewedWrite(state, files[0].filename, true, () => box(page).check());
  await expect(page.getByText(/Cannot clear a completed Viewed change/)).toBeVisible();
  await expect(box(page)).toBeDisabled();
  expect(await pendingRecords(page)).toHaveLength(1);
  await page.evaluate(() => { window.blockViewedCleanup = false; });
  await page.getByRole('button', { name: 'Retry Viewed sync', exact: true }).click();
  await expect(box(page)).toBeEnabled();
  await expect(box(page)).toBeChecked();
  expect(state.states.alice[files[0].filename]).toBe('Viewed');
  expect(await pendingRecords(page)).toHaveLength(0);
  expect(calls(state, 'github.pull.file.viewed.set')).toHaveLength(1);
});

test('storage read failure on reload keeps controls locked until records can be recovered', async ({ page }) => {
  const state = await install(page);
  await page.goto(path); await viewedReady(page); await expect(box(page)).toBeEnabled();
  state.writeFailure = { status: 504, code: 'github_timeout', message: 'Timed out' };
  await expectViewedWrite(state, files[0].filename, true, () => box(page).check()); await waitingForConfirmation(page); await readFinished(page);
  const [record] = await pendingRecords(page);
  await page.addInitScript(() => {
    const get = Storage.prototype.getItem;
    window.blockViewedRead = true;
    Storage.prototype.getItem = function(key) {
      if (window.blockViewedRead && key.startsWith('moondiff.viewed.pending.v1:')) throw new DOMException('Blocked', 'SecurityError');
      return get.call(this, key);
    };
  });
  await page.reload();
  await expect(page.getByText(/Cannot read pending Viewed changes/)).toBeVisible();
  await expect(box(page)).toBeDisabled();
  await page.evaluate(() => { window.blockViewedRead = false; });
  await page.getByRole('button', { name: 'Retry Viewed sync', exact: true }).click();
  await waitingForConfirmation(page); await readFinished(page);
  await expect(box(page)).toBeDisabled();
  expect(await pendingRecords(page)).toEqual([record]);
  expect(calls(state, 'github.pull.file.viewed.set')).toHaveLength(1);
});


for (const kind of ['inline', 'reply', 'overall']) {
  test(`a delayed identity check retains the ${kind} editor while Viewed waits for confirmation`, async ({ page }) => {
    const state = await installMbt(page);
    await page.goto(path); await viewedReady(page); await expect(mbtBox(page)).toBeEnabled();
    state.writeFailure = { status: 504, code: 'github_timeout', message: 'Timed out' };
    await expectViewedWrite(state, mbtFiles[0].filename, false, () => mbtBox(page).uncheck()); await waitingForConfirmation(page); await readFinished(page);
    if (kind === 'overall') await page.getByRole('button', { name: 'Add overall comment', exact: true }).click();
    else await openMbtDraft(page, kind);
    const editor = page.locator('textarea');
    await editor.fill('Preserve this selection');
    await editor.focus();
    await editor.evaluate(el => el.setSelectionRange(2, 8, 'backward'));
    const original = await editor.elementHandle();
    const authGate = gate(); state.authGate = authGate;
    await page.evaluate(() => { dispatchEvent(new Event('pagehide')); dispatchEvent(new Event('pageshow')); });
    await expect(page.getByText('Checking GitHub session…', { exact: true })).toBeVisible();
    await expect(editor).toBeFocused();
    await expect(editor).toHaveValue('Preserve this selection');
    await expect(page.getByRole('button', { name: 'Post comment', exact: true })).toBeDisabled();
    expect(await original.evaluate(el => el.isConnected && el === document.activeElement)).toBe(true);
    authGate.resolve();
    await expect(page.getByRole('button', { name: 'Account: alice', exact: true })).toBeVisible();
    await waitingForConfirmation(page); await readFinished(page);
    expect(await original.evaluate(el => el.isConnected && el === document.activeElement)).toBe(true);
    expect(await editor.evaluate(el => [el.selectionStart, el.selectionEnd, el.selectionDirection])).toEqual([2, 8, 'backward']);
    expect(calls(state, 'github.pull.file.viewed.set')).toHaveLength(1);
  });
}

for (const width of [1440, 390]) {
  test(`PR title and global navigation skip Viewed files after expansion and sync at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 720 });
    const title = 'Review the complete pull request title while navigating changes across multiple files';
    const navigationFiles = ['first.mbt', 'viewed.mbt', 'last.mbt'].map(filename => ({
      ...mbtFiles[0], filename,
    }));
    const source = ref => ['fn navigate() {', ...Array.from({ length: 45 }, (_, i) => `  ${ref === head ? 'new' : 'old'}_call_${i}()`), '}'].join('\n');
    const state = await install(page, {
      files: navigationFiles, source, title,
      states: { alice: { 'viewed.mbt': 'Viewed' } },
    });
    await page.goto(path);
    const checkbox = index => page.getByRole('checkbox', { name: `Viewed ${navigationFiles[index].filename}`, exact: true });
    const next = page.locator('.change-titlebar').getByRole('button', { name: 'Next change', exact: true });
    const prev = page.locator('.change-titlebar').getByRole('button', { name: 'Previous change', exact: true });
    const landed = async index => {
      await expect.poll(() => card(page, index).evaluate(el => {
        const title = document.querySelector('.change-titlebar').getBoundingClientRect();
        const toolbar = document.querySelector('.hero-workspace').getBoundingClientRect();
        const heading = el.querySelector('.file-heading').getBoundingClientRect();
        const summary = el.querySelector('.semantic-section-title').getBoundingClientRect();
        const row = el.querySelector('[data-change-block-start]').getBoundingClientRect();
        return Math.abs(title.top - toolbar.bottom) <= 1 && Math.abs(heading.top - title.bottom) <= 1 &&
          Math.abs(summary.top - heading.bottom) <= 1 && Math.abs(row.top - summary.bottom - 8) <= 1;
      })).toBe(true);
    };
    await expect(checkbox(1)).toBeChecked();
    await expect(checkbox(0)).toBeEnabled();
    await expect(page.locator('.commit-message-title')).toHaveText(title);
    await card(page, 1).locator('.file-toggle').click();
    await expect(card(page, 1)).toHaveClass(/expanded/);
    await expect(card(page, 1).locator('[data-change-block-start]')).toHaveCount(1);
    // Manual reading inside an excluded file has no current change: Previous
    // and Next should select the nearest eligible blocks on either side.
    await card(page, 1).evaluate(el => el.scrollIntoView());
    await prev.click(); await landed(0);
    await card(page, 1).evaluate(el => el.scrollIntoView());
    await next.click(); await landed(2);
    await page.evaluate(() => window.scrollTo(0, 0));
    await next.click(); await landed(0);
    await next.click(); await landed(2);
    await next.click(); await landed(0);
    await prev.click(); await landed(2);
    await prev.click(); await landed(0);

    // Remote updates keep manually expanded files open, but change eligibility.
    state.states.alice['first.mbt'] = 'Viewed';
    state.states.alice['viewed.mbt'] = 'Unviewed';
    const reads = calls(state, 'github.pull.viewed.get').length;
    await refresh(page);
    await expect.poll(() => calls(state, 'github.pull.viewed.get').length).toBeGreaterThan(reads);
    await expect(checkbox(0)).toBeChecked();
    await expect(checkbox(1)).not.toBeChecked();
    await expect(card(page, 0)).toHaveClass(/expanded/);
    await page.evaluate(() => window.scrollTo(0, 0));
    await next.click(); await landed(1);
    await next.click(); await landed(2);
    await prev.click(); await landed(1);

    await expectViewedWrite(state, 'viewed.mbt', true, () => checkbox(1).check());
    await expect(checkbox(1)).toBeEnabled();
    await card(page, 1).locator('.file-toggle').click();
    await expect(card(page, 1)).toHaveClass(/expanded/);
    await page.evaluate(() => window.scrollTo(0, 0));
    await next.click(); await landed(2);
    await next.click(); await landed(2);
    await prev.click(); await landed(2);
    await card(page, 2).locator('.file-toggle').click();
    await expect(next).toBeDisabled(); await expect(prev).toBeDisabled();
    await expectViewedWrite(state, 'viewed.mbt', false, () => checkbox(1).uncheck());
    await expect(next).toBeEnabled();
    await next.click(); await landed(1);
    await expect(next).toBeFocused();
  });
}


for (const boundary of ['navigation', 'account change']) test(`Viewed confirmation timers stop after ${boundary}`, async ({ page }) => {
  const clock = await controlViewedTimers(page);
  const state = await install(page);
  await page.goto(path); await viewedReady(page);
  state.writeFailure = { status: 504, code: 'github_timeout', message: 'Timed out' };
  await expectViewedWrite(state, files[0].filename, true, () => box(page).check());
  await waitingForConfirmation(page); await readFinished(page);
  await waitForViewedTimer(page, 2000);
  if (boundary === 'navigation') {
    await page.locator('a.workspace-home').click();
    await clock.until(() => page.getByRole('tab').first().isVisible(), 'left Viewed scope');
  } else {
    const before = await page.evaluate(() => __moondiffTestState());
    state.user = 'bob';
    await refresh(page);
    await waitForState(page, state => state.identityEpoch > before.identityEpoch &&
      state.application?.generation > before.application.generation && !state.checking &&
      state.application.viewed.ready && !state.application.viewed.loading, 'new account Viewed state accepted');
    await expect(page.getByRole('button', { name: 'Account: bob', exact: true })).toBeVisible();
    await expect(box(page)).toBeEnabled();
    await expect(page.locator('.viewed-refreshing')).toHaveCount(0);
  }
  const reads = calls(state, 'github.pull.viewed.get').length;
  await clock.jump(120_000);
  await settleRegions(page);
  expect(calls(state, 'github.pull.viewed.get')).toHaveLength(reads);
  expect(calls(state, 'github.pull.file.viewed.set')).toHaveLength(1);
});
