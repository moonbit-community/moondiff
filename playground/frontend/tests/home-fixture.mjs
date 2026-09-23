import { expect } from '@playwright/test';
import { successFixture } from '../../tests/protocol-fixtures.mjs';

const base = 'a'.repeat(40), head = 'b'.repeat(40);
const pull = (number, overrides = {}) => ({ owner: 'upstream', repo: 'repo', number: String(number), title: `Pull request ${number}`, author: 'alice', updated_at: '2026-09-01T12:00:00Z', draft: false, ...overrides });
const commits = (start, length, overrides = {}) => ({ items: Array.from({ length }, (_, i) => ({ sha: (start + i).toString(16).padStart(40, '0'), message: `Commit ${start + i}`, author: 'fork-author', committed_at: '2026-09-01T00:00:00Z' })), total_count: start + length - 1, base_sha: base, head_sha: head, ...overrides });
const success = (kind, value) => ({ $tag: 'Success', value: { $tag: kind, '0': value } });
const failure = (code, message, status = 502) => ({ status, json: { $tag: 'Failure', error: { status, code, message } } });
function gate() { let release; const promise = new Promise(r => { release = r; }); return { promise, release }; }
async function setup(page, handler) {
  const state = { user: 'alice', calls: [], statusGate: null, installUrl: null };
  await page.addInitScript(() => {
    window.dashboardDocumentId = crypto.randomUUID();
    window.oldLandingSeen = false;
    new MutationObserver(() => {
      if (document.querySelector('.hero-landing, #commit-url, .route-example, .supported-links, footer')) window.oldLandingSeen = true;
    }).observe(document, { subtree: true, childList: true });
  });
  // Popups share the same session and API fixtures as the homepage.
  await page.context().route('**/api/auth/status', async route => {
    if (state.statusGate) await state.statusGate.promise;
    await route.fulfill({ json: successFixture('auth.status', { authenticated: Boolean(state.user), csrf_token: 'fixture', ...(state.installUrl ? { install_url: state.installUrl } : {}), ...(state.user ? { login: state.user, user_id: state.user } : {}) }) });
  });
  await page.context().route('**/api/auth/logout', async route => { state.user = null; await route.fulfill({ json: { $tag: 'Success', value: null } }); });
  await page.context().route('**/api/rpc', async route => {
    const { request } = route.request().postDataJSON();
    const kind = request.$tag, args = request['0']; state.calls.push({ kind, args });
    if (handler && await handler({ route, kind, args, state })) return;
    let value;
    switch (kind) {
      case 'ViewerPullsGet': value = success('ViewerPulls', { items: args.kind.$tag === 'Authored' ? [pull(3, { draft: true })] : [pull(1), pull(2, { owner: 'another', repo: 'project' })], total_count: args.kind.$tag === 'Authored' ? 1 : 2 }); break;
      case 'PullCommitsGet': value = success('PullCommits', commits(1, 1)); break;
      case 'PullGet': value = successFixture('github.pull.get', { title: 'Loaded PR', html_url: 'https://github.com/upstream/repo/pull/1', base: { sha: base, repo: { full_name: 'upstream/repo' } }, head: { sha: head, repo: { full_name: 'fork/repo' } }, additions: 0, deletions: 0, changed_files: 0, commits: 0 }); break;
      case 'CompareGet': value = successFixture('github.compare.get', { merge_base_commit: { sha: base } }); break;
      case 'PullFiles': value = successFixture('github.pull.files', []); break;
      case 'CommentsList': value = successFixture('github.comments.list', { issue_comments: [], review_comments: [], commit_comments: [] }); break;
      case 'PullViewedGet': value = successFixture('github.pull.viewed.get', { base_sha: base, head_sha: head, files: [] }); break;
      case 'PullMergeStatusGet': value = successFixture('github.pull.merge.status', { base_sha: args.expected_base_sha, head_sha: args.expected_head_sha, open: true, draft: false, merged: false, mergeable: true, rebaseable: true, mergeable_state: 'clean', ci_checks: [], ci_warnings: [] }); break;
      case 'CommitGet': value = successFixture('github.commit.get', { sha: args.sha, html_url: `https://github.com/fork/repo/commit/${args.sha}`, commit: { message: 'Loaded commit' }, parents: [], stats: { additions: 0, deletions: 0, total: 0 }, files: [] }); break;
      default: throw new Error(`Unexpected request ${kind}`);
    }
    await route.fulfill({ json: value });
  });
  return state;
}
const reviews = page => page.locator('#home-panel-review');
const authored = page => page.locator('#home-panel-authored');
const row = (page, title) => page.getByRole('tabpanel').locator('.home-pull').filter({ has: page.getByRole('link', { name: title, exact: true }) });
async function noLanding(page) { await expect(page.locator('.hero-landing, #commit-url, .route-example, .supported-links, .public-note, footer')).toHaveCount(0); }

export async function selectTab(page, kind) {
  await page.getByRole('tab', { name: kind === 'Authored' ? /^Pull requests authored by me/ : /^Review requests/ }).click();
}
export async function signOut(page) {
  await page.getByRole('button', { name: /^Account:/ }).click();
  await page.getByRole('menuitem', { name: 'Sign out' }).click();
}
export { base, head, pull, commits, success, failure, gate, setup, reviews, authored, row, noLanding };
