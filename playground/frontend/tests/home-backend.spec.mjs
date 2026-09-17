import { expect, test } from '@playwright/test';
import { cpSync, copyFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { browser, repository } from '../../backend/tests/server-fixture.mjs';
import { searchPull, startHomeServer, legacyPullCursor } from '../../backend/tests/home-fixture.mjs';
import { fixtureRequest } from '../../tests/protocol-fixtures.mjs';

import { reviews, authored, selectTab, signOut } from './home-fixture.mjs';
const row = (page, number) => reviews(page).locator('.home-pull').filter({ has: page.getByRole('link', { name: `Pull request ${number}`, exact: true, includeHidden: true }) });

test('pre-upgrade PR cursors reload each list through the real backend and preserve commit caches', async ({ page, context }) => {
  const assets = mkdtempSync(join(tmpdir(), 'moondiff-home-browser-'));
  cpSync(join(repository, 'playground/frontend/public'), assets, { recursive: true });
  copyFileSync(join(repository, '_build/js/release/build/moonbit-community/moondiff-playground/main/main.js'), join(assets, 'index.js'));
  const f = await startHomeServer({ staticDir: assets });
  try {
    f.state.rows = Array.from({ length: 51 }, (_, i) => searchPull(i + 1, {
      title: `Pull request ${i + 1}`, repository_url: 'https://api.github.com/repos/upstream/repo',
    }));
    const user = browser(f); await user.login();
    const [name, value] = user.cookie.split('=');
    await context.addCookies([{ name, value, url: f.base, httpOnly: true, sameSite: 'Lax' }]);
    const calls = [], failures = [], cursors = new Map();
    await page.route(f.base + '/api/rpc', async route => {
      const request = fixtureRequest(route.request().postDataJSON());
      calls.push(request);
      if (request.op === 'github.viewer.pulls.get' && !cursors.has(request.args.kind.$tag)) {
        const response = await route.fetch(), json = await response.json();
        expect(json.$tag).toBe('Success');
        const cursor = legacyPullCursor(f, request.args.kind.$tag, 51);
        cursors.set(request.args.kind.$tag, cursor);
        json.value['0'].next_cursor = cursor;
        await route.fulfill({ response, json });
      } else await route.continue();
    });
    page.on('response', async response => {
      if (response.url() === f.base + '/api/rpc' && response.status() === 400) failures.push((await response.json()).error.code);
    });
    await page.goto(f.base);
    await selectTab(page, 'ReviewRequested');
    await expect(reviews(page).locator('.home-pull')).toHaveCount(50);
    await expect(authored(page).locator('.home-pull')).toHaveCount(50);
    const one = row(page, 1);
    await one.getByRole('button', { name: /Expand commits/ }).click();
    await expect(one.locator('.home-commit')).toHaveCount(100);
    const pullCalls = kind => calls.filter(c => c.op === 'github.viewer.pulls.get' && c.args.kind.$tag === kind);
    for (const [kind, list] of [['ReviewRequested', reviews(page)], ['Authored', authored(page)]]) {
      await selectTab(page, kind);
      const more = list.locator(':scope > .home-page-actions').getByRole('button', { name: 'Load more' });
      await more.click();
      await expect.poll(() => pullCalls(kind).length).toBe(3);
      expect(pullCalls(kind).map(c => c.args.cursor)).toEqual([undefined, cursors.get(kind), undefined]);
      await expect(list.locator('.home-pull')).toHaveCount(50);
      await expect(one.locator('.home-commit')).toHaveCount(100);
      await more.click();
      await expect(list.locator('.home-pull')).toHaveCount(51);
      expect(pullCalls(kind)[3].args.cursor).not.toBe(cursors.get(kind));
    }
    await selectTab(page, 'ReviewRequested');
    await one.getByRole('button', { name: 'Load more', exact: true }).click();
    await expect(one.locator('.home-commit')).toHaveCount(200);
    expect(calls.filter(c => c.op === 'github.pull.commits.get')).toHaveLength(2);
    expect(failures).toEqual(['invalid_cursor', 'invalid_cursor']);
  } finally {
    await f.close(); rmSync(assets, { recursive: true, force: true });
  }
});

test('same-account sign-in in another tab recovers each expired cursor through the real backend', async ({ page, context }) => {
  const assets = mkdtempSync(join(tmpdir(), 'moondiff-home-browser-'));
  cpSync(join(repository, 'playground/frontend/public'), assets, { recursive: true });
  copyFileSync(join(repository, '_build/js/release/build/moonbit-community/moondiff-playground/main/main.js'), join(assets, 'index.js'));
  const f = await startHomeServer({ staticDir: assets });
  try {
    f.state.rows = Array.from({ length: 51 }, (_, i) => searchPull(i + 1, {
      title: `Pull request ${i + 1}`, repository_url: 'https://api.github.com/repos/upstream/repo',
    }));
    const user = browser(f); await user.login();
    const [name, value] = user.cookie.split('=');
    await context.addCookies([{ name, value, url: f.base, httpOnly: true, sameSite: 'Lax' }]);
    const calls = [], failures = [];
    page.on('request', request => {
      if (request.url() === f.base + '/api/rpc') calls.push(fixtureRequest(request.postDataJSON()));
    });
    page.on('response', async response => {
      if (response.url() === f.base + '/api/rpc' && response.status() === 400) failures.push((await response.json()).error.code);
    });
    await page.addInitScript(() => { window.homeDocumentId = crypto.randomUUID(); });
    await page.goto(f.base);
    await selectTab(page, 'ReviewRequested');
    const documentId = await page.evaluate(() => window.homeDocumentId);
    await expect(reviews(page).locator('.home-pull')).toHaveCount(50);
    await expect(authored(page).locator('.home-pull')).toHaveCount(50);
    const one = row(page, 1), two = row(page, 2);
    await one.getByRole('button', { name: /Expand commits/ }).click();
    await expect(one.locator('.home-commit')).toHaveCount(100);
    await two.getByRole('button', { name: /Expand commits/ }).click();
    await expect(two.locator('.home-commit')).toHaveCount(100);
    await two.getByRole('button', { name: /Collapse commits/ }).click();
    const pullCalls = kind => calls.filter(c => c.op === 'github.viewer.pulls.get' && c.args.kind.$tag === kind);
    const commitCalls = number => calls.filter(c => c.op === 'github.pull.commits.get' && c.args.number === String(number));
    const stalePulls = Object.fromEntries(['Authored', 'ReviewRequested'].map(kind => [kind, pullCalls(kind).length]));
    const other = await context.newPage();
    await other.goto(f.base);
    await expect(other.getByRole('button', { name: 'Account: alice' })).toBeVisible();
    await signOut(other);
    await expect(other.getByRole('button', { name: 'Sign in with GitHub' }).first()).toBeVisible();
    await other.getByRole('button', { name: 'Sign in with GitHub' }).first().click();
    await expect(other.locator('.device-code').first()).toBeVisible();
    f.approve(await other.locator('.device-code').first().textContent());
    f.sql('UPDATE authorizations SET next_poll=0');
    await expect(other.getByRole('button', { name: 'Account: alice' })).toBeVisible();
    await page.bringToFront();
    await expect(page.getByRole('button', { name: 'Account: alice' })).toBeVisible();
    await expect(one.locator('.home-commit')).toHaveCount(100);
    for (const kind of ['Authored', 'ReviewRequested']) expect(pullCalls(kind)).toHaveLength(stalePulls[kind]);

    await selectTab(page, 'ReviewRequested');
    await one.getByRole('button', { name: 'Load more', exact: true }).click();
    await expect.poll(() => commitCalls(1).length).toBe(3);
    expect(commitCalls(1)[1].args.cursor).toBeTruthy();
    expect(commitCalls(1)[2].args.cursor).toBeUndefined();
    await expect(one.locator('.home-commit')).toHaveCount(100);
    await expect(one.getByRole('button', { name: /Collapse commits/ })).toHaveAttribute('aria-expanded', 'true');
    await selectTab(page, 'ReviewRequested');
    await one.getByRole('button', { name: 'Load more', exact: true }).click();
    await expect(one.locator('.home-commit')).toHaveCount(200);
    await expect(one.locator('.home-commit-link').last()).toContainText('Commit 200');

    // PR recovery leaves both expanded state and unrelated cached commits intact.
    const reviewMore = reviews(page).locator(':scope > .home-page-actions').getByRole('button', { name: 'Load more' });
    await reviewMore.click();
    await expect.poll(() => pullCalls('ReviewRequested').length).toBe(3);
    expect(pullCalls('ReviewRequested')[1].args.cursor).toBeTruthy();
    expect(pullCalls('ReviewRequested')[2].args.cursor).toBeUndefined();
    await expect(reviews(page).locator('.home-pull')).toHaveCount(50);
    await expect(one.locator('.home-commit')).toHaveCount(200);
    expect(pullCalls('Authored')).toHaveLength(1);
    await two.getByRole('button', { name: /Expand commits/ }).click();
    await expect(two.locator('.home-commit')).toHaveCount(100);
    expect(commitCalls(2)).toHaveLength(1);
    await two.getByRole('button', { name: /Collapse commits/ }).click();

    await selectTab(page, 'Authored');
    const authoredMore = authored(page).locator(':scope > .home-page-actions').getByRole('button', { name: 'Load more' });
    await authoredMore.click();
    await expect.poll(() => pullCalls('Authored').length).toBe(3);
    expect(pullCalls('Authored')[2].args.cursor).toBeUndefined();
    await expect(authored(page).locator('.home-pull')).toHaveCount(50);
    await authoredMore.click();
    await expect(authored(page).locator('.home-pull')).toHaveCount(51);
    await selectTab(page, 'ReviewRequested');
    await reviewMore.click();
    await expect(reviews(page).locator('.home-pull')).toHaveCount(51);
    expect(failures).toEqual(['invalid_cursor', 'invalid_cursor', 'invalid_cursor']);
    expect(await page.evaluate(() => window.homeDocumentId)).toBe(documentId);
    await other.close();
  } finally {
    await f.close(); rmSync(assets, { recursive: true, force: true });
  }
});
