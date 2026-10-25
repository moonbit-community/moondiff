import assert from 'node:assert/strict';
import test, { before } from 'node:test';
import { gzipSync } from 'node:zlib';
import { buildServer, startServer, browser } from './server-fixture.mjs';

before(buildServer);
const args = { owner: 'alice', repo: 'repo', sha: '123abcd', page: 1 };
const commit = { sha: args.sha, html_url: 'https://github.com/alice/repo/commit/123abcd', commit: { message: 'fixture' }, parents: [], files: [], stats: { additions: 0, deletions: 0, total: 0 } };
const comment = { id: 1, body: 'hello', html_url: 'https://github.com/comment/1', created_at: '2026-10-23' };
const read = (user, repo = 'repo') => user.rpc('github.commit.get', { ...args, repo });
const barrier = () => Promise.withResolvers();

test('serial API and OAuth requests reuse independent sockets and isolate per-request headers', async t => {
  const fixture = await startServer((request, response) => {
    if (request.method === 'POST' && request.path.endsWith('/comments')) {
      response.end(JSON.stringify(comment)); return true;
    }
  });
  t.after(() => fixture.close());
  const alice = browser(fixture), bob = browser(fixture);
  await alice.login(); await bob.login('bob');
  const start = fixture.requests.length;
  assert.equal((await read(alice)).ok, true);
  assert.equal((await alice.rpc('github.issue.comment.create', { owner: 'alice', repo: 'repo', number: '1', body: 'hello' })).ok, true);
  assert.equal((await read(bob)).ok, true);
  assert.equal((await read(alice)).ok, true);
  const reads = fixture.requests.slice(start);
  assert.equal(new Set(reads.map(request => request.socket)).size, 1);
  assert.deepEqual(reads.map(request => request.headers.authorization), ['Bearer access-alice', 'Bearer access-alice', 'Bearer access-bob', 'Bearer access-alice']);
  assert(reads.every(request => request.headers['user-agent'] === 'moondiff'));
  assert.equal(reads[1].headers['content-type'], 'application/json');
  assert(reads[1].headers['content-length']);
  assert.equal(reads[2].headers['content-type'], undefined);
  assert.equal(reads[2].headers['content-length'], undefined);
  const oauth = fixture.requests.filter(request => request.path.startsWith('/login/'));
  assert.equal(new Set(oauth.map(request => request.socket)).size, 1);
  assert.notEqual(oauth[0].socket, reads[0].socket);
  assert.equal(fixture.transport.connections, 2);
});

test('API and OAuth capacity is independently capped at eight and two', { timeout: 15_000 }, async t => {
  const apiFull = barrier(), oauthFull = barrier(), release = barrier();
  let api = 0, oauth = 0, maxApi = 0, maxOauth = 0, held = false;
  const fixture = await startServer(async (request, response) => {
    if (!held) return false;
    const isApi = request.path.includes('/commits/');
    const isOauth = request.path === '/login/device/code';
    if (!isApi && !isOauth) return false;
    if (isApi) { api++; maxApi = Math.max(maxApi, api); if (api === 8) apiFull.resolve(); }
    else { oauth++; maxOauth = Math.max(maxOauth, oauth); if (oauth === 2) oauthFull.resolve(); }
    response.once('finish', () => { if (isApi) api--; else oauth--; });
    await release.promise;
    return false;
  });
  t.after(() => { release.resolve(); return fixture.close(); });
  const user = browser(fixture); await user.login();
  const signins = Array.from({ length: 3 }, () => browser(fixture));
  await Promise.all(signins.map(user => user.session()));
  held = true;
  const reads = Array.from({ length: 20 }, () => read(user));
  await apiFull.promise;
  const starts = signins.map(user => user.begin());
  await oauthFull.promise;
  assert.equal(api, 8);
  assert.equal(oauth, 2);
  assert.equal(fixture.sockets.size, 10, 'connecting, busy and idle sockets share each pool cap');
  release.resolve();
  assert((await Promise.all(reads)).every(result => result.ok));
  await Promise.all(starts);
  assert.equal(maxApi, 8); assert.equal(maxOauth, 2);
  assert.equal(fixture.transport.maxOpen, 10);
  assert.equal(new Set(fixture.requests.filter(request => request.path.includes('/commits/')).map(request => request.socket)).size, 8);
});

