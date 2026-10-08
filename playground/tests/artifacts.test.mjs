import assert from 'node:assert/strict';
import { cpSync, existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import test from 'node:test';
import { gzipSync } from 'node:zlib';
import { createHash } from 'node:crypto';
import { repository, startServer, browser } from '../backend/tests/server-fixture.mjs';
import { writeStaticAssets } from '../scripts/static-assets.mjs';
const dist = join(repository, 'playground/dist');

test('asset URLs are stable for identical content and change independently with JS or CSS', t => {
  const root = mkdtempSync(join(tmpdir(), 'moondiff-asset-build-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const publicDir = join(root, 'public');
  cpSync(join(repository, 'playground/frontend/public'), publicDir, { recursive: true });
  const build = (name, client) => {
    const output = join(root, name);
    writeStaticAssets(publicDir, output, client);
    const html = readFileSync(join(output, 'index.html'), 'utf8');
    const assets = [...html.matchAll(/(?:href|src)="(\/(?:index|styles)\.([0-9a-f]{64})\.(js|css))"/g)];
    assert.equal(assets.length, 2);
    for (const [, path, hash] of assets) {
      assert.equal(createHash('sha256').update(readFileSync(join(output, path))).digest('hex'), hash);
    }
    assert(!html.includes('"/index.js"') && !html.includes('"/styles.css"'));
    return { html, ...Object.fromEntries(assets.map(([, path, , type]) => [type, path])) };
  };
  const first = build('first', 'console.log("first");');
  assert.deepEqual(build('unchanged', 'console.log("first");'), first);
  const scriptChanged = build('script-changed', 'console.log("other");');
  assert.notEqual(scriptChanged.js, first.js);
  assert.notEqual(scriptChanged.html, first.html);
  assert.equal(scriptChanged.css, first.css);
  writeFileSync(join(publicDir, 'styles.css'), 'body { color: red; }');
  const styleChanged = build('style-changed', 'console.log("first");');
  assert.notEqual(styleChanged.css, first.css);
  assert.notEqual(styleChanged.html, first.html);
  assert.equal(styleChanged.js, first.js);
});

test('release contains a Wasm module and self-contained root assets runnable with moonrun', async t => {
  assert(existsSync(dist), 'Build the release with npm run build before checking artifacts.');
  assert.deepEqual(readdirSync(dist).sort(), ['moondiff-server.wasm', 'static']);
  const wasmPath = join(dist, 'moondiff-server.wasm');
  assert.deepEqual([...readFileSync(wasmPath).subarray(0, 8)], [0, 97, 115, 109, 1, 0, 0, 0]);
  const staticDir = join(dist, 'static');
  const html = readFileSync(join(staticDir, 'index.html'), 'utf8');
  for (const [, asset] of html.matchAll(/(?:href|src)="(\/[^"#]+)"/g)) assert(existsSync(join(staticDir, asset)), `Missing ${asset}`);
  const assets = [...html.matchAll(/(?:href|src)="(\/((?:index|styles)\.([0-9a-f]{64})\.(?:js|css)))"/g)];
  assert.equal(assets.length, 2, 'JS and CSS must have content-hashed URLs.');
  for (const [, , file, hash] of assets) {
    assert.equal(createHash('sha256').update(readFileSync(join(staticDir, file))).digest('hex'), hash);
  }
  assert(!existsSync(join(staticDir, 'index.js')));
  assert(!existsSync(join(staticDir, 'styles.css')));
  assert(!existsSync(join(repository, 'playground/server.mjs')));
  assert(!existsSync(join(repository, '.github/workflows/pages.yml')));
  const client = readFileSync(join(staticDir, assets.find(([, path]) => path.endsWith('.js'))[1]), 'utf8');
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
  for (const path of ['/healthz', '/', '/alice/repo/pull/42', '/alice/repo/pull/42/commits/123abcd']) assert.equal((await fetch(f.base + path)).status, 200, path);
  for (const [, path] of assets) {
    const response = await fetch(f.base + path);
    assert.equal(response.status, 200, path);
    assert.equal(response.headers.get('cache-control'), 'public, max-age=31536000, immutable');
    assert.deepEqual(Buffer.from(await response.arrayBuffer()), readFileSync(join(staticDir, path)));
  }
  for (const path of ['/unknown', '/auth/login', '/auth/callback']) assert.equal((await fetch(f.base + path)).status, 404);
  const user = browser(f); assert.equal((await user.login()).user_id, '1');
  await f.stop(); await f.start(); assert.equal((await user.status()).authenticated, true);
});
