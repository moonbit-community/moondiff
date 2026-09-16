import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { gunzipSync } from 'node:zlib';
import { installRenderProbe, renderCounts, settleRegions, toggleCommit } from '../../tests/render-probe.mjs';
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
