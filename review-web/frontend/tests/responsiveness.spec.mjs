import { expect, test } from '../../tests/browser-test.mjs';
import { installRenderingFixture, syntheticFixture, gate } from './rendering-fixture.mjs';
import { installRenderProbe, settleRegions } from '../../tests/render-probe.mjs';
import { successFixture } from '../../tests/protocol-fixtures.mjs';

function responseFixture(options) {
  const value = syntheticFixture(options);
  value.files[0].filename = 'src/primary.mbt';
  value.sources = Object.fromEntries(Object.entries(value.sources).map(([key, source]) => [key.replace(':local_test.mbt', ':src/primary.mbt'), source]));
  return value;
}

for (const age of [31_000, 300_000]) test(`history restores cached diff and highlights before blocked metadata after ${age}ms`, async ({ page }) => {
  await installRenderProbe(page);
  const fixture = responseFixture({ files: 2, declarations: 8 });
  const state = await installRenderingFixture(page, fixture, { authenticated: true });
  await page.goto('/example/regions/pull/1');
  await expect(page.locator('.loading-inline')).toHaveCount(0);
  await expect(page.locator('.file-card').filter({ has: page.locator('.diff-scroll table') })).toHaveCount(2);
  await page.getByRole('link', { name: /Moondiff/ }).click();
  await expect(page.getByRole('tab').first()).toBeVisible();
  await settleRegions(page);
  const before = await page.evaluate(() => window.__moondiffMetrics.files);
  const sources = state.calls.filter(call => call.op === 'github.content.get').length;
  await page.clock.setFixedTime(new Date(Date.now() + age));
  const metadata = gate(); let held = false;
  await page.route('**/api/rpc', async route => {
    if (route.request().postDataJSON().request.$tag === 'PullGet') {
      held = true; await metadata.promise;
    }
    await route.fallback();
  });
  await page.goBack();
  await expect.poll(() => held).toBe(true);
  await expect(page.locator('.file-card').filter({ has: page.locator('.diff-scroll table') })).toHaveCount(2);
  await expect(page.getByText('Checking the current PR version…', { exact: true })).toBeVisible();
  await settleRegions(page);
  const during = await page.evaluate(() => window.__moondiffMetrics.files);
  for (const file of fixture.files) {
    expect(during[file.filename].diff).toBe(before[file.filename].diff);
    expect(during[file.filename].highlight).toBe(before[file.filename].highlight);
  }
  expect(state.calls.filter(call => call.op === 'github.content.get')).toHaveLength(sources);
  metadata.resolve();
  await expect(page.getByText('Checking the current PR version…', { exact: true })).toHaveCount(0);
});

test('an eligible cold visit uses one complete snapshot RPC', async ({ page }) => {
  const fixture = responseFixture({ files: 2, declarations: 4 });
  await installRenderingFixture(page, fixture, { authenticated: true });
  const reads = [];
  page.on('request', request => {
    if (request.url().endsWith('/api/rpc')) reads.push(request.postDataJSON().request.$tag);
  });
  await page.route('**/api/rpc', async route => {
    if (route.request().postDataJSON().request.$tag !== 'PullSnapshotGet') return route.fallback();
    await route.fulfill({ json: successFixture('github.pull.snapshot.get', { $tag: 'Complete', '0': {
      metadata: { title: fixture.message, html_url: 'https://github.com/example/regions/pull/1',
        base: { sha: fixture.base, repo: { full_name: 'example/regions' } },
        head: { sha: fixture.sha, repo: { full_name: 'example/regions' } },
        additions: 1, deletions: 1, changed_files: fixture.files.length, commits: 0 },
      comparison: { merge_base_commit: { sha: fixture.base } }, files: fixture.files, signature: 'fixed-fixture',
    } }) });
  });
  await page.goto('/example/regions/pull/1');
  await expect(page.locator('.file-card').filter({ has: page.locator('.diff-scroll table') })).toHaveCount(2);
  expect(reads.filter(kind => kind === 'PullSnapshotGet')).toHaveLength(1);
  expect(reads.filter(kind => ['CompareGet', 'PullFiles'].includes(kind))).toHaveLength(0);
});

