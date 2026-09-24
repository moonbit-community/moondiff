import { expect, test } from '@playwright/test';
import { fixtureRequest, successFixture } from '../../tests/protocol-fixtures.mjs';
import { settleRegions } from '../../tests/render-probe.mjs';

const base = 'a'.repeat(40);
const middle = 'b'.repeat(40);
const head = 'c'.repeat(40);
const unrelated = 'd'.repeat(40);
const file = {
  filename: 'src/main.mbt', status: 'modified', additions: 1, deletions: 1,
  changes: 2, patch: '@@ -1 +1 @@\n-fn old() {}\n+fn new() {}',
};
const pull = {
  title: 'Fork interval fixture', html_url: 'https://github.com/upstream/project/pull/17',
  base: { sha: base, repo: { full_name: 'upstream/project' } },
  head: { sha: head, repo: { full_name: 'fork/project' } },
  additions: 1, deletions: 1, changed_files: 1, commits: 2,
};

function commit(sha, parent, message = `Change ${sha.slice(0, 7)}`) {
  return { sha, commit: { message }, parents: [{ sha: parent }] };
}

function baseCommit(sha = base, message = `Base ${sha.slice(0, 7)}`) {
  return { sha, commit: { message }, parents: [] };
}

function linearCommits(total, { firstParent = base, finalSha = head, message = i => `Commit ${i + 1}` } = {}) {
  const shas = Array.from({ length: total }, (_, i) => i === total - 1 ? finalSha : i.toString(16).padStart(40, '0'));
  return shas.map((sha, i) => commit(sha, i === 0 ? firstParent : shas[i - 1], message(i)));
}

function comparison(a = base, b = head, { merge = a, count = 2, files = [file] } = {}) {
  const commits = count === 0 ? [] : count === 1
    ? [commit(b, a)] : [commit(middle, a), commit(b, middle)];
  return {
    base_commit: baseCommit(a),
    merge_base_commit: { sha: merge }, total_commits: count,
    commits,
    files,
  };
}

async function publicFixture(page, makeCompare = () => comparison()) {
  const calls = [];
  await page.route('**/api/auth/status', route => route.fulfill({
    json: { $tag: 'Success', value: { authenticated: false } },
  }));
  await page.route('**/api/rpc', route => {
    calls.push({ transport: 'rpc', tag: route.request().postDataJSON().request.$tag });
    return route.fulfill({ status: 401, json: { $tag: 'Failure', error: {
      status: 401, code: 'authentication_required', message: 'Sign in',
    } } });
  });
  await page.route('https://api.github.com/**', route => {
    const url = new URL(route.request().url());
    calls.push({ transport: 'public', url: url.href });
    const headers = { 'Access-Control-Allow-Origin': '*' };
    if (url.pathname.includes('/contents/')) {
      const source = url.searchParams.get('ref') === base ? 'fn old() {}\n' : 'fn new() {}\n';
      return route.fulfill({ body: source, contentType: 'text/plain', headers });
    }
    if (url.pathname.endsWith('/pulls/19')) {
      return route.fulfill({ json: { ...pull, html_url: 'https://github.com/upstream/project/pull/19', commits: 20 }, headers });
    }
    if (url.pathname.endsWith('/pulls/19/files')) {
      return route.fulfill({ json: [file], headers });
    }
    if (url.pathname.endsWith('/pulls/19/commits')) {
      return route.fulfill({ json: linearCommits(20), headers });
    }
    if (url.pathname.endsWith('/issues/19/comments') || url.pathname.endsWith('/pulls/19/comments')) {
      return route.fulfill({ json: [], headers });
    }
    if (url.pathname.includes('/compare/')) {
      const pair = url.pathname.split('/compare/')[1].split('...');
      return route.fulfill({ json: makeCompare(pair[0], pair[1], url), headers });
    }
    if (url.pathname.endsWith('/commits/aaaaaaa') || url.pathname.endsWith('/commits/ccccccc')) {
      const resolved = url.pathname.endsWith('/aaaaaaa') ? base : head;
      expect(route.request().headers().accept).toBe('application/vnd.github.sha');
      return route.fulfill({ body: `${resolved}\n`, contentType: 'text/plain', headers });
    }
    return route.fulfill({ status: 404, json: { message: `Unexpected ${url.pathname}` }, headers });
  });
  return calls;
}

async function privateFixture(page, { rangeResponse = null, pullData = pull, compareResponse = null, commitPage = null, resolveSha = null } = {}) {
  const calls = [];
  let pullReads = 0;
  await page.context().route('**/api/auth/status', route => route.fulfill({
    json: { $tag: 'Success', value: { authenticated: true, csrf_token: 'fixture', user_id: '1', login: 'reviewer' } },
  }));
  await page.context().route('https://api.github.com/**', route => {
    calls.push({ transport: 'public', url: route.request().url() });
    return route.abort();
  });
  await page.context().route('**/api/rpc', async route => {
    const { op, args } = fixtureRequest(route.request().postDataJSON());
    calls.push({ transport: 'rpc', op, args });
    let value;
    switch (op) {
      case 'github.pull.get': value = typeof pullData === 'function' ? pullData(++pullReads) : pullData; break;
      case 'github.compare.get': value = compareResponse
        ? compareResponse(args) : { merge_base_commit: { sha: base } }; break;
      case 'github.pull.files': value = [file]; break;
      case 'github.range.compare.get': value = rangeResponse
        ? await rangeResponse(args) : comparison(args.base, args.head, { count: args.head === middle ? 1 : 2 }); break;
      case 'github.pull.commit.page.get': value = commitPage
        ? await commitPage(args) : [commit(middle, base, 'Middle commit'), commit(head, middle, 'Final commit')]; break;
      case 'github.sha.resolve.get': value = resolveSha
        ? resolveSha(args) : args.sha === 'aaaaaaa' ? base : args.sha === 'bbbbbbb' ? middle : head; break;
      case 'github.content.get': {
        const source = args.ref === base ? 'fn old() {}\n' : 'fn new() {}\n';
        value = { base64: Buffer.from(source).toString('base64'), size: Buffer.byteLength(source), content_type: 'text/plain' };
        break;
      }
      case 'github.comments.list': value = { issue_comments: [], review_comments: [], commit_comments: [] }; break;
      case 'github.pull.viewed.get': value = { base_sha: base, head_sha: head, files: [{ path: file.filename, state: { $tag: 'Unviewed' } }] }; break;
      case 'github.pull.merge.status': value = {
        base_sha: base, head_sha: head, open: true, draft: false, merged: false,
        mergeable: false, rebaseable: false, mergeable_state: 'dirty', ci_checks: [], ci_warnings: [],
      }; break;
      default: throw new Error(`Unexpected RPC ${op}`);
    }
    if (value?.error) return route.fulfill({ status: value.error.status, json: { $tag: 'Failure', error: value.error } }).catch(() => {});
    return route.fulfill({ json: successFixture(op, value) }).catch(() => {});
  });
  return calls;
}

