import { rpcRequest } from '../../tests/protocol-fixtures.mjs';
import assert from 'node:assert/strict';
import test, { before } from 'node:test';
import { randomBytes } from 'node:crypto';
import { createServer, request as httpRequest } from 'node:http';
import { once } from 'node:events';
import { writeFileSync } from 'node:fs';
import { buildServer, startServer, browser } from './server-fixture.mjs';
import { startViewedServer, repositoryPaths } from './viewed-fixture.mjs';
import { startHomeServer, searchPull, searchPage, commitSha, sealHomeCursor, legacyPullCursor } from './home-fixture.mjs';

before(buildServer);

async function listen(server) {
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  return server.address().port;
}

async function closeServer(server) {
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
}

test('automatic fixture ports retry an address-in-use allocation', async t => {
  const occupied = createServer((_request, response) => response.end('occupied'));
  const occupiedPort = await listen(occupied);
  t.after(() => closeServer(occupied));
  let allocations = 0;
  const allocatePort = async () => {
    allocations++;
    if (allocations === 1) return occupiedPort;
    const reservation = createServer();
    const port = await listen(reservation);
    await closeServer(reservation);
    return port;
  };
  const f = await startServer(undefined, { allocatePort });
  t.after(() => f.close());
  assert.equal(allocations, 2);
  assert.notEqual(f.port, occupiedPort);
  assert.equal(await (await fetch(`${f.base}/healthz`)).text(), 'ok\n');
});

test('an unrelated health server cannot satisfy fixture readiness', async t => {
  const unrelated = createServer((_request, response) => {
    response.statusCode = 200;
    response.end('ok\n');
  });
  const port = await listen(unrelated);
  t.after(() => closeServer(unrelated));
  await assert.rejects(
    startServer(undefined, { port }),
    /Address already in use|EADDRINUSE/i,
  );
});

test('fixture restart keeps the first successful port', async t => {
  const f = await startServer();
  t.after(() => f.close());
  const { port, base } = f;
  await f.stop();
  await f.start();
  assert.equal(f.port, port);
  assert.equal(f.base, base);
  assert.equal(await (await fetch(`${f.base}/healthz`)).text(), 'ok\n');
});

test('anonymous status is read only and session creation validates origin and JSON', async t => {
  const f = await startServer(); t.after(() => f.close());
  const user = browser(f);
  for (let i = 0; i < 4; i++) {
    const response = await user.request('/api/auth/status');
    assert.equal(response.headers.get('set-cookie'), null);
    assert.equal((await response.json()).value.authenticated, false);
  }
  assert.deepEqual(f.sql('SELECT count(*) FROM sessions'), [[0]]);
  const create = (headers, body = '{}') => user.request('/api/auth/session', { method: 'POST', headers, body });
  for (const [headers, body, status] of [
    [{ 'Content-Type': 'application/json' }, '{}', 403],
    [{ Origin: 'https://evil.example', 'Content-Type': 'application/json' }, '{}', 403],
    [{ Origin: f.base, 'Content-Type': 'text/plain' }, '{}', 415],
    [{ Origin: f.base, 'Content-Type': 'application/json' }, '{', 400],
    [{ Origin: f.base, 'Content-Type': 'application/json' }, '{"extra":true}', 400],
  ]) {
    const response = await create(headers, body);
    assert.equal(response.status, status);
    assert.equal(response.headers.get('set-cookie'), null);
  }
  assert.deepEqual(f.sql('SELECT count(*) FROM sessions'), [[0]]);
  const first = await user.session();
  assert.equal(first.authenticated, false);
  assert.equal(typeof user.csrf, 'string');
  const cookie = user.cookie;
  await user.session();
  assert.equal(user.cookie, cookie);
  assert.deepEqual(f.sql('SELECT count(*) FROM sessions'), [[1]]);
});

test('anonymous session cap cleans expired rows and login extends the session', async t => {
  const f = await startServer(undefined, { env: { MOONDIFF_ANONYMOUS_SESSION_LIMIT: '2' } }); t.after(() => f.close());
  const first = browser(f), second = browser(f), third = browser(f);
  await first.session(); await second.session();
  const full = await third.request('/api/auth/session', { method: 'POST', headers: { Origin: f.base, 'Content-Type': 'application/json' }, body: '{}' });
  assert.equal(full.status, 429);
  assert.equal((await full.json()).error.code, 'session_limit');
  assert.equal(full.headers.get('set-cookie'), null);
  assert.deepEqual(f.sql('SELECT count(*) FROM sessions'), [[2]]);
  f.sql('UPDATE sessions SET expires=1 WHERE csrf=?', [second.csrf]);
  await third.session();
  assert.deepEqual(f.sql('SELECT count(*) FROM sessions'), [[2]]);
  await first.login();
  const [[expires]] = f.sql('SELECT expires FROM sessions WHERE csrf=?', [first.csrf]);
  assert(Math.abs(expires - Date.now() / 1000 - 30 * 86400) < 5);
  await browser(f).session();
  assert.deepEqual(f.sql("SELECT count(*) FROM sessions WHERE tokens=''"), [[2]]);
});

test('authorization relationships and cascade cleanup work without foreign_keys PRAGMA', async t => {
  const f = await startServer(); t.after(() => f.close());
  const user = browser(f);
  const authorization = await user.begin();
  const [[sessionId]] = f.sql('SELECT id FROM sessions');
  assert.throws(() => f.sql("INSERT INTO authorizations (session_id,id,target_id,epoch,phase,expires) VALUES ('missing','attempt','attempt',0,'starting',9999999999)"), /authorization session is missing/);
  assert.throws(() => f.sql("UPDATE authorizations SET session_id='missing' WHERE session_id=?", [sessionId]), /authorization session is missing/);
  assert.throws(() => f.sql("UPDATE sessions SET id='changed' WHERE id=?", [sessionId]), /session has a pending authorization/);
  f.sql('DELETE FROM sessions WHERE id=?', [sessionId]);
  assert.deepEqual(f.sql('SELECT COUNT(*) FROM authorizations'), [[0]]);
  assert.equal((await user.poll(authorization)).ok, false);
  assert.equal((await user.status()).authenticated, false);
});

test('Wasm restores existing WAL sessions and adds ownership triggers on startup', async t => {
  const f = await startServer(); t.after(() => f.close());
  const user = browser(f);
  await user.login();
  await f.stop();
  assert.deepEqual(f.sql('PRAGMA journal_mode=WAL'), [['wal']]);
  for (const [name] of f.sql("SELECT name FROM sqlite_master WHERE type='trigger'")) f.sql(`DROP TRIGGER "${name}"`);
  await f.start();
  const status = await user.status();
  assert.equal(status.authenticated, true);
  assert.equal(status.user_id, '1');
  await user.begin();
  f.sql('DELETE FROM sessions');
  assert.deepEqual(f.sql('SELECT COUNT(*) FROM authorizations'), [[0]]);
  assert.equal((await user.status()).authenticated, false);
});
const args = { owner: 'alice', repo: 'repo', sha: '123abcd', page: 1 };
function gate() { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; }
function raw(f, path, method = 'GET') {
  return new Promise((resolve, reject) => {
    const req = httpRequest({ hostname: '127.0.0.1', port: f.port, path, method }, res => {
      const chunks = []; res.on('data', c => chunks.push(c)); res.on('end', () => resolve({ status: res.statusCode, body: Buffer.concat(chunks).toString() }));
    }); req.on('error', reject); req.end();
  });
}

test('Wasm serves direct routes and HEAD; denies traversal, symlinks, missing paths', async t => {
  const f = await startServer(); t.after(() => f.close());
  const contentSecurityPolicy = "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' https://avatars.githubusercontent.com data:; connect-src 'self' https://api.github.com; frame-ancestors 'none'; base-uri 'self'; form-action 'self'";
  for (const path of ['/', '/alice/repo/pull/42', '/alice/repo/commit/123abcd', '/alice/repo/pull/42/commits/123abcd']) {
    const res = await fetch(f.base + path); assert.equal(res.status, 200); assert.equal(res.headers.get('content-security-policy'), contentSecurityPolicy); assert.match(await res.text(), /fixture/);
  }
  const head = await fetch(f.base + '/styles.css', { method: 'HEAD' }); assert.equal(head.status, 200); assert.equal(await head.text(), '');
  for (const path of ['/missing', '/alice/repo/pull/0', '/..%2Foutside.txt', '/escape', '/a/%2e%2e/styles.css']) assert.equal((await raw(f, path)).status, 404, path);
  assert.equal((await raw(f, '/%XX')).status, 400);
  assert.equal((await raw(f, '/', 'POST')).status, 405);
});

test('device login without a client secret, user isolation, encrypted persistence and restart', async t => {
  const f = await startServer(); t.after(() => f.close());
  assert.equal(f.env.MOONDIFF_GITHUB_CLIENT_SECRET, undefined);
  const alice = browser(f), bob = browser(f);
  const flow = await alice.begin();
  await bob.session();
  assert.equal((await bob.poll(flow)).error.code, 'authorization_not_found');
  assert.equal((await bob.cancel(flow)).value.authenticated, false);
  const [[encrypted]] = f.sql('SELECT credentials FROM authorizations WHERE phase=\'pending\'');
  assert(![...f.devices.keys()].some(code => encrypted.includes(code)));
  assert.equal(flow.phase, 'pending');
  assert.equal(typeof flow.expires_at, 'number');
  assert.equal(typeof flow.retry_after, 'number');
  f.approve(flow.user_code);
  const result = await alice.poll(flow, true);
  assert.equal(result.value.user_id, '1');
  assert.equal(result.value.device_flow.phase, 'completed');
  assert.equal((await bob.login('bob')).user_id, '2');
  const rows = f.sql('SELECT id,tokens,user_id FROM sessions');
  assert.equal(rows.length, 2);
  assert(rows.every(([id, tokens]) => /^[a-f0-9]{64}$/.test(id) && !tokens.includes('access-') && !tokens.includes('refresh-')));
  assert(!JSON.stringify(result).match(/access_token|refresh_token|device_code|credentials/));
  const exchange = f.requests.find(r => r.path === '/login/oauth/access_token');
  assert.equal(exchange.headers.accept, 'application/json');
  assert.deepEqual(Object.keys(exchange.body).sort(), ['client_id', 'device_code', 'grant_type']);
  assert.equal(exchange.body.grant_type, 'urn:ietf:params:oauth:grant-type:device_code');
  assert(f.requests.every(r => !r.body || !('client_secret' in r.body)));
  await f.stop(); await f.start();
  assert.equal((await alice.status()).login, 'alice');
  assert.equal((await bob.status()).login, 'bob');
  assert((await alice.rpc('github.commit.get', args)).ok); assert.equal(f.requests.at(-1).headers.authorization, 'Bearer access-alice');
  assert((await bob.rpc('github.commit.get', args)).ok); assert.equal(f.requests.at(-1).headers.authorization, 'Bearer access-bob');
  await alice.logout(); assert.equal((await alice.status()).authenticated, false); assert.equal((await bob.status()).authenticated, true);
});

