import { test, expect } from '@playwright/test';
import { installRenderProbe, renderCounts, settleRegions } from '../../tests/render-probe.mjs';
import { gate, installRenderingFixture, navigate, syntheticFixture } from './rendering-fixture.mjs';
import { holdRegionFrames } from './dom-timing.mjs';

const card = (page, index) => page.locator(`#moondiff-file-${index}`);
const route = fixture => `/example/regions/commit/${fixture.sha}`;

async function loaded(page, fixture) {
  await expect(page.locator('.file-card')).toHaveCount(fixture.files.length);
  await expect(page.locator('.loading-inline')).toHaveCount(0, { timeout: 30_000 });
  await settleRegions(page);
}
function unchanged(before, after, paths) {
  for (const path of paths) expect(after.files[path], `unrelated ${path}`).toEqual(before.files[path]);
  expect(after.errors).toEqual([]);
}

for (const algorithm of ['Token', 'Tree']) for (const layout of ['Split', 'Unified']) {
  test(`file, section, tree and draft isolation: ${algorithm}/${layout}`, async ({ page }) => {
    await installRenderProbe(page);
    const fixture = syntheticFixture();
    const state = await installRenderingFixture(page, fixture, { authenticated: true });
    await page.goto('/example/regions/pull/1'); await loaded(page, fixture);
    await page.getByRole('button', { name: algorithm, exact: true }).click();
    await page.getByRole('button', { name: layout, exact: true }).click();
    await settleRegions(page);
    const other = fixture.files.filter((_, i) => i !== 1).map(f => f.filename);
    let before = await renderCounts(page);
    await card(page, 1).locator('summary').first().click(); await settleRegions(page);
    let after = await renderCounts(page); unchanged(before, after, other);
    expect(after.files[fixture.files[1].filename].rows).toBe(before.files[fixture.files[1].filename].rows);
    await card(page, 1).locator('summary').first().click(); await settleRegions(page);
    const region = page.locator('[data-region="file:src/unrelated-1.mbt"]');
    const gutter = card(page, 1).locator('.new-line-number').filter({ has: page.getByRole('button', { name: 'Comment on line 2', exact: true }) }).first();
    await gutter.hover(); await gutter.getByRole('button').click();
    const editor = region.locator('textarea'); await expect(editor).toBeFocused();
    await editor.fill('local draft body');
    await editor.evaluate(el => { el.setSelectionRange(2, 7, 'backward'); el.scrollTop = 3; });
    before = await renderCounts(page);
    await editor.press('End'); await editor.pressSequentially(' more');
    after = await renderCounts(page); unchanged(before, after, other);
    const path = fixture.files[1].filename;
    for (const count of ['patch', 'projection', 'rows', 'diff', 'highlight']) expect(after.files[path][count], count).toBe(before.files[path][count]);
    // Editor follows the owning file between rows and fallback discussion.
    await editor.evaluate(el => { el.setSelectionRange(1, 5, 'backward'); });
    await card(page, 1).locator('.file-toggle').evaluate(el => el.click());
    await expect(region.locator('.file-discussions textarea')).toBeFocused();
    expect(await editor.evaluate(el => [el.selectionStart, el.selectionEnd, el.selectionDirection])).toEqual([1, 5, 'backward']);
    await card(page, 1).locator('.file-toggle').evaluate(el => el.click());
    await expect(card(page, 1).locator('textarea')).toBeFocused();
    expect(await editor.evaluate(el => [el.selectionStart, el.selectionEnd, el.selectionDirection])).toEqual([1, 5, 'backward']);
    // Tree search and width do not invalidate any file input.
    before = await renderCounts(page);
    await page.getByRole('button', { name: 'Search files', exact: true }).click();
    await page.getByRole('searchbox', { name: 'Search changed files' }).fill('unrelated-2');
    await page.getByRole('searchbox', { name: 'Search changed files' }).fill('');
    await page.getByRole('treeitem', { name: 'Collapse directory src', exact: true }).click();
    await page.getByRole('treeitem', { name: 'Expand directory src', exact: true }).click();
    const divider = page.getByRole('separator', { name: 'Resize file tree' });
    const rect = await divider.boundingBox();
    await page.mouse.move(rect.x + rect.width / 2, Math.max(rect.y, 150) + 10);
    await page.mouse.down(); await page.mouse.move(rect.x + 110, Math.max(rect.y, 150) + 10); await page.mouse.up();
    await expect(divider).toHaveAttribute('aria-valuenow', /^(3|4)\d{2}$/);
    after = await renderCounts(page); unchanged(before, after, fixture.files.map(f => f.filename));
    await editor.fill('Viewed keeps this draft');
    before = await renderCounts(page);
    const viewed = page.getByRole('checkbox', { name: `Viewed ${path}`, exact: true });
    await viewed.check(); await expect(viewed).toBeChecked(); await expect(viewed).toBeEnabled();
    expect(state.calls.some(c => c.op === 'github.pull.file.viewed.set' && c.args.path === path)).toBe(true);
    after = await renderCounts(page); unchanged(before, after, other);
    await expect(editor).toHaveValue('Viewed keeps this draft');
  });
}

