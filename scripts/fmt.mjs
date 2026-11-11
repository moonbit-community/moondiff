import { spawnSync } from 'node:child_process';
import { resolve } from 'node:path';

const repository = resolve(import.meta.dirname, '..');
// Workspace formatting currently drops moon.work comments. Format each module
// independently so the published-dependency policy and local test example survive.
for (const directory of ['.', 'review-web/protocol', 'review-web/frontend', 'review-web/backend']) {
  const result = spawnSync('moon', ['-C', directory, 'fmt', ...process.argv.slice(2)], {
    cwd: repository,
    env: { ...process.env, MOON_WORK: 'off' },
    stdio: 'inherit',
  });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}