test('concurrent refresh is shared and logout defeats a late token response', async t => {
  const entered = gate(), released = gate();
  let delay = false;
  const f = await startServer(async r => { if (delay && r.body?.grant_type === 'refresh_token') { entered.resolve(); await released.promise; } });
  t.after(() => { released.resolve(); return f.close(); });
  const user = browser(f); await user.login();
  f.sql('UPDATE sessions SET access_expires=1');
  const results = await Promise.all(Array.from({ length: 8 }, () => user.rpc('github.commit.get', args)));
  assert(results.every(r => r.ok));
  assert.equal(f.requests.filter(r => r.body?.grant_type === 'refresh_token').length, 1);
  assert.deepEqual(Object.keys(f.requests.find(r => r.body?.grant_type === 'refresh_token').body).sort(), ['client_id', 'grant_type', 'refresh_token']);
  delay = true; f.sql('UPDATE sessions SET access_expires=1');
  const pending = user.rpc('github.commit.get', args); await entered.promise;
  assert.equal((await user.logout()).status, 200); released.resolve();
  assert.equal((await pending).ok, false);
  assert.equal((await user.status()).authenticated, false);
});

test('logout invalidates pending and in-flight device authorizations', async t => {
  const entered = gate(), released = gate();
  let delay = false;
  const f = await startServer(async r => { if (delay && r.body?.device_code) { entered.resolve(); await released.promise; } });
  t.after(() => { released.resolve(); return f.close(); });
  const user = browser(f); let flow = await user.begin();
  await user.logout();
  assert.equal((await user.poll(flow)).error.code, 'csrf_failed');
  await user.status(); flow = await user.begin(); f.approve(flow.user_code); delay = true;
  const pending = user.poll(flow, true);
  await entered.promise; await user.logout(); released.resolve(); assert.equal((await pending).ok, false);
  assert.equal((await user.status()).authenticated, false);
});

test('CSRF, operation validation, anonymous RPC denial and authenticated writes', async t => {
  const f = await startServer(); t.after(() => f.close());
  const user = browser(f); await user.status();
  const calls = f.requests.length;
  assert.equal((await user.rpc('github.commit.get', args)).error.code, 'authentication_required');
  assert.equal(f.requests.length, calls);
  assert.equal((await user.rpc('github.issue.comment.create', { owner: 'alice', repo: 'repo', number: '1', body: 'hello' })).error.code, 'authentication_required');
  await user.login();
  assert.equal((await user.logout({ Origin: 'https://evil.example' })).status, 403);
  assert.equal((await user.logout({ 'X-CSRF-Token': 'wrong' })).status, 403);
  for (const path of ['/auth/login', '/auth/login?csrf=wrong', '/auth/callback']) assert.equal((await user.request(path)).status, 404);
  assert.equal((await user.rpc('github.fetch', args)).error.code, 'invalid_arguments');
  assert.equal((await user.rpc('github.commit.get', { ...args, url: 'http://evil' })).error.code, 'invalid_arguments');
});

const mergeBase = '1'.repeat(40), mergeHead = 'a'.repeat(40);
const mergeArgs = { owner: 'alice', repo: 'repo', number: '42', expected_base_sha: mergeBase, expected_head_sha: mergeHead };
const mergeSnapshot = (overrides = {}) => ({
  base: { sha: mergeBase }, head: { sha: mergeHead }, state: 'open', draft: false,
  merged: false, mergeable: true, rebaseable: true, mergeable_state: 'clean', ...overrides,
});

test('merge status aggregates paginated checks and statuses, tolerates partial CI access, and pins the snapshot', async t => {
  const f = await startServer((r, res) => {
    const send = value => { res.end(JSON.stringify(value)); return true; };
    const url = new URL(r.path, 'http://stub');
    const repo = url.pathname.split('/')[3];
    if (url.pathname.endsWith('/pulls/42')) {
      return send(mergeSnapshot(repo === 'changed' ? { head: { sha: 'b'.repeat(40) } } : {}));
    }
    if (url.pathname.endsWith('/check-runs')) {
      if (repo === 'partial') { res.statusCode = 403; return send({ message: 'Checks permission missing' }); }
      const page = Number(url.searchParams.get('page'));
      const start = page === 1 ? 0 : 100;
      const length = page === 1 ? 100 : 1;
      return send({ total_count: 101, check_runs: Array.from({ length }, (_, i) => ({
        name: `check-${start + i}`, status: 'completed', conclusion: 'success',
        details_url: start + i === 0 ? 'javascript:alert(1)' : `https://example.com/check/${start + i}`,
        html_url: null, output: { title: 'Passed' },
      })) });
    }
    if (url.pathname.endsWith('/status')) return send({ total_count: 1, statuses: [{
      context: 'deploy', state: repo === 'partial' ? 'success' : 'failure',
      description: 'Deployment status', target_url: 'https://example.com/deploy',
    }] });
  });
  t.after(() => f.close());
  const user = browser(f); await user.login();
  const aggregate = await user.rpc('github.pull.merge.status', { ...mergeArgs, repo: 'aggregate' });
  assert.equal(aggregate.ok, true);
  assert.equal(aggregate.value.ci_summary.$tag, 'Failure');
  assert.equal(aggregate.value.ci_checks.length, 102);
  assert.equal(aggregate.value.ci_checks[0].details_url, undefined);
  assert.equal(aggregate.value.ci_checks.at(-1).source.$tag, 'CommitStatus');
  assert.equal(f.requests.filter(r => r.path.includes('/aggregate/') && r.path.includes('/check-runs')).length, 2);

  const partial = await user.rpc('github.pull.merge.status', { ...mergeArgs, repo: 'partial' });
  assert.equal(partial.ok, true);
  assert.equal(partial.value.ci_summary.$tag, 'Success');
  assert.deepEqual(partial.value.ci_warnings, ['Check runs could not be read; CI results are incomplete.']);
  assert.equal(partial.value.ci_checks.length, 1);

  const changed = await user.rpc('github.pull.merge.status', { ...mergeArgs, repo: 'changed' });
  assert.equal(changed.ok, false);
  assert.equal(changed.error.code, 'pull_snapshot_changed');
  assert.equal(f.requests.filter(r => r.path.includes('/changed/') && (r.path.includes('/check-runs') || r.path.includes('/status?'))).length, 0);
});

test('rebase merge requires CSRF and authentication, revalidates SHAs, and sends the pinned head', async t => {
  const f = await startServer((r, res) => {
    const send = value => { res.end(JSON.stringify(value)); return true; };
    if (r.path.endsWith('/pulls/42') && r.method === 'GET') return send(mergeSnapshot());
    if (r.path.endsWith('/pulls/42/merge') && r.method === 'PUT') {
      return send({ merged: true, sha: 'c'.repeat(40), message: 'Pull Request successfully merged' });
    }
  });
  t.after(() => f.close());
  const user = browser(f); await user.status();
  assert.equal((await user.rpc('github.pull.rebase.merge', mergeArgs)).error.code, 'authentication_required');
  await user.login();
  assert.equal((await user.rpc('github.pull.rebase.merge', mergeArgs, { Origin: 'https://evil.example' })).error.code, 'csrf_failed');
  assert.equal((await user.rpc('github.pull.rebase.merge', mergeArgs, { 'X-CSRF-Token': '' })).error.code, 'csrf_failed');
  assert.equal(f.requests.filter(r => r.method === 'PUT').length, 0);
  const merged = await user.rpc('github.pull.rebase.merge', mergeArgs);
  assert.equal(merged.ok, true);
  assert.equal(merged.value.merged, true);
  assert.equal(merged.value.sha, 'c'.repeat(40));
  const put = f.requests.find(r => r.method === 'PUT' && r.path.endsWith('/pulls/42/merge'));
  assert.deepEqual(put.body, { sha: mergeHead, merge_method: 'rebase' });
  assert.equal(put.headers.authorization, 'Bearer access-alice');
});

