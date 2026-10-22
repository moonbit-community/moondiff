import assert from 'node:assert/strict';
import test, { before } from 'node:test';
import { buildServer, startServer, browser } from './server-fixture.mjs';

before(buildServer);
const args = number => ({ owner: 'alice', repo: 'repo', number: String(number) });
const metadata = (count, overrides = {}) => ({
  title: `Snapshot ${count}`, html_url: 'https://github.com/alice/repo/pull/1',
  base: { sha: 'a'.repeat(40), repo: { full_name: 'alice/repo' } },
  head: { sha: 'b'.repeat(40), repo: { full_name: 'fork/repo' } },
  additions: count, deletions: 0, changed_files: count, commits: 0, ...overrides,
});
const file = (index, patch = '+new') => ({ filename: `file${index}.mbt`, status: 'modified', additions: 1, deletions: 0, changes: 1, patch });
const delay = () => new Promise(resolve => setTimeout(resolve, 15));

test('aggregate boundaries, metadata-only fallback, two upstream reads and session-scoped cache confirmation', async t => {
  let active = 0, maxActive = 0;
  const completed = [];
  let title = '', fork = 'fork/repo';
  const fixture = await startServer(async (request, response) => {
    const url = new URL(request.path, 'http://fixture');
    if (!url.pathname.startsWith('/repos/alice/repo/')) return false;
    active++; maxActive = Math.max(maxActive, active);
    await delay();
    const number = Number(url.pathname.match(/\/pulls\/(\d+)/)?.[1]);
    if (/\/pulls\/\d+$/.test(url.pathname)) response.end(JSON.stringify(metadata(number, { ...(title ? { title } : {}), head: { sha: 'b'.repeat(40), repo: { full_name: fork } } })));
    else if (url.pathname.includes('/compare/')) response.end(JSON.stringify({ merge_base_commit: { sha: 'c'.repeat(40) } }));
    else if (url.pathname.endsWith('/files')) {
      const start = (Number(url.searchParams.get('page')) - 1) * 100;
      response.end(JSON.stringify(Array.from({ length: Math.min(100, number - start) }, (_, i) => file(start + i, number === 299 ? 'x'.repeat(30_000) : '+new'))));
    } else return false;
    active--; completed.push(request.path);
    return true;
  });
  t.after(() => fixture.close());
  const alice = browser(fixture); await alice.login();
  for (const count of [1, 100, 101, 112, 300]) {
    const start = fixture.requests.length;
    const result = await alice.rpc('github.pull.snapshot.get', args(count));
    assert.equal(result.ok, true, JSON.stringify(result));
    assert.equal(result.value.$tag, 'Complete');
    assert.equal(result.value['0'].files.length, count);
    const reads = fixture.requests.slice(start);
    assert.match(reads.at(-1).path, /\/pulls\/\d+$/);
    assert.equal(reads.filter(read => read.path.includes('/files?')).length, Math.ceil(count / 100));
    assert.match(completed.at(-1), /\/pulls\/\d+$/);
  }
  assert.equal(maxActive, 2);
  for (const count of [301, 3001, 299]) {
    const result = await alice.rpc('github.pull.snapshot.get', args(count));
    assert.equal(result.ok, true, JSON.stringify(result));
    assert.equal(result.value.$tag, 'MetadataOnly');
    assert.equal(result.value['0'].changed_files, count);
  }
  title = 'Title changed without changing content';
  let start = fixture.requests.length;
  const hit = await alice.rpc('github.pull.snapshot.get', args(112));
  assert.equal(hit.value['0'].metadata.title, title);
  assert.equal(fixture.requests.length - start, 1);
  const bob = browser(fixture); await bob.login('bob');
  start = fixture.requests.length;
  assert.equal((await bob.rpc('github.pull.snapshot.get', args(112))).value.$tag, 'Complete');
  assert.equal(fixture.requests.length - start, 5);
  fork = 'renamed-fork/repo';
  start = fixture.requests.length;
  const changed = await alice.rpc('github.pull.snapshot.get', args(112));
  assert.equal(changed.value['0'].metadata.head.repo.full_name, fork);
  assert.equal(fixture.requests.length - start, 5);
  await alice.login('bob');
  start = fixture.requests.length;
  assert.equal((await alice.rpc('github.pull.snapshot.get', args(112))).value.$tag, 'Complete');
  assert.equal(fixture.requests.length - start, 5, 'a new auth epoch in the same session cannot reuse the old cache');
  title = 'x'.repeat(8 * 1_048_576 - 4_000);
  start = fixture.requests.length;
  const oversizedHit = await alice.rpc('github.pull.snapshot.get', args(112));
  assert.equal(oversizedHit.ok, true);
  assert.equal(oversizedHit.value.$tag, 'MetadataOnly');
  assert.equal(fixture.requests.length - start, 1);
});

test('aggregate independently validates after both reads, rebuilds once and rejects repeated drift', async t => {
  let reads = 0, unstable = false;
  const fixture = await startServer(async (request, response) => {
    if (!request.path.startsWith('/repos/alice/repo/')) return false;
    if (/\/pulls\/\d+$/.test(request.path)) {
      reads++;
      const sha = unstable ? (reads % 2 ? 'b' : 'd') : (reads > 1 ? 'd' : 'b');
      response.end(JSON.stringify(metadata(1, { head: { sha: sha.repeat(40), repo: { full_name: 'fork/repo' } } })));
    } else if (request.path.includes('/compare/')) response.end(JSON.stringify({ merge_base_commit: { sha: 'c'.repeat(40) } }));
    else if (request.path.includes('/files?')) response.end(JSON.stringify([file(0)]));
    else return false;
    return true;
  });
  t.after(() => fixture.close());
  const user = browser(fixture); await user.login();
  const result = await user.rpc('github.pull.snapshot.get', args(1));
  assert.equal(result.ok, true, JSON.stringify(result));
  assert.equal(result.value['0'].metadata.head.sha, 'd'.repeat(40));
  assert.equal(reads, 3);
  unstable = true; reads = 0;
  const failure = await user.rpc('github.pull.snapshot.get', args(2));
  assert.equal(failure.error.code, 'pull_snapshot_changed');
  assert.equal(reads, 3);
});
