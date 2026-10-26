import { writePerformanceReport, comparisonOrder } from '../../tests/performance-report.mjs';
import { test, expect } from '../../tests/browser-test.mjs';
import { readFileSync } from 'node:fs';
import { gunzipSync } from 'node:zlib';
import { installRenderProbe, renderCounts, settleRegions, toggleCommit, toggleDetailsPaint } from '../../tests/render-probe.mjs';
import { installRenderingFixture, syntheticFixture } from './rendering-fixture.mjs';

const parser = JSON.parse(gunzipSync(readFileSync(new URL('./fixtures/parser-836b5e03.json.gz', import.meta.url))));
const card = (page, index) => page.locator(`#moondiff-file-${index}`);
const route = fixture => `/example/regions/commit/${fixture.sha}`;

async function loaded(page, fixture) {
  await expect(page.locator('.file-card')).toHaveCount(fixture.files.length);
  await expect(page.locator('.loading-inline')).toHaveCount(0, { timeout: 30_000 });
  await settleRegions(page, 30_000);
}
function unchanged(before, after, paths) {
  for (const path of paths) expect(after.files[path], `unrelated ${path}`).toEqual(before.files[path]);
  expect(after.errors).toEqual([]);
}

for (const [name, fixture] of [
  ['parser-836b5e03', parser],
  ['synthetic-small', syntheticFixture({ files: 4, declarations: 12 })],
  ['synthetic-large', syntheticFixture({ files: 12, declarations: 80 })],
]) {
  for (const rate of [1, 6]) {
    test(`independent ignored-file rendering: ${name}, ${rate}x CPU`, async ({ page }, info) => {
      test.setTimeout(90_000);
      await installRenderProbe(page);
      await installRenderingFixture(page, fixture);
      await page.goto(route(fixture)); await loaded(page, fixture);
      const local = fixture.files[0].filename;
      const localCard = page.locator(`.file-card[data-file-path="${local}"]`);
      await expect(localCard).toHaveCount(1);
      const localId = await localCard.getAttribute('id');
      expect(localId).toBeTruthy();
      const session = await page.context().newCDPSession(page);
      await session.send('Emulation.setCPUThrottlingRate', { rate });
      const before = await renderCounts(page, 30_000);
      const durations = [];
      for (let i = 0; i < 4; i++) {
        durations.push(await toggleCommit(page, localId));
        await expect(localCard).toHaveClass(i % 2 ? 'file-card expanded' : 'file-card');
        await settleRegions(page, 30_000);
      }
      const after = await renderCounts(page, 30_000);
      unchanged(before, after, fixture.files.filter(f => f.filename !== local).map(f => f.filename));
      expect(after.files[local].view - before.files[local].view).toBe(4);
      expect(after.files[local].diff).toBe(before.files[local].diff);
      expect(after.files[local].highlight).toBe(before.files[local].highlight);
      expect(after.files[local].patch).toBe(before.files[local].patch);
      expect(after.files[local].vdom).toBeGreaterThan(before.files[local].vdom);
      await writePerformanceReport(info, 'render-performance.json', { fixture: name, cpuRate: rate,
        samples: durations, groups: { commitMs: durations },
        longTasks: after.longTasks.slice(before.longTasks.length), before, after });
      await session.send('Emulation.setCPUThrottlingRate', { rate: 1 });
    });
  }
}