test('rebase merge exposes stable preflight and GitHub error categories', async t => {
  const errors = {
    denied: [403, 'merge_permission_denied'], limited: [403, 'rate_limit'],
    blocked: [405, 'merge_blocked'], putstale: [409, 'pull_snapshot_changed'],
    rejected: [422, 'merge_rejected'], outage: [503, 'merge_upstream_failure'],
    expired: [401, 'authentication_required'],
  };
  const f = await startServer((r, res) => {
    const send = value => { res.end(JSON.stringify(value)); return true; };
    const url = new URL(r.path, 'http://stub');
    const repo = url.pathname.split('/')[3];
    if (url.pathname.endsWith('/pulls/42') && r.method === 'GET') {
      if (repo === 'predenied') { res.statusCode = 403; return send({ message: 'Forbidden' }); }
      if (repo === 'stale') return send(mergeSnapshot({ head: { sha: 'b'.repeat(40) } }));
      if (repo === 'draft') return send(mergeSnapshot({ draft: true }));
      if (repo === 'unknown') return send(mergeSnapshot({ mergeable: null, rebaseable: null, mergeable_state: 'unknown' }));
      if (repo === 'preconflict') return send(mergeSnapshot({ mergeable: false, rebaseable: false, mergeable_state: 'dirty' }));
      if (repo === 'preblocked') return send(mergeSnapshot({ mergeable_state: 'blocked' }));
      return send(mergeSnapshot());
    }
    if (url.pathname.endsWith('/pulls/42/merge') && r.method === 'PUT') {
      if (repo === 'refused') return send({ merged: false, sha: null, message: 'GitHub did not merge this pull request' });
      if (repo === 'invalidresult') return send({ merged: true, sha: null, message: 'Merged without a SHA' });
      const [status] = errors[repo]; res.statusCode = status;
      if (repo === 'limited') res.setHeader('x-ratelimit-remaining', '0');
      return send({ message: 'GitHub rejected merge' });
    }
  });
  t.after(() => f.close());
  const user = browser(f); await user.login();
  const refused = await user.rpc('github.pull.rebase.merge', { ...mergeArgs, repo: 'refused' });
  assert.equal(refused.ok, true);
  assert.equal(refused.value.merged, false);
  assert.equal(refused.value.message, 'GitHub did not merge this pull request');
  assert.equal((await user.rpc('github.pull.rebase.merge', { ...mergeArgs, repo: 'invalidresult' })).error.code, 'invalid_github_response');
  for (const [repo, code] of [['predenied', 'merge_permission_denied'], ['stale', 'pull_snapshot_changed'], ['draft', 'pull_is_draft'], ['unknown', 'mergeability_unknown'], ['preconflict', 'merge_conflict'], ['preblocked', 'merge_blocked']]) {
    const result = await user.rpc('github.pull.rebase.merge', { ...mergeArgs, repo });
    assert.equal(result.error.code, code, repo);
  }
  assert.equal(f.requests.filter(r => r.method === 'PUT' && r.path.includes('/stale/')).length, 0);
  assert.equal(f.requests.filter(r => r.method === 'PUT' && r.path.includes('/draft/')).length, 0);
  assert.equal(f.requests.filter(r => r.method === 'PUT' && r.path.includes('/unknown/')).length, 0);
  assert.equal(f.requests.filter(r => r.method === 'PUT' && r.path.includes('/preconflict/')).length, 0);
  assert.equal(f.requests.filter(r => r.method === 'PUT' && r.path.includes('/preblocked/')).length, 0);
  for (const [repo, [, code]] of Object.entries(errors)) {
    const result = await user.rpc('github.pull.rebase.merge', { ...mergeArgs, repo });
    assert.equal(result.error.code, code, repo);
  }
  assert.equal(f.requests.filter(r => r.method === 'PUT' && r.path.includes('/putstale/')).length, 1);
});

test('wrong key refuses startup and tampered identity/ciphertext cannot authenticate', async t => {
  const f = await startServer(); t.after(() => f.close());
  const user = browser(f); await user.login(); await f.stop();
  await assert.rejects(f.start({ MOONDIFF_TOKEN_KEY: randomBytes(64).toString('base64') }), /exited/);
  await f.start(); f.sql("UPDATE sessions SET user_id='2'");
  assert.equal((await user.status()).authenticated, false);
  await user.login(); f.sql("UPDATE sessions SET tokens='AAAA'");
  assert.equal((await user.status()).authenticated, false);
});

test('content size limit, comment normalization, ownership, writes and errors', async t => {
  const comment = { id: 123, body: 'hello', html_url: 'https://github.com/comment/123', created_at: '2026-09-10', user: { id: 1, login: 'alice', avatar_url: 'ignored' }, path: 'a.mbt', commit_id: '123abcd', original_line: null, side: 'RIGHT' };
  const f = await startServer((r, res) => {
    if (r.path.includes('/contents/large')) { res.end(Buffer.alloc(1048577)); return true; }
    if (r.path.includes('/contents/')) { res.setHeader('content-type', 'text/plain'); res.end('fn hello {}'); return true; }
    if (r.path.includes('limited')) { res.statusCode = 403; res.setHeader('x-ratelimit-remaining', '0'); res.end('{}'); return true; }
    if (r.path.includes('private')) { res.statusCode = 404; res.end('{}'); return true; }
    if (r.path.includes('/comments')) {
      if (r.method === 'DELETE') { res.statusCode = 204; res.end(); }
      else if (r.path.includes('per_page')) res.end(JSON.stringify([comment]));
      else res.end(JSON.stringify(r.path.endsWith('/999') ? { ...comment, user: { id: 2 } } : comment));
      return true;
    }
  }); t.after(() => f.close());
  const user = browser(f); await user.login();
  const repo = { owner: 'alice', repo: 'repo' };
  const source = await user.rpc('github.content.get', { ...repo, path: 'a.mbt', ref: '123abcd' });
  assert.equal(Buffer.from(source.value.base64, 'base64').toString(), 'fn hello {}');
  assert.equal((await user.rpc('github.content.get', { ...repo, path: 'large', ref: '123abcd' })).error.code, 'source_too_large');
  const comments = await user.rpc('github.comments.list', { ...repo, kind: 'pull', number: '1' });
  assert.equal(comments.value.issue_comments[0].id, '123'); assert(!('original_line' in comments.value.review_comments[0])); assert(!('avatar_url' in comments.value.issue_comments[0].user));
  for (const kind of ['issue', 'review', 'commit']) {
    assert.equal((await user.rpc(`github.${kind}.comment.delete`, { ...repo, comment_id: '999' })).error.code, 'permission_denied');
    assert.deepEqual((await user.rpc(`github.${kind}.comment.delete`, { ...repo, comment_id: '123' })).value, { deleted: true });
  }
  const creates = [
    ['issue.comment', { number: '1' }], ['review.comment', { number: '1', commit_id: '123abcd', path: 'a.mbt', line: 1, side: 'RIGHT' }],
    ['commit.comment', { sha: '123abcd', path: 'a.mbt', position: 1 }], ['review.reply', { number: '1', comment_id: '123' }],
  ];
  for (const [op, fields] of creates) assert.equal((await user.rpc(`github.${op}.create`, { ...repo, ...fields, body: 'hello' })).value.id, '123');
  assert.equal((await user.rpc('github.commit.get', { ...args, repo: 'limited' })).error.code, 'rate_limit');
  assert.equal((await user.rpc('github.commit.get', { ...args, repo: 'private' })).error.code, 'not_found_or_not_installed');
});

test('rejected access tokens refresh once; abandoned waiters cannot discard rotation', async t => {
  const entered = gate(), released = gate();
  let refreshes = 0;
  const f = await startServer(async (r, res) => {
    if (r.body?.grant_type === 'refresh_token') {
      refreshes++; entered.resolve(); await released.promise;
      res.end(JSON.stringify({ access_token: 'rotated', refresh_token: 'rotated-refresh', expires_in: 3600, refresh_token_expires_in: 10000 })); return true;
    }
    if (r.path.startsWith('/repos/') && r.headers.authorization === 'Bearer access-alice') { res.statusCode = 401; res.end('{}'); return true; }
  }); t.after(() => { released.resolve(); return f.close(); });
  const user = browser(f); await user.login();
  const abort = new AbortController();
  const cancelled = user.request('/api/rpc', { method: 'POST', signal: abort.signal, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(rpcRequest('github.commit.get', args)) });
  await entered.promise; abort.abort(); await assert.rejects(cancelled, { name: 'AbortError' });
  const waiting = Array.from({ length: 8 }, () => user.rpc('github.commit.get', args));
  released.resolve(); assert((await Promise.all(waiting)).every(result => result.ok));
  assert.equal(refreshes, 1); await f.stop(); await f.start();
  assert((await user.rpc('github.commit.get', args)).ok); assert.equal(f.requests.at(-1).headers.authorization, 'Bearer rotated');
});

test('expired refresh and pending states retain identity for recovery but never authenticate', async t => {
  const f = await startServer(); t.after(() => f.close());
  const user = browser(f); await user.login();
  f.sql('UPDATE sessions SET access_expires=1, refresh_expires=1');
  const expired = await user.status(); assert.equal(expired.authenticated, false); assert.equal(expired.user_id, '1');
  const old = await user.begin(), same = await user.begin();
  assert.equal(old.id, same.id);
  await user.cancel(old);
  const latest = await user.begin(); f.approve(latest.user_code, 'bob');
  assert.equal((await user.poll(old)).value.device_flow.phase, 'cancelled');
  assert.equal((await user.poll(latest, true)).value.user_id, '2');
  const timedOut = await user.begin(); f.sql('UPDATE authorizations SET expires=1');
  assert.equal((await user.poll(timedOut)).value.device_flow.phase, 'expired');
  assert.equal((await user.status()).user_id, '2');
  f.sql('UPDATE sessions SET expires=1');
  assert.equal((await user.status()).authenticated, false);
  assert.equal(f.sql('SELECT count(*) FROM sessions')[0][0], 1);
  await user.session();
  assert.equal(f.sql('SELECT count(*) FROM authorizations')[0][0], 0);
});

test('pagination is complete or fails explicitly; private credentials and error categories survive RPC', async t => {
  const f = await startServer((r, res) => {
    const url = new URL(r.path, 'http://stub');
    const page = Number(url.searchParams.get('page'));
    if (r.path.startsWith('/repos/alice/private') && !r.headers.authorization) { res.statusCode = 404; res.end('{}'); return true; }
    if (url.pathname.endsWith('/comments')) {
      if (r.path.includes('/denied/')) { res.statusCode = 403; res.end('{"message":"Forbidden"}'); }
      else if (r.path.includes('/limited/')) { res.statusCode = 429; res.end('{}'); }
      else if (r.path.includes('/anchor/')) { res.statusCode = 422; res.end('{"message":"Invalid line"}'); }
      else res.end(JSON.stringify(Array.from({ length: r.path.includes('/overflow/') || page === 1 ? 100 : 1 }, (_, i) => ({ id: (page - 1) * 100 + i + 1, body: 'Comment', html_url: 'https://github.com/comment/1', created_at: '2026-09-10' }))));
      return true;
    }
  }); t.after(() => f.close());
  const user = browser(f); await user.status();
  assert.equal((await user.rpc('github.commit.get', { ...args, repo: 'private' })).ok, false);
  await user.login(); assert.equal((await user.rpc('github.commit.get', { ...args, repo: 'private' })).ok, true);
  const list = repo => user.rpc('github.comments.list', { owner: 'alice', repo, kind: 'commit', sha: '123abcd' });
  const comments = (await list('repo')).value.commit_comments;
  assert.equal(comments.length, 101); assert.equal(comments.at(-1).id, '101');
  assert.equal((await list('overflow')).error.code, 'pagination_limit');
  assert.equal(f.requests.filter(r => r.path.includes('/overflow/')).length, 100);
  for (const [repo, code] of [['denied', 'permission_denied'], ['limited', 'rate_limit'], ['anchor', 'invalid_comment_anchor']]) assert.equal((await list(repo)).error.code, code);
  const write = { owner: 'alice', repo: 'repo', number: '1', body: 'hello' };
  assert.equal((await user.rpc('github.issue.comment.create', write, { Origin: 'https://evil.example' })).error.code, 'csrf_failed');
  assert.equal((await user.rpc('github.issue.comment.create', write, { 'X-CSRF-Token': '' })).error.code, 'csrf_failed');
});