async function restorePage(page) {
  await page.evaluate(() => {
    dispatchEvent(new PageTransitionEvent('pagehide', { persisted: true }));
    dispatchEvent(new PageTransitionEvent('pageshow', { persisted: true }));
    dispatchEvent(new Event('focus'));
  });
}

test('anonymous shared interval normalizes short SHAs and renders a read-only net diff', async ({ page }) => {
  const response = comparison();
  response.base_commit.commit.message = 'Base subject\n\nBase details';
  response.commits[0].commit.message = 'First subject\n\nFirst details';
  response.commits.at(-1).commit.message = 'Head subject\n\nHead details';
  const calls = await publicFixture(page, () => response);
  await page.goto('/example/project/compare/aaaaaaa..ccccccc');
  await expect(page).toHaveURL(`/example/project/compare/${base}..${head}`);
  const title = page.locator('.range-review-title');
  await expect(title).toHaveText('First subject .. Head subject');
  await expect(title.locator('.range-title-commit')).toHaveText(['First subject', 'Head subject']);
  await expect(title.locator('.range-title-separator')).toHaveText('..');
  expect(await title.locator('.range-title-separator').evaluate(el => getComputedStyle(el).color))
    .not.toBe(await title.evaluate(el => getComputedStyle(el).color));
  await expect(page.locator('.range-endpoints')).toHaveCount(0);
  await expect(page.locator('.range-summary')).toContainText('2 commits · 1 file · +1 −1');
  await page.locator('.range-toggle-commits').click();
  await expect(page.locator('.range-commits li span')).toHaveText(['First subject', 'Head subject']);
  await expect(page.locator('.file-card')).toHaveCount(1);
  await expect(page.locator('.file-card')).toContainText('fn new');
  await expect(page.locator('.line-comment-button, .viewed-control, .comments-overview, .pull-merge-card')).toHaveCount(0);
  await page.reload();
  await expect(page.locator('.file-card')).toHaveCount(1);
  expect(calls.some(c => c.transport === 'rpc')).toBe(false);
  expect(calls.some(c => c.url?.includes(`/compare/${base}...${head}?per_page=100&page=1`))).toBe(true);
  expect(calls.filter(c => c.url?.includes('/commits/')).length).toBe(2);
});

test('authenticated private interval uses RPC and never sends the read to public GitHub', async ({ page }) => {
  const calls = await privateFixture(page);
  await page.goto(`/upstream/project/compare/${base}..${head}`);
  await expect(page.locator('.file-card')).toHaveCount(1);
  await expect(page.locator('.range-review')).toContainText('2 commits');
  expect(calls.some(c => c.op === 'github.range.compare.get')).toBe(true);
  expect(calls.some(c => c.transport === 'public')).toBe(false);
});

test('short shared interval keeps its URL when ancestry validation fails', async ({ page }) => {
  await publicFixture(page, () => comparison(base, head, { merge: unrelated }));
  await page.goto('/example/project/compare/aaaaaaa..ccccccc');
  await expect(page.locator('.empty-state.error')).toContainText('ancestor');
  await expect(page).toHaveURL('/example/project/compare/aaaaaaa..ccccccc');
});

test('shared interval waits for its final commit before replacing a short URL', async ({ page }) => {
  let release;
  const held = new Promise(resolve => { release = resolve; });
  const commits = linearCommits(101, { message: i => `Commit ${i}` }).slice(0, 100);
  const calls = await privateFixture(page, {
    rangeResponse: async args => {
      if (args.page === 2) await held;
      return {
        base_commit: baseCommit(), merge_base_commit: { sha: base },
        total_commits: 101,
        commits: args.page === 1 ? commits : [commit(head, commits[99].sha, 'Final commit')],
        ...(args.page === 1 ? { files: [file] } : {}),
      };
    },
  });
  try {
    await page.goto('/upstream/project/compare/aaaaaaa..ccccccc');
    await expect.poll(() => calls.filter(c => c.op === 'github.range.compare.get').length).toBe(2);
    await expect(page).toHaveURL('/upstream/project/compare/aaaaaaa..ccccccc');
    await expect(page.locator('.range-review')).toHaveCount(0);
    release();
    await expect(page).toHaveURL(`/upstream/project/compare/${base}..${head}`);
    await expect(page.locator('.range-summary')).toContainText('101 commits');
    await expect(page.locator('.range-title-commit')).toHaveText(['Commit 0', 'Final commit']);
  } finally { release(); }
});

