import { test, expect } from '../../tests/browser-test.mjs';
import { fixtureRequest, successFixture } from '../../tests/protocol-fixtures.mjs';
import { settleRegions } from '../../tests/render-probe.mjs';
import { gate, installRenderingFixture, syntheticFixture } from './rendering-fixture.mjs';

function interfaceFixture(count = 5) {
  const fixture = syntheticFixture({ files: 0 });
  function add(filename, status = 'modified', previous_filename) {
    const source = filename.endsWith('.mbt');
    const old = source ? 'fn value() -> Int { 1 }\n' : 'pub fn value() -> Int\n';
    const next = source ? 'fn value() -> Int { 2 }\n' : 'pub fn value() -> String\n';
    const additions = status === 'removed' ? 0 : 1;
    const deletions = status === 'added' ? 0 : 1;
    fixture.files.push({ filename, status, previous_filename, additions, deletions, changes: additions + deletions,
      patch: `@@ -${deletions},${deletions} +${additions},${additions} @@\n${deletions ? `-${old}` : ''}${additions ? `+${next}` : ''}` });
    if (deletions) fixture.sources[`${fixture.base}:${previous_filename ?? filename}`] = old;
    if (additions) fixture.sources[`${fixture.sha}:${filename}`] = next;
  }
  add('z/source.mbt');
  add('z/deep/pkg.generated.mbti');
  add('a/main.mbt');
  add('pkg.generated.mbti', 'added');
  add('renamed/interface.txt', 'renamed', 'old/pkg.generated.mbti');
  add('removed/pkg.generated.mbti', 'removed');
  add('new/pkg.generated.mbti', 'renamed', 'old/interface.txt');
  add('README.md');
  for (let i = 5; i < count; i++) add(`extra/part-${i}/pkg.generated.mbti`);
  return fixture;
}

async function installFixture(page, fixture, options) {
  const state = await installRenderingFixture(page, fixture, { authenticated: true, ...options });
  await page.route('**/api/rpc', async route => {
    const { op, args } = fixtureRequest(route.request().postDataJSON());
    if (op !== 'github.range.compare.get') return route.fallback();
    state.calls.push({ op, args });
    await route.fulfill({ json: successFixture(op, {
      base_commit: { sha: fixture.base, commit: { message: 'Base' }, parents: [] },
      merge_base_commit: { sha: fixture.base }, total_commits: 1,
      commits: [{ sha: fixture.sha, commit: { message: fixture.message }, parents: [{ sha: fixture.base }] }],
      files: fixture.files,
    }) });
  });
  return state;
}

const card = (page, index) => page.locator(`#moondiff-file-${index}`);
const sources = state => state.calls.filter(call => call.op === 'github.content.get');
const sourceKey = args => `${args.ref}:${args.path}`;
const paths = page => page.locator('.file-card').evaluateAll(cards => cards.map(card => card.dataset.filePath));
const orderedPaths = ['z/deep/pkg.generated.mbti', 'pkg.generated.mbti', 'renamed/interface.txt',
  'removed/pkg.generated.mbti', 'new/pkg.generated.mbti', 'z/source.mbt', 'a/main.mbt', 'README.md'];

const routes = {
  PR: f => '/example/regions/pull/1',
  Commit: f => `/example/regions/commit/${f.sha}`,
  PullCommit: f => `/example/regions/pull/1/commits/${f.sha}`,
  Range: f => `/example/regions/compare/${f.base}..${f.sha}`,
  'PR range': f => `/example/regions/pull/1/compare/${f.base}..${f.sha}`,
};

for (const [kind, route] of Object.entries(routes)) {
  test(`${kind} pins interfaces globally and requests them first with four concurrent sides`, async ({ page }) => {
    const fixture = interfaceFixture();
    const pending = new Map();
    const state = await installFixture(page, fixture, { sourceGate: args => {
      const blocked = gate(); pending.set(sourceKey(args), blocked); return blocked.promise;
    } });
    const ordered = orderedPaths.slice(0, -1).map(path => fixture.files.find(file => file.filename === path));
    const expected = ordered.flatMap(file => [
      ...(file.status === 'added' ? [] : [`${fixture.base}:${file.previous_filename ?? file.filename}`]),
      ...(file.status === 'removed' ? [] : [`${fixture.sha}:${file.filename}`]),
    ]);
    const interfaceSides = expected.length - 4;
    await page.goto(route(fixture));
    await expect.poll(() => paths(page)).toEqual(orderedPaths);
    await expect(page.locator('.file-card.expanded')).toHaveCount(7);
    await expect.poll(() => sources(state).length).toBe(4);
    expect(sources(state).map(call => sourceKey(call.args))).toEqual(expected.slice(0, 4));
    // Retain the first interface side while freeing slots for every later file.
    for (let i = 1; i <= interfaceSides - 3; i++) {
      pending.get(expected[i]).resolve();
      await expect.poll(() => sources(state).length).toBe(4 + i);
    }
    expect(sources(state).map(call => sourceKey(call.args))).toEqual(expected.slice(0, interfaceSides + 1));
    expect(sources(state).at(-1).args.path).toBe('z/source.mbt');
    expect(state.activeSources).toBe(4);
    state.sourceGate = null;
    for (const blocked of pending.values()) blocked.resolve();
    await expect(page.locator('.loading-inline')).toHaveCount(0);
    await expect.poll(() => sources(state).length).toBe(expected.length);
    expect(state.maxActiveSources).toBe(4);
    expect(sources(state).map(call => sourceKey(call.args))).toEqual(expected);
  });
}