test('session creation issues a Secure HttpOnly host cookie and a 20-minute opaque session', async t => {
  const f = await startServer(undefined, { env: { MOONDIFF_PUBLIC_URL: 'https://localhost' } }); t.after(() => f.close());
  const anonymous = await fetch(f.base + '/api/auth/status');
  assert.equal(anonymous.headers.get('set-cookie'), null);
  assert.equal((await anonymous.json()).value.csrf_token, undefined);
  const res = await fetch(f.base + '/api/auth/session', { method: 'POST', headers: { Origin: 'https://localhost', 'Content-Type': 'application/json' }, body: '{}' });
  assert.match(res.headers.get('set-cookie'), /^__Host-moondiff=/);
  for (const flag of ['Secure', 'HttpOnly', 'SameSite=Lax', 'Path=/', 'Max-Age=2592000']) assert(res.headers.get('set-cookie').includes(flag));
  const [[expires]] = f.sql('SELECT expires FROM sessions');
  assert(Math.abs(expires - Date.now() / 1000 - 20 * 60) < 5);
  assert.equal((await res.json()).value.authenticated, false);
});

test('device start preserves a full authorization window and login extends the session', async t => {
  const f = await startServer(); t.after(() => f.close());
  const user = browser(f); await user.session();
  f.sql('UPDATE sessions SET expires=? WHERE csrf=?', [Math.floor(Date.now() / 1000) + 30, user.csrf]);
  const started = Math.floor(Date.now() / 1000);
  const flow = await user.begin('short-session-attempt-000');
  const [[sessionExpires, authorizationExpires]] = f.sql(
    'SELECT sessions.expires,authorizations.expires FROM sessions JOIN authorizations ON authorizations.session_id=sessions.id WHERE authorizations.id=?',
    [flow.id],
  );
  assert(authorizationExpires >= started + 15 * 60);
  assert(authorizationExpires <= Math.floor(Date.now() / 1000) + 15 * 60);
  assert.equal(sessionExpires, authorizationExpires + 5 * 60);
  f.approve(flow.user_code);
  assert.equal((await user.poll(flow, true)).value.authenticated, true);
  const [[loggedInExpires]] = f.sql('SELECT expires FROM sessions WHERE csrf=?', [user.csrf]);
  assert(Math.abs(loggedInExpires - Date.now() / 1000 - 30 * 86400) < 5);
});

test('reused device authorization repairs fixed session grace without sliding', async t => {
  const f = await startServer(); t.after(() => f.close());
  const user = browser(f); await user.session();
  const attempt = 'legacy-active-attempt-000';
  const flow = await user.begin(attempt);
  const authorizationExpires = Math.floor(Date.now() / 1000) + 10 * 60;
  f.sql('UPDATE authorizations SET expires=?,next_poll=? WHERE id=?', [authorizationExpires, 9999999999999, flow.id]);
  f.sql('UPDATE sessions SET expires=? WHERE csrf=?', [Math.floor(Date.now() / 1000) + 30, user.csrf]);
  assert.equal((await user.begin(attempt)).id, flow.id);
  const expectedSessionExpires = authorizationExpires + 5 * 60;
  assert.deepEqual(f.sql('SELECT expires FROM sessions WHERE csrf=?', [user.csrf]), [[expectedSessionExpires]]);
  for (const id of ['overlap-attempt-000001', 'overlap-attempt-000002', attempt]) {
    assert.equal((await user.begin(id)).id, flow.id);
    assert.deepEqual(f.sql('SELECT expires FROM sessions WHERE csrf=?', [user.csrf]), [[expectedSessionExpires]]);
  }
  assert.deepEqual(f.sql("SELECT COUNT(*) FROM authorizations WHERE phase IN ('starting','pending','verifying')"), [[1]]);
});

test('temporary OAuth outages and malformed upstream JSON keep recovery credentials intact', async t => {
  let unavailable = false;
  const f = await startServer((r, res) => {
    if (unavailable && r.body?.grant_type === 'refresh_token') { res.statusCode = 503; res.end('Unavailable'); return true; }
    if (r.path.startsWith('/repos/')) { res.end('not JSON'); return true; }
  }); t.after(() => f.close());
  const user = browser(f); await user.login(); f.sql('UPDATE sessions SET access_expires=1');
  const before = f.sql('SELECT tokens,epoch FROM sessions'); unavailable = true;
  assert.equal((await (await user.request('/api/auth/status')).json()).error.code, 'github_http_503');
  assert.deepEqual(f.sql('SELECT tokens,epoch FROM sessions'), before);
  unavailable = false; assert.equal((await user.status()).authenticated, true);
  assert.equal((await user.rpc('github.commit.get', args)).error.code, 'invalid_github_response');
});

test('all device endpoints validate cookies, Origin, CSRF, JSON and arguments', async t => {
  const f = await startServer(); t.after(() => f.close());
  const user = browser(f); await user.session();
  for (const action of ['start', 'poll', 'cancel']) {
    const body = action === 'start' ? { attempt_id: 'valid-attempt-000000' } : { authorization_id: 'valid-attempt-000000' };
    for (const headers of [{ Origin: 'https://evil.example' }, { 'X-CSRF-Token': '' }, { Cookie: '' }]) {
      assert.equal((await user.device(action, body, headers)).error.code, 'csrf_failed');
    }
    for (const bad of [{}, { ...body, unexpected: true }, { [Object.keys(body)[0]]: '../bad' }]) {
      assert.equal((await user.device(action, bad)).error.code, 'invalid_arguments');
    }
    const invalid = await user.request(`/api/auth/device/${action}`, { method: 'POST', headers: { Origin: f.base, 'X-CSRF-Token': user.csrf, 'Content-Type': 'application/json' }, body: '{' });
    assert.equal(invalid.status, 400);
  }
  assert.equal(f.requests.length, 0);
});

test('shared starts and polls obey persisted intervals and cumulative slow_down', async t => {
  const entered = gate(), released = gate();
  let slow = false, hold = true;
  const f = await startServer(async (r, res) => {
    if (r.path === '/login/device/code' && hold) { entered.resolve(); await released.promise; }
    if (r.body?.device_code && slow) { res.end(JSON.stringify({ error: 'slow_down' })); return true; }
  }); t.after(() => { released.resolve(); return f.close(); });
  const user = browser(f); await user.status();
  const one = user.begin('same-attempt-00000000'); await entered.promise;
  const others = Array.from({ length: 6 }, (_, i) => user.begin(i % 2 ? 'same-attempt-00000000' : `overlap-attempt-0000${i}`));
  released.resolve(); hold = false;
  const flows = await Promise.all([one, ...others]);
  assert(flows.every(flow => flow.id === flows[0].id));
  assert.equal(f.requests.filter(r => r.path === '/login/device/code').length, 1);
  const flow = flows[0];
  await Promise.all(Array.from({ length: 8 }, () => user.poll(flow)));
  assert.equal(f.requests.filter(r => r.body?.device_code).length, 0);
  f.sql('UPDATE authorizations SET next_poll=0 WHERE id=?', [flow.id]);
  await Promise.all(Array.from({ length: 8 }, () => user.poll(flow)));
  assert.equal(f.requests.filter(r => r.body?.device_code).length, 1);
  slow = true;
  for (const interval of [6, 11]) {
    const result = await user.poll(flow, true);
    assert.equal(result.value.device_flow.retry_after, interval);
    assert.equal(f.sql('SELECT interval FROM authorizations WHERE id=?', [flow.id])[0][0], interval);
    await user.poll(flow);
  }
  assert.equal(f.requests.filter(r => r.body?.device_code).length, 3);
  await f.stop(); await f.start();
  const restored = (await user.status()).device_flow;
  assert.equal(restored.id, flow.id); assert.equal(restored.user_code, flow.user_code);
  await user.poll(flow);
  assert.equal(f.requests.filter(r => r.body?.device_code).length, 3);
  slow = false; f.approve(flow.user_code);
  assert.equal((await user.poll(flow, true)).value.authenticated, true);
});

test('cancellation tombstones defeat reordered starts and late device responses', async t => {
  const entered = gate(), released = gate();
  let delay = true;
  const f = await startServer(async r => {
    if (r.path === '/login/device/code' && delay) { entered.resolve(); await released.promise; }
  }); t.after(() => { released.resolve(); return f.close(); });
  const user = browser(f); await user.session();
  const id = 'cancel-before-start-0000';
  await user.cancel({ id });
  assert.equal((await user.begin(id)).phase, 'cancelled');
  assert.equal(f.requests.length, 0);
  const pending = user.begin('cancel-during-start-000'); await entered.promise;
  await user.cancel({ id: 'cancel-during-start-000' }); released.resolve();
  assert.equal((await pending).phase, 'cancelled');
  assert.equal((await user.status()).device_flow, undefined);
  delay = false;
  const retry = await user.begin(); assert.equal(retry.phase, 'pending');
  assert.notEqual(retry.id, 'cancel-during-start-000');
  const old = await user.begin('cancel-during-start-000'); assert.equal(old.phase, 'cancelled');
  assert.equal((await user.status()).device_flow.id, retry.id);
  const alias = await user.begin('reuse-another-attempt-0'); assert.equal(alias.id, retry.id);
  await user.cancel({ id: 'reuse-another-attempt-0' });
  assert.equal((await user.poll(retry)).value.device_flow.phase, 'cancelled');
  assert(f.sql("SELECT credentials FROM authorizations WHERE phase='cancelled'").every(([value]) => value === ''));
});

