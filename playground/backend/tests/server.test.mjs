import { rpcRequest } from '../../tests/protocol-fixtures.mjs';
import assert from 'node:assert/strict';
import test, { before } from 'node:test';
import { randomBytes } from 'node:crypto';
import { request as httpRequest } from 'node:http';
import { buildServer, startServer, browser } from './server-fixture.mjs';

before(buildServer);

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
  for (const path of ['/', '/alice/repo/pull/42', '/alice/repo/commit/123abcd', '/alice/repo/pull/42/commits/123abcd']) {
    const res = await fetch(f.base + path); assert.equal(res.status, 200); assert.match(await res.text(), /fixture/);
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
  await bob.status();
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

test('CSRF, operation validation, anonymous reads and authenticated writes', async t => {
  const f = await startServer(); t.after(() => f.close());
  const user = browser(f); await user.status();
  assert((await user.rpc('github.commit.get', args)).ok);
  assert.equal((await user.rpc('github.issue.comment.create', { owner: 'alice', repo: 'repo', number: '1', body: 'hello' })).error.code, 'authentication_required');
  await user.login();
  assert.equal((await user.logout({ Origin: 'https://evil.example' })).status, 403);
  assert.equal((await user.logout({ 'X-CSRF-Token': 'wrong' })).status, 403);
  for (const path of ['/auth/login', '/auth/login?csrf=wrong', '/auth/callback']) assert.equal((await user.request(path)).status, 404);
  assert.equal((await user.rpc('github.fetch', args)).error.code, 'invalid_arguments');
  assert.equal((await user.rpc('github.commit.get', { ...args, url: 'http://evil' })).error.code, 'invalid_arguments');
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

test('production status issues a Secure HttpOnly host cookie and a 30-day opaque session', async t => {
  const f = await startServer(undefined, { env: { MOONDIFF_PUBLIC_URL: 'https://localhost' } }); t.after(() => f.close());
  const res = await fetch(f.base + '/api/auth/status');
  assert.match(res.headers.get('set-cookie'), /^__Host-moondiff=/);
  for (const flag of ['Secure', 'HttpOnly', 'SameSite=Lax', 'Path=/', 'Max-Age=2592000']) assert(res.headers.get('set-cookie').includes(flag));
  const [[expires]] = f.sql('SELECT expires FROM sessions');
  assert(Math.abs(expires - Date.now() / 1000 - 30 * 86400) < 5);
  assert.equal((await res.json()).value.authenticated, false);
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
  const user = browser(f); await user.status();
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
  const user = browser(f); await user.status();
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
  const user = browser(f); await user.status();
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