test('fork PR selector opens a fixed interval in a new tab and keeps PR comments available', async ({ page }) => {
  const calls = await privateFixture(page);
  await page.goto('/upstream/project/pull/17');
  await expect(page.locator('.file-card')).toHaveCount(1);
  await expect(page.locator('.add-overall-comment')).toBeVisible();
  await expect(page.locator('.range-selector input')).toHaveCount(0);
  await expect(page.locator('.range-selector select')).toHaveCount(2);
  await page.evaluate(() => { window.originalCard = document.querySelector('.file-card'); });
  await expect(page.locator('.range-selector select').nth(1).locator(`option[value="${middle}"]`)).toHaveCount(1);
  await expect(page.locator('.range-selector .range-load-more')).toHaveCount(0);
  await page.locator('.range-selector select').nth(1).selectOption(middle);
  await settleRegions(page);
  expect(await page.evaluate(() => document.querySelector('.file-card') === window.originalCard)).toBe(true);
  const viewInterval = page.locator('.range-apply');
  await expect(viewInterval).toHaveAttribute('href', `/upstream/project/pull/17/compare/${base}..${middle}`);
  await expect(viewInterval).toHaveAttribute('target', '_blank');
  await expect(viewInterval).toHaveAttribute('rel', 'noopener noreferrer');
  const [intervalPage] = await Promise.all([
    page.context().waitForEvent('page'),
    viewInterval.click(),
  ]);
  await expect(page).toHaveURL('/upstream/project/pull/17');
  await expect(page.locator('.add-overall-comment')).toBeVisible();
  await settleRegions(page);
  expect(await page.evaluate(() => document.querySelector('.file-card') === window.originalCard)).toBe(true);
  await expect(intervalPage).toHaveURL(`/upstream/project/pull/17/compare/${base}..${middle}`);
  await expect(intervalPage.locator('.range-review')).toContainText('1 commit');
  await expect(intervalPage.locator('.range-title-commit')).toHaveText(['Change bbbbbbb', 'Change bbbbbbb']);
  await intervalPage.evaluate(() => {
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText: async value => { window.copiedRangeLink = value; } },
    });
  });
  await intervalPage.locator('.range-copy').click();
  expect(await intervalPage.evaluate(() => window.copiedRangeLink)).toBe(intervalPage.url());
  await expect(intervalPage.locator('.line-comment-button, .viewed-control, .comments-overview, .pull-merge-card')).toHaveCount(0);
  await expect(intervalPage.locator('.range-links a', { hasText: 'Go to commit comments' })).toBeVisible();
  await expect(intervalPage.getByRole('link', { name: 'Return to PR' })).toHaveCount(0);
  await expect(intervalPage.getByRole('link', { name: 'Go to PR comments' })).toHaveCount(0);
  const sources = calls.filter(c => c.op === 'github.content.get').map(c => [c.args.owner, c.args.repo, c.args.ref]);
  expect(sources).toContainEqual(['upstream', 'project', base]);
  expect(sources).toContainEqual(['fork', 'project', middle]);
  await intervalPage.reload();
  await expect(intervalPage.locator('.range-review')).toContainText('1 commit');
  await expect(page).toHaveURL('/upstream/project/pull/17');
  await expect(page.locator('.add-overall-comment')).toBeVisible();
});

test('retrying a failed fork PR interval preserves its route and fork source', async ({ page }) => {
  let reads = 0;
  const calls = await privateFixture(page, {
    rangeResponse: args => ++reads === 1
      ? { error: { status: 503, code: 'github_http_503', message: 'Unavailable' } }
      : comparison(args.base, args.head, { count: 1 }),
  });
  const route = `/upstream/project/pull/17/compare/${base}..${middle}`;
  await page.goto(route);
  await expect(page.getByRole('button', { name: 'Try again' })).toBeVisible();
  await expect(page).toHaveURL(route);
  await page.getByRole('button', { name: 'Try again' }).click();
  await expect(page).toHaveURL(route);
  await expect(page.locator('.range-review')).toContainText('1 commit');
  await expect(page.locator('.file-card')).toContainText('fn new');
  expect(calls.filter(c => c.op === 'github.range.compare.get').map(c => c.args.head)).toEqual([middle, middle]);
  expect(calls.filter(c => c.op === 'github.content.get').map(c => [c.args.owner, c.args.repo, c.args.ref]))
    .toContainEqual(['fork', 'project', middle]);
});

test('over-limit fork PR skips full file pages and opens a smaller interval', async ({ page }) => {
  const calls = await privateFixture(page, { pullData: { ...pull, changed_files: 3_001 } });
  await page.goto('/upstream/project/pull/17');
  await expect(page.locator('.range-limit')).toContainText("3,000-file API limit");
  await expect(page.locator('.range-selector select')).toHaveCount(2);
  await expect(page.locator('.range-selector select').first()).toBeEnabled();
  await expect(page.locator('.file-card, .file-tree-sidebar, .comments-overview, .viewed-control, .pull-merge-card')).toHaveCount(0);
  await expect(page.locator('.workspace-actions')).toHaveCount(0);
  expect(calls.filter(c => c.op === 'github.pull.files')).toHaveLength(0);
  expect(calls.filter(c => c.op === 'github.compare.get').map(c => [c.args.base, c.args.head]))
    .toEqual([[base, head]]);
  expect(calls.filter(c => c.op === 'github.comments.list' || c.op === 'github.pull.viewed.get' || c.op === 'github.pull.merge.status')).toHaveLength(0);
  await page.locator('.range-selector select').nth(1).selectOption(middle);
  await expect(page.locator('.range-apply')).toHaveAttribute('href', `/upstream/project/pull/17/compare/${base}..${middle}`);
  const [interval] = await Promise.all([
    page.context().waitForEvent('page'),
    page.locator('.range-apply').click(),
  ]);
  await expect(interval.locator('.range-review')).toContainText('1 commit');
  await expect(interval.locator('.file-card')).toContainText('fn new');
  expect(calls.filter(c => c.op === 'github.content.get').map(c => [c.args.owner, c.args.repo, c.args.ref]))
    .toContainEqual(['fork', 'project', middle]);
  await expect(page).toHaveURL('/upstream/project/pull/17');
  await expect(page.locator('.file-card')).toHaveCount(0);
});

