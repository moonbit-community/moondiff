import assert from 'node:assert/strict';
import { randomBytes, createCipheriv, createHmac } from 'node:crypto';
import { startServer } from './server-fixture.mjs';

// Reproduce authenticated cursors with the real test server key, including old formats.
export function sealHomeCursor(f, scope, data) {
  const [[id, epoch, user]] = f.sql('SELECT id,epoch,user_id FROM sessions');
  const key = Buffer.from(f.env.MOONDIFF_TOKEN_KEY, 'base64'), iv = randomBytes(16);
  const cipher = createCipheriv('aes-256-cbc', key.subarray(0, 32), iv);
  const payload = Buffer.concat([Buffer.from([1]), iv, cipher.update(JSON.stringify(data)), cipher.final()]);
  const fields = ['moondiff-token-v1', `home:${scope}:${epoch}`, `${id}:${user}`];
  const authenticated = fields.flatMap(text => { const bytes = Buffer.from(text), size = Buffer.alloc(4); size.writeInt32BE(bytes.length); return [size, bytes]; });
  const mac = createHmac('sha256', key.subarray(32)).update(Buffer.concat([...authenticated, payload])).digest();
  return Buffer.concat([payload, mac]).toString('base64');
}

export function legacyPullCursor(f, kind, total) {
  return sealHomeCursor(f, `pulls:${kind === 'Authored' ? 'author:@me' : 'user-review-requested:@me'}`, {
    windows: [{ since: '0', until: String(Math.floor(Date.now() / 1000)), page: 2, offset: 0 }], total,
  });
}

export function searchPull(number, overrides = {}) {
  return { number, title: `PR ${number}`, repository_url: `https://api.github.com/repos/org/repo${number % 3}`,
    state: 'open', draft: number % 2 === 0, pull_request: {}, user: { login: 'alice' },
    updated_at: new Date(Date.UTC(2026, 8, 1) - Math.floor(number / 3) * 1000).toISOString().replace('.000Z', 'Z'),
    requested: ['alice'], ...overrides };
}
export function searchPage(request, rows, incomplete = false) {
  const url = new URL(request.path, 'http://stub');
  assert.equal(url.searchParams.get('per_page'), '50');
  assert.equal(url.searchParams.get('sort'), 'updated');
  assert.equal(url.searchParams.get('order'), 'desc');
  const match = /^is:pr is:open (author:@me|user-review-requested:@me) updated:(\S+)\.\.(\S+)$/.exec(url.searchParams.get('q'));
  assert(match, `unexpected query ${url.searchParams.get('q')}`);
  const who = request.headers.authorization.replace('Bearer access-', '');
  const lower = Date.parse(match[2]), upper = Date.parse(match[3]);
  assert(Number.isFinite(lower) && Number.isFinite(upper));
  const selected = rows.filter(p => p.state === 'open' && p.pull_request && (match[1] === 'author:@me' ? p.user?.login === who : p.requested?.includes(who)) && Date.parse(p.updated_at) >= lower && Date.parse(p.updated_at) <= upper).sort((a, b) => b.updated_at.localeCompare(a.updated_at));
  const page = Number(url.searchParams.get('page'));
  assert(page <= 20, 'must split before the Search 1,000-result limit');
  return { total_count: selected.length, incomplete_results: incomplete, items: selected.slice((page - 1) * 50, page * 50) };
}

export const commitSha = number => number.toString(16).padStart(40, '0');
const commitDate = '2026-09-01T00:00:00Z';
function graphqlCommit(number) {
  return { commit: { oid: commitSha(number), messageHeadline: `GraphQL commit ${number}`, committedDate: commitDate,
    author: number === 1 ? { name: 'Unlinked Author' } : { name: 'Author', user: { login: 'fork-author' } } } };
}
function restCommit(number) {
  return { sha: commitSha(number), author: number === 1 ? null : { login: 'fork-author' },
    commit: { message: `Commit ${number}\r\n\nBody must not reach the browser`,
      author: { name: 'Unlinked Author', date: '2026-08-01T00:00:00Z' }, committer: { date: commitDate } } };
}

export async function startHomeServer({ total = 301, ...options } = {}) {
  const state = { total, base: 'a'.repeat(40), head: 'b'.repeat(40), rows: [],
    graphqlErrors: null, restFailure: null, afterPage: null, transformCompare: null, transformConnection: null };
  const fixture = await startServer((r, res) => {
    const send = body => { res.end(JSON.stringify(body)); return true; };
    if (r.path.startsWith('/search/issues?')) return send(searchPage(r, state.rows));
    if (r.path === '/graphql') {
      assert.equal(r.headers.authorization, 'Bearer access-alice');
      assert.equal(r.body.variables.owner, 'upstream');
      assert.equal(r.body.variables.repo, 'repo');
      const { number } = r.body.variables;
      const pull = { id: `PR${number}`, baseRefOid: state.base, headRefOid: state.head,
        baseRepository: { nameWithOwner: 'upstream/repo' }, headRepository: { nameWithOwner: 'fork/repo' },
        commits: { totalCount: state.total } };
      if (r.body.query.includes('query PullCommits(')) {
        assert.match(r.body.query, /commits\(first: 100, after: \$cursor\)/);
        const offset = Number(r.body.variables.cursor || 0);
        // GitHub's GraphQL PR connection stops at 250 even when totalCount is larger.
        const limit = Math.min(state.total, 250), end = Math.min(offset + 100, limit);
        assert(offset <= limit);
        Object.assign(pull.commits, { nodes: Array.from({ length: end - offset }, (_, i) => graphqlCommit(offset + i + 1)),
          pageInfo: { hasNextPage: end < limit, endCursor: String(end) } });
        state.transformConnection?.(pull.commits);
        if (state.total <= 250) state.afterPage?.({ source: 'graphql', page: offset / 100 + 1 });
      } else {
        assert.match(r.body.query, /query PullCommitsSnapshot/);
        assert.match(r.body.query, /commits\(first: 1\) \{ totalCount \}/);
      }
      return send({ data: { repository: { pullRequest: pull } }, ...(state.graphqlErrors ? { errors: state.graphqlErrors } : {}) });
    }
    if (r.path.includes('/compare/')) {
      const url = new URL(r.path, 'http://stub');
      // Full snapshot OIDs, in the PR's base repo; never fork names or branch refs.
      assert.equal(url.pathname, `/repos/upstream/repo/compare/${state.base}...${state.head}`);
      assert.equal(url.searchParams.get('per_page'), '100');
      const page = Number(url.searchParams.get('page'));
      assert(Number.isInteger(page) && page >= 1);
      if (state.restFailure) {
        res.statusCode = state.restFailure.status;
        for (const [key, value] of Object.entries(state.restFailure.headers || {})) res.setHeader(key, value);
        return send({ message: 'Fixture GitHub failure' });
      }
      const start = (page - 1) * 100, end = Math.min(start + 100, state.total);
      const data = { total_commits: state.total,
        commits: Array.from({ length: Math.max(0, end - start) }, (_, i) => restCommit(start + i + 1)),
        ...(page === 1 ? { files: [{ filename: 'secret.mbt', patch: 'Diff must not reach the browser' }] } : {}) };
      state.transformCompare?.(data, page);
      state.afterPage?.({ source: 'compare', page });
      return send(data);
    }
  }, options);
  return { ...fixture, state };
}