test('file containment keeps CI disclosure input-to-paint responsive', async ({ page }, info) => {
  test.setTimeout(150_000);
  const fixture = syntheticFixture({ files: 12, declarations: 80 });
  await installRenderProbe(page);
  await installRenderingFixture(page, fixture, {
    authenticated: true,
    mergeStatus: {
      base_sha: fixture.base,
      head_sha: fixture.sha,
      open: true,
      draft: false,
      merged: false,
      mergeable: true,
      rebaseable: true,
      mergeable_state: 'clean',
      ci_summary: { $tag: 'Success' },
      ci_checks: [
        { name: 'MoonBit tests', state: { $tag: 'Success' }, description: 'Passed', details_url: 'https://example.com/check/1', source: { $tag: 'CheckRun' } },
        { name: 'Browser tests', state: { $tag: 'Success' }, description: 'Passed', details_url: 'https://example.com/check/2', source: { $tag: 'CheckRun' } },
      ],
      ci_warnings: [],
    },
  });
  await page.goto('/example/regions/pull/1');
  await loaded(page, fixture);
  await expect(page.locator('.file-card[data-render-contained="true"]')).toHaveCount(fixture.files.length);
  const containment = await page.locator('.file-card').evaluateAll(cards => cards.map(card => ({
    visibility: getComputedStyle(card).contentVisibility,
    intrinsic: parseFloat(card.style.getPropertyValue('--file-intrinsic-block-size')),
  })));
  expect(containment.every(value => value.visibility === 'auto' && value.intrinsic > 0)).toBe(true);

  const session = await page.context().newCDPSession(page);
  const selector = '.pull-ci-disclosure > summary';
  const samples = { contained: [], visible: [] };
  const setContained = async contained => {
    await page.locator('.file-card').evaluateAll((cards, active) => {
      for (const card of cards) {
        if (active) card.style.removeProperty('content-visibility');
        else card.style.setProperty('content-visibility', 'visible');
      }
      // Resolve the style mode before timing the next input without paying for
      // five unrelated observer-settling frames on the intentionally slow
      // uncontained baseline.
      document.body.getBoundingClientRect();
    }, contained);
  };
  const measure = async contained => {
    const result = await toggleDetailsPaint(page, selector, session);
    samples[contained ? 'contained' : 'visible'].push(result);
  };
  try {
    await session.send('Emulation.setCPUThrottlingRate', { rate: 6 });
    for (const order of comparisonOrder) {
      for (const mode of order) {
        const contained = mode === 'A';
        await session.send('Emulation.setCPUThrottlingRate', { rate: 1 });
        await setContained(contained);
        await session.send('Emulation.setCPUThrottlingRate', { rate: 6 });
        // Each round/mode has one warm-up and two recorded samples.
        await toggleDetailsPaint(page, selector, session);
        await measure(contained); await measure(contained);
      }
    }
  } finally {
    await session.send('Emulation.setCPUThrottlingRate', { rate: 1 });
    await setContained(true);
  }
  await writePerformanceReport(info, 'ci-disclosure-paint.json', {
    fixture: { files: 12, declarations: 80 }, cpuRate: 6, samples,
    groups: Object.fromEntries(Object.entries(samples).map(([mode, values]) => [mode, values.map(value => value.duration)])),
    sampling: 'AB/BA; one warm-up and two samples per mode per round', containment,
  });
});