test('over-limit PR commit choices use manual fixed comparison pages', async ({ page }) => {
  const commits = linearCommits(251);
  const calls = await privateFixture(page, {
    pullData: { ...pull, changed_files: 3_001, commits: 251 },
    rangeResponse: args => ({
      base_commit: baseCommit(), merge_base_commit: { sha: base },
      total_commits: 251,
      commits: commits.slice((args.page - 1) * 100, args.page * 100),
      ...(args.page === 1 ? { files: [file] } : {}),
    }),
  });
  await page.goto('/upstream/project/pull/17');
  await expect(page.locator('.range-manual-reason')).toContainText('251 commits');
  await expect(page.locator('.range-selector .range-load-more')).toHaveText('Load PR commits');
  expect(calls.filter(c => c.op === 'github.range.compare.get')).toHaveLength(0);
  for (let pageNumber = 1; pageNumber <= 3; pageNumber++) {
    await page.locator('.range-selector .range-load-more').click();
    await expect(page.locator('.range-selector select').first().locator('option')).toHaveCount(Math.min(pageNumber * 100, 251));
  }
  await expect(page.locator('.range-apply')).toBeEnabled();
  expect(calls.filter(c => c.op === 'github.range.compare.get').map(c => c.args.page)).toEqual([1, 2, 3]);
  expect(calls.filter(c => c.op === 'github.pull.files' || c.op === 'github.pull.commit.page.get')).toHaveLength(0);
  await expect(page.locator('.file-card')).toHaveCount(0);
});

test('over-limit PR retries a failed commit page inside the selector', async ({ page }) => {
  let reads = 0;
  const calls = await privateFixture(page, {
    pullData: { ...pull, changed_files: 3_001 },
    commitPage: () => ++reads === 1
      ? { error: { status: 503, code: 'github_http_503', message: 'Unavailable' } }
      : [commit(middle, base), commit(head, middle)],
  });
  await page.goto('/upstream/project/pull/17');
  await expect(page.locator('.range-error')).toBeVisible();
  await expect(page.locator('.range-selector .range-load-more')).toHaveText('Retry loading commits');
  await page.locator('.range-selector .range-load-more').click();
  await expect(page.locator('.range-selector select').first()).toBeEnabled();
  expect(calls.filter(c => c.op === 'github.pull.commit.page.get').map(c => c.args.page)).toEqual([1, 1]);
  expect(calls.filter(c => c.op === 'github.pull.files')).toHaveLength(0);
});

test('over-limit PR preserves comparison choices across a failed later page', async ({ page }) => {
  const commits = linearCommits(251);
  let failed = false;
  const calls = await privateFixture(page, {
    pullData: { ...pull, changed_files: 3_001, commits: 251 },
    rangeResponse: args => {
      if (args.page === 2 && !failed) {
        failed = true;
        return { error: { status: 503, code: 'github_http_503', message: 'Unavailable' } };
      }
      return {
        base_commit: baseCommit(), merge_base_commit: { sha: base },
        total_commits: 251,
        commits: commits.slice((args.page - 1) * 100, args.page * 100),
        ...(args.page === 1 ? { files: [file] } : {}),
      };
    },
  });
  await page.goto('/upstream/project/pull/17');
  await page.locator('.range-selector .range-load-more').click();
  await expect(page.locator('.range-selector select').first().locator('option')).toHaveCount(100);
  await page.locator('.range-selector .range-load-more').click();
  await expect(page.locator('.range-error')).toBeVisible();
  await expect(page.locator('.range-selector select').first().locator('option')).toHaveCount(100);
  await page.locator('.range-selector .range-load-more').click();
  await expect(page.locator('.range-selector select').first().locator('option')).toHaveCount(200);
  expect(calls.filter(c => c.op === 'github.range.compare.get').map(c => c.args.page)).toEqual([1, 2, 2]);
  expect(calls.filter(c => c.op === 'github.pull.files')).toHaveLength(0);
});

test('over-limit PR with branched history disables interval selection', async ({ page }) => {
  const calls = await privateFixture(page, {
    pullData: { ...pull, changed_files: 3_001, commits: 3 },
    commitPage: () => [
      commit(middle, base),
      commit(unrelated, base),
      { ...commit(head, middle), parents: [{ sha: middle }, { sha: unrelated }] },
    ],
  });
  await page.goto('/upstream/project/pull/17');
  await expect(page.locator('.range-unsupported')).toContainText('branched or merged commit history');
  await expect(page.locator('.range-selector select').first()).toBeDisabled();
  await expect(page.locator('.range-selector select').nth(1)).toBeDisabled();
  await expect(page.locator('.range-apply')).toBeDisabled();
  expect(calls.filter(c => c.op === 'github.pull.files')).toHaveLength(0);
});

test('over-limit PR retries one changed snapshot with the new fixed head', async ({ page }) => {
  const latest = { ...pull, changed_files: 3_001, commits: 1, head: { ...pull.head, sha: middle } };
  const calls = await privateFixture(page, {
    pullData: read => read === 1 ? { ...pull, changed_files: 3_001 } : latest,
    commitPage: () => [commit(middle, base)],
  });
  await page.goto('/upstream/project/pull/17');
  await expect(page.locator('.range-selector select').first()).toBeEnabled();
  await expect(page.locator('.range-apply')).toHaveAttribute('href', `/upstream/project/pull/17/compare/${base}..${middle}`);
  expect(calls.filter(c => c.op === 'github.compare.get').map(c => c.args.head)).toEqual([head, middle]);
  expect(calls.filter(c => c.op === 'github.pull.files')).toHaveLength(0);
});

test('over-limit PR fails explicitly when both selector snapshots change', async ({ page }) => {
  const first = { ...pull, changed_files: 3_001 };
  const second = { ...first, head: { ...pull.head, sha: middle } };
  const third = { ...second, head: { ...pull.head, sha: unrelated } };
  const calls = await privateFixture(page, {
    pullData: read => read === 1 ? first : read === 2 ? second : third,
  });
  await page.goto('/upstream/project/pull/17');
  await expect(page.locator('.empty-state.error')).toContainText('changed while it was loading');
  await expect(page.locator('.range-selector')).toHaveCount(0);
  expect(calls.filter(c => c.op === 'github.compare.get').map(c => c.args.head)).toEqual([head, middle]);
  expect(calls.filter(c => c.op === 'github.pull.files')).toHaveLength(0);
});