test('chunked, gzip, no-content and close-delimited bodies are consumed before returning sockets', async t => {
  const fixture = await startServer((request, response) => {
    if (request.method === 'DELETE') { response.statusCode = 204; response.end(); return true; }
    if (request.path.endsWith('/issues/comments/1')) { response.end(JSON.stringify({ ...comment, user: { id: 1, login: 'alice' } })); return true; }
    if (!request.path.includes('/commits/')) return false;
    const json = JSON.stringify(commit);
    if (request.path.includes('/chunked/')) {
      response.write(json.slice(0, 20)); response.end(json.slice(20));
    } else if (request.path.includes('/gzip/')) {
      response.setHeader('Content-Encoding', 'gzip');
      const zipped = gzipSync(json); response.write(zipped.subarray(0, 10)); response.end(zipped.subarray(10));
    } else if (request.path.includes('/gzipfixed/')) {
      response.setHeader('Content-Encoding', 'gzip'); response.end(gzipSync(json));
    } else if (request.path.includes('/close/')) {
      response.setHeader('Connection', 'keep-alive, Close'); response.end(json);
    } else if (request.path.includes('/delimited/')) {
      response.useChunkedEncodingByDefault = false;
      response.shouldKeepAlive = false;
      response.flushHeaders(); response.end(json);
    } else return false;
    return true;
  });
  t.after(() => fixture.close());
  const user = browser(fixture); await user.login();
  const start = fixture.requests.length;
  for (const repo of ['chunked', 'gzip', 'gzipfixed', 'repo']) {
    const result = await read(user, repo);
    assert.equal(result.ok, true, `${repo}: ${JSON.stringify(result)}`);
  }
  const first = fixture.requests[start].socket;
  assert(fixture.requests.slice(start).every(request => request.socket === first));
  assert.equal((await user.rpc('github.issue.comment.delete', { owner: 'alice', repo: 'repo', comment_id: '1' })).ok, true);
  assert.equal((await read(user)).ok, true);
  assert.equal(fixture.requests.at(-1).socket, first, '204 keeps an otherwise persistent connection');
  for (const repo of ['close', 'delimited']) {
    assert.equal((await read(user, repo)).ok, true);
    const previous = fixture.requests.at(-1).socket;
    assert.equal((await read(user)).ok, true);
    assert.notEqual(fixture.requests.at(-1).socket, previous);
  }
});

