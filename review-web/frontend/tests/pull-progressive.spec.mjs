import { test, expect } from '@playwright/test';
import { installRenderProbe, renderCounts, settleRegions } from '../../tests/render-probe.mjs';
import { gate, installRenderingFixture, navigate, syntheticFixture } from './rendering-fixture.mjs';

const card = (page, index) => page.locator(`#moondiff-file-${index}`);
const sources = state => state.calls.filter(call => call.op === 'github.content.get');
const toggle = (page, index) => card(page, index).locator('.file-toggle').evaluate(button => button.click());
const scroll = (page, index) => card(page, index).evaluate(element => {
  window.dispatchEvent(new WheelEvent('wheel', { deltaY: 1 }));
  window.scrollTo({ top: window.scrollY + element.getBoundingClientRect().top - 160, behavior: 'instant' });
});
async function warm(page, state, count = 80) {
  await expect.poll(() => sources(state).length, { timeout: 30_000 }).toBe(count);
  await expect(page.locator('.loading-inline')).toHaveCount(0, { timeout: 30_000 });
  await expect.poll(() => page.evaluate(() => __moondiffMetrics.pull_sources?.pending)).toBe(0);
  await settleRegions(page);
}

for (const authenticated of [true]) {
  test(`PR continuously prefetches forty files and opens locally (${authenticated ? 'signed in' : 'anonymous'})`, async ({ page }) => {
    const fixture = syntheticFixture({ files: 40, declarations: 2 });
    const tail = gate();
    await installRenderProbe(page);
    const state = await installRenderingFixture(page, fixture, {
      authenticated,
      sourceGate: args => fixture.files.findIndex(file => file.filename === args.path) >= 20 ? tail.promise : undefined,
    });
    await page.goto('/example/regions/pull/1');
    await expect(page.locator('.file-card')).toHaveCount(40);
    await expect(page.locator('.loading-inline')).toHaveCount(0, { timeout: 30_000 });
    await expect.poll(() => sources(state).length).toBe(44);
    const before = await renderCounts(page);
    tail.resolve(); await warm(page, state);
    expect(state.maxActiveSources).toBeLessThanOrEqual(4);
    await expect(page.locator('.file-card.expanded')).toHaveCount(20);
    const after = await renderCounts(page);
    for (const file of fixture.files.slice(0, 20)) expect(after.files[file.filename]).toEqual(before.files[file.filename]);
    for (const file of fixture.files.slice(20)) {
      expect(after.files[file.filename]?.diff ?? 0).toBe(0);
      expect(after.files[file.filename]?.highlight ?? 0).toBe(0);
      expect(after.files[file.filename]?.patch ?? 0).toBe(before.files[file.filename]?.patch ?? 0);
    }
    state.sourceFailure = () => ({ status: 500, code: 'offline', detail: 'Source network blocked after prefetch' });
    await page.evaluate(() => {
      window.progressiveBatches = [];
      let size = 0;
      Object.defineProperty(__moondiffMetrics.progressive, 'batch_size', {
        configurable: true, enumerable: true, get: () => size,
        set(value) { size = value; progressiveBatches.push({ frame: document.timeline.currentTime, size: value }); },
      });
    });
    await toggle(page, 39);
    await expect(card(page, 39)).toHaveClass('file-card expanded');
    await expect(card(page, 39).locator('.loading-inline')).toHaveCount(0);
    await scroll(page, 30);
    await expect(card(page, 30)).toHaveClass('file-card expanded');
    await settleRegions(page);
    const expanded = await renderCounts(page);
    expect(expanded.files[fixture.files[30].filename].diff).toBeGreaterThan(0);
    expect(expanded.progressive.batch_size).toBeLessThanOrEqual(2);
    const batches = await page.evaluate(() => progressiveBatches);
    expect(batches.length).toBeGreaterThan(0);
    const byFrame = new Map();
    for (const batch of batches) byFrame.set(batch.frame, (byFrame.get(batch.frame) ?? 0) + batch.size);
    expect([...byFrame.values()].every(count => count <= 2)).toBe(true);
    expect(sources(state)).toHaveLength(80);
    await expect(card(page, 20)).toHaveClass('file-card');
    expect(expanded.errors).toEqual([]);
  });
}

