import { expect, test as baseTest } from '@playwright/test';
import { cpSync, copyFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { browser, repository } from '../../backend/tests/server-fixture.mjs';
import { startViewedServer, repositoryPaths } from '../../backend/tests/viewed-fixture.mjs';
import { fixtureRequest } from '../../tests/protocol-fixtures.mjs';

const test = baseTest.extend({
  backend: async ({ page }, use) => {
    // The Playwright webServer builds both targets before any test starts.
    const assets = mkdtempSync(join(tmpdir(), 'moondiff-viewed-browser-'));
    cpSync(join(repository, 'playground/frontend/public'), assets, { recursive: true });
    copyFileSync(join(repository, '_build/js/release/build/moonbit-community/moondiff-playground/main/main.js'), join(assets, 'index.js'));
    const f = await startViewedServer({ staticDir: assets });
    const user = browser(f);
    try {
      await user.login();
      const [name, value] = user.cookie.split('=');
      await page.context().addCookies([{ name, value, url: f.base, httpOnly: true, sameSite: 'Lax' }]);
      const calls = [], failed = [];
      page.on('request', request => {
        if (request.url() === f.base + '/api/rpc') calls.push(fixtureRequest(request.postDataJSON()));
      });
      page.on('requestfailed', request => failed.push(request));
      await use({ ...f, user, calls, failed });
    } finally {
      await f.close();
      rmSync(assets, { recursive: true, force: true });
    }
  },
});

const card = (page, i = 0) => page.locator(`#moondiff-file-${i}`);
const box = (page, i = 0) => card(page, i).getByRole('checkbox');
const reads = backend => backend.calls.filter(c => c.op === 'github.pull.viewed.get');
const writes = backend => backend.calls.filter(c => c.op === 'github.pull.file.viewed.set');
async function expectViewedWrite(backend, path, viewed, action) {
  const before = writes(backend).length;
  const expected = { path, base_sha: backend.state.base, head_sha: backend.state.head, viewed };
  await action();
  // Wait for this operation even if the checkbox still looks enabled from the previous render.
  await expect.poll(() => writes(backend).length).toBe(before + 1);
  expect(writes(backend)[before].args).toMatchObject(expected);
}
const restore = page => page.evaluate(() => {
  dispatchEvent(new Event('pagehide'));
  dispatchEvent(new Event('pageshow'));
});
const open = (page, backend, target = '/alice/repo/pull/42') => page.goto(backend.base + target);
async function openInline(page, index = 0) {
  const gutter = card(page, index).locator('.review-gutter.new-line-number').filter({ has: page.locator('.line-number-value', { hasText: /^2$/ }) });
  await gutter.hover();
  await gutter.getByRole('button', { name: 'Comment on line 2', exact: true }).click();
  return card(page, index).locator('textarea');
}

for (const viewed of [true, false]) {
  for (const applied of [true, false]) {
    test(`restored ${viewed ? 'mark' : 'unmark'} stays disabled until the real backend confirms ${applied ? 'applied' : 'unapplied'} write`, async ({ page, backend }) => {
      const path = backend.state.files[0];
      backend.state.forScope().set(path, viewed ? 'UNVIEWED' : 'VIEWED');
      await open(page, backend); await expect(box(page)).toBeEnabled();
      const hold = backend.state.holdWrite(path, { applied, fail: !applied });
      await expectViewedWrite(backend, backend.state.files[0], viewed, () => box(page).setChecked(viewed));
      await hold.entered.promise;
      // The browser really aborts the POST while the local server is in GitHub.
      await restore(page);
      await expect.poll(() => reads(backend).length).toBe(2);
      await expect.poll(() => backend.failed.filter(r => r.postData()?.includes('PullFileViewedSet')).length).toBe(1);
      await expect(box(page)).toBeChecked({ checked: viewed });
      await expect(box(page)).toBeDisabled();
      await restore(page);
      await expect.poll(() => reads(backend).length).toBe(3);
      await expect(box(page)).toBeDisabled();
      expect(backend.state.reads).toHaveLength(1);
      // Both interrupted confirmation requests fail; manual retry must keep
      // the pending write and issue only a read after GitHub finishes.
      backend.state.failReads = 2;
      hold.release.resolve();
      await expect(page.getByRole('button', { name: 'Recheck Viewed', exact: true })).toBeVisible();
      await expect(box(page)).toBeDisabled();
      await expect(box(page)).toBeChecked({ checked: viewed });
      await page.getByRole('button', { name: 'Recheck Viewed', exact: true }).click();
      if (applied) await expect(box(page)).toBeEnabled();
      else {
        await expect(card(page).getByText('Waiting for GitHub confirmation', { exact: true })).toBeVisible();
        await expect(box(page)).toBeDisabled();
      }
      await expect(box(page)).toBeChecked({ checked: viewed });
      if (viewed) await expect(card(page)).not.toHaveClass(/expanded/);
      else await expect(card(page)).toHaveClass(/expanded/);
      expect(writes(backend)).toHaveLength(1);
      expect(backend.state.mutations).toHaveLength(1);
      expect(backend.state.forScope().get(path)).toBe((applied ? viewed : !viewed) ? 'VIEWED' : 'UNVIEWED');
    });
  }
}

test('restored unmark confirmation retains subsequent expansion, code and inline draft selection', async ({ page, backend }) => {
  const path = backend.state.files[0];
  backend.state.forScope().set(path, 'VIEWED');
  await open(page, backend); await expect(box(page)).toBeEnabled();
  const hold = backend.state.holdWrite(path, { applied: false, fail: true });
  await expectViewedWrite(backend, backend.state.files[0], false, () => box(page).uncheck()); await hold.entered.promise;
  const editor = await openInline(page);
  await editor.fill('Keep this draft through recovery');
  await expect(editor).toBeFocused();
  await editor.evaluate(el => el.setSelectionRange(2, 8, 'backward'));
  const original = await editor.elementHandle();
  const code = await card(page).locator('table').elementHandle();
  // Hold the identity response so AuthChecking must render separately.
  let releaseAuth;
  const authGate = new Promise(resolve => { releaseAuth = resolve; });
  await page.route('**/api/auth/status', async route => {
    const response = await route.fetch();
    await authGate;
    await route.fulfill({ response });
  });
  await restore(page);
  await expect(page.getByText('Checking GitHub session…', { exact: true })).toBeVisible();
  await expect(editor).toBeFocused();
  await expect(card(page).getByRole('button', { name: 'Post comment', exact: true })).toBeDisabled();
  expect(await original.evaluate(el => el.isConnected)).toBe(true);
  releaseAuth();
  await expect.poll(() => reads(backend).length).toBe(2);
  await expect(editor).toHaveValue('Keep this draft through recovery');
  await expect(editor).toBeFocused();
  hold.release.resolve();
  await expect(card(page).getByText('Waiting for GitHub confirmation', { exact: true })).toBeVisible();
  await expect(box(page)).toBeDisabled(); await expect(box(page)).not.toBeChecked();
  await expect(card(page)).toHaveClass(/expanded/);
  await expect(editor).toBeFocused();
  expect(await original.evaluate(el => el.isConnected && el === document.activeElement)).toBe(true);
  expect(await code.evaluate(el => el.isConnected)).toBe(true);
  expect(await editor.evaluate(el => [el.selectionStart, el.selectionEnd, el.selectionDirection])).toEqual([2, 8, 'backward']);
  expect(backend.state.mutations).toHaveLength(1);
});

test('restoration confirms all queued files before enabling controls', async ({ page, backend }) => {
  await open(page, backend); await expect(box(page)).toBeEnabled();
  const first = backend.state.holdWrite(backend.state.files[0]);
  const second = backend.state.holdWrite(backend.state.files[1]);
  await expectViewedWrite(backend, backend.state.files[0], true, () => box(page).check()); await first.entered.promise;
  await expectViewedWrite(backend, backend.state.files[1], true, () => box(page, 1).check());
  await restore(page); await expect.poll(() => reads(backend).length).toBe(2);
  first.release.resolve(); await second.entered.promise;
  await expect(box(page)).toBeDisabled(); await expect(box(page, 1)).toBeDisabled();
  expect(backend.state.reads).toHaveLength(1);
  second.release.resolve();
  await expect(box(page)).toBeEnabled(); await expect(box(page, 1)).toBeEnabled();
  await expect(box(page)).toBeChecked(); await expect(box(page, 1)).toBeChecked();
  for (const path of backend.state.files) expect(backend.state.forScope().get(path)).toBe('VIEWED');
  expect(backend.state.mutations).toHaveLength(2);
  expect(writes(backend)).toHaveLength(2);
});

test('restoring another account discards the old pending write and draft', async ({ page, backend }) => {
  await open(page, backend); await expect(box(page)).toBeEnabled();
  const editor = await openInline(page); await editor.fill('Alice only');
  const hold = backend.state.holdWrite(backend.state.files[0]);
  await expectViewedWrite(backend, backend.state.files[0], true, () => box(page).check()); await hold.entered.promise;
  await backend.user.login('bob');
  await restore(page);
  await expect(page.getByText('Signed in as bob', { exact: true })).toBeVisible();
  await expect(box(page)).toBeEnabled(); await expect(box(page)).not.toBeChecked();
  await expect(page.locator('textarea')).toHaveCount(0);
  hold.release.resolve();
  await expect.poll(() => backend.state.forScope().get(backend.state.files[0])).toBe('VIEWED');
  await expect(box(page)).not.toBeChecked();
  expect(backend.state.mutations).toHaveLength(1);
});

test('a snapshot change during restored write uses Load latest', async ({ page, backend }) => {
  await open(page, backend); await expect(box(page)).toBeEnabled();
  const hold = backend.state.holdWrite(backend.state.files[0]);
  await expectViewedWrite(backend, backend.state.files[0], true, () => box(page).check()); await hold.entered.promise;
  await restore(page); await expect.poll(() => reads(backend).length).toBe(2);
  backend.state.head = 'b'.repeat(40); hold.release.resolve();
  await expect(page.getByRole('button', { name: 'Load latest', exact: true })).toBeVisible();
  await expect(box(page)).toBeDisabled();
  await page.getByRole('button', { name: 'Load latest', exact: true }).click();
  await expect(box(page)).toBeEnabled();
  await expect(box(page)).toBeChecked();
  await expectViewedWrite(backend, backend.state.files[0], false, () => box(page).uncheck());
  await expect(box(page)).toBeEnabled();
  await expect(box(page)).not.toBeChecked();
  expect(backend.state.forScope().get(backend.state.files[0])).toBe('UNVIEWED');
});

test('special and ordinary filenames support source, inline comments and Viewed together', async ({ page, backend }) => {
  backend.state.files = repositoryPaths;
  for (const target of ['/alice/repo/pull/42', `/alice/repo/commit/${backend.state.head}`]) {
    await open(page, backend, target);
    for (const [i, path] of repositoryPaths.entries()) {
      const file = card(page, i);
      const expand = file.getByRole('button', { name: /^Expand / });
      if (await expand.count()) await expand.click();
      await expect(file.locator('table')).toBeVisible();
      const editor = await openInline(page, i);
      await editor.fill(`Comment for file ${i}`);
      await file.getByRole('button', { name: 'Post comment', exact: true }).click();
      await expect(editor).toHaveCount(0);
      expect(backend.state.comments.at(-1).path).toBe(path);
      expect(backend.calls.filter(c => c.op === 'github.content.get' && c.args.path === path).length).toBeGreaterThan(0);
      if (target.includes('/pull/')) {
        await expect(box(page, i)).toBeEnabled();
        const before = backend.state.mutations.length;
        await expectViewedWrite(backend, path, true, () => box(page, i).check());
        await expect.poll(() => backend.state.mutations.length).toBe(before + 1);
        await expect(box(page, i)).toBeEnabled();
        await expect(box(page, i)).toBeChecked();
        expect(backend.state.forScope().get(path)).toBe('VIEWED');
        expect(backend.state.mutations[before]).toMatchObject({ path, viewed: true });
        await expectViewedWrite(backend, path, false, () => box(page, i).uncheck());
        await expect.poll(() => backend.state.mutations.length).toBe(before + 2);
        await expect(box(page, i)).toBeEnabled();
        await expect(box(page, i)).not.toBeChecked();
        expect(backend.state.forScope().get(path)).toBe('UNVIEWED');
        expect(backend.state.mutations[before + 1]).toMatchObject({ path, viewed: false });
      }
    }
  }
  expect(backend.state.comments).toHaveLength(repositoryPaths.length * 2);
  expect(backend.state.mutations).toHaveLength(repositoryPaths.length * 2);
});

test('upstream timeout followed by old reads stays locked until the original GitHub mutation finishes', async ({ page, backend }) => {
  test.setTimeout(75000);
  await open(page, backend); await expect(box(page)).toBeEnabled();
  const hold = backend.state.holdWrite(backend.state.files[0]);
  await expectViewedWrite(backend, backend.state.files[0], true, () => box(page).check()); await hold.entered.promise;
  // The production upstream deadline expires after 30 seconds, releasing FIFO
  // while GitHub may still finish the original mutation later.
  await expect.poll(() => backend.state.reads.length, { timeout: 40000 }).toBeGreaterThanOrEqual(3);
  await expect(card(page).getByText('Waiting for GitHub confirmation', { exact: true })).toBeVisible();
  await expect(box(page)).toBeDisabled(); await expect(box(page)).toBeChecked();
  await expect(box(page, 1)).toBeEnabled();
  expect(backend.state.forScope().get(backend.state.files[0])).toBeUndefined();
  expect(backend.state.mutations).toHaveLength(1);
  hold.release.resolve();
  await expect(box(page)).toBeEnabled({ timeout: 15000 });
  await expect(box(page)).toBeChecked();
  expect(backend.state.forScope().get(backend.state.files[0])).toBe('VIEWED');
  expect(writes(backend)).toHaveLength(1);
  expect(backend.state.mutations).toHaveLength(1);
});
