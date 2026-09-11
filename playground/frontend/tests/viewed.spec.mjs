import { expect, test } from '@playwright/test';
import { fixtureRequest, successFixture } from '../../tests/protocol-fixtures.mjs';

const base = '1'.repeat(40), head = 'a'.repeat(40), merge = '2'.repeat(40);
const path = '/alice/repo/pull/42';
const files = ['src/a.txt', 'src/new name.txt', 'README.md'].map((filename, i) => ({
  filename, ...(i === 1 ? { previous_filename: 'src/old.txt' } : {}),
  status: i === 1 ? 'renamed' : 'modified', additions: 1, deletions: 1, changes: 2,
  patch: '@@ -1,3 +1,3 @@\n context\n-old\n+new\n tail',
}));
function gate() { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; }
async function install(page, options = {}) {
  const state = {
    user: 'alice', authenticated: true, base, head, calls: [], states: {},
    readGate: null, writeGate: null, readFailure: null, writeFailure: null, applyOnFailure: false,
    files, reviewComments: [], contentFailure: null,
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
  await page.route('**/api/**', async route => {
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
    if (op === 'github.pull.get') value = { title: 'Viewed fixture', html_url: 'https://github.com/alice/repo/pull/42', base: { sha: state.base, repo: { full_name: 'alice/repo' } }, head: { sha: state.head, repo: { full_name: 'alice/repo' } }, additions: state.files.length, deletions: state.files.length, changed_files: state.files.length };
    else if (op === 'github.compare.get') value = { merge_base_commit: { sha: merge } };
    else if (op === 'github.pull.files') value = state.files;
    else if (op === 'github.commit.get') value = { sha: args.sha, html_url: `https://github.com/alice/repo/commit/${args.sha}`, commit: { message: 'Commit fixture' }, parents: [{ sha: base }], stats: { additions: 3, deletions: 3, total: 6 }, files };
    else if (op === 'github.content.get') {
      const text = state.source ? state.source(args.ref) : `context\n${args.ref === head ? 'new' : 'old'}\ntail`;
      value = { base64: Buffer.from(text).toString('base64'), size: Buffer.byteLength(text) };
      failure = state.contentFailure; state.contentFailure = null;
    }
    else if (op === 'github.comments.list') value = { issue_comments: [], review_comments: state.reviewComments, commit_comments: [] };
    else if (op === 'github.review.comment.create' || op === 'github.review.reply.create') {
      value = {
        id: '22', body: args.body, html_url: 'https://github.com/comment/22', created_at: '2026-09-11T09:00:00Z',
        user: { login: state.user }, path: args.path ?? state.files[0].filename, line: 2, side: 'RIGHT', position: 3,
        commit_id: state.head, ...(op === 'github.review.reply.create' ? { in_reply_to_id: args.comment_id } : {}),
      };
      state.reviewComments.push(value);
    }
    else if (op === 'github.pull.viewed.get') {
      value = { base_sha: state.base, head_sha: state.head, files: state.files.map(file => ({ path: file.filename, state: { $tag: states()[file.filename] || 'Unviewed' } })) };
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
    await route.fulfill({ status: failure?.status || 200, json: failure ? { $tag: 'Failure', error: failure } : successFixture(op, value) }).catch(() => {});
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
  // Native checkbox state and enabled controls can precede the render that sends the write.
  await expect.poll(() => calls(state, 'github.pull.file.viewed.set').length).toBe(before + 1);
  expect(calls(state, 'github.pull.file.viewed.set')[before].args).toMatchObject(expected);
}
const refresh = page => page.evaluate(() => window.reactivate());

for (const width of [1280, 390]) {
  test(`Viewed restores, marks, expands, preserves cache and supports keyboard at ${width}px`, async ({ page }) => {
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
    await page.screenshot({ path: `/tmp/moondiff-viewed-${width}.png`, fullPage: true });
    await page.reload();
    await expect(box(page, 1)).toBeChecked();
    await expect(card(page, 1)).not.toHaveClass(/expanded/);
  });
}

test('Viewed rejects repeated operations, rolls back clear failure and keeps a comment draft', async ({ page }) => {
  const state = await install(page);
  await page.goto(path); await expect(box(page)).toBeEnabled();
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
    await page.goto(path); await expect(box(page)).toBeEnabled();
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
  await page.goto(path); await expect(box(page)).toBeEnabled();
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
  await page.goto(path); await expect(box(page)).toBeDisabled();
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

test('manual refresh and page restoration retain an expanded viewed file and its inline draft', async ({ page }) => {
  const state = await install(page, { states: { alice: { 'src/a.txt': 'Viewed' } } });
  await page.goto(path); await expect(box(page)).toBeChecked();
  await card(page).getByRole('button', { name: 'Expand src/a.txt', exact: true }).click();
  const gutter = card(page).locator('.review-gutter.new-line-number').filter({ has: page.locator('.line-number-value', { hasText: /^2$/ }) });
  await gutter.hover();
  await gutter.getByRole('button', { name: 'Comment on line 2', exact: true }).click();
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
async function openMbtDraft(page, kind) {
  if (kind === 'reply') {
    await card(page).getByRole('button', { name: 'Reply', exact: true }).click();
  } else {
    const gutter = card(page).locator('.review-gutter.new-line-number').filter({ has: page.locator('.line-number-value', { hasText: /^2$/ }) });
    await gutter.hover();
    await gutter.getByRole('button', { name: 'Comment on line 2', exact: true }).click();
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
      await page.goto(path); await expect(mbtBox(page)).toBeChecked();
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
const waitingForConfirmation = page => expect(card(page).getByText('Waiting for GitHub confirmation', { exact: true })).toBeVisible();
const readFinished = page => expect(page.locator('.viewed-refreshing')).toHaveCount(0);
async function controlViewedTimers(page) {
  // Control only the retry delays. Rabbita's animation-frame rendering and
  // transport callbacks keep running, so UI assertions also observe real renders.
  await page.addInitScript(() => {
    const schedule = window.setTimeout, cancel = window.clearTimeout;
    const jobs = new Map();
    let now = 0, sequence = 0;
    window.setTimeout = (callback, delay, ...args) => {
      if (![2000, 4000, 8000, 16000, 30000].includes(delay)) return schedule(callback, delay, ...args);
      const id = --sequence;
      jobs.set(id, { at: now + delay, run: () => callback(...args) });
      return id;
    };
    window.clearTimeout = id => { if (!jobs.delete(id)) cancel(id); };
    window.advanceViewed = delta => {
      now += delta;
      for (const [id, job] of jobs) if (job.at <= now) { jobs.delete(id); job.run(); }
    };
  });
}
const advanceViewed = (page, ms) => page.evaluate(ms => window.advanceViewed(ms), ms);

for (const viewed of [true, false]) {
  test(`timed-out ${viewed ? 'mark' : 'unmark'} keeps waiting through old reads and automatically confirms one late mutation`, async ({ page }) => {
    await controlViewedTimers(page);
    if (viewed) await page.setViewportSize({ width: 390, height: 850 });
    const state = await install(page, { states: { alice: { 'src/a.txt': viewed ? 'Unviewed' : 'Viewed' } } });
    await page.goto(path); await expect(box(page)).toBeEnabled();
    state.writeFailure = { status: 504, code: 'github_timeout', message: 'Timed out' };
    await expectViewedWrite(state, files[0].filename, viewed, () => box(page).setChecked(viewed));
    await waitingForConfirmation(page); await readFinished(page);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    const [record] = await pendingRecords(page);
    expect(record).toMatchObject({ user_id: '1', owner: 'alice', repo: 'repo', number: '42', path: files[0].filename, viewed, base_sha: base, head_sha: head });
    expect(Object.keys(record).sort()).toEqual(['id', 'user_id', 'owner', 'repo', 'number', 'path', 'viewed', 'base_sha', 'head_sha'].sort());
    for (const [i, delay] of [2000, 4000].entries()) {
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
  await page.goto(path); await expect(box(page)).toBeEnabled();
  state.writeFailure = { status: 504, code: 'github_timeout', message: 'Timed out' };
  state.readFailure = { status: 503, code: 'unavailable', message: 'Read unavailable' };
  await expectViewedWrite(state, files[0].filename, true, () => box(page).check()); await waitingForConfirmation(page); await readFinished(page);
  let count = 2;
  for (const delay of [2000, 4000, 8000, 16000, 30000, 30000]) {
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
  await expect.poll(() => calls(state, 'github.pull.viewed.get').length).toBe(9);
  await readFinished(page);
  state.states.alice[files[0].filename] = 'Viewed';
  await advanceViewed(page, 2000);
  await expect(box(page)).toBeEnabled();
  await expect(box(page)).toBeChecked();
  expect(state.states.alice[files[0].filename]).toBe('Viewed');
  expect(calls(state, 'github.pull.file.viewed.set')).toHaveLength(1);
});

test('rate limits pause confirmation and page restoration opens a new round', async ({ page }) => {
  await controlViewedTimers(page);
  const state = await install(page);
  await page.goto(path); await expect(box(page)).toBeEnabled();
  state.writeFailure = { status: 504, code: 'github_timeout', message: 'Timed out' };
  state.readFailure = { status: 429, code: 'rate_limit', message: 'Try later' };
  await expectViewedWrite(state, files[0].filename, true, () => box(page).check()); await waitingForConfirmation(page); await readFinished(page);
  await advanceViewed(page, 120000);
  expect(calls(state, 'github.pull.viewed.get')).toHaveLength(2);
  await refresh(page);
  await expect.poll(() => calls(state, 'github.pull.viewed.get').length).toBe(3);
  await readFinished(page);
  state.states.alice[files[0].filename] = 'Viewed';
  await advanceViewed(page, 2000);
  await expect(box(page)).toBeEnabled();
  await expect(box(page)).toBeChecked();
  expect(state.states.alice[files[0].filename]).toBe('Viewed');
  expect(calls(state, 'github.pull.file.viewed.set')).toHaveLength(1);
});

test('reload restores pending changes by path after reordering and isolates login accounts', async ({ page }) => {
  const state = await install(page);
  await page.goto(path); await expect(box(page)).toBeEnabled();
  state.writeFailure = { status: 504, code: 'github_timeout', message: 'Timed out' };
  await expectViewedWrite(state, files[0].filename, true, () => box(page).check()); await waitingForConfirmation(page); await readFinished(page);
  const [record] = await pendingRecords(page);
  state.files = [files[2], files[1], files[0]];
  state.authenticated = false;
  await page.reload();
  await expect(box(page)).toBeDisabled();
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

test('Load latest retains an unconfirmed operation without restoring its old expansion', async ({ page }) => {
  const state = await installMbt(page);
  await page.goto(path); await expect(mbtBox(page)).toBeEnabled();
  state.writeFailure = { status: 504, code: 'github_timeout', message: 'Timed out' };
  await expectViewedWrite(state, mbtFiles[0].filename, false, () => mbtBox(page).uncheck()); await waitingForConfirmation(page); await readFinished(page);
  await card(page).getByRole('button', { name: 'Collapse src/main.mbt', exact: true }).click();
  const [record] = await pendingRecords(page);
  state.head = 'b'.repeat(40);
  await refresh(page);
  await page.getByRole('button', { name: 'Load latest', exact: true }).click();
  await waitingForConfirmation(page); await readFinished(page);
  await expect(mbtBox(page)).toBeDisabled(); await expect(mbtBox(page)).not.toBeChecked();
  await expect(card(page)).toHaveClass(/expanded/);
  expect(await pendingRecords(page)).toEqual([record]);
  state.states.alice[mbtFiles[0].filename] = 'Unviewed';
  await page.getByRole('button', { name: 'Recheck Viewed', exact: true }).click();
  await expect(mbtBox(page)).toBeEnabled();
  await expect(mbtBox(page)).not.toBeChecked();
  expect(state.states.alice[mbtFiles[0].filename]).toBe('Unviewed');
  expect(calls(state, 'github.pull.file.viewed.set')).toHaveLength(1);
});

test('session storage failure sends no mutation and preserves draft selection and expansion', async ({ page }) => {
  const state = await installMbt(page);
  await page.goto(path); await expect(mbtBox(page)).toBeEnabled();
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
  await page.goto(path); await expect(box(page)).toBeEnabled();
  const first = gate(); state.writeGate = first;
  await expectViewedWrite(state, files[0].filename, true, () => box(page).check()); await expect(box(page)).toBeDisabled();
  const [oldRecord] = await pendingRecords(page);
  // The mock applies before replying. Reload confirms its target from storage.
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
  await page.goto(path); await expect(box(page)).toBeEnabled();
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
  await page.goto(path); await expect(box(page)).toBeEnabled();
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
  await page.goto(path); await expect(box(page)).toBeEnabled();
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
    await page.goto(path); await expect(mbtBox(page)).toBeEnabled();
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
    await expect(page.getByText('Signed in as alice', { exact: true })).toBeVisible();
    await waitingForConfirmation(page); await readFinished(page);
    expect(await original.evaluate(el => el.isConnected && el === document.activeElement)).toBe(true);
    expect(await editor.evaluate(el => [el.selectionStart, el.selectionEnd, el.selectionDirection])).toEqual([2, 8, 'backward']);
    expect(calls(state, 'github.pull.file.viewed.set')).toHaveLength(1);
  });
}