test('anonymous forty-file PR preserves request quota for manual and scrolling loads', async ({ page }) => {
  const fixture = syntheticFixture({ files: 40, declarations: 2 });
  await installRenderProbe(page);
  // Forty initial source sides fit in the simulated anonymous allowance, plus
  // enough for deliberate browsing. A continuous scan would exhaust it.
  let quota = 60;
  const state = await installRenderingFixture(page, fixture, {
    authenticated: false,
    sourceFailure: () => --quota < 0 ? { status: 429, code: 'rate_limit', detail: 'Anonymous quota exhausted' } : undefined,
  });
  await page.goto('/example/regions/pull/1');
  await warm(page, state, 40);
  await page.waitForTimeout(150);
  expect(sources(state)).toHaveLength(40);
  await expect(page.locator('.file-card.expanded')).toHaveCount(20);
  await toggle(page, 39);
  await expect(card(page, 39).locator('.diff-scroll table').first()).toBeVisible();
  expect(sources(state)).toHaveLength(42);
  await scroll(page, 30);
  await expect(card(page, 30).locator('.diff-scroll table').first()).toBeVisible();
  await settleRegions(page);
  expect(quota).toBeGreaterThanOrEqual(0);
  expect(sources(state).length).toBeLessThanOrEqual(60);
  expect(state.maxActiveSources).toBeLessThanOrEqual(4);
  await expect(card(page, 25)).toHaveClass('file-card');
  expect(sources(state).some(call => call.args.path === fixture.files[25].filename)).toBe(false);
});

test('PR demand overtakes initial files with four active reads and no duplicate requests', async ({ page }) => {
  const fixture = syntheticFixture({ files: 40, declarations: 1 });
  const blocked = new Map();
  await installRenderProbe(page);
  const state = await installRenderingFixture(page, fixture, { authenticated: true, sourceGate: args => {
    const pending = gate(); blocked.set(`${args.ref}:${args.path}`, pending); return pending.promise;
  } });
  await page.goto('/example/regions/pull/1');
  await expect.poll(() => sources(state).length).toBe(4);
  await toggle(page, 35);
  expect(sources(state)).toHaveLength(4);
  const first = sources(state)[0].args;
  blocked.get(`${first.ref}:${first.path}`).resolve();
  await expect.poll(() => sources(state).length).toBe(5);
  expect(sources(state)[4].args.path).toBe(fixture.files[35].filename);
  await toggle(page, 35); await toggle(page, 35);
  state.sourceGate = null;
  for (const pending of blocked.values()) pending.resolve();
  await warm(page, state);
  expect(new Set(sources(state).map(call => `${call.args.ref}:${call.args.path}`)).size).toBe(80);
  expect(state.maxActiveSources).toBeLessThanOrEqual(4);
});

test('hidden PR finishes in-flight reads and resumes dispatch on visibility', async ({ page }) => {
  const fixture = syntheticFixture({ files: 40, declarations: 1 });
  const initial = gate();
  await installRenderProbe(page);
  const state = await installRenderingFixture(page, fixture, { authenticated: true, sourceGate: () => initial.promise });
  await page.goto('/example/regions/pull/1');
  await expect.poll(() => sources(state).length).toBe(4);
  await page.evaluate(() => {
    Object.defineProperty(document, 'hidden', { configurable: true, value: true });
    document.dispatchEvent(new Event('visibilitychange'));
  });
  initial.resolve();
  await expect.poll(() => state.activeSources).toBe(0);
  await page.waitForTimeout(150);
  expect(sources(state)).toHaveLength(4);
  await page.evaluate(() => {
    Object.defineProperty(document, 'hidden', { configurable: true, value: false });
    document.dispatchEvent(new Event('visibilitychange'));
  });
  await warm(page, state);
  await expect(page.locator('.file-card.expanded')).toHaveCount(20);
});

