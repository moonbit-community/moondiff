import { rpcRequest, readResponse, readStatus } from '../../tests/protocol-fixtures.mjs';
import { spawn, spawnSync } from 'node:child_process';
import { createServer } from 'node:http';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, symlinkSync } from 'node:fs';
import { once } from 'node:events';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import { randomBytes } from 'node:crypto';

export const repository = resolve(import.meta.dirname, '../../..');
export const serverWasm = join(repository, '_build/wasm/release/build/moonbit-community/moondiff-playground-server/main/main.wasm');
export function buildServer() {
  const result = spawnSync('moon', ['build', 'playground/backend/main', '--target', 'wasm', '--release'], { cwd: repository, encoding: 'utf8' });
  if (result.status !== 0) throw new Error(result.stdout + result.stderr);
}
export async function startServer(handler, options = {}) {
  const root = mkdtempSync(join(tmpdir(), 'moondiff-server-'));
  const staticDir = options.staticDir || join(root, 'static');
  if (!options.staticDir) mkdirSync(staticDir);
  if (!options.staticDir) writeFileSync(join(staticDir, 'index.html'), '<!doctype html><title>fixture</title>');
  if (!options.staticDir) writeFileSync(join(staticDir, 'styles.css'), 'body { color: navy; }');
  writeFileSync(join(root, 'outside.txt'), 'secret');
  if (!options.staticDir) symlinkSync(join(root, 'outside.txt'), join(staticDir, 'escape'));
  const requests = [];
  const devices = new Map();
  function approve(userCode, who = 'alice') {
    const entry = [...devices.values()].find(entry => entry.user_code === userCode);
    if (!entry) throw new Error('Unknown verification code');
    entry.who = who;
  }
  const stub = createServer(async (req, res) => {
    try {
      const chunks = [];
      for await (const chunk of req) chunks.push(chunk);
      const text = Buffer.concat(chunks).toString();
      const record = { path: req.url, method: req.method, headers: req.headers, body: text ? JSON.parse(text) : undefined };
      requests.push(record);
      res.setHeader('content-type', 'application/json');
      if (await handler?.(record, res, requests)) return;
      if (req.url === '/login/device/code') {
        const device_code = randomBytes(20).toString('hex');
        const user_code = randomBytes(4).toString('hex').toUpperCase().replace(/(.{4})(.{4})/, '$1-$2');
        devices.set(device_code, { user_code });
        res.end(JSON.stringify({ device_code, user_code, verification_uri: `http://127.0.0.1:${stub.address().port}/login/device`, expires_in: 900, interval: 1 }));
      } else if (req.url === '/login/device') {
        res.setHeader('content-type', 'text/html');
        res.end('<!doctype html><title>GitHub device verification</title><form action="/device/approve"><label>Verification code <input name="user_code" required></label><button>Authorize device</button></form>');
      } else if (req.url.startsWith('/device/approve?')) {
        approve(new URL(req.url, 'http://localhost').searchParams.get('user_code'));
        res.setHeader('content-type', 'text/html'); res.end('<!doctype html><title>Authorized</title><p>Device authorized. Return to Moondiff.</p>');
      } else if (req.url === '/login/oauth/access_token') {
        const who = record.body.refresh_token?.replace('refresh-', '') || devices.get(record.body.device_code)?.who;
        if (!who) { res.end(JSON.stringify({ error: 'authorization_pending' })); return; }
        res.end(JSON.stringify({ access_token: `access-${who}`, refresh_token: `refresh-${who}`, expires_in: 3600, refresh_token_expires_in: 100000 }));
      } else if (req.url === '/user') {
        const who = req.headers.authorization?.replace('Bearer access-', '') || 'alice';
        res.end(JSON.stringify({ id: who === 'bob' ? 2 : 1, login: who }));
       } else { res.end(JSON.stringify({ sha: '123abcd', html_url: 'https://github.com/alice/repo/commit/123abcd', commit: {message: 'fixture'}, parents: [], stats: {additions: 0, deletions: 0, total: 0}, files: [] })); }
    } catch (error) { res.statusCode = 500; res.end(JSON.stringify({ error: String(error) })); }
  });
  stub.listen(0, '127.0.0.1');
  await once(stub, 'listening');
  const placeholder = createServer();
  placeholder.listen(0, '127.0.0.1');
  await once(placeholder, 'listening');
  const port = options.port || placeholder.address().port;
  await new Promise(r => placeholder.close(r));
  const base = `http://127.0.0.1:${port}`;
  const stubURL = `http://127.0.0.1:${stub.address().port}`;
  const database = join(root, 'sessions.db');
  const env = { ...process.env, MOONDIFF_LISTEN: `127.0.0.1:${port}`, MOONDIFF_PUBLIC_URL: base, MOONDIFF_STATIC_DIR: staticDir, MOONDIFF_DATABASE: database, MOONDIFF_TOKEN_KEY: randomBytes(64).toString('base64'), MOONDIFF_GITHUB_CLIENT_ID: 'test-client', MOONDIFF_GITHUB_INSTALL_URL: 'https://github.com/apps/test/installations/new', MOONDIFF_TEST_MODE: '1', MOONDIFF_TEST_GITHUB_URL: stubURL, MOONDIFF_TEST_OAUTH_URL: stubURL, ...options.env };
  delete env.MOONDIFF_GITHUB_CLIENT_SECRET;
  let child;
  let output = '';
  async function stop() {
    if (!child?.pid || child.exitCode !== null || child.signalCode !== null) return;
    child.kill('SIGTERM');
    await once(child, 'exit');
  }
  async function start(overrides = {}) {
    const runtime = process.env.MOONRUN_OVERRIDE || 'moonrun';
    child = spawn(runtime, [options.wasmPath || serverWasm], { cwd: root, env: { ...env, ...overrides }, stdio: ['ignore', 'pipe', 'pipe'] });
    let spawnError;
    child.on('error', error => { spawnError = error; });
    output = '';
    child.stdout.on('data', b => { output += b; });
    child.stderr.on('data', b => { output += b; });
    for (let i = 0; i < 200; i++) {
      if (spawnError) throw new Error(`Could not start ${runtime}: ${spawnError.message}`);
      if (child.exitCode !== null || child.signalCode !== null) throw new Error(`Wasm server exited: ${output}`);
      try { if ((await fetch(base + '/healthz', { signal: AbortSignal.timeout(200) })).ok) return; } catch {}
      await new Promise(r => setTimeout(r, 25));
    }
    throw new Error(`Wasm server did not start: ${output}`);
  }
  try { await start(); } catch (error) { await stop(); stub.closeAllConnections(); stub.close(); rmSync(root, { recursive: true, force: true }); throw error; }
  return {
    root, base, port, env, database, requests, devices, approve, get output() { return output; }, start, stop,
    sql(sql, params = []) {
      const result = spawnSync('python3', ['-c', 'import sqlite3,json,sys; db=sqlite3.connect(sys.argv[1]); rows=db.execute(sys.argv[2],json.loads(sys.argv[3])).fetchall(); db.commit(); print(json.dumps(rows))', database, sql, JSON.stringify(params)], { encoding: 'utf8' });
      if (result.status !== 0) throw new Error(result.stderr);
      return JSON.parse(result.stdout);
    },
    async close() { await stop(); stub.closeAllConnections(); await new Promise(r => stub.close(r)); rmSync(root, { recursive: true, force: true }); },
  };
}

