import { chromium } from '@playwright/test';
import { resolve, join } from 'node:path';
import { tmpdir } from 'node:os';
import { cpSync, copyFileSync, readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { gunzipSync } from 'node:zlib';
import { buildServer, startServer, repository as root } from '../backend/tests/server-fixture.mjs';
import { syntheticFixture, installRenderingFixture } from '../frontend/tests/rendering-fixture.mjs';
import { toggleCommit, settleRegions } from './render-probe.mjs';
// Both workspaces must already have release JS bundles; no source is edited.
if (!process.argv[2]) throw new Error('Usage: node tests/benchmark-rendering.mjs <built-baseline-workspace> [results.json]');
const baseline = resolve(process.argv[2]);
const output = process.argv[3] ?? join(tmpdir(), 'moondiff-render-comparison.json');
const parser = JSON.parse(gunzipSync(readFileSync(root + '/playground/frontend/tests/fixtures/parser-836b5e03.json.gz')));
const assets = [], servers = [], results = [];
let browser;
try {
  buildServer();
  for (const source of [baseline, root]) {
    const dir = mkdtempSync(join(tmpdir(), 'moondiff-render-benchmark-assets-')); assets.push(dir);
    cpSync(source + '/playground/frontend/public', dir, { recursive: true });
    copyFileSync(source + '/_build/js/release/build/moonbit-community/moondiff-playground/main/main.js', dir + '/index.js');
    servers.push(await startServer(undefined, { staticDir: dir }));
  }
  browser = await chromium.launch();
  for (const [name, fixture] of [['parser-836b5e03', parser], ['synthetic-small', syntheticFixture({ files: 4, declarations: 12 })], ['synthetic-large', syntheticFixture({ files: 12, declarations: 80 })]]) {
    for (const rate of [1, 6]) for (const [i, label] of ['before', 'after'].entries()) {
      const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
      await page.addInitScript(() => {
        window.longTasks = [];
        new PerformanceObserver(list => { for (const e of list.getEntries()) window.longTasks.push({ start: e.startTime, duration: e.duration }); }).observe({ type: 'longtask', buffered: true });
      });
      await installRenderingFixture(page, fixture);
      await page.goto(servers[i].base + '/example/regions/commit/' + fixture.sha);
      await page.waitForFunction(count => document.querySelectorAll('.file-card').length === count && !document.querySelector('.loading-inline'), fixture.files.length, { timeout: 60000 });
      await settleRegions(page);
      const shape = await page.evaluate(() => ({ rows: document.querySelectorAll('table tr').length, elements: document.querySelectorAll('*').length }));
      const session = await page.context().newCDPSession(page);
      await session.send('Emulation.setCPUThrottlingRate', { rate });
      const start = await page.evaluate(() => performance.now()), durations = [];
      for (let n = 0; n < 4; n++) { durations.push(await toggleCommit(page)); await settleRegions(page); }
      const longTasks = await page.evaluate(start => window.longTasks.filter(e => e.start >= start), start);
      const result = { fixture: name, label, rate, shape, durations, longTasks }; results.push(result); console.log(JSON.stringify(result));
      await page.close();
    }
  }
  writeFileSync(output, JSON.stringify(results, null, 2));
} finally {
  await browser?.close();
  for (const server of servers) await server.close();
  for (const dir of assets) rmSync(dir, { recursive: true, force: true });
}