test('PR rate limit blocks new demand while retaining ordinary file errors', async ({ page }) => {
  const fixture = syntheticFixture({ files: 40, declarations: 1 });
  await installRenderProbe(page);
  const state = await installRenderingFixture(page, fixture, { authenticated: true, sourceFailure: args => {
    if (args.path === fixture.files[20].filename && args.ref === fixture.base) return { status: 500, code: 'unavailable', detail: 'One file failed' };
    if (args.path === fixture.files[23].filename && args.ref === fixture.base) return { status: 429, code: 'rate_limit', detail: 'Rate limited' };
  } });
  await page.goto('/example/regions/pull/1');
  await expect.poll(() => sources(state).length).toBeGreaterThanOrEqual(47);
  await expect.poll(() => state.activeSources).toBe(0);
  await settleRegions(page);
  const stopped = sources(state).length;
  expect(stopped).toBeLessThan(80);
  await page.waitForTimeout(150);
  expect(sources(state)).toHaveLength(stopped);
  await expect(page.locator('.rate-limit')).toHaveText('GitHub is limiting requests. Please refresh this page later.');
  await toggle(page, 30);
  await expect(card(page, 30).locator('.paused')).toBeAttached();
  await expect(card(page, 30).locator('.loading-inline')).toHaveCount(0);
  await toggle(page, 20);
  await expect(card(page, 20).getByRole('button', { name: 'Retry file' })).toBeAttached();
  state.sourceFailure = null;
  await card(page, 20).getByRole('button', { name: 'Retry file' }).evaluate(button => button.click());
  expect(sources(state)).toHaveLength(stopped);

});

test('scroll expansion respects manual collapse and Viewed and disposes on route exit', async ({ page }) => {
  const fixture = syntheticFixture({ files: 40, declarations: 1 });
  await installRenderProbe(page);
  const state = await installRenderingFixture(page, fixture, { authenticated: true,
    viewed: { [fixture.files[22].filename]: true },
  });
  await page.goto('/example/regions/pull/1'); await warm(page, state);
  await toggle(page, 21); await toggle(page, 21);
  await scroll(page, 21); await settleRegions(page);
  await expect(card(page, 21)).toHaveClass('file-card');
  await expect(card(page, 22)).toHaveClass('file-card');
  await expect(card(page, 23)).toHaveClass('file-card expanded');
  const focus = await page.evaluate(() => document.activeElement?.className);
  await page.evaluate(() => window.scrollBy(0, 5)); await settleRegions(page);
  expect(await page.evaluate(() => document.activeElement?.className)).toBe(focus);
  await navigate(page, `/example/regions/commit/${fixture.sha}`);
  await expect(page.locator('.file-card.expanded')).toHaveCount(20);
  await navigate(page, '/example/regions/pull/1');
  await expect(card(page, 21)).toHaveClass('file-card');
  await scroll(page, 21); await settleRegions(page);
  await expect(card(page, 21)).toHaveClass('file-card');
  await navigate(page, '/');
  await expect(page.locator('.file-card')).toHaveCount(0);
  await settleRegions(page);
  const metrics = await renderCounts(page);
  expect(metrics.progressive.targets).toBe(0);
  expect(metrics.progressive.listening).toBe(false);
  expect(metrics.active.observers).toBe(0);
  expect(await page.evaluate(() => document.documentElement.style.overflowAnchor)).toBe('');
});