export function browser(fixture) {
  let cookie = '';
  let csrf = '';
  return {
    get cookie() { return cookie; },
    get csrf() { return csrf; },
    async request(path, options = {}) {
      const res = await fetch(fixture.base + path, { redirect: 'manual', ...options, headers: { Cookie: cookie, ...options.headers } });
      if (res.headers.get('set-cookie')) cookie = res.headers.get('set-cookie').split(';')[0];
      return res;
    },
    async status() {
      const res = await this.request('/api/auth/status');
      const result = await res.json();
      if (result.$tag !== 'Success') throw new Error(JSON.stringify(result));
      csrf = result.value.csrf_token;
      return readStatus(result.value);
    },
    async device(action, body, headers = {}) {
      const res = await this.request(`/api/auth/device/${action}`, { method: 'POST', headers: { 'Content-Type': 'application/json', Origin: fixture.base, 'X-CSRF-Token': csrf, ...headers }, body: JSON.stringify(body) });
      return readResponse(await res.json(), true);
    },
    async begin(attempt = randomBytes(24).toString('base64url')) {
      if (!csrf) await this.status();
      const result = await this.device('start', { attempt_id: attempt });
      if (!result.ok) throw new Error(JSON.stringify(result));
      return result.value.device_flow;
    },
    async poll(flow, ready = false) {
      if (ready) fixture.sql('UPDATE authorizations SET next_poll=0 WHERE id=?', [flow.id]);
      return this.device('poll', { authorization_id: flow.id });
    },
    async cancel(flow) { return this.device('cancel', { authorization_id: flow.id }); },
    async login(who = 'alice') {
      const flow = await this.begin();
      fixture.approve(flow.user_code, who);
      const result = await this.poll(flow, true);
      if (!result.ok || !result.value.authenticated) throw new Error(JSON.stringify(result));
      return this.status();
    },
    async logout(headers = {}) { return this.request('/api/auth/logout', { method: 'POST', headers: { Origin: fixture.base, 'X-CSRF-Token': csrf, ...headers } }); },
    async rpc(op, args, headers = {}) {
      const res = await this.request('/api/rpc', { method: 'POST', headers: { 'Content-Type': 'application/json', Origin: fixture.base, 'X-CSRF-Token': csrf, ...headers }, body: JSON.stringify(rpcRequest(op, args)) });
      return readResponse(await res.json());
    },
  };
}
