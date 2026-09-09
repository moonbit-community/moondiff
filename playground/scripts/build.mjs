import { spawnSync } from 'node:child_process';
import { cpSync, copyFileSync, mkdtempSync, mkdirSync, renameSync, rmSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
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
  mkdirSync(join(staging, 'static'));
  cpSync(join(playground, 'frontend/public'), join(staging, 'static'), { recursive: true });
  copyFileSync(join(target, 'js/release/build/moonbit-community/moondiff-playground/main/main.js'), join(staging, 'static/index.js'));
  copyFileSync(join(target, 'wasm/release/build/moonbit-community/moondiff-playground-server/main/main.wasm'), join(staging, 'moondiff-server.wasm'));
  rmSync(join(playground, 'dist'), { recursive: true, force: true });
  renameSync(staging, join(playground, 'dist'));
  console.log(`Built ${join(playground, 'dist')} (Wasm module and static assets; run with moonrun)`);
} finally {
  rmSync(target, { recursive: true, force: true });
  rmSync(staging, { recursive: true, force: true });
}