test('cancel and logout during identity lookup cannot install tokens', async t => {
  for (const action of ['cancel', 'logout']) {
    const entered = gate(), released = gate();
    const f = await startServer(async r => { if (r.path === '/user') { entered.resolve(); await released.promise; } });
    t.after(() => { released.resolve(); return f.close(); });
    const user = browser(f), flow = await user.begin(); f.approve(flow.user_code);
    const poll = user.poll(flow, true); await entered.promise;
    if (action === 'cancel') await user.cancel(flow); else await user.logout();
    released.resolve(); const result = await poll;
    assert(!result.ok || !result.value.authenticated);
    assert.equal((await user.status()).authenticated, false);
    assert(f.sql('SELECT tokens FROM sessions').every(([tokens]) => tokens === ''));
  }
});

test('logout during device start cannot recreate the session or authorization', async t => {
  const entered = gate(), released = gate();
  const f = await startServer(async r => { if (r.path === '/login/device/code') { entered.resolve(); await released.promise; } });
  t.after(() => { released.resolve(); return f.close(); });
  const user = browser(f); await user.session();
  const result = user.device('start', { attempt_id: 'logout-during-start-000' }); await entered.promise;
  await user.logout(); released.resolve(); assert.equal((await result).ok, false);
  assert.deepEqual(f.sql('SELECT count(*) FROM authorizations'), [[0]]);
  assert.equal((await user.status()).authenticated, false);
});

test('denial, expiration, invalid device codes and configuration errors end authorization', async t => {
  let error = 'access_denied';
  const f = await startServer((r, res) => { if (r.body?.device_code) { res.end(JSON.stringify({ error })); return true; } });
  t.after(() => f.close()); const user = browser(f);
  for (const [code, phase, message] of [
    ['access_denied', 'denied', /declined/], ['expired_token', 'expired', /expired/],
    ['incorrect_device_code', 'failed', /no longer accepts/], ['device_flow_disabled', 'failed', /enabled/],
    ['incorrect_client_credentials', 'failed', /configuration/], ['unsupported_grant_type', 'failed', /configuration/],
  ]) {
    error = code; const flow = await user.begin();
    const status = (await user.poll(flow, true)).value;
    assert.equal(status.device_flow.phase, phase); assert.match(status.device_flow.message, message);
    assert.equal(status.authenticated, false);
    assert.equal(f.sql('SELECT credentials FROM authorizations WHERE id=?', [flow.id])[0][0], '');
    assert.equal((await user.status()).device_flow.phase, phase);
  }
  const flow = await user.begin(); f.sql('UPDATE authorizations SET expires=1 WHERE id=?', [flow.id]);
  const count = f.requests.length;
  assert.equal((await user.poll(flow, true)).value.device_flow.phase, 'expired');
  assert.equal(f.requests.length, count);
});

test('temporary device and user outages back off and recover after restart without redeeming twice', async t => {
  let stage = 'start';
  const f = await startServer((r, res) => {
    if ((stage === 'start' && r.path === '/login/device/code') || (stage === 'poll' && r.body?.device_code)) {
      res.statusCode = 503; res.end('Unavailable'); return true;
    }
    if (stage === 'user' && r.path === '/user') {
      res.statusCode = 429; res.setHeader('Retry-After', '12'); res.end('{}'); return true;
    }
  }); t.after(() => f.close()); const user = browser(f);
  let flow = await user.begin(); assert.equal(flow.phase, 'starting'); assert.equal(flow.retry_after, 5);
  stage = '';
  flow = (await user.poll(flow, true)).value.device_flow; assert.equal(flow.phase, 'pending');
  stage = 'poll';
  for (const wait of [5, 10]) {
    const status = (await user.poll(flow, true)).value;
    assert.equal(status.device_flow.phase, 'pending'); assert.equal(status.device_flow.retry_after, wait);
  }
  stage = 'user'; f.approve(flow.user_code);
  const verifying = (await user.poll(flow, true)).value;
  assert.equal(verifying.device_flow.phase, 'verifying'); assert.equal(verifying.device_flow.retry_after, 12);
  assert(!JSON.stringify(verifying).match(/access-alice|refresh-alice|device_code|access_token/));
  const exchanges = f.requests.filter(r => r.body?.device_code).length;
  await f.stop(); await f.start();
  assert.equal((await user.status()).device_flow.phase, 'verifying');
  await user.poll(flow); assert.equal(f.requests.filter(r => r.path === '/user').length, 1);
  stage = '';
  assert.equal((await user.poll(flow, true)).value.user_id, '1');
  assert.equal(f.requests.filter(r => r.body?.device_code).length, exchanges);
});

test('verification URLs and encrypted device credentials are bound to their authorization', async t => {
  let malicious = true;
  const f = await startServer((r, res) => {
    if (malicious && r.path === '/login/device/code') {
      res.end(JSON.stringify({ device_code: 'x'.repeat(40), user_code: 'AAAA-BBBB', verification_uri: 'https://evil.example/login/device', expires_in: 900, interval: 1 })); return true;
    }
  }); t.after(() => f.close()); const user = browser(f);
  assert.equal((await user.begin()).phase, 'failed');
  malicious = false;
  const first = await user.begin();
  const [[credentials]] = f.sql('SELECT credentials FROM authorizations WHERE id=?', [first.id]);
  await user.cancel(first);
  const second = await user.begin();
  f.sql('UPDATE authorizations SET credentials=? WHERE id=?', [credentials, second.id]);
  assert.equal((await user.poll(second, true)).value.device_flow.phase, 'failed');
  assert.equal(f.requests.filter(r => r.body?.device_code).length, 0);
});

test('network disconnects preserve the attempt and later polls recover', async t => {
  let disconnected = true;
  const f = await startServer((r, res) => {
    if (disconnected && r.path === '/login/device/code') { res.destroy(); return true; }
  }); t.after(() => f.close()); const user = browser(f);
  const flow = await user.begin(); assert.equal(flow.phase, 'starting'); assert.equal(flow.retry_after, 5);
  disconnected = false;
  const recovered = (await user.poll(flow, true)).value.device_flow;
  assert.equal(recovered.id, flow.id); assert.equal(recovered.phase, 'pending');
  f.approve(recovered.user_code);
  assert.equal((await user.poll(recovered, true)).value.authenticated, true);
});

test('a late refresh cannot overwrite a newly confirmed device identity', async t => {
  const entered = gate(), released = gate();
  const f = await startServer(async r => { if (r.body?.grant_type === 'refresh_token') { entered.resolve(); await released.promise; } });
  t.after(() => { released.resolve(); return f.close(); });
  const user = browser(f); await user.login(); f.sql('UPDATE sessions SET access_expires=1');
  const old = user.rpc('github.commit.get', args); await entered.promise;
  const flow = await user.begin(); f.approve(flow.user_code, 'bob');
  assert.equal((await user.poll(flow, true)).value.user_id, '2'); released.resolve();
  assert.equal((await old).ok, false);
  assert.equal((await user.status()).user_id, '2');
  assert((await user.rpc('github.commit.get', args)).ok); assert.equal(f.requests.at(-1).headers.authorization, 'Bearer access-bob');
});

const viewedArgs = { owner: 'alice', repo: 'repo', number: '42' };
const viewedSnapshot = { id: 'PR_fixture', baseRefOid: '1'.repeat(40), headRefOid: 'a'.repeat(40) };
const viewedWrite = { ...viewedArgs, path: 'new/目录 name.mbt', viewed: true, base_sha: viewedSnapshot.baseRefOid, head_sha: viewedSnapshot.headRefOid };
const viewedReadsFor = (state, who, args) => state.reads.filter(read =>
  read.who === who && read.owner.toLowerCase() === args.owner.toLowerCase() &&
  read.repo.toLowerCase() === args.repo.toLowerCase() && String(read.number) === String(args.number));
function viewedPage(nodes, hasNextPage = false, endCursor = null, totalCount = nodes.length, snapshot = viewedSnapshot) {
  return { data: { repository: { pullRequest: { ...snapshot, files: { totalCount, nodes, pageInfo: { hasNextPage, endCursor } } } } } };
}

test('Viewed paginates 100 files, preserves all three states, and verifies the snapshot', async t => {
  const nodes = Array.from({ length: 103 }, (_, i) => ({ path: `src/${i}.mbt`, viewerViewedState: ['VIEWED', 'UNVIEWED', 'DISMISSED'][i % 3] }));
  const f = await startServer((r, res) => {
    if (r.path !== '/graphql') return;
    assert.equal(r.method, 'POST'); assert.match(r.headers.authorization, /^Bearer access-/);
    assert.deepEqual({ ...r.body.variables, cursor: undefined }, { ...viewedArgs, number: 42, cursor: undefined });
    if (r.body.query.includes('ViewedFiles')) {
      assert.match(r.body.query, /files\(first: 100, after: \$cursor\)/);
      const next = r.body.variables.cursor === 'next';
      res.end(JSON.stringify(viewedPage(next ? nodes.slice(100) : nodes.slice(0, 100), !next, next ? null : 'next', 103)));
    } else res.end(JSON.stringify({ data: { repository: { pullRequest: viewedSnapshot } } }));
    return true;
  }); t.after(() => f.close());
  const user = browser(f); await user.status();
  assert.equal((await user.rpc('github.pull.viewed.get', viewedArgs)).error.code, 'authentication_required');
  assert.equal(f.requests.filter(r => r.path === '/graphql').length, 0);
  await user.login(); f.sql('UPDATE sessions SET access_expires=1');
  const result = await user.rpc('github.pull.viewed.get', viewedArgs);
  assert(result.ok, JSON.stringify(result));
  assert.equal(result.value.files.length, 103);
  assert.deepEqual(result.value.files.slice(0, 3).map(f => f.state.$tag), ['Viewed', 'Unviewed', 'Dismissed']);
  assert.equal(result.value.base_sha, viewedSnapshot.baseRefOid);
  assert.equal(result.value.head_sha, viewedSnapshot.headRefOid);
  assert.equal(f.requests.filter(r => r.path === '/graphql').length, 3);
  assert.equal(f.requests.filter(r => r.body?.grant_type === 'refresh_token').length, 1);
});