for (const failedStep of ['compare', 'validation']) {
  test(`over-limit PR ${failedStep} failure retries from its route`, async ({ page }) => {
    let failed = false;
    const calls = await privateFixture(page, {
      pullData: read => {
        if (failedStep === 'validation' && read === 2 && !failed) {
          failed = true;
          return { error: { status: 503, code: 'github_http_503', message: 'Unavailable' } };
        }
        return { ...pull, changed_files: 3_001 };
      },
      compareResponse: () => {
        if (failedStep === 'compare' && !failed) {
          failed = true;
          return { error: { status: 503, code: 'github_http_503', message: 'Unavailable' } };
        }
        return { merge_base_commit: { sha: base } };
      },
    });
    await page.goto('/upstream/project/pull/17');
    await expect(page.getByRole('button', { name: 'Try again' })).toBeVisible();
    await page.getByRole('button', { name: 'Try again' }).click();
    await expect(page.locator('.range-selector select').first()).toBeEnabled();
    await expect(page).toHaveURL('/upstream/project/pull/17');
    expect(calls.filter(c => c.op === 'github.pull.files')).toHaveLength(0);
  });
}

test('PR From labels included commits and both selectors allow the same commit', async ({ page }) => {
  await privateFixture(page, {
    pullData: { ...pull, commits: 3 },
    commitPage: () => [
      commit(middle, base, `Commit ${middle.slice(0, 7)}`),
      commit(unrelated, middle, `Commit ${unrelated.slice(0, 7)}`),
      commit(head, unrelated, `Commit ${head.slice(0, 7)}`),
    ],
  });
  await page.goto('/upstream/project/pull/17');
  await expect(page.locator('.file-card')).toHaveCount(1);
  await page.evaluate(() => { window.originalCard = document.querySelector('.file-card'); });
  const from = page.locator('.range-selector select').first();
  const to = page.locator('.range-selector select').nth(1);
  await expect(to.locator('option')).toHaveCount(3);
  await expect(from.locator(`option[value="${base}"]`)).toContainText(middle.slice(0, 7));
  await expect(from.locator(`option[value="${head}"]`)).toHaveCount(0);
  await expect(to.locator(`option[value="${base}"]`)).toHaveCount(0);
  await to.selectOption(unrelated);
  await expect(from.locator('option')).toHaveCount(2);
  await expect(from.locator(`option[value="${unrelated}"]`)).toHaveCount(0);
  await expect(from.locator(`option[value="${head}"]`)).toHaveCount(0);
  await from.selectOption(middle);
  await expect(to).toHaveValue(unrelated);
  await expect(to.locator('option')).toHaveCount(2);
  await expect(to.locator(`option[value="${unrelated}"]`)).toHaveCount(1);
  await expect(to.locator(`option[value="${middle}"]`)).toHaveCount(0);
  await to.selectOption(head);
  await expect(from.locator('option')).toHaveCount(3);
  await from.selectOption(unrelated);
  await expect(to.locator('option')).toHaveCount(1);
  await expect(to).toHaveValue(head);
  await expect(from.locator('option:checked')).toContainText(head.slice(0, 7));
  expect(await page.evaluate(() => document.querySelector('.file-card') === window.originalCard)).toBe(true);
});

test('a merged PR keeps its diff and explains why commit intervals are unavailable', async ({ page }) => {
  const calls = await privateFixture(page, {
    pullData: { ...pull, commits: 3 },
    commitPage: () => [
      commit(middle, base),
      commit(unrelated, base),
      { ...commit(head, middle), parents: [{ sha: middle }, { sha: unrelated }] },
    ],
  });
  await page.goto('/upstream/project/pull/17');
  await expect(page.locator('.file-card')).toHaveCount(1);
  await page.evaluate(() => { window.originalCard = document.querySelector('.file-card'); });
  await expect(page.locator('.range-unsupported')).toContainText('branched or merged commit history');
  await expect(page.locator('.range-selector select')).toHaveCount(2);
  await expect(page.locator('.range-selector select').first()).toBeDisabled();
  await expect(page.locator('.range-selector select').nth(1)).toBeDisabled();
  await expect(page.locator('.range-apply')).toBeDisabled();
  await expect(page.locator('.add-overall-comment')).toBeVisible();
  await settleRegions(page);
  expect(await page.evaluate(() => document.querySelector('.file-card') === window.originalCard)).toBe(true);
  expect(calls.filter(c => c.op === 'github.range.compare.get')).toHaveLength(0);
});

test('a linear PR uses parent order even when commit pages arrive out of order', async ({ page }) => {
  await privateFixture(page, {
    pullData: { ...pull, commits: 3 },
    commitPage: () => [
      commit(unrelated, middle, 'Second'),
      commit(middle, base, 'First'),
      commit(head, unrelated, 'Last'),
    ],
  });
  await page.goto('/upstream/project/pull/17');
  const from = page.locator('.range-selector select').first();
  const to = page.locator('.range-selector select').nth(1);
  await expect(from).toBeEnabled();
  await expect(from.locator('option').first()).toContainText('First');
  await expect(from.locator(`option[value="${middle}"]`)).toContainText('Second');
  await expect(to.locator('option').last()).toContainText('Last');
});

test('PR From includes the selected first or last commit without changing shared compare semantics', async ({ page }) => {
  await privateFixture(page, {
    rangeResponse: args => comparison(args.base, args.head, { count: 1 }),
  });
  await page.goto('/upstream/project/pull/17');
  const from = page.locator('.range-selector select').first();
  const to = page.locator('.range-selector select').nth(1);
  await expect(from.locator('option')).toHaveCount(2);
  await expect(from.locator(`option[value="${base}"]`)).toContainText('Middle commit');
  await to.selectOption(middle);
  const [firstInterval] = await Promise.all([
    page.context().waitForEvent('page'),
    page.locator('.range-apply').click(),
  ]);
  await expect(page).toHaveURL('/upstream/project/pull/17');
  await expect(firstInterval).toHaveURL(`/upstream/project/pull/17/compare/${base}..${middle}`);
  await expect(firstInterval.locator('.range-summary')).toContainText('1 commit');
  await firstInterval.close();
  await to.selectOption(head);
  await expect(from.locator(`option[value="${middle}"]`)).toContainText('Final commit');
  await from.selectOption(middle);
  await expect(to).toHaveValue(head);
  await expect(to.locator('option')).toHaveCount(1);
  const [lastInterval] = await Promise.all([
    page.context().waitForEvent('page'),
    page.locator('.range-apply').click(),
  ]);
  await expect(page).toHaveURL('/upstream/project/pull/17');
  await expect(lastInterval).toHaveURL(`/upstream/project/pull/17/compare/${middle}..${head}`);
  await expect(lastInterval.locator('.range-summary')).toContainText('1 commit');
});