for (const layout of ['Split', 'Unified']) for (const action of ['restore', 'search', 'outside click', 'cancel', 'route']) {
  test(`reply migration across a source response: ${action}, ${layout}`, async ({ page }) => {
    await installRenderProbe(page);
    const fixture = syntheticFixture({ files: 3, declarations: 3 });
    const pending = gate();
    const path = fixture.files[1].filename;
    const state = await installRenderingFixture(page, fixture, {
      authenticated: true,
      contentGate: { path: fixture.files[2].filename, ...pending },
      comments: [{ id: '20', body: 'Root comment', user: { login: 'reviewer' },
        html_url: 'https://github.com/example/regions/pull/1#discussion_r20',
        created_at: '2026-08-18T08:01:00Z', path, line: 2, side: 'RIGHT',
        position: 14, commit_id: fixture.sha }],
    });
    await page.goto('/example/regions/pull/1');
    await expect(card(page, 1).locator('table').first()).toBeVisible();
    await expect(card(page, 2)).toContainText('Loading file contents');
    await page.getByRole('button', { name: layout, exact: true }).click();
    // Open search before drafting so focusing it in the gap needs no model update.
    await page.getByRole('button', { name: 'Search files', exact: true }).click();
    const search = page.getByRole('searchbox', { name: 'Search changed files' });
    await card(page, 1).getByRole('button', { name: 'Reply', exact: true }).click();
    const editor = page.locator('.comment-editor textarea');
    await expect(editor).toBeFocused();
    const body = 'Keep this migrating reply\n' + 'Keep the scroll position\n'.repeat(30);
    await editor.fill(body);
    await settleRegions(page);
    const draftId = await editor.getAttribute('data-draft-id');
    const interaction = el => [el.selectionStart, el.selectionEnd, el.selectionDirection, el.scrollTop];
    const saved = await editor.evaluate(el => {
      el.setSelectionRange(3, 12, 'backward');
      el.scrollTop = 48;
      return [el.selectionStart, el.selectionEnd, el.selectionDirection, el.scrollTop];
    });
    expect(saved[3]).toBeGreaterThan(0);
    await page.evaluate(() => {
      window.restoredDrafts = [];
      document.addEventListener('focusin', event => {
        if (event.target.matches('textarea[data-draft-id]')) window.restoredDrafts.push(event.target.dataset.draftId);
      });
    });
    const fileRegion = `file:${path}`;
    const barrier = await holdRegionFrames(page, [fileRegion, 'discussion']);
    try {
      state.comments = [];
      // Simulate a background refresh without moving focus off the draft.
      await page.getByRole('button', { name: 'Refresh', exact: true }).evaluate(el => el.click());
      await barrier.blocked();
      if (action === 'cancel') {
        // The source region still shows its old editor while both commits wait.
        await page.locator('.comment-editor').getByRole('button', { name: 'Cancel', exact: true }).evaluate(el => el.click());
        await expect.poll(() => page.evaluate(() => __moondiffEditorInteraction.records.size)).toBe(0);
      }
      await barrier.release([fileRegion]);
      await expect(editor).toHaveCount(0);
      if (action === 'route') {
        await navigate(page, '/');
        await expect(page.locator('.pr-dashboard')).toBeVisible();
        await page.getByRole('button', { name: /^Account:/ }).focus();
      }
      // This unrelated response must arrive after detachment and before the
      // destination commit; capturing it used to erase the saved focus intent.
      pending.resolve();
      if (action !== 'route') await expect(card(page, 2).locator('table').first()).toBeVisible();
      await settleRegions(page);
      if (action === 'search') await search.focus();
      if (action === 'outside click') await page.getByRole('heading', { name: 'Comments', exact: true }).click();
    } finally {
      pending.resolve();
      await barrier.release();
    }
    await settleRegions(page);
    if (action === 'cancel' || action === 'route') {
      await expect(editor).toHaveCount(0);
      expect(await page.evaluate(() => __moondiffEditorInteraction.records.size)).toBe(0);
      expect(await page.evaluate(() => __moondiffEditorInteraction.active)).toBe('');
      expect(await page.evaluate(() => __moondiffEditorInteraction.stopListening)).toBeNull();
      if (action === 'route') await expect(page.getByRole('button', { name: /^Account:/ })).toBeFocused();
    } else {
      await expect(page.locator('.unavailable-reply-draft textarea')).toHaveCount(1);
      await expect(editor).toHaveAttribute('data-draft-id', draftId);
      await expect(editor).toHaveValue(body);
      expect(await editor.evaluate(interaction)).toEqual(saved);
      if (action === 'restore') await expect(editor).toBeFocused();
      else await expect(editor).not.toBeFocused();
      if (action === 'search') await expect(search).toBeFocused();
    }
    expect(await page.evaluate(() => window.restoredDrafts)).toEqual(action === 'restore' ? [draftId] : []);
    expect((await renderCounts(page)).errors).toEqual([]);
  });
}