for (const draft of [false, true]) test(`a prepared new version ${draft ? 'preserves a draft created during source loading' : 'switches after its target source is ready'}`, async ({ page }) => {
  const fixture = responseFixture({ files: 1, declarations: 4 });
  const state = await installRenderingFixture(page, fixture, { authenticated: true });
  await page.goto('/example/regions/pull/1');
  await expect(page.locator('.diff-scroll table').first()).toBeVisible();
  await page.getByRole('link', { name: /Moondiff/ }).click();
  await expect(page.getByRole('tab').first()).toBeVisible();
  const sha = 'd'.repeat(40);
  state.fixture = { ...fixture, sha, sources: { ...fixture.sources,
    [`${sha}:${fixture.files[0].filename}`]: 'pub fn new_revision() -> Int { 42 }\n',
  } };
  const sources = gate(); let held = false;
  await page.route('**/api/rpc', async route => {
    const request = route.request().postDataJSON().request;
    if (request.$tag === 'ContentGet' && request['0'].revision === sha) {
      held = true; await sources.promise;
    }
    await route.fallback();
  });
  await page.goBack();
  await expect.poll(() => held).toBe(true);
  await expect(page.locator('.file-card')).toContainText('value_0');
  await expect(page.locator('.file-card')).not.toContainText('new_revision');
  if (draft) {
    await page.getByRole('button', { name: 'Add overall comment' }).click();
    await page.locator('.comment-editor textarea').fill('This draft belongs to the old version');
  }
  sources.resolve();
  if (draft) {
    await expect(page.getByText(/This PR has a newer version/)).toBeVisible();
    await expect(page.locator('.file-card')).toContainText('value_0');
    await expect(page.locator('.comment-editor textarea')).toHaveValue('This draft belongs to the old version');
    await expect(page.getByRole('button', { name: 'Post comment' })).toBeDisabled();
  } else {
    await expect(page.locator('.file-card')).toContainText('new_revision');
    await expect(page.getByText('Checking the current PR version…', { exact: true })).toHaveCount(0);
  }
});

test('parsed page retention releases DOM immediately and evicted source states after two later pages', async ({ page }) => {
  await installRenderProbe(page);
  await installRenderingFixture(page, responseFixture({ files: 2, declarations: 4 }), { authenticated: true });
  await page.goto('/example/regions/pull/1');
  await expect(page.locator('.diff-scroll table').first()).toBeVisible();
  await expect(page.locator('.loading-inline')).toHaveCount(0);
  await settleRegions(page);
  await page.evaluate(() => {
    window.retainedDOM = Array.from(document.querySelectorAll('.file-card'), node => new WeakRef(node));
    window.retainedSources = window.__moondiffMetrics.sources.slice();
  });
  await page.getByRole('link', { name: /Moondiff/ }).click();
  await expect(page.getByRole('tab').first()).toBeVisible();
  await settleRegions(page);
  const session = await page.context().newCDPSession(page);
  await session.send('HeapProfiler.collectGarbage');
  expect(await page.evaluate(() => retainedDOM.filter(ref => ref.deref()).length)).toBe(0);
  expect(await page.evaluate(() => retainedSources.filter(ref => ref.deref()).length)).toBeGreaterThan(0);
  for (const number of [2, 3]) {
    await page.evaluate(number => {
      const path = `/example/regions/pull/${number}`;
      history.pushState({ moondiff: { id: crypto.randomUUID(), sequence: history.state.moondiff.sequence + 1, path } }, '', path);
      dispatchEvent(new PopStateEvent('popstate'));
    }, number);
    await expect(page.locator('.diff-scroll table').first()).toBeVisible();
    await expect(page.locator('.loading-inline')).toHaveCount(0);
    await page.getByRole('link', { name: /Moondiff/ }).click();
    await expect(page.getByRole('tab').first()).toBeVisible();
  }
  await settleRegions(page);
  await session.send('HeapProfiler.collectGarbage');
  expect(await page.evaluate(() => retainedSources.filter(ref => ref.deref()).length)).toBe(0);
});