test('PR navigation and history restoration keep their position and an active editor keeps focus', async ({ page }) => {
  const fixture = syntheticFixture({ files: 40, declarations: 2 });
  await installRenderProbe(page);
  const state = await installRenderingFixture(page, fixture, { authenticated: true });
  await page.goto('/example/regions/pull/1'); await warm(page, state);
  await page.locator('[data-region="tree"] [aria-label="Open src/unrelated-30.mbt"]').evaluate(button => button.click());
  await expect(card(page, 30)).toHaveClass('file-card expanded');
  await settleRegions(page);
  await expect(card(page, 29)).toHaveClass('file-card');
  await expect(card(page, 31)).toHaveClass('file-card');
  // A delayed native scroll notification is not fresh user scrolling input.
  await page.evaluate(() => window.dispatchEvent(new Event('scroll')));
  await settleRegions(page);
  await expect(card(page, 29)).toHaveClass('file-card');
  await expect(card(page, 31)).toHaveClass('file-card');
  await card(page, 30).locator('.file-toggle').evaluate(button => button.focus({ preventScroll: true }));
  const y = await page.evaluate(() => scrollY);
  await page.locator('a.workspace-home').evaluate(link => link.click());
  await expect(page.locator('.file-card')).toHaveCount(0);
  await page.goBack();
  await expect(card(page, 30)).toHaveClass('file-card expanded');
  await settleRegions(page);
  await page.evaluate(() => window.dispatchEvent(new Event('scroll')));
  await settleRegions(page);
  await expect.poll(() => page.evaluate(() => scrollY)).toBe(y);
  await expect(card(page, 30).locator('.file-toggle')).toBeFocused();
  await expect(card(page, 31)).toHaveClass('file-card');
  const comment = card(page, 30).locator('.new-line-number').getByRole('button', { name: 'Comment on line 2', exact: true }).first();
  await comment.evaluate(button => button.click());
  const editor = page.locator('textarea');
  await expect(editor).toBeFocused();
  await editor.fill('Keep my place and selection');
  await editor.evaluate(element => element.setSelectionRange(2, 9, 'backward'));
  await scroll(page, 31); await settleRegions(page);
  expect(await page.evaluate(() => document.documentElement.style.overflowAnchor)).toBe('');
  await expect(card(page, 31)).toHaveClass('file-card');
  await expect(editor).toBeFocused();
  expect(await editor.evaluate(element => [element.selectionStart, element.selectionEnd, element.selectionDirection])).toEqual([2, 9, 'backward']);
});

test('leaving a PR cancels its prefetch and rejects source results from the retired snapshot', async ({ page }) => {
  const fixture = syntheticFixture({ files: 40, declarations: 1 });
  const tail = gate();
  await installRenderProbe(page);
  const state = await installRenderingFixture(page, fixture, { authenticated: true,
    sourceGate: args => fixture.files.findIndex(file => file.filename === args.path) >= 20 ? tail.promise : undefined,
  });
  await page.goto('/example/regions/pull/1');
  await expect.poll(() => sources(state).length).toBe(44);
  await navigate(page, '/');
  await expect(page.locator('.file-card')).toHaveCount(0);
  await settleRegions(page);
  expect((await renderCounts(page)).active.observers).toBe(0);
  const sha = 'c'.repeat(40);
  state.fixture = { ...fixture, sha, sources: Object.fromEntries(Object.entries(fixture.sources).map(([key, source]) =>
    [key.replace(fixture.sha, sha), source.replaceAll('1\n', '99\n')])) };
  state.sourceGate = null;
  await navigate(page, '/example/regions/pull/2');
  await expect(page.locator('.file-card')).toHaveCount(40);
  await expect.poll(() => sources(state).filter(call => call.args.ref === sha).length).toBe(40);
  await expect(page.locator('.loading-inline')).toHaveCount(0);
  tail.resolve(); await settleRegions(page);
  await toggle(page, 30);
  await expect(card(page, 30)).toHaveClass('file-card expanded');
  await expect(card(page, 30)).toContainText('99');
  await expect(card(page, 31)).toHaveClass('file-card');
});
