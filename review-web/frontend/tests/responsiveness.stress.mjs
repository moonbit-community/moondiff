import { requestsFor, waitUntil, trackRoute } from '../../tests/browser-control.mjs';
import { writePerformanceReport, comparisonOrder } from '../../tests/performance-report.mjs';
import { expect, test } from '../../tests/browser-test.mjs';
import { readFile } from 'node:fs/promises';
import { installRenderingFixture, syntheticFixture } from './rendering-fixture.mjs';
import { installRenderProbe, instrumentRenderProbe, settleRegions, waitForState } from '../../tests/render-probe.mjs';
import { successFixture } from '../../tests/protocol-fixtures.mjs';
import { minifyFrontend } from '../../scripts/minify.mjs';

const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const route = '/example/regions/pull/9';

async function enter(page, path, history = false) {
  return page.evaluate(({ path, history: back }) => new Promise(resolve => {
    const start = performance.now();
    let readyFrames = 0;
    const frame = () => {
      const ready = location.pathname === path && document.querySelector('.diff-scroll table');
      readyFrames = ready ? readyFrames + 1 : 0;
      if (readyFrames >= 2) resolve(performance.now() - start);
      else requestAnimationFrame(frame);
    };
    if (back) window.history.back();
    else {
      const sequence = (window.history.state?.moondiff?.sequence || 0) + 1;
      window.history.pushState({ moondiff: { id: crypto.randomUUID(), sequence, path } }, '', path);
      dispatchEvent(new PopStateEvent('popstate'));
    }
    requestAnimationFrame(frame);
  }), { path, history });
}

test('fixed latency cold, five-minute repeat and history performance', async ({ browser }, info) => {
  test.setTimeout(150_000);
  const baseline = process.env.MOONDIFF_BASELINE_JS
    ? minifyFrontend(instrumentRenderProbe(await readFile(process.env.MOONDIFF_BASELINE_JS, 'utf8')))
    : null;
  const fixture = syntheticFixture({ files: 2, declarations: 24 });
  fixture.files[0].filename = 'src/primary.mbt';
  fixture.sources = Object.fromEntries(Object.entries(fixture.sources).map(([key, value]) => [key.replace(':local_test.mbt', ':src/primary.mbt'), value]));
  const samples = { current: [], ...(baseline ? { baseline: [] } : {}) };
  const orders = baseline ? comparisonOrder.map(order => order.map(mode => mode === 'A' ? 'current' : 'baseline')) : Array.from({ length: 8 }, () => ['current']);
  for (const [round, order] of orders.entries()) {
    for (const variant of order) for (let iteration = 0; iteration < (baseline ? 3 : 1); iteration++) {
      const context = await browser.newContext();
      try {
        const page = await context.newPage();
        await installRenderProbe(page);
        await page.clock.setFixedTime(new Date('2026-08-18T01:00:00Z'));
        if (variant === 'baseline') await page.route(/\/index\.[a-f\d]+\.js$/, handler => handler.fulfill({ body: baseline, contentType: 'text/javascript' }));
        await installRenderingFixture(page, fixture, { authenticated: true });
        const requests = [], recorder = requestsFor(page);
        const activeRequests = new Set();
        page.on('request', request => {
          if (request.url().endsWith('/api/rpc')) {
            requests.push(request.postDataJSON().request.$tag);
            activeRequests.add(request);
          }
        });
        const finished = request => {
          activeRequests.delete(request);
        };
        page.on('requestfinished', finished);
        page.on('requestfailed', finished);
        await page.route('**/api/rpc', async handler => {
          handler = trackRoute(handler);
          const { request } = handler.request().postDataJSON();
          // Model 25ms browser round-trip plus 25ms for each upstream stage.
          // Aggregate: metadata, parallel compare/files, independent validation.
          await pause(request.$tag === 'PullSnapshotGet' ? 100 : 50);
          if (request.$tag !== 'PullSnapshotGet') return handler.fallback();
          await handler.fulfill({ json: successFixture('github.pull.snapshot.get', { $tag: 'Complete', '0': {
            metadata: { title: fixture.message, html_url: 'https://github.com/example/regions/pull/9',
              base: { sha: fixture.base, repo: { full_name: 'example/regions' } },
              head: { sha: fixture.sha, repo: { full_name: 'example/regions' } },
              additions: 1, deletions: 1, changed_files: 2, commits: 0 },
            comparison: { merge_base_commit: { sha: fixture.base } }, files: fixture.files, signature: 'performance-fixture',
          } }) });
        });
        await page.goto('/');
        await expect(page.getByRole('tab').first()).toBeVisible();
        const sample = {};
        for (const scenario of ['cold', 'repeat', 'history']) {
          if (scenario !== 'cold') {
            await page.locator('a.workspace-home').click();
            await expect(page.getByRole('tab').first()).toBeVisible();
          }
          if (scenario === 'repeat') await page.clock.setFixedTime(new Date('2026-08-18T01:05:00Z'));
          const begin = requests.length, after = recorder.checkpoint();
          const duration = await enter(page, route, scenario === 'history');
          await expect(page.locator('.loading-inline')).toHaveCount(0);
          await settleRegions(page);
          await waitForState(page, state => state.reads === 0 && state.tasks === 0 &&
            state.backgroundOwner === null && !state.checking &&
            state.application?.viewed.ready && !state.application.viewed.loading && !state.application.merge.loading, 'completed navigation requests');
          await waitUntil(() => activeRequests.size === 0, { label: 'all RPC bodies received', diagnostic: () => requestsFor(page).snapshot() });
          const received = recorder.matching({ after, target: '/api/rpc' });
          expect(received.filter(request => request.phases.failed || request.phases.cancelled ||
            request.phases.received === undefined || !Number.isFinite(request.responseBytes))).toEqual([]);
          const metrics = await page.evaluate(() => window.__moondiffMetrics);
          expect(metrics.errors).toEqual([]);
          sample[scenario] = {
            ms: duration, requests: requests.length - begin,
            responseBytes: received.reduce((sum, request) => sum + request.responseBytes, 0),
            snapshotRpcs: requests.slice(begin).filter(kind => ['PullSnapshotGet', 'CompareGet', 'PullFiles'].includes(kind)).length,
            cacheHitRate: metrics.prefetch?.hit_rate || 0,
            files: Object.fromEntries(Object.entries(metrics.files).map(([path, counts]) => [path, { diff: counts.diff, highlight: counts.highlight }])),
          };
          if (variant === 'current' && scenario !== 'cold') expect(sample[scenario].files).toEqual(sample.cold.files);
        }
        if (variant === 'current') expect(sample.cold.snapshotRpcs).toBe(1);
        if (!baseline || iteration > 0) samples[variant].push({ round, ...sample });
      } finally { await context.close(); }
    }
  }
  await writePerformanceReport(info, 'response-performance.json', {
    fixture: { files: 2, declarations: 24, browserLatencyMs: 25, upstreamStageLatencyMs: 25 }, cpuRate: 1,
    sampling: baseline ? 'AB/BA; one warm-up and two samples per mode per round' : 'eight samples per scenario', samples,
    groups: Object.fromEntries(Object.entries(samples).flatMap(([variant, rounds]) =>
      ['cold', 'repeat', 'history'].map(scenario => [`${variant}.${scenario}`, rounds.map(sample => sample[scenario].ms)]))),
  });
});
