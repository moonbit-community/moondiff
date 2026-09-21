import { test, expect } from '@playwright/test';
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
  await settleRegions(page);
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
      const session = await page.context().newCDPSession(page);
      await session.send('Emulation.setCPUThrottlingRate', { rate });
      const before = await renderCounts(page);
      const durations = [];
      for (let i = 0; i < 4; i++) {
        durations.push(await toggleCommit(page));
        await expect(card(page, 0)).toHaveClass(i % 2 ? 'file-card expanded' : 'file-card');
        await settleRegions(page);
      }
      const after = await renderCounts(page);
      unchanged(before, after, fixture.files.slice(1).map(f => f.filename));
      const local = fixture.files[0].filename;
      expect(after.files[local].view - before.files[local].view).toBe(4);
      expect(after.files[local].diff).toBe(before.files[local].diff);
      expect(after.files[local].highlight).toBe(before.files[local].highlight);
      expect(after.files[local].patch).toBe(before.files[local].patch);
      expect(after.files[local].vdom).toBeGreaterThan(before.files[local].vdom);
      await info.attach('render-performance.json', { contentType: 'application/json', body: JSON.stringify({ fixture: name, rate, durations, longTasks: after.longTasks.slice(before.longTasks.length), before, after }, null, 2) });
      await session.send('Emulation.setCPUThrottlingRate', { rate: 1 });
    });
  }
}

const median = values => {
  const sorted = values.slice().sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
};

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
    // Materialize the intentionally slow baseline before throttling. Repeatedly
    // switching a 56k-node page back to full rendering would benchmark the
    // test setup rather than the disclosure interaction.
    await setContained(false);
    await session.send('Emulation.setCPUThrottlingRate', { rate: 6 });
    await measure(false); await measure(false);
    samples.visible.length = 0;
    for (let i = 0; i < 4; i++) await measure(false);

    await setContained(true);
    await measure(true); await measure(true);
    samples.contained.length = 0;
    for (let i = 0; i < 4; i++) await measure(true);
  } finally {
    await session.send('Emulation.setCPUThrottlingRate', { rate: 1 });
    await setContained(true);
  }
  const containedMedian = median(samples.contained.map(sample => sample.duration));
  const visibleMedian = median(samples.visible.map(sample => sample.duration));
  await info.attach('ci-disclosure-paint.json', {
    contentType: 'application/json',
    body: JSON.stringify({ containedMedian, visibleMedian, samples, containment }, null, 2),
  });
  expect(containedMedian).toBeLessThan(visibleMedian * 0.8);
});