test('Viewed writes resolve node IDs, preserve renamed paths, check CSRF and stop on changed snapshots', async t => {
  let snapshot = viewedSnapshot, changeDuringMutation = false;
  const f = await startServer((r, res) => {
    if (r.path !== '/graphql') return;
    if (r.body.query.startsWith('mutation')) {
      assert.deepEqual(r.body.variables, { id: 'PR_fixture', path: viewedWrite.path });
      const op = r.body.query.includes('unmarkFileAsViewed') ? 'unmarkFileAsViewed' : 'markFileAsViewed';
      if (changeDuringMutation) snapshot = { ...snapshot, headRefOid: 'b'.repeat(40) };
      res.end(JSON.stringify({ data: { [op]: { pullRequest: snapshot } } }));
    } else res.end(JSON.stringify({ data: { repository: { pullRequest: snapshot } } }));
    return true;
  }); t.after(() => f.close());
  const user = browser(f); await user.status();
  assert.equal((await user.rpc('github.pull.file.viewed.set', viewedWrite)).error.code, 'authentication_required');
  await user.login();
  for (const headers of [{ Origin: 'https://evil.example' }, { 'X-CSRF-Token': 'wrong' }]) {
    assert.equal((await user.rpc('github.pull.file.viewed.set', viewedWrite, headers)).error.code, 'csrf_failed');
  }
  assert.equal(f.requests.filter(r => r.path === '/graphql').length, 0);
  for (const viewed of [true, false]) {
    const result = await user.rpc('github.pull.file.viewed.set', { ...viewedWrite, viewed });
    assert(result.ok, JSON.stringify(result));
    assert.deepEqual(result.value.file, { path: viewedWrite.path, state: { $tag: viewed ? 'Viewed' : 'Unviewed' } });
  }
  snapshot = { ...viewedSnapshot, baseRefOid: '2'.repeat(40) };
  const mutations = () => f.requests.filter(r => r.body?.query?.startsWith('mutation')).length;
  const before = mutations();
  assert.equal((await user.rpc('github.pull.file.viewed.set', viewedWrite)).error.code, 'pull_snapshot_changed');
  assert.equal(mutations(), before);
  snapshot = viewedSnapshot; changeDuringMutation = true;
  assert.equal((await user.rpc('github.pull.file.viewed.set', viewedWrite)).error.code, 'pull_snapshot_changed');
});

test('Viewed rejects partial GraphQL errors and malformed or changed pagination', async t => {
  let response = {}, mode = '', pages = 0;
  const f = await startServer((r, res) => {
    if (r.path !== '/graphql') return;
    pages++;
    if (mode === 'repeat') response = viewedPage([{ path: `src/${pages}`, viewerViewedState: 'VIEWED' }], true, 'same', 3);
    if (mode === 'changed') response = viewedPage([{ path: 'src/last', viewerViewedState: 'VIEWED' }], false, null, 1, pages > 1 ? { ...viewedSnapshot, headRefOid: 'b'.repeat(40) } : viewedSnapshot);
    res.end(JSON.stringify(response)); return true;
  }); t.after(() => f.close());
  const user = browser(f); await user.login();
  for (const [type, code] of [['FORBIDDEN', 'permission_denied'], ['RATE_LIMITED', 'rate_limit'], ['UNAUTHORIZED', 'authentication_required'], ['NOT_FOUND', 'not_found_or_not_installed'], ['OTHER', 'github_graphql_error']]) {
    response = { ...viewedPage([]), errors: [{ type, message: 'upstream private details' }] };
    assert.equal((await user.rpc('github.pull.viewed.get', viewedArgs)).error.code, code);
  }
  for (const value of [
    viewedPage([{ path: 'a', viewerViewedState: 'UNKNOWN' }]),
    viewedPage([{ path: 'a', viewerViewedState: 'VIEWED' }, { path: 'a', viewerViewedState: 'VIEWED' }]),
    viewedPage([], true, 'cursor', 1), viewedPage([], false, null, 1),
    viewedPage([{ path: '../bad', viewerViewedState: 'VIEWED' }]),
    { data: { repository: { pullRequest: null } } },
  ]) {
    response = value;
    assert.equal((await user.rpc('github.pull.viewed.get', viewedArgs)).error.code, 'invalid_github_response');
  }
  response = viewedPage([], false, null, 3001);
  assert.equal((await user.rpc('github.pull.viewed.get', viewedArgs)).error.code, 'pagination_limit');
  mode = 'repeat'; pages = 0;
  assert.equal((await user.rpc('github.pull.viewed.get', viewedArgs)).error.code, 'invalid_github_response');
  assert.equal(pages, 2);
  mode = 'changed'; pages = 0;
  assert.equal((await user.rpc('github.pull.viewed.get', viewedArgs)).error.code, 'pull_snapshot_changed');
});

for (const viewed of [true, false]) {
  test(`Viewed confirmation waits for a disconnected ${viewed ? 'mark' : 'unmark'} across sessions`, async t => {
    const f = await startViewedServer(); t.after(() => f.close());
    const user = browser(f), restored = browser(f), bob = browser(f);
    await user.login(); await restored.login(); await bob.login('bob');
    const path = f.state.files[0];
    f.state.forScope().set(path, viewed ? 'UNVIEWED' : 'VIEWED');
    const hold = f.state.holdWrite(path);
    const abort = new AbortController();
    const writing = user.request('/api/rpc', {
      method: 'POST', signal: abort.signal,
      headers: { 'Content-Type': 'application/json', Origin: f.base, 'X-CSRF-Token': user.csrf },
      body: JSON.stringify(rpcRequest('github.pull.file.viewed.set', { ...viewedWrite, path, viewed })),
    });
    await hold.entered.promise;
    abort.abort(); await assert.rejects(writing, { name: 'AbortError' });
    let settled = false;
    const confirming = restored.rpc('github.pull.viewed.get', { ...viewedArgs, owner: 'ALICE', repo: 'Repo' }).then(result => { settled = true; return result; });
    // Independent users, repositories and PRs remain usable while Alice waits.
    for (const [reader, scope] of [
      [bob, viewedArgs], [restored, { ...viewedArgs, repo: 'other' }], [restored, { ...viewedArgs, number: '43' }],
    ]) assert((await reader.rpc('github.pull.viewed.get', scope)).ok);
    assert.equal(settled, false);
    assert.equal(viewedReadsFor(f.state, 'alice', viewedArgs).length, 0);
    hold.release.resolve();
    const result = await confirming;
    assert(result.ok, JSON.stringify(result));
    assert.equal(result.value.files[0].state.$tag, viewed ? 'Viewed' : 'Unviewed');
    assert.equal(f.state.mutations.length, 1);
  });
}

test('Viewed serializes multiple files and continues after a failed mutation', async t => {
  const f = await startViewedServer(); t.after(() => f.close());
  const user = browser(f); await user.login();
  const [first, second] = f.state.files;
  const hold = f.state.holdWrite(first, { fail: true });
  const one = user.rpc('github.pull.file.viewed.set', { ...viewedWrite, path: first });
  await hold.entered.promise;
  const two = user.rpc('github.pull.file.viewed.set', { ...viewedWrite, path: second });
  // A completed independent scope proves the server has continued scheduling
  // after the second request was submitted without entering this scope's FIFO.
  assert((await user.rpc('github.pull.viewed.get', { ...viewedArgs, number: '43' })).ok);
  const read = user.rpc('github.pull.viewed.get', viewedArgs);
  assert((await user.rpc('github.pull.viewed.get', { ...viewedArgs, number: '44' })).ok);
  assert.equal(f.state.mutations.length, 1);
  assert.equal(viewedReadsFor(f.state, 'alice', viewedArgs).length, 0);
  hold.release.resolve();
  assert.equal((await one).ok, false);
  assert.equal((await two).ok, true);
  assert.deepEqual((await read).value.files.map(f => f.state.$tag), ['Viewed', 'Viewed']);
  assert.deepEqual(f.state.mutations.map(m => m.path), [first, second]);
});

test('repository filenames survive source URL encoding, both comment APIs and Viewed', async t => {
  const f = await startViewedServer({ state: { files: repositoryPaths } }); t.after(() => f.close());
  const user = browser(f); await user.login();
  for (const path of repositoryPaths) {
    const source = await user.rpc('github.content.get', { owner: 'alice', repo: 'repo', path, ref: viewedSnapshot.headRefOid });
    assert(source.ok, JSON.stringify(source));
    const encoded = path.split('/').map(encodeURIComponent).join('/');
    assert.equal(f.requests.at(-1).path, `/repos/alice/repo/contents/${encoded}?ref=${viewedSnapshot.headRefOid}`);
    for (const [op, args] of [
      ['github.review.comment.create', { ...viewedArgs, path, body: 'PR comment', commit_id: viewedSnapshot.headRefOid, line: 2, side: 'RIGHT' }],
      ['github.commit.comment.create', { owner: 'alice', repo: 'repo', sha: viewedSnapshot.headRefOid, path, body: 'Commit comment', position: 3 }],
    ]) {
      const result = await user.rpc(op, args);
      assert(result.ok, JSON.stringify(result));
      assert.equal(f.requests.at(-1).body.path, path);
      assert.equal(result.value.path, path);
    }
    for (const viewed of [true, false]) {
      const result = await user.rpc('github.pull.file.viewed.set', { ...viewedWrite, path, viewed });
      assert(result.ok, JSON.stringify(result));
      assert.equal(f.requests.at(-1).body.variables.path, path);
      const read = await user.rpc('github.pull.viewed.get', viewedArgs);
      assert(read.ok, JSON.stringify(read));
      assert.deepEqual(read.value.files.map(f => f.path), repositoryPaths);
      assert.equal(read.value.files.find(f => f.path === path).state.$tag, viewed ? 'Viewed' : 'Unviewed');
    }
  }
});

