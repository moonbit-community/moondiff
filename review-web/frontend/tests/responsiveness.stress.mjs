import { expect, test } from '@playwright/test';
import { readFile, writeFile } from 'node:fs/promises';
import { installRenderingFixture, syntheticFixture } from './rendering-fixture.mjs';
import { installRenderProbe, instrumentRenderProbe, settleRegions } from '../../tests/render-probe.mjs';
import { successFixture } from '../../tests/protocol-fixtures.mjs';
import { minifyFrontend } from '../../scripts/minify.mjs';

const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const percentile = (values, p) => [...values].sort((a, b) => a - b)[Math.ceil(values.length * p) - 1];
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
  for (let round = 0; round < 8; round++) {
    // Interleave the two builds to reduce time-dependent host-load bias.
    for (const variant of baseline ? (round % 2 ? ['current', 'baseline'] : ['baseline', 'current']) : ['current']) {
      const context = await browser.newContext();
      try {
        const page = await context.newPage();
        await installRenderProbe(page);
        await page.addInitScript(() => {
          const now = Date.now;
          window.fixtureAge = 0;
          Date.now = () => now() + window.fixtureAge;
        });
        if (variant === 'baseline') await page.route(/\/index\.[a-f\d]+\.js$/, handler => handler.fulfill({ body: baseline, contentType: 'text/javascript' }));
        await installRenderingFixture(page, fixture, { authenticated: true });
        const requests = [], responses = [];
        const pendingBodies = [], activeRequests = new Set();
        let lastActivity = Date.now();
        page.on('request', request => {
          if (request.url().endsWith('/api/rpc')) {
            requests.push(request.postDataJSON().request.$tag);
            activeRequests.add(request); lastActivity = Date.now();
          }
        });
        const finished = request => {
          if (activeRequests.delete(request)) lastActivity = Date.now();
        };
        page.on('requestfinished', finished);
        page.on('requestfailed', finished);
        page.on('response', response => {
          if (response.url().endsWith('/api/rpc')) pendingBodies.push(response.body().then(body => responses.push(body.length)).catch(() => {}));
        });
        await page.route('**/api/rpc', async handler => {
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
          if (scenario === 'repeat') await page.evaluate(() => { window.fixtureAge += 300_000; });
          const begin = requests.length, bytesBegin = responses.length;
          const duration = await enter(page, route, scenario === 'history');
          await expect(page.locator('.loading-inline')).toHaveCount(0);
          await settleRegions(page);
          await expect.poll(() => activeRequests.size === 0 && Date.now() - lastActivity >= 100, { intervals: [25] }).toBe(true);
          await Promise.all(pendingBodies);
          const metrics = await page.evaluate(() => window.__moondiffMetrics);
          sample[scenario] = {
            ms: duration, requests: requests.length - begin,
            responseBytes: responses.slice(bytesBegin).reduce((sum, value) => sum + value, 0),
            snapshotRpcs: requests.slice(begin).filter(kind => ['PullSnapshotGet', 'CompareGet', 'PullFiles'].includes(kind)).length,
            cacheHitRate: metrics.prefetch?.hit_rate || 0,
            files: Object.fromEntries(Object.entries(metrics.files).map(([path, counts]) => [path, { diff: counts.diff, highlight: counts.highlight }])),
          };
          if (variant === 'current' && scenario !== 'cold') expect(sample[scenario].files).toEqual(sample.cold.files);
        }
        if (variant === 'current') expect(sample.cold.snapshotRpcs).toBe(1);
        samples[variant].push(sample);
      } finally { await context.close(); }
    }
  }
  const summary = Object.fromEntries(Object.entries(samples).map(([variant, rounds]) => [variant,
    Object.fromEntries(['cold', 'repeat', 'history'].map(scenario => [scenario, {
      p50: percentile(rounds.map(round => round[scenario].ms), .5),
      p95: percentile(rounds.map(round => round[scenario].ms), .95),
      meanRequests: rounds.reduce((sum, round) => sum + round[scenario].requests, 0) / rounds.length,
      meanResponseBytes: rounds.reduce((sum, round) => sum + round[scenario].responseBytes, 0) / rounds.length,
      cacheHitRate: rounds.at(-1)[scenario].cacheHitRate,
    }]))]));
  const report = info.outputPath('response-performance.json');
  await writeFile(report, JSON.stringify({ model: '25ms browser + 25ms upstream stages; eight interleaved rounds; two MoonBit files, 24 declarations each; repeat after five minutes', summary, samples }, null, 2));
  await info.attach('response-performance.json', { contentType: 'application/json', path: report });
  console.log(JSON.stringify(summary));
});