test('disconnect recovery is limited to one reused GET before headers; writes and body failures are never replayed', async t => {
  const counts = new Map();
  const fixture = await startServer((request, response) => {
    if (!request.path.startsWith('/repos/')) return false;
    const repo = request.path.split('/')[3];
    counts.set(repo, (counts.get(repo) || 0) + 1);
    if (['once', 'always', 'write'].includes(repo) && (repo !== 'once' || counts.get(repo) === 1)) {
      response.socket.destroy(); return true;
    }
    if (repo === 'partial') {
      response.writeHead(200, { 'Content-Length': 1000 });
      response.write('{'); response.socket.end(); return true;
    }
    if (repo === 'protocol') { response.socket.end('HTTP/1.1 200 OK\r\nmalformed header\r\n\r\n'); return true; }
    if (repo === 'encoding') { response.setHeader('Content-Encoding', 'unsupported'); response.end('{}'); return true; }
    if (repo === 'large') { response.end('x'.repeat(8 * 1_048_576 + 1)); return true; }
    if (repo === 'ziplarge' || repo === 'ziptruncated') {
      response.setHeader('Content-Encoding', 'gzip');
      const zipped = gzipSync(repo === 'ziplarge' ? 'x'.repeat(8 * 1_048_576 + 1) : JSON.stringify(commit));
      response.end(repo === 'ziptruncated' ? zipped.subarray(0, zipped.length - 6) : zipped);
      return true;
    }
    if (repo === 'http') { response.statusCode = 503; response.end('{}'); return true; }
    return false;
  });
  t.after(() => fixture.close());
  const user = browser(fixture); await user.login();
  assert.equal((await read(user, 'once')).ok, true);
  assert.equal(counts.get('once'), 2);
  assert.equal((await read(user, 'always')).ok, false);
  assert.equal(counts.get('always'), 2);
  for (const repo of ['write', 'partial', 'protocol', 'encoding', 'large', 'ziplarge', 'ziptruncated', 'http']) {
    assert.equal((await read(user)).ok, true, 'a failed exchange releases its capacity');
    const failure = repo === 'write'
      ? await user.rpc('github.issue.comment.create', { owner: 'alice', repo, number: '1', body: 'hello' })
      : await read(user, repo);
    assert.equal(failure.ok, false, repo);
    assert.equal(counts.get(repo), 1, repo);
    if (repo === 'large' || repo === 'ziplarge') assert.equal(failure.error.code, 'response_too_large');
    if (repo === 'protocol' || repo === 'encoding') assert.equal(failure.error.code, 'internal_error');
  }
  assert.equal((await read(user)).ok, true);
  // A peer that disappears while idle produces the same narrowly scoped recovery.
  const previous = fixture.requests.at(-1).socket;
  const socket = fixture.sockets.get(previous);
  const closed = new Promise(resolve => socket.once('close', resolve));
  socket.destroy(); await closed;
  assert.equal((await read(user)).ok, true);
  assert.notEqual(fixture.requests.at(-1).socket, previous);
});

test('issue and review comment page chains cross a barrier together and preserve page order', { timeout: 8000 }, async t => {
  const both = barrier();
  const branches = new Set();
  const fixture = await startServer(async (request, response) => {
    const url = new URL(request.path, 'http://fixture');
    if (!url.pathname.endsWith('/comments')) return false;
    if (url.pathname.includes('/denied/')) { response.statusCode = 403; response.end('{}'); return true; }
    const branch = url.pathname.includes('/issues/') ? 'issue' : 'review';
    const page = Number(url.searchParams.get('page'));
    if (page === 1) {
      branches.add(branch);
      if (branches.size === 2) both.resolve();
      await both.promise;
    }
    const start = (branch === 'issue' ? 0 : 1000) + (page - 1) * 100;
    response.end(JSON.stringify(Array.from({ length: page === 1 ? 100 : 1 }, (_, index) => ({ ...comment, id: start + index + 1, ...(branch === 'review' ? { path: 'file.mbt', commit_id: '123abcd' } : {}) }))));
    return true;
  });
  t.after(() => { both.resolve(); return fixture.close(); });
  const user = browser(fixture); await user.login();
  const result = await user.rpc('github.comments.list', { owner: 'alice', repo: 'repo', kind: 'pull', number: '1' });
  assert.equal(result.ok, true, JSON.stringify(result));
  assert.deepEqual(result.value.issue_comments.map(comment => comment.id), Array.from({ length: 101 }, (_, i) => String(i + 1)));
  assert.deepEqual(result.value.review_comments.map(comment => comment.id), Array.from({ length: 101 }, (_, i) => String(i + 1001)));
  assert.deepEqual(fixture.requests.filter(request => request.path.endsWith('page=1') && request.path.includes('/comments')).map(request => request.path.split('/')[4]).sort(), ['issues', 'pulls']);
  const denied = await user.rpc('github.comments.list', { owner: 'alice', repo: 'denied', kind: 'pull', number: '1' });
  assert.equal(denied.error.code, 'permission_denied');
});
