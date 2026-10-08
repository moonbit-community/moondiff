import { spawnSync } from 'node:child_process';
import { copyFileSync, mkdtempSync, readFileSync, renameSync, rmSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { gzipSync } from 'node:zlib';
import { minifyFrontend } from './minify.mjs';
import { writeStaticAssets } from './static-assets.mjs';
const playground = resolve(import.meta.dirname, '..');
const repository = resolve(playground, '..');
const target = mkdtempSync(join(tmpdir(), 'moondiff-release-'));
const staging = mkdtempSync(join(playground, '.dist-'));
try {
  for (const [backend, pkg] of [['js', 'playground/frontend/main'], ['wasm', 'playground/backend/main']]) {
    const build = spawnSync('moon', ['build', pkg, '--target', backend, '--release', '--target-dir', target], { cwd: repository, stdio: 'inherit' });
    if (build.error) throw build.error;
    if (build.status !== 0) throw new Error(`MoonBit ${backend} build failed (${build.status}).`);
  }
  const source = readFileSync(join(target, 'js/release/build/moonbit-community/moondiff-playground/main/main.js'), 'utf8');
  const client = minifyFrontend(source);
  writeStaticAssets(join(playground, 'frontend/public'), join(staging, 'static'), client);
  copyFileSync(join(target, 'wasm/release/build/moonbit-community/moondiff-playground-server/main/main.wasm'), join(staging, 'moondiff-server.wasm'));
  rmSync(join(playground, 'dist'), { recursive: true, force: true });
  renameSync(staging, join(playground, 'dist'));
  console.log(`Frontend JS: ${Buffer.byteLength(source)} bytes -> ${Buffer.byteLength(client)} bytes minified (${gzipSync(client, { level: 5 }).length} bytes gzip level 5)`);
  console.log(`Built ${join(playground, 'dist')} (Wasm module and static assets; run with moonrun)`);
} finally {
  rmSync(target, { recursive: true, force: true });
  rmSync(staging, { recursive: true, force: true });
}
