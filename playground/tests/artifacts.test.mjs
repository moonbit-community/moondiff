import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import { gzipSync } from 'node:zlib';
import { repository, startServer, browser } from '../backend/tests/server-fixture.mjs';
const dist = join(repository, 'playground/dist');

test('release contains a Wasm module and self-contained root assets runnable with moonrun', async t => {
  assert(existsSync(dist), 'Build the release with npm run build before checking artifacts.');
  assert.deepEqual(readdirSync(dist).sort(), ['moondiff-server.wasm', 'static']);
  const wasmPath = join(dist, 'moondiff-server.wasm');
  assert.deepEqual([...readFileSync(wasmPath).subarray(0, 8)], [0, 97, 115, 109, 1, 0, 0, 0]);
  const staticDir = join(dist, 'static');
  const html = readFileSync(join(staticDir, 'index.html'), 'utf8');
  for (const [, asset] of html.matchAll(/(?:href|src)="(\/[^"#]+)"/g)) assert(existsSync(join(staticDir, asset)), `Missing ${asset}`);
  assert(!existsSync(join(repository, 'playground/server.mjs')));
  assert(!existsSync(join(repository, '.github/workflows/pages.yml')));
  const client = readFileSync(join(staticDir, 'index.js'), 'utf8');
  const clientBytes = Buffer.byteLength(client);
  const gzipBytes = gzipSync(client, { level: 5 }).length;
  t.diagnostic(`Frontend JS: ${clientBytes} bytes, ${gzipBytes} bytes gzip level 5`);
  assert(clientBytes <= 2_500_000, `Release JS exceeds the 2.5 MB budget: ${clientBytes} bytes`);
  assert(gzipBytes <= 500_000, `Release JS exceeds the 500 KB gzip budget: ${gzipBytes} bytes`);
  // These hooks are injected by render-probe.mjs; the optional metrics sink is part of the app.
  for (const probe of ['__moondiffPendingPaints', '__moondiffFrameBarrier', '__moondiffProbeRegion']) {
    assert(!client.includes(probe), `Test probe leaked into release JS: ${probe}`);
  }
  assert(!client.includes('chrome.runtime') && !client.includes('__moondiffExtensionHost'));
  assert(client.includes('https://api.github.com'));
  assert(!existsSync(join(staticDir, 'http-client.js')));
  assert(!client.includes('MoondiffHttp') && !client.includes('client_secret'));
  assert(client.includes('/api/rpc') && client.includes('/api/auth/session') && client.includes('/api/auth/device/poll'));
  const f = await startServer(undefined, { wasmPath, staticDir }); t.after(() => f.close());
  for (const path of ['/healthz', '/', '/alice/repo/pull/42', '/alice/repo/pull/42/commits/123abcd', '/index.js']) assert.equal((await fetch(f.base + path)).status, 200, path);
  for (const path of ['/unknown', '/auth/login', '/auth/callback']) assert.equal((await fetch(f.base + path)).status, 404);
  const user = browser(f); assert.equal((await user.login()).user_id, '1');
  await f.stop(); await f.start(); assert.equal((await user.status()).authenticated, true);
});
