import { expect, test } from '@playwright/test';

const base = 'a'.repeat(40);
const merge = 'b'.repeat(40);
const head = 'c'.repeat(40);
const commit = 'd'.repeat(40);
const repository = 'https://api.github.com/repos/example/project';
const pull = {
  title: 'Public read fixture', html_url: 'https://github.com/example/project/pull/42',
  base: { sha: base }, head: { sha: head },
  additions: 1, deletions: 1, changed_files: 1, commits: 0,
};
const file = {
  filename: 'src/example.mbt', status: 'modified', additions: 1, deletions: 1,
  changes: 2, patch: '@@ -1 +1 @@\n-fn old() {}\n+fn fresh() {}',
};
const commitData = {
  sha: commit, html_url: `https://github.com/example/project/commit/${commit}`,
  commit: { message: 'Public commit fixture' }, parents: [],
  stats: { additions: 0, deletions: 0, total: 0 }, files: [],
};

async function install(page, commentResponse = () => []) {
  const requests = [];
  const rpc = [];
  await page.route('**/api/auth/status', route => route.fulfill({
    json: { $tag: 'Success', value: { authenticated: false, install_url: 'https://github.com/apps/test/installations/new' } },
  }));
  await page.route('**/api/rpc', route => {
    rpc.push(route.request().postDataJSON().request.$tag);
    return route.fulfill({ status: 401, json: { $tag: 'Failure', error: {
      status: 401, code: 'authentication_required', message: 'Sign in to continue.',
    } } });
  });
  await page.route('https://api.github.com/**', async route => {
    const request = route.request();
    const url = new URL(request.url());
    requests.push(request);
    const path = url.pathname;
    const headers = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Expose-Headers': 'x-ratelimit-remaining' };
    if (path.includes('/contents/')) {
      return route.fulfill({ status: 200, contentType: 'text/plain', body: 'fn fresh() {}\n', headers });
    }
    if (path.endsWith('/comments')) {
      const result = commentResponse(url);
      return route.fulfill(typeof result === 'string'
        ? { status: 200, contentType: 'application/json', body: result, headers }
        : { status: 200, json: result, headers });
    }
    if (path.endsWith('/pulls/42/files')) return route.fulfill({ json: [file], headers });
    if (path.endsWith('/pulls/42')) return route.fulfill({ json: pull, headers });
    if (path.includes('/compare/')) return route.fulfill({ json: { merge_base_commit: { sha: merge } }, headers });
    if (path.endsWith(`/commits/${commit}`)) return route.fulfill({ json: commitData, headers });
    return route.fulfill({ status: 404, json: { message: `Unexpected ${path}` }, headers });
  });
  return { requests, rpc };
}

test('anonymous commit and PR data use six direct GitHub read categories without credentials', async ({ page }) => {
  const { requests, rpc } = await install(page);
  await page.goto('/example/project/pull/42');
  await expect(page.getByText('Public read fixture', { exact: true }).first()).toBeVisible();
  await expect.poll(() => requests.map(r => r.url()).filter(url => url.includes('/contents/')).length).toBeGreaterThan(0);
  await expect.poll(() => requests.some(r => r.url().includes('/issues/42/comments?'))).toBe(true);
  await expect.poll(() => requests.some(r => r.url().includes('/pulls/42/comments?'))).toBe(true);
  await page.goto(`/example/project/commit/${commit}`);
  await expect(page.getByText('Public commit fixture', { exact: true }).first()).toBeVisible();
  await expect.poll(() => requests.some(r => r.url().includes(`/commits/${commit}/comments?`))).toBe(true);
  const urls = requests.map(r => r.url());
  expect(urls.some(url => url.includes('/pulls/42/files?'))).toBe(true);
  expect(urls.some(url => url.includes(`/compare/${base}...${head}`))).toBe(true);
  expect(urls.some(url => url.includes(`/commits/${commit}?`))).toBe(true);
  expect(urls.every(url => url.startsWith(repository))).toBe(true);
  for (const request of requests) {
    const headers = await request.allHeaders();
    expect(headers).not.toHaveProperty('cookie');
    expect(headers).not.toHaveProperty('authorization');
    expect(headers).not.toHaveProperty('x-github-api-version');
  }
  expect(rpc).toEqual([]);
});

test('public comments retain large numeric IDs and read a second page', async ({ page }) => {
  const firstPage = Array.from({ length: 100 }, (_, index) => ({
    id: index + 1, body: `Page one ${index}`, html_url: 'https://github.com/comment/1',
    created_at: '2026-09-10T00:00:00Z', user: { login: 'alice' },
  }));
  const { requests, rpc } = await install(page, url => {
    if (!url.pathname.endsWith('/issues/42/comments')) return [];
    if (url.searchParams.get('page') === '1') return firstPage;
    return '[{"id":9007199254740993,"body":"Last paginated public comment","html_url":"https://github.com/comment/last","created_at":"2026-09-10T00:00:00Z","user":{"login":"alice"}}]';
  });
  await page.goto('/example/project/pull/42');
  await expect.poll(() => requests.some(r => r.url().includes('/issues/42/comments?per_page=100&page=2'))).toBe(true);
  await expect(page.getByText('Last paginated public comment')).toBeVisible();
  expect(rpc).toEqual([]);
});

test('public oversized, rate-limited and network reads show errors without backend fallback', async ({ page }) => {
  const { rpc } = await install(page);
  await page.route(`${repository}/commits/**`, route => {
    const revision = new URL(route.request().url()).pathname.split('/').at(-1);
    const headers = { 'Access-Control-Allow-Origin': '*' };
    if (revision === '1'.repeat(40)) {
      return route.fulfill({ body: 'x'.repeat(8_388_609), contentType: 'application/json', headers });
    }
    if (revision === '2'.repeat(40)) {
      return route.fulfill({ status: 403, json: { message: 'API rate limit exceeded' },
        headers: { ...headers, 'X-RateLimit-Remaining': '0' } });
    }
    return route.abort('failed');
  });
  for (const [revision, message] of [
    ['1'.repeat(40), /8 MiB/],
    ['2'.repeat(40), /rate limit/i],
    ['3'.repeat(40), /network or CORS policy/i],
  ]) {
    await page.goto(`/example/project/commit/${revision}`);
    await expect(page.locator('.error').first()).toContainText(message);
  }
  expect(rpc).toEqual([]);
});

test('public source larger than 1 MiB is rejected without backend fallback', async ({ page }) => {
  const { rpc } = await install(page);
  await page.route(`${repository}/contents/**`, route => route.fulfill({
    body: 'x'.repeat(1_048_577), contentType: 'text/plain',
    headers: { 'Access-Control-Allow-Origin': '*' },
  }));
  await page.goto('/example/project/pull/42');
  await expect(page.locator('.file-card').first()).toContainText('larger than 1 MiB');
  expect(rpc).toEqual([]);
});

test('browser-blocked public response stays visible and never falls back to the backend', async ({ page }) => {
  const { rpc } = await install(page);
  await page.route(`${repository}/commits/**`, route => {
    if (new URL(route.request().url()).pathname.endsWith(`/commits/${commit}`)) {
      return route.abort('blockedbyresponse');
    }
    return route.fallback();
  });
  await page.goto(`/example/project/commit/${commit}`);
  await expect(page.locator('.error').first()).toContainText('network or CORS policy');
  expect(rpc).toEqual([]);
});
