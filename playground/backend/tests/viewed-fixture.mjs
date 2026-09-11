import { startServer } from './server-fixture.mjs';

export const viewedBase = '1'.repeat(40), viewedHead = 'a'.repeat(40);
export const viewedArgs = { owner: 'alice', repo: 'repo', number: '42' };
export const repositoryPaths = [
  'src/normal.mbt', 'src/back\\slash.mbt', 'src/line\nfeed.mbt',
  'src/tab\tname.mbt', 'src/del\x7fname.mbt', '目录/🐇 space %?#.mbt',
  ' leading and trailing ',
];
export function gate() {
  let resolve;
  const promise = new Promise(r => { resolve = r; });
  return { promise, resolve };
}

// Real backend fixture: mutations wait BEFORE changing GitHub state. Reads have
// no artificial ordering; only the backend coordinator can keep them behind it.
export async function startViewedServer(options = {}) {
  const state = {
    base: viewedBase, head: viewedHead, failReads: 0, reads: [], mutations: [],
    files: ['src/main.mbt', 'src/second.mbt'], states: new Map(), holds: [],
    comments: [], ...options.state,
  };
  const snapshot = () => ({ id: 'PR_fixture', baseRefOid: state.base, headRefOid: state.head });
  const scope = (who, args) => `${who}:${args.owner.toLowerCase()}/${args.repo.toLowerCase()}:${args.number}`;
  state.forScope = (who = 'alice', args = viewedArgs) => {
    const key = scope(who, args);
    if (!state.states.has(key)) state.states.set(key, new Map());
    return state.states.get(key);
  };
  state.holdWrite = (path, { applied = true, fail = false } = {}) => {
    const hold = { path, applied, fail, entered: gate(), release: gate(), used: false };
    state.holds.push(hold);
    return hold;
  };
  const fixture = await startServer(async (r, res) => {
    const send = value => { res.end(JSON.stringify(value)); return true; };
    const who = r.headers.authorization?.replace('Bearer access-', '') || 'anonymous';
    if (r.path === '/graphql') {
      const { query, variables } = r.body;
      if (query.startsWith('mutation')) {
        const viewed = !query.includes('unmarkFileAsViewed');
        const mutation = { who, path: variables.path, viewed };
        state.mutations.push(mutation);
        const hold = state.holds.find(h => !h.used && h.path === variables.path);
        if (hold) { hold.used = true; hold.entered.resolve(); await hold.release.promise; }
        if (!hold || hold.applied) state.forScope(who).set(variables.path, viewed ? 'VIEWED' : 'UNVIEWED');
        if (hold?.fail) { res.statusCode = 503; return send({}); }
        return send({ data: { [viewed ? 'markFileAsViewed' : 'unmarkFileAsViewed']: { pullRequest: snapshot() } } });
      }
      if (query.includes('ViewedFiles')) {
        state.reads.push({ who, ...variables });
        if (state.failReads > 0) { state.failReads--; res.statusCode = 503; return send({}); }
        const values = state.forScope(who, variables);
        return send({ data: { repository: { pullRequest: {
          ...snapshot(), files: {
            totalCount: state.files.length,
            nodes: state.files.map(path => ({ path, viewerViewedState: values.get(path) || 'UNVIEWED' })),
            pageInfo: { hasNextPage: false, endCursor: null },
          },
        } } } });
      }
      return send({ data: { repository: { pullRequest: snapshot() } } });
    }
    if (!r.path.startsWith('/repos/')) return;
    const files = state.files.map(filename => ({
      filename, status: 'modified', additions: 1, deletions: 1, changes: 2,
      patch: '@@ -1,3 +1,3 @@\n fn answer() -> Int {\n-  1\n+  2\n }',
    }));
    if (r.path.includes('/contents/')) {
      res.setHeader('content-type', 'text/plain');
      res.end(`fn answer() -> Int {\n  ${r.path.endsWith(state.head) ? 2 : 1}\n}\n`);
      return true;
    }
    if (r.path.includes('/comments')) {
      if (r.method === 'POST') {
        const comment = {
          id: state.comments.length + 1, ...r.body, user: { id: who === 'bob' ? 2 : 1, login: who },
          html_url: 'https://github.com/alice/repo/pull/42#comment', created_at: '2026-09-11T00:00:00Z',
        };
        state.comments.push(comment);
        return send(comment);
      }
      return send([]);
    }
    if (r.path.includes('/compare/')) return send({ merge_base_commit: { sha: state.base } });
    if (r.path.includes('/files?')) return send(files);
    if (r.path.includes('/pulls/')) return send({
      title: 'Viewed integration fixture', html_url: 'https://github.com/alice/repo/pull/42',
      base: { sha: state.base, repo: { full_name: 'alice/repo' } },
      head: { sha: state.head, repo: { full_name: 'alice/repo' } },
      additions: files.length, deletions: files.length, changed_files: files.length,
    });
    if (r.path.includes('/commits/')) return send({
      sha: state.head, html_url: `https://github.com/alice/repo/commit/${state.head}`,
      commit: { message: 'Filename fixture' }, parents: [{ sha: state.base }],
      stats: { additions: files.length, deletions: files.length, total: files.length * 2 }, files,
    });
  }, options);
  return {
    ...fixture, state,
    async close() {
      state.holds.forEach(h => h.release.resolve());
      await fixture.close();
    },
  };
}