test('more than twenty interfaces expand while sources keep their remaining budget', async ({ page }) => {
  const fixture = interfaceFixture(25);
  const state = await installFixture(page, fixture);
  await page.goto(`/example/regions/commit/${fixture.sha}`);
  await expect(page.locator('.file-card')).toHaveCount(28);
  await expect(page.locator('.file-card.expanded')).toHaveCount(25);
  await expect(page.locator('.loading-inline')).toHaveCount(0);
  expect((await paths(page)).slice(-3)).toEqual(['z/source.mbt', 'a/main.mbt', 'README.md']);
  expect(sources(state)).toHaveLength(48);
  expect(sources(state).some(call => call.args.path.endsWith('.mbt'))).toBe(false);
  expect(state.maxActiveSources).toBeLessThanOrEqual(4);
});

test('reordered indices preserve tree directories, comments, Viewed and saved collapse state', async ({ page }) => {
  const fixture = interfaceFixture();
  const state = await installFixture(page, fixture, {
    viewed: { 'a/main.mbt': true },
    comments: [{ id: '20', body: 'Interface discussion', user: { login: 'reviewer' },
      html_url: 'https://github.com/example/regions/pull/1#discussion_r20',
      created_at: '2026-09-01T00:00:00Z', path: 'renamed/interface.txt', line: 1, side: 'RIGHT',
      position: 2, commit_id: fixture.sha }],
  });
  await page.goto('/example/regions/pull/1');
  await expect.poll(() => paths(page)).toEqual(orderedPaths);
  await expect(page.locator('.loading-inline')).toHaveCount(0);
  await expect(card(page, 2).getByText('Interface discussion', { exact: true })).toBeAttached();
  await expect(card(page, 6).getByRole('checkbox', { name: 'Viewed a/main.mbt', exact: true })).toBeChecked();
  await expect(card(page, 6)).toHaveClass('file-card');
  const tree = page.locator('[data-region="tree"]');
  await expect(tree.locator('[aria-label="Open z/deep/pkg.generated.mbti"]')).toHaveAttribute('aria-level', '3');
  const source = tree.locator('[aria-label="Open z/source.mbt"]');
  await expect(source).toHaveAttribute('aria-level', '2');
  await source.evaluate(button => button.click());
  await expect(source).toHaveAttribute('aria-selected', 'true');
  await settleRegions(page);
  await expect(card(page, 5)).toBeInViewport();
  await expect(card(page, 5)).toHaveAttribute('data-file-path', 'z/source.mbt');
  await card(page, 1).getByRole('checkbox', { name: 'Viewed pkg.generated.mbti', exact: true }).evaluate(box => box.click());
  await expect.poll(() => state.calls.filter(call => call.op === 'github.pull.file.viewed.set').map(call => call.args.path)).toEqual(['pkg.generated.mbti']);
  await expect(card(page, 1).getByRole('checkbox')).toBeChecked();
  await expect(card(page, 0).getByRole('checkbox')).not.toBeChecked();
  await card(page, 0).locator('.file-toggle').evaluate(button => button.click());
  await expect(card(page, 0)).toHaveClass('file-card');
  await page.locator('a.workspace-home').evaluate(link => link.click());
  await expect(page.locator('.file-card')).toHaveCount(0);
  await page.goBack();
  await expect.poll(() => paths(page)).toEqual(orderedPaths);
  await expect(card(page, 0)).toHaveClass('file-card');
  await expect(card(page, 2).getByText('Interface discussion', { exact: true })).toBeAttached();
  await expect(card(page, 6).getByRole('checkbox')).toBeChecked();
});

for (const [kind, route] of Object.entries(routes)) {
  test(`${kind} anonymous initial expansion caps 35 interfaces at twenty files`, async ({ page }) => {
    const fixture = interfaceFixture(35);
    const state = await installFixture(page, fixture, { authenticated: false });
    await page.goto(route(fixture));
    await expect(page.locator('.file-card')).toHaveCount(38);
    await expect(page.locator('.file-card.expanded')).toHaveCount(20);
    await expect(page.locator('.loading-inline')).toHaveCount(0);
    // Added and deleted interfaces each need just one side.
    expect(sources(state)).toHaveLength(38);
    expect(state.maxActiveSources).toBeLessThanOrEqual(4);
    const ordered = await paths(page);
    expect(ordered.slice(0, 5)).toEqual(orderedPaths.slice(0, 5));
    expect(sources(state).every(call => !call.args.path.endsWith('.mbt'))).toBe(true);
  });
}