const viewerPullsOp = 'github.viewer.pulls.get';
const pullCommitsOp = 'github.pull.commits.get';
const authoredPulls = { kind: { $tag: 'Authored' } };
const reviewPulls = { kind: { $tag: 'ReviewRequested' } };
test('homepage searches all accessible repositories with direct review and author filters, drafts and paging', async t => {
  const rows = Array.from({ length: 63 }, (_, i) => searchPull(i + 1));
  rows.push(searchPull(100, { state: 'closed' }), searchPull(101, { state: 'closed', pull_request: { merged_at: 'today' } }), searchPull(102, { pull_request: undefined }));
  rows.push(searchPull(200, { user: { login: 'bob' }, requested: [], team_requested: ['alice-team'] }));
  rows.push(searchPull(201, { user: { login: 'bob' }, requested: ['alice'] }));
  const f = await startServer((r, res) => {
    if (!r.path.startsWith('/search/issues?')) return;
    res.end(JSON.stringify(searchPage(r, rows))); return true;
  }); t.after(() => f.close());
  const alice = browser(f), bob = browser(f);
  await alice.status();
  assert.equal((await alice.rpc(viewerPullsOp, authoredPulls)).error.code, 'authentication_required');
  assert.equal(f.requests.filter(r => r.path.startsWith('/search')).length, 0);
  await alice.login(); await bob.login('bob');
  const first = await alice.rpc(viewerPullsOp, authoredPulls);
  assert.equal(first.ok, true, JSON.stringify(first));
  assert.equal(first.value.total_count, 63); assert.equal(first.value.items.length, 50);
  assert.equal(new Set(first.value.items.map(p => p.repo)).size, 3);
  assert(first.value.items.some(p => p.draft)); assert(!first.value.incomplete);
  const cursor = first.value.next_cursor;
  const second = await alice.rpc(viewerPullsOp, { ...authoredPulls, cursor });
  assert.equal(second.value.items.length, 13); assert(!second.value.next_cursor);
  const review = await alice.rpc(viewerPullsOp, reviewPulls);
  assert.equal(review.value.total_count, 64);
  assert.equal((await bob.rpc(viewerPullsOp, { ...authoredPulls, cursor })).error.code, 'invalid_cursor');
  assert.equal((await alice.rpc(viewerPullsOp, { ...reviewPulls, cursor })).error.code, 'invalid_cursor');
  assert.equal((await alice.rpc(viewerPullsOp, { ...authoredPulls, cursor: cursor + 'x' })).error.code, 'invalid_cursor');
  for (const extra of [{ username: 'bob' }, { query: 'is:closed' }]) assert.equal((await alice.rpc(viewerPullsOp, { ...authoredPulls, ...extra })).error.code, 'invalid_arguments');
});

for (const args of [authoredPulls, reviewPulls]) test(`${args.kind.$tag} confirms the total before splitting 1,000-result windows without losing timestamp ties`, async t => {
  const rows = Array.from({ length: 1107 }, (_, i) => searchPull(i + 1));
  let incomplete = true;
  const f = await startServer((r, res) => {
    if (!r.path.startsWith('/search/issues?')) return;
    const result = searchPage(r, rows, incomplete);
    if (incomplete) result.total_count = 0;
    incomplete = false;
    res.end(JSON.stringify(result)); return true;
  }); t.after(() => f.close());
  const user = browser(f); await user.login();
  const partial = await user.rpc(viewerPullsOp, args);
  assert.equal(partial.ok, true, JSON.stringify(partial));
  assert.equal(partial.value.total_count, 0);
  assert.match(partial.value.incomplete, /incomplete/);
  assert.deepEqual(partial.value.items, []);
  assert(partial.value.next_cursor);
  let cursor = partial.value.next_cursor; const items = [];
  for (let page = 0; page < 40; page++) {
    const result = await user.rpc(viewerPullsOp, { ...args, cursor });
    assert.equal(result.ok, true, JSON.stringify(result));
    assert.equal(result.value.total_count, 1107);
    assert(!result.value.incomplete, result.value.incomplete);
    assert.equal(result.value.items.length, result.value.next_cursor ? 50 : 7);
    items.push(...result.value.items); cursor = result.value.next_cursor;
    if (!cursor) break;
  }
  assert(!cursor); assert.equal(items.length, 1107);
  assert.equal(new Set(items.map(p => `${p.repo}/${p.number}`)).size, 1107);
  assert.deepEqual(items.map(p => p.updated_at), items.map(p => p.updated_at).sort().reverse());
  assert(new Set(f.requests.filter(r => r.path.startsWith('/search')).map(r => new URL(r.path, 'http://stub').searchParams.get('q'))).size > 1);
});

for (const args of [authoredPulls, reviewPulls]) {
  for (const [counts, total] of [[[0], 1], [[0, 7, 2], 1], [[4, 2], 0]]) {
    test(`${args.kind.$tag} replaces provisional totals ${counts.join(', ')} with the first complete total ${total}`, async t => {
      let attempt = 0;
      const rows = Array.from({ length: total }, (_, i) => searchPull(i + 1));
      const paths = [];
      const f = await startServer((r, res) => {
        if (!r.path.startsWith('/search/issues?')) return;
        paths.push(r.path);
        const result = searchPage(r, rows, attempt < counts.length);
        if (attempt < counts.length) result.total_count = counts[attempt];
        attempt++;
        res.end(JSON.stringify(result)); return true;
      }); t.after(() => f.close());
      const user = browser(f); await user.login();
      let cursor;
      for (const count of counts) {
        const partial = await user.rpc(viewerPullsOp, { ...args, ...(cursor ? { cursor } : {}) });
        assert.equal(partial.ok, true, JSON.stringify(partial));
        assert.equal(partial.value.total_count, count);
        assert.deepEqual(partial.value.items, []);
        assert.match(partial.value.incomplete, /incomplete/);
        cursor = partial.value.next_cursor; assert(cursor);
      }
      const complete = await user.rpc(viewerPullsOp, { ...args, cursor });
      assert.equal(complete.ok, true, JSON.stringify(complete));
      assert.equal(complete.value.total_count, total);
      assert.deepEqual(complete.value.items.map(p => p.number), rows.map(p => String(p.number)));
      assert(!complete.value.next_cursor); assert(!complete.value.incomplete);
      assert.equal(paths.length, counts.length + 1);
      assert.equal(new Set(paths).size, 1, 'retries must use the original search window and page');
    });
  }

  test(`${args.kind.$tag} keeps the confirmed total through incomplete and changed later pages`, async t => {
    let rows = Array.from({ length: 51 }, (_, i) => searchPull(i + 1));
    let provisional;
    const paths = [];
    const f = await startServer((r, res) => {
      if (!r.path.startsWith('/search/issues?')) return;
      paths.push(r.path);
      const result = searchPage(r, rows, provisional !== undefined);
      if (provisional !== undefined) result.total_count = provisional;
      res.end(JSON.stringify(result)); return true;
    }); t.after(() => f.close());
    const user = browser(f); await user.login();
    const first = await user.rpc(viewerPullsOp, args);
    assert.equal(first.ok, true, JSON.stringify(first));
    assert.equal(first.value.total_count, 51); assert.equal(first.value.items.length, 50);
    let cursor = first.value.next_cursor; assert(cursor);
    for (const count of [0, 99]) {
      provisional = count;
      const partial = await user.rpc(viewerPullsOp, { ...args, cursor });
      assert.equal(partial.ok, true, JSON.stringify(partial));
      assert.equal(partial.value.total_count, 51);
      assert.deepEqual(partial.value.items, []);
      assert.match(partial.value.incomplete, /incomplete/);
      cursor = partial.value.next_cursor; assert(cursor);
    }
    provisional = undefined; rows.push(searchPull(52));
    const complete = await user.rpc(viewerPullsOp, { ...args, cursor });
    assert.equal(complete.ok, true, JSON.stringify(complete));
    assert.equal(complete.value.total_count, 51);
    assert.deepEqual(complete.value.items.map(p => p.number), ['51', '52']);
    assert(!complete.value.next_cursor); assert(!complete.value.incomplete);
    assert.equal(new Set(paths.slice(1)).size, 1, 'later-page retries must not advance');
    assert.equal(new URL(paths[1], 'http://stub').searchParams.get('page'), '2');
    const refreshed = await user.rpc(viewerPullsOp, args);
    assert.equal(refreshed.value.total_count, 52);
  });

  test(`${args.kind.$tag} rejects pre-confirmation cursors before calling GitHub and accepts a fresh traversal`, async t => {
    const f = await startHomeServer(); t.after(() => f.close());
    f.state.rows = Array.from({ length: 51 }, (_, i) => searchPull(i + 1));
    const user = browser(f); await user.login();
    const cursor = legacyPullCursor(f, args.kind.$tag, 51);
    const requests = f.requests.length;
    const expired = await user.rpc(viewerPullsOp, { ...args, cursor });
    assert.equal(expired.error?.status, 400);
    assert.equal(expired.error?.code, 'invalid_cursor');
    assert.equal(f.requests.length, requests, 'old cursors must not call GitHub');
    const first = await user.rpc(viewerPullsOp, args);
    assert.equal(first.ok, true, JSON.stringify(first));
    assert.equal(first.value.total_count, 51); assert.equal(first.value.items.length, 50);
    assert(first.value.next_cursor);
    const last = await user.rpc(viewerPullsOp, { ...args, cursor: first.value.next_cursor });
    assert.equal(last.ok, true, JSON.stringify(last));
    assert.equal(last.value.total_count, 51); assert.equal(last.value.items.length, 1);
    assert(!last.value.next_cursor);
  });
}