test('PR commit choices use dedicated pages without rebuilding the diff', async ({ page }) => {
  const commits = linearCommits(101, { message: i => i === 100 ? 'Final commit' : `Commit ${i}` });
  const calls = await privateFixture(page, {
    pullData: { ...pull, commits: 101 },
    commitPage: args => commits.slice((args.page - 1) * 100, args.page * 100),
  });
  await page.goto('/upstream/project/pull/17');
  await expect(page.locator('.file-card')).toHaveCount(1);
  await page.evaluate(() => { window.originalCard = document.querySelector('.file-card'); });
  await expect(page.locator('.range-selector select').first().locator('option')).toHaveCount(101);
  await expect(page.locator('.range-selector select').nth(1).getByText('Final commit')).toHaveCount(1);
  await expect(page.locator('.range-selector .range-load-more')).toHaveCount(0);
  await settleRegions(page);
  expect(await page.evaluate(() => document.querySelector('.file-card') === window.originalCard)).toBe(true);
  expect(calls.filter(c => c.op === 'github.pull.commit.page.get').map(c => c.args.page)).toEqual([1, 2]);
  expect(calls.filter(c => c.op === 'github.range.compare.get')).toHaveLength(0);
});

test('restoring a PR retries its canceled commit page and keeps the shown diff', async ({ page }) => {
  const commits = linearCommits(101);
  const canceled = [];
  page.on('requestfailed', request => {
    if (!request.url().endsWith('/api/rpc')) return;
    const { op, args } = fixtureRequest(request.postDataJSON());
    if (op === 'github.pull.commit.page.get' && args.page === 2) canceled.push(request.failure()?.errorText);
  });
  let release;
  const held = new Promise(resolve => { release = resolve; });
  let secondReads = 0;
  const calls = await privateFixture(page, {
    pullData: { ...pull, commits: 101 },
    commitPage: async args => {
      if (args.page === 2 && ++secondReads === 1) await held;
      return commits.slice((args.page - 1) * 100, args.page * 100);
    },
  });
  try {
    await page.goto('/upstream/project/pull/17');
    await expect(page.locator('.file-card')).toHaveCount(1);
    await expect.poll(() => calls.filter(c => c.op === 'github.pull.commit.page.get').map(c => c.args.page))
      .toEqual([1, 2]);
    await expect(page.locator('.range-selector select').first().locator('option')).toHaveCount(100);
    await page.evaluate(() => { window.originalCard = document.querySelector('.file-card'); });
    const validations = calls.filter(c => c.op === 'github.pull.get').length;
    await restorePage(page);
    await expect.poll(() => canceled.length).toBe(1);
    await expect(page.locator('.range-selector select').first().locator('option')).toHaveCount(101);
    expect(calls.filter(c => c.op === 'github.pull.commit.page.get').map(c => c.args.page)).toEqual([1, 2, 2]);
    expect(calls.filter(c => c.op === 'github.pull.get').length).toBeGreaterThan(validations);
    expect(calls.filter(c => c.op === 'github.pull.files')).toHaveLength(1);
    expect(await page.evaluate(() => document.querySelector('.file-card') === window.originalCard)).toBe(true);
    release();
    await expect(page.locator('.range-selector select').first().locator('option')).toHaveCount(101);
  } finally { release(); }
});

test('PR #19 shaped page automatically shows all 20 commits', async ({ page }) => {
  const commits = linearCommits(20);
  const calls = await privateFixture(page, {
    pullData: { ...pull, html_url: 'https://github.com/upstream/project/pull/19', commits: 20 },
    commitPage: () => commits,
  });
  await page.goto('/upstream/project/pull/19');
  await expect(page.locator('.file-card')).toHaveCount(1);
  await expect(page.locator('.range-selector select').first().locator('option')).toHaveCount(20);
  await expect(page.locator('.range-selector select').nth(1)).toContainText('Commit 20');
  await expect(page.locator('.range-selector .range-load-more')).toHaveCount(0);
  expect(calls.filter(c => c.op === 'github.pull.commit.page.get').map(c => c.args.number)).toEqual(['19']);
  expect(calls.filter(c => c.op === 'github.range.compare.get')).toHaveLength(0);
});

test('anonymous PR #19 commit page reads GitHub directly', async ({ page }) => {
  const calls = await publicFixture(page);
  await page.goto('/upstream/project/pull/19');
  await expect(page.locator('.file-card')).toHaveCount(1);
  await expect(page.locator('.range-selector select').first().locator('option')).toHaveCount(20);
  await expect(page.locator('.range-selector .range-load-more')).toHaveCount(0);
  expect(calls.some(c => c.url?.includes('/pulls/19/commits?per_page=100&page=1'))).toBe(true);
  expect(calls.some(c => c.transport === 'rpc')).toBe(false);
});

for (const total of [100, 250]) {
  test(`${total} PR commits use complete dedicated pages`, async ({ page }) => {
    const commits = linearCommits(total);
    const calls = await privateFixture(page, {
      pullData: { ...pull, commits: total },
      commitPage: args => commits.slice((args.page - 1) * 100, args.page * 100),
    });
    await page.goto('/upstream/project/pull/17');
    await expect(page.locator('.file-card')).toHaveCount(1);
    await page.evaluate(() => { window.originalCard = document.querySelector('.file-card'); });
    const pages = Math.ceil(total / 100);
    await expect(page.locator('.range-selector select').first().locator('option')).toHaveCount(total);
    await expect(page.locator('.range-selector .range-load-more')).toHaveCount(0);
    expect(calls.filter(c => c.op === 'github.pull.commit.page.get').map(c => c.args.page))
      .toEqual(Array.from({ length: pages }, (_, i) => i + 1));
    expect(calls.filter(c => c.op === 'github.range.compare.get')).toHaveLength(0);
    await settleRegions(page);
    expect(await page.evaluate(() => document.querySelector('.file-card') === window.originalCard)).toBe(true);
  });
}