test('source arrival and stale callbacks stay with their mount, repeated navigation releases stores', async ({ page }) => {
  await installRenderProbe(page);
  const fixture = syntheticFixture();
  const delay = gate();
  const state = await installRenderingFixture(page, fixture, { contentGate: { path: fixture.files[1].filename, ...delay } });
  await page.goto(route(fixture));
  await expect(card(page, 2).locator('table').first()).toBeVisible();
  await expect(card(page, 1)).toContainText('Loading file contents');
  const before = await renderCounts(page); delay.resolve(); await loaded(page, fixture);
  const after = await renderCounts(page);
  unchanged(before, after, fixture.files.filter((_, i) => i !== 1).map(f => f.filename));
  const baseline = after.active;
  expect(baseline.runtimeStores).toBe(baseline.stores + 1);
  for (let i = 0; i < 4; i++) {
    await card(page, 0).locator('.file-toggle').evaluate(el => { el.click(); el.click(); el.click(); });
    await navigate(page, '/');
    await expect(page.locator('.hero-landing')).toBeVisible(); await settleRegions(page);
    let counts = await renderCounts(page);
    expect(counts.active).toMatchObject({ mounts: 2, stores: 2, subscriptions: 2, runtimeStores: 3, observers: 0 });
    expect(counts.errors).toEqual([]);
    expect(await page.evaluate(() => __moondiffRegionLayout.records.size)).toBe(2);
    expect(await page.evaluate(() => __moondiffEditorInteraction.records.size)).toBe(0);
    const pending = gate();
    state.contentGate = { path: fixture.files[1].filename, ...pending };
    await navigate(page, route(fixture));
    await expect(card(page, 1)).toContainText('Loading file contents');
    await navigate(page, '/'); pending.resolve();
    await expect(page.locator('.hero-landing')).toBeVisible(); await settleRegions(page);
    expect((await renderCounts(page)).errors).toEqual([]);
    await navigate(page, route(fixture)); await loaded(page, fixture);
    counts = await renderCounts(page); expect(counts.active).toEqual(baseline);
  }
});