test('large PR retains more than 32 MiB of prefetched source and expands without network', async ({ page }, info) => {
  test.setTimeout(150_000);
  const fixture = syntheticFixture({ files: 60, declarations: 2 });
  for (const file of fixture.files.slice(20)) {
    for (const sha of [fixture.base, fixture.sha]) {
      fixture.sources[`${sha}:${file.filename}`] += `\n// ${'padding '.repeat(62_500)}\n`;
    }
  }
  const sourceBytes = Object.values(fixture.sources).reduce((sum, text) => sum + Buffer.byteLength(text), 0);
  expect(sourceBytes).toBeGreaterThan(32 * 1024 * 1024);
  await installRenderProbe(page);
  const state = await installRenderingFixture(page, fixture, { authenticated: true });
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Performance.enable');
  const memory = async label => {
    const { metrics } = await cdp.send('Performance.getMetrics');
    return { label, usedJSHeap: metrics.find(metric => metric.name === 'JSHeapUsedSize')?.value,
      totalJSHeap: metrics.find(metric => metric.name === 'JSHeapTotalSize')?.value };
  };
  const samples = [await memory('before navigation')];
  const started = performance.now();
  await page.goto('/example/regions/pull/1');
  await expect(page.locator('.file-card.expanded')).toHaveCount(20);
  await expect(page.locator('.loading-inline')).toHaveCount(0, { timeout: 30_000 });
  const firstScreenMs = performance.now() - started;
  samples.push(await memory('first screen'));
  const calls = () => state.calls.filter(call => call.op === 'github.content.get');
  await expect.poll(() => calls().length, { timeout: 90_000 }).toBe(120);
  await expect.poll(() => state.activeSources, { timeout: 90_000 }).toBe(0);
  await expect.poll(() => page.evaluate(() => __moondiffMetrics.pull_sources?.pending), { timeout: 30_000 }).toBe(0);
  await settleRegions(page, 30_000);
  samples.push(await memory('all source retained'));
  const prefetched = await renderCounts(page, 30_000);
  expect(prefetched.counters.prefetch_evictions).toBeGreaterThan(0);
  expect(prefetched.prefetch.cache_bytes).toBeLessThanOrEqual(32 * 1024 * 1024);
  for (const file of fixture.files.slice(20)) {
    expect(prefetched.files[file.filename]?.diff ?? 0).toBe(0);
    expect(prefetched.files[file.filename]?.highlight ?? 0).toBe(0);
  }
  state.sourceFailure = () => ({ status: 500, code: 'offline', detail: 'No source network after prefetch' });
  const scrollStarted = performance.now();
  await card(page, 20).evaluate(element => {
    window.dispatchEvent(new WheelEvent('wheel', { deltaY: 1 }));
    window.scrollTo({ top: window.scrollY + element.getBoundingClientRect().top - 160, behavior: 'instant' });
  });
  await expect(card(page, 20)).toHaveClass('file-card expanded');
  await settleRegions(page, 30_000);
  const scrollExpandMs = performance.now() - scrollStarted;
  await card(page, 59).locator('.file-toggle').evaluate(button => button.click());
  await expect(card(page, 59)).toHaveClass('file-card expanded');
  await expect(card(page, 59).locator('.loading-inline')).toHaveCount(0);
  await settleRegions(page, 30_000);
  samples.push(await memory('after local expansion'));
  const expanded = await renderCounts(page, 30_000);
  expect(calls()).toHaveLength(120);
  expect(expanded.counters.source_cache_hits ?? 0).toBe(prefetched.counters.source_cache_hits ?? 0);
  expect(state.maxActiveSources).toBeLessThanOrEqual(4);
  expect(expanded.files[fixture.files[20].filename].diff).toBeGreaterThan(0);
  await page.evaluate(() => {
    window.retiredPRSources = __moondiffMetrics.sources.slice();
    __moondiffMetrics.sources.length = 0;
  });
  await page.evaluate(() => { history.pushState(null, '', '/'); dispatchEvent(new PopStateEvent('popstate')); });
  await expect(page.locator('.file-card')).toHaveCount(0);
  await settleRegions(page, 30_000);
  expect((await renderCounts(page, 30_000)).progressive.targets).toBe(0);
  await cdp.send('HeapProfiler.collectGarbage');
  expect(await page.evaluate(() => retiredPRSources.filter(ref => ref.deref()).length)).toBe(0);
  samples.push(await memory('after leaving and GC'));
  await writePerformanceReport(info, 'pull-prefetch-performance.json', {
    fixture: { files: 60, declarations: 2, sourceBytes }, cpuRate: 1,
    samples: { firstScreenMs: [firstScreenMs], scrollExpandMs: [scrollExpandMs] },
    groups: { firstScreenMs: [firstScreenMs], scrollExpandMs: [scrollExpandMs] },
    longTasks: expanded.longTasks, memory: samples, maxSourceConcurrency: state.maxActiveSources,
    prefetchCounters: prefetched.counters, expandedCounters: expanded.counters,
  });
});