test('251 PR commits use fixed SHA compare pages', async ({ page }) => {
  const commits = linearCommits(251);
  const calls = await privateFixture(page, {
    pullData: { ...pull, commits: 251 },
    rangeResponse: args => ({
      base_commit: baseCommit(), merge_base_commit: { sha: base },
      total_commits: 251,
      commits: commits.slice((args.page - 1) * 100, args.page * 100),
      ...(args.page === 1 ? { files: [file] } : {}),
    }),
  });
  await page.goto('/upstream/project/pull/17');
  await expect(page.locator('.file-card')).toHaveCount(1);
  await page.evaluate(() => { window.originalCard = document.querySelector('.file-card'); });
  await expect(page.locator('.range-manual-reason')).toContainText('251 commits');
  await expect(page.locator('.range-manual-reason')).toContainText('at most 250');
  expect(calls.filter(c => c.op === 'github.range.compare.get')).toHaveLength(0);
  for (let i = 0; i < 3; i++) {
    await page.locator('.range-selector .range-load-more').click();
    await expect(page.locator('.range-selector select').first().locator('option')).toHaveCount(Math.min((i + 1) * 100, 251));
    if (i < 2) await expect(page.locator('.range-apply')).toBeDisabled();
  }
  await expect(page.locator('.range-apply')).toBeEnabled();
  expect(calls.filter(c => c.op === 'github.range.compare.get').map(c => c.args.page)).toEqual([1, 2, 3]);
  expect(calls.filter(c => c.op === 'github.pull.commit.page.get')).toHaveLength(0);
  await settleRegions(page);
  expect(await page.evaluate(() => document.querySelector('.file-card') === window.originalCard)).toBe(true);
});

test('restoring a large PR retries the same compare page with earlier commits intact', async ({ page }) => {
  const commits = linearCommits(251);
  const canceled = [];
  page.on('requestfailed', request => {
    if (!request.url().endsWith('/api/rpc')) return;
    const { op, args } = fixtureRequest(request.postDataJSON());
    if (op === 'github.range.compare.get' && args.page === 2) canceled.push(request.failure()?.errorText);
  });
  let release;
  const held = new Promise(resolve => { release = resolve; });
  let secondReads = 0;
  const calls = await privateFixture(page, {
    pullData: { ...pull, commits: 251 },
    rangeResponse: async args => {
      if (args.page === 2 && ++secondReads === 1) await held;
      return {
        base_commit: baseCommit(), merge_base_commit: { sha: base },
        total_commits: 251,
        commits: commits.slice((args.page - 1) * 100, args.page * 100),
        ...(args.page === 1 ? { files: [file] } : {}),
      };
    },
  });
  try {
    await page.goto('/upstream/project/pull/17');
    await expect(page.locator('.file-card')).toHaveCount(1);
    await page.locator('.range-selector .range-load-more').click();
    await expect(page.locator('.range-selector select').first().locator('option')).toHaveCount(100);
    await page.evaluate(() => { window.originalCard = document.querySelector('.file-card'); });
    await page.locator('.range-selector .range-load-more').click();
    await expect.poll(() => calls.filter(c => c.op === 'github.range.compare.get').map(c => c.args.page))
      .toEqual([1, 2]);
    await restorePage(page);
    await expect.poll(() => canceled.length).toBe(1);
    await expect(page.locator('.range-selector select').first().locator('option')).toHaveCount(200);
    expect(calls.filter(c => c.op === 'github.range.compare.get').map(c => c.args.page)).toEqual([1, 2, 2]);
    expect(calls.filter(c => c.op === 'github.pull.files')).toHaveLength(1);
    expect(await page.evaluate(() => document.querySelector('.file-card') === window.originalCard)).toBe(true);
    release();
    await expect(page.locator('.range-selector select').first().locator('option')).toHaveCount(200);
  } finally { release(); }
});

test('missing PR commit count automatically loads a short comparison', async ({ page }) => {
  const calls = await privateFixture(page, { pullData: { ...pull, commits: undefined } });
  await page.goto('/upstream/project/pull/17');
  await expect(page.locator('.range-selector select').first().locator('option')).toHaveCount(2);
  await expect(page.locator('.range-selector .range-load-more')).toHaveCount(0);
  expect(calls.filter(c => c.op === 'github.range.compare.get').map(c => c.args.page)).toEqual([1]);
  expect(calls.filter(c => c.op === 'github.pull.commit.page.get')).toHaveLength(0);
});

test('missing PR commit count automatically finishes a short paginated comparison', async ({ page }) => {
  const commits = linearCommits(101);
  const calls = await privateFixture(page, {
    pullData: { ...pull, commits: undefined },
    rangeResponse: args => ({
      base_commit: baseCommit(), merge_base_commit: { sha: base },
      total_commits: 101,
      commits: commits.slice((args.page - 1) * 100, args.page * 100),
      ...(args.page === 1 ? { files: [file] } : {}),
    }),
  });
  await page.goto('/upstream/project/pull/17');
  await expect(page.locator('.range-selector select').nth(1).getByText('Commit 101')).toHaveCount(1);
  await expect(page.locator('.range-selector .range-load-more')).toHaveCount(0);
  expect(calls.filter(c => c.op === 'github.range.compare.get').map(c => c.args.page)).toEqual([1, 2]);
});

test('missing PR commit count pauses after discovering a large comparison', async ({ page }) => {
  const commits = linearCommits(251);
  const calls = await privateFixture(page, {
    pullData: { ...pull, commits: undefined },
    rangeResponse: args => ({
      base_commit: baseCommit(), merge_base_commit: { sha: base },
      total_commits: 251,
      commits: commits.slice((args.page - 1) * 100, args.page * 100),
      ...(args.page === 1 ? { files: [file] } : {}),
    }),
  });
  await page.goto('/upstream/project/pull/17');
  await expect(page.locator('.range-selector select').first().locator('option')).toHaveCount(100);
  await expect(page.locator('.range-manual-reason')).toContainText('251 commits');
  await expect(page.locator('.range-selector .range-load-more')).toHaveText('Load more commits');
  expect(calls.filter(c => c.op === 'github.range.compare.get').map(c => c.args.page)).toEqual([1]);
  await page.locator('.range-selector .range-load-more').click();
  await expect(page.locator('.range-selector select').first().locator('option')).toHaveCount(200);
  expect(calls.filter(c => c.op === 'github.range.compare.get').map(c => c.args.page)).toEqual([1, 2]);
});