test('Viewed persistence observes committed checkbox properties and synchronous storage failure rolls back', async ({ page }) => {
  await installRenderProbe(page);
  const fixture = syntheticFixture();
  const state = await installRenderingFixture(page, fixture, { authenticated: true });
  await page.goto('/example/regions/pull/1'); await loaded(page, fixture);
  const checkbox = card(page, 1).getByRole('checkbox'); await expect(checkbox).toBeEnabled();
  await page.evaluate(() => {
    Storage.prototype.setItem = function (key) {
      if (!key.startsWith('moondiff.viewed.pending.v1:')) return;
      const el = document.querySelector('#moondiff-file-1 input[type=checkbox]');
      window.storageCommit = { checked: el.checked, disabled: el.disabled, optimisticLabel: el.closest('label').classList.contains('is-viewed') };
      throw new Error('synchronous storage failure');
    };
  });
  const before = await renderCounts(page);
  await checkbox.click();
  await expect.poll(() => page.evaluate(() => window.storageCommit)).toEqual({ checked: true, disabled: true, optimisticLabel: true });
  await expect(checkbox).not.toBeChecked();
  await expect(card(page, 1)).toHaveClass('file-card expanded');
  expect(state.calls.filter(c => c.op === 'github.pull.file.viewed.set')).toHaveLength(0);
  unchanged(before, await renderCounts(page), fixture.files.filter((_, i) => i !== 1).map(f => f.filename));
});

test('navigation in the same frame cancels UI waits and completes Viewed storage ownership cleanup', async ({ page }) => {
  await installRenderProbe(page);
  const fixture = syntheticFixture();
  const state = await installRenderingFixture(page, fixture, { authenticated: true });
  await page.goto('/example/regions/pull/1'); await loaded(page, fixture);
  await expect(card(page, 1).getByRole('checkbox')).toBeEnabled();
  await page.evaluate(() => {
    document.querySelector('#moondiff-file-1 input[type=checkbox]').click();
    document.querySelector('[data-region="tree"] [aria-label="Open src/unrelated-2.mbt"]').click();
    history.pushState(null, '', '/'); dispatchEvent(new PopStateEvent('popstate'));
  });
  await expect(page.locator('.pr-dashboard')).toBeVisible(); await settleRegions(page);
  expect(state.calls.filter(c => c.op === 'github.pull.file.viewed.set')).toHaveLength(0);
  expect(await page.evaluate(() => Object.keys(sessionStorage).filter(k => k.startsWith('moondiff.viewed.pending.v1:')))).toEqual([]);
  expect((await renderCounts(page)).errors).toEqual([]);
});

test('retired region DOM and file snapshots are collectable after navigation', async ({ page }) => {
  await installRenderProbe(page);
  const fixture = syntheticFixture();
  await installRenderingFixture(page, fixture);
  await page.goto(route(fixture)); await loaded(page, fixture);
  await page.evaluate(() => {
    window.retiredDOM = Array.from(document.querySelectorAll('.file-card'), node => new WeakRef(node));
    window.retiredSources = __moondiffMetrics.sources.slice();
    __moondiffMetrics.sources.length = 0;
  });
  expect(await page.evaluate(() => retiredSources.length)).toBeGreaterThan(0);
  await navigate(page, '/'); await expect(page.locator('.hero-landing')).toBeVisible(); await settleRegions(page);
  const session = await page.context().newCDPSession(page);
  await session.send('HeapProfiler.collectGarbage');
  expect(await page.evaluate(() => retiredDOM.filter(ref => ref.deref()).length)).toBe(0);
  expect(await page.evaluate(() => retiredSources.filter(ref => ref.deref()).length)).toBe(0);
});
