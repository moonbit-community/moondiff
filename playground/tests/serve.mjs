import { cpSync, copyFileSync, mkdtempSync, rmSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { buildServer, startServer, repository } from '../backend/tests/server-fixture.mjs';
const assets = mkdtempSync(join(tmpdir(), 'moondiff-e2e-assets-'));
buildServer();
const build = spawnSync('moon', ['build', 'playground/frontend/main', '--target', 'js', '--release'], { cwd: repository, stdio: 'inherit' });
if (build.status !== 0) process.exit(build.status || 1);
cpSync(join(repository, 'playground/frontend/public'), assets, { recursive: true });
copyFileSync(join(repository, '_build/js/release/build/moonbit-community/moondiff-playground/main/main.js'), join(assets, 'index.js'));
const fixture = await startServer((request, response) => {
  if (request.path.startsWith('/repos/fixture/repo/')) {
    const path = new URL(request.path, 'http://localhost').pathname;
    if (path.endsWith('/comments')) response.end('[]');
    else if (path.includes('/contents/')) response.end('pub fn hello() { 42 }\n');
    else {
      const sha = path.split('/').at(-1);
      response.end(JSON.stringify({ sha, html_url: `https://github.com/fixture/repo/commit/${sha}`, commit: { message: 'Fixture root commit' }, parents: [], stats: { additions: 1, deletions: 0, total: 1 }, files: [{ filename: 'hello.mbt', status: 'added', additions: 1, deletions: 0, changes: 1, patch: '@@ -0,0 +1 @@\n+pub fn hello() { 42 }' }] }));
    }
    return true;
  }
}, { staticDir: assets, port: Number(process.env.PORT || 4173) });
async function shutdown() { await fixture.close(); rmSync(assets, { recursive: true, force: true }); process.exit(0); }
for (const signal of ['SIGTERM', 'SIGINT', 'SIGHUP']) process.on(signal, shutdown);
console.log(`Playground Wasm E2E server: ${fixture.base}`);