test('incomplete and unsplittable search windows retain retry cursors', async t => {
  let incomplete = true;
  let rows = [searchPull(1)];
  const f = await startServer((r, res) => {
    if (!r.path.startsWith('/search/issues?')) return;
    res.end(JSON.stringify(searchPage(r, rows, incomplete))); return true;
  }); t.after(() => f.close());
  const user = browser(f); await user.login();
  const partial = await user.rpc(viewerPullsOp, authoredPulls);
  assert.match(partial.value.incomplete, /incomplete/);
  assert.equal(partial.value.items.length, 0); assert(partial.value.next_cursor);
  incomplete = false;
  const retry = await user.rpc(viewerPullsOp, { ...authoredPulls, cursor: partial.value.next_cursor });
  assert.equal(retry.value.items.length, 1); assert(!retry.value.incomplete);
  rows = Array.from({ length: 1001 }, (_, i) => searchPull(i + 1, { updated_at: '2026-09-01T00:00:00Z' }));
  const tied = await user.rpc(viewerPullsOp, authoredPulls);
  assert.equal(tied.ok, true, JSON.stringify(tied));
  assert.match(tied.value.incomplete, /same update time/); assert(tied.value.next_cursor);
});

const commitArgs = { owner: 'upstream', repo: 'repo', number: '42' };
for (const total of [0, 250, 251, 301]) test(`homepage loads all ${total} commits in order using one source, including fork commits`, async t => {
  const f = await startHomeServer({ total }); t.after(() => f.close());
  const user = browser(f);
  await user.status();
  assert.equal((await user.rpc(pullCommitsOp, commitArgs)).error.code, 'authentication_required');
  assert.equal(f.requests.filter(r => r.path === '/graphql').length, 0);
  await user.login();
  const items = []; let cursor;
  for (let i = 0; i < 5; i++) {
    const page = await user.rpc(pullCommitsOp, { ...commitArgs, ...(cursor ? { cursor } : {}) });
    assert(page.ok, JSON.stringify(page));
    assert.equal(page.value.total_count, total);
    assert.equal(page.value.base_sha, f.state.base); assert.equal(page.value.head_sha, f.state.head);
    assert.equal(page.value.items.length, Math.min(100, total - items.length));
    items.push(...page.value.items); cursor = page.value.next_cursor;
    if (!cursor) break;
  }
  assert(!cursor); assert.equal(items.length, total);
  assert.deepEqual(items.map(c => c.sha), Array.from({ length: total }, (_, i) => commitSha(i + 1)));
  assert.equal(new Set(items.map(c => c.sha)).size, total);
  if (total) {
    assert.equal(items[0].author, 'Unlinked Author'); assert.equal(items[1].author, 'fork-author');
    for (const [index, item] of items.entries()) {
      assert.equal(item.message, `${total > 250 ? 'Commit' : 'GraphQL commit'} ${index + 1}`);
      assert.equal(item.committed_at, '2026-09-01T00:00:00Z');
      assert.deepEqual(Object.keys(item).sort(), ['author', 'committed_at', 'message', 'sha']);
    }
  }
  const graphqlPages = f.requests.filter(r => r.body?.query?.includes('query PullCommits('));
  const comparePages = f.requests.filter(r => r.path.includes('/compare/'));
  assert.equal(graphqlPages.length, total > 250 ? 1 : Math.max(1, Math.ceil(total / 100)));
  assert.deepEqual(comparePages.map(r => new URL(r.path, 'http://stub').searchParams.get('page')),
    total > 250 ? Array.from({ length: Math.ceil(total / 100) }, (_, i) => String(i + 1)) : []);
});

for (const total of [250, 301]) test(`commit snapshot checks reject base, head and count changes before and during ${total}-commit pages`, async t => {
  const f = await startHomeServer({ total }); t.after(() => f.close());
  const user = browser(f); await user.login();
  const original = { base: f.state.base, head: f.state.head, total };
  const first = await user.rpc(pullCommitsOp, commitArgs);
  assert(first.ok, JSON.stringify(first));
  for (const field of ['base', 'head', 'total']) {
    const mutate = () => { f.state[field] = field === 'total' ? total + 1 : 'c'.repeat(40); };
    for (const timing of ['before', 'during']) {
      Object.assign(f.state, original, { afterPage: null });
      if (timing === 'before') mutate();
      else f.state.afterPage = mutate;
      const result = await user.rpc(pullCommitsOp, { ...commitArgs, cursor: first.value.next_cursor });
      assert.equal(result.error?.code, 'pull_commits_changed', `${field} ${timing}: ${JSON.stringify(result)}`);
    }
    // A first-page race must also fail without publishing a partial snapshot.
    Object.assign(f.state, original, { afterPage: mutate });
    assert.equal((await user.rpc(pullCommitsOp, commitArgs)).error?.code, 'pull_commits_changed');
  }
});

test('compare rejects inconsistent totals, short, empty, oversized and duplicate pages', async t => {
  const f = await startHomeServer(); t.after(() => f.close());
  const user = browser(f); await user.login();
  const first = await user.rpc(pullCommitsOp, commitArgs);
  const second = await user.rpc(pullCommitsOp, { ...commitArgs, cursor: first.value.next_cursor });
  const third = await user.rpc(pullCommitsOp, { ...commitArgs, cursor: second.value.next_cursor });
  for (const transform of [
    data => { data.total_commits--; },
    data => { data.total_commits = 301.5; },
    data => { delete data.total_commits; },
    data => { data.commits.pop(); },
    data => { data.commits = []; },
    data => { data.commits.push(data.commits[0]); },
    data => { data.commits[1] = data.commits[0]; },
    data => { data.commits[0].sha = 'bad'; },
    data => { delete data.commits[0].commit.committer; },
  ]) {
    f.state.transformCompare = transform;
    for (const cursor of [undefined, first.value.next_cursor]) {
      const result = await user.rpc(pullCommitsOp, { ...commitArgs, ...(cursor ? { cursor } : {}) });
      assert.equal(result.error?.code, 'invalid_github_response', JSON.stringify(result));
    }
  }
  // The terminal page must account for exactly the remaining single commit.
  for (const length of [0, 2, 100]) {
    f.state.transformCompare = data => { data.commits = Array.from({ length }, () => data.commits[0]); };
    assert.equal((await user.rpc(pullCommitsOp, { ...commitArgs, cursor: third.value.next_cursor })).error?.code, 'invalid_github_response');
  }
});

test('GraphQL commit pages reject premature completion and non-progressing cursors', async t => {
  const f = await startHomeServer({ total: 250 }); t.after(() => f.close());
  const user = browser(f); await user.login();
  const first = await user.rpc(pullCommitsOp, commitArgs);
  for (const transform of [
    data => { data.pageInfo.hasNextPage = false; },
    data => { data.pageInfo.endCursor = '100'; },
    data => { data.pageInfo.endCursor = ''; },
    data => { data.nodes = []; },
    data => { data.nodes.push(data.nodes[0]); },
    data => { data.nodes[1] = data.nodes[0]; },
  ]) {
    f.state.transformConnection = transform;
    const result = await user.rpc(pullCommitsOp, { ...commitArgs, cursor: first.value.next_cursor });
    assert.equal(result.error?.code, 'invalid_github_response', JSON.stringify(result));
  }
});

// Reproduce a valid pre-upgrade encrypted cursor, with the real test server key.
function legacyCommitCursor(f) {
  return sealHomeCursor(f, 'commits:upstream/repo/42', {
    after: '100', base: f.state.base, head: f.state.head, loaded: 100, total: f.state.total,
  });
}

for (const total of [250, 301]) test(`commit cursors bind session, repository, PR and source for ${total} commits; old formats fail`, async t => {
  const f = await startHomeServer({ total }); t.after(() => f.close());
  const user = browser(f); await user.login();
  const first = await user.rpc(pullCommitsOp, commitArgs), cursor = first.value.next_cursor;
  const legacy = legacyCommitCursor(f);
  const count = f.requests.length;
  for (const args of [
    { ...commitArgs, cursor: legacy }, { ...commitArgs, cursor: cursor + 'x' },
    { ...commitArgs, number: '43', cursor }, { ...commitArgs, owner: 'fork', cursor },
    { ...commitArgs, repo: 'another', cursor },
  ]) assert.equal((await user.rpc(pullCommitsOp, args)).error?.code, 'invalid_cursor');
  assert.equal(f.requests.length, count, 'invalid cursors must not call GitHub');
  const other = browser(f); await other.login();
  assert.equal((await other.rpc(pullCommitsOp, { ...commitArgs, cursor })).error?.code, 'invalid_cursor');
  await user.logout(); await user.status(); await user.login();
  assert.equal((await user.rpc(pullCommitsOp, { ...commitArgs, cursor })).error?.code, 'invalid_cursor');
  assert.equal((await user.rpc(pullCommitsOp, commitArgs)).ok, true);
});

test('commit pagination preserves GraphQL partial-error and REST permission, rate-limit and session handling', async t => {
  const f = await startHomeServer(); t.after(() => f.close());
  const user = browser(f); await user.login();
  const first = await user.rpc(pullCommitsOp, commitArgs);
  for (const [type, code] of [['FORBIDDEN', 'permission_denied'], ['RATE_LIMITED', 'rate_limit'], ['UNAUTHORIZED', 'authentication_required'], ['NOT_FOUND', 'not_found_or_not_installed']]) {
    f.state.graphqlErrors = [{ type }];
    assert.equal((await user.rpc(pullCommitsOp, commitArgs)).error?.code, code);
  }
  f.state.graphqlErrors = null;
  for (const [status, code] of [[403, 'permission_denied'], [404, 'not_found_or_not_installed'], [429, 'rate_limit'], [401, 'authentication_required']]) {
    f.state.restFailure = { status };
    const result = await user.rpc(pullCommitsOp, { ...commitArgs, cursor: first.value.next_cursor });
    assert.equal(result.error?.code, code, JSON.stringify(result));
  }
});

test('closing a tab during a response aborts its connection without stopping the server', async t => {
  const f = await startServer(); t.after(() => f.close());
  writeFileSync(`${f.root}/static/large.js`, Buffer.alloc(8 * 1024 * 1024, 32));
  for (let attempt = 0; attempt < 3; attempt++) {
    await new Promise((resolve, reject) => {
      const request = httpRequest(`${f.base}/large.js`, response => {
        response.once('data', () => { response.destroy(); resolve(); });
        response.on('error', () => {});
      });
      request.on('error', reject); request.end();
    });
    assert.equal(await (await fetch(`${f.base}/healthz`)).text(), 'ok\n', f.output);
  }
});