test('changed PR snapshot rejects commit page while keeping diff and retry', async ({ page }) => {
  const calls = await privateFixture(page, {
    pullData: read => read >= 3 ? { ...pull, commits: 3 } : pull,
  });
  await page.goto('/upstream/project/pull/17');
  await expect(page.locator('.file-card')).toHaveCount(1);
  await page.evaluate(() => { window.originalCard = document.querySelector('.file-card'); });
  await expect(page.locator('.range-error')).toContainText('changed while it was loading');
  await expect(page.locator('.range-selector .range-load-more')).toHaveText('Retry loading commits');
  await expect(page.locator('.range-selector input')).toHaveCount(0);
  expect(await page.evaluate(() => document.querySelector('.file-card') === window.originalCard)).toBe(true);
  expect(calls.filter(c => c.op === 'github.pull.commit.page.get')).toHaveLength(1);
});

test('failed PR commit page keeps the diff and retries from the same page', async ({ page }) => {
  let reads = 0;
  const calls = await privateFixture(page, {
    commitPage: () => ++reads === 1
      ? { error: { status: 503, code: 'github_http_503', message: 'Unavailable' } }
      : [commit(middle, base, 'Middle commit'), commit(head, middle, 'Final commit')],
  });
  await page.goto('/upstream/project/pull/17');
  await expect(page.locator('.file-card')).toHaveCount(1);
  await page.evaluate(() => { window.originalCard = document.querySelector('.file-card'); });
  await expect(page.locator('.range-error')).toBeVisible();
  await expect(page.locator('.range-selector .range-load-more')).toHaveText('Retry loading commits');
  await expect(page.locator('.range-selector input')).toHaveCount(0);
  await page.locator('.range-selector .range-load-more').click();
  await expect(page.locator('.range-selector select').first().locator('option')).toHaveCount(2);
  expect(calls.filter(c => c.op === 'github.pull.commit.page.get').map(c => c.args.page)).toEqual([1, 1]);
  expect(await page.evaluate(() => document.querySelector('.file-card') === window.originalCard)).toBe(true);
});

test('short PR interval resolves a fork commit and reloads with a static URL', async ({ page }) => {
  const calls = await privateFixture(page, {
    resolveSha: args => args.owner === 'upstream' && args.sha === 'bbbbbbb'
      ? { error: { status: 404, code: 'not_found_or_not_installed', message: 'Not found' } }
      : args.sha === 'aaaaaaa' ? base : middle,
  });
  const route = `/upstream/project/pull/17/compare/${base}..${middle}`;
  const githubUrl = `https://github.com/upstream/project/compare/${base}..${middle}`;
  const workspace = page.locator('.hero-workspace');
  await page.goto('/upstream/project/pull/17/compare/aaaaaaa..bbbbbbb');
  await expect(page).toHaveURL(route);
  await expect(page.locator('.range-review')).toContainText('1 commit');
  await expect(workspace.locator('.workspace-url')).toHaveText(githubUrl);
  await expect(workspace.locator('.workspace-url')).toHaveAttribute('title', githubUrl);
  await expect(workspace.locator('.workspace-url')).toHaveAttribute('href', githubUrl);
  await expect(workspace.locator('form, #commit-url')).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'View diff' })).toHaveCount(0);
  expect(calls.filter(c => c.op === 'github.sha.resolve.get').map(c => c.args.owner)).toEqual(['upstream', 'upstream', 'fork']);
  const count = calls.filter(c => c.op === 'github.sha.resolve.get').length;
  await page.reload();
  await expect(page).toHaveURL(route);
  await expect(page.locator('.range-review')).toContainText('1 commit');
  await expect(workspace.locator('.workspace-url')).toHaveText(githubUrl);
  await expect(workspace.locator('.workspace-url')).toHaveAttribute('title', githubUrl);
  await expect(workspace.locator('.workspace-url')).toHaveAttribute('href', githubUrl);
  await expect(workspace.locator('form, #commit-url')).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'View diff' })).toHaveCount(0);
  expect(calls.filter(c => c.op === 'github.sha.resolve.get')).toHaveLength(count);
  expect(calls.some(c => c.op === 'github.content.get' && c.args.owner === 'fork' && c.args.ref === middle)).toBe(true);
});

test('nonancestor, empty and 300-file intervals report the correct review state', async ({ page }) => {
  const calls = await publicFixture(page, (a, b) => {
    if (a === unrelated) return comparison(unrelated, head, { merge: base });
    if (a === b) return comparison(base, base, { count: 0, files: [] });
    return comparison(base, head, { count: 2, files: Array.from({ length: 300 }, (_, i) => ({ ...file, filename: `file-${i}.mbt` })) });
  });
  await page.goto(`/example/project/compare/${unrelated}..${head}`);
  await expect(page.locator('.empty-state.error')).toContainText('ancestor');
  await page.goto(`/example/project/compare/${base}..${base}`);
  await expect(page.locator('.range-summary')).toContainText('0 commits · 0 files');
  await expect(page.locator('.range-title-commit')).toHaveText([
    `Base ${base.slice(0, 7)}`, `Base ${base.slice(0, 7)}`,
  ]);
  await expect(page.locator('.file-card')).toHaveCount(0);
  await page.goto(`/example/project/compare/${base}..${head}`);
  await expect(page.locator('.range-limit')).toContainText('at most 300 changed files');
  await expect(page.locator('.range-limit a')).toHaveAttribute('href', `https://github.com/example/project/compare/${base}...${head}`);
  await expect(page.locator('.file-card')).toHaveCount(0);
});
