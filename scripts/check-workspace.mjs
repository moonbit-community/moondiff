import { spawnSync } from 'node:child_process';
import { realpathSync } from 'node:fs';
import { isAbsolute, join, relative, resolve, sep } from 'node:path';

const repository = realpathSync(resolve(import.meta.dirname, '..'));
const reviewWeb = join(repository, 'review-web');
// Inspect the repository's workspace even when the caller overrides MOON_WORK.
const tree = spawnSync('moon', ['tree', '--json'], {
  cwd: join(reviewWeb, 'frontend'),
  env: { ...process.env, MOON_WORK: join(reviewWeb, 'moon.work') },
  encoding: 'utf8',
});
if (tree.error) throw tree.error;
if (tree.status !== 0) {
  process.stderr.write(tree.stderr || tree.stdout);
  process.exit(tree.status ?? 1);
}

const { modules } = JSON.parse(tree.stdout);
for (const member of modules.filter(module => module.workspace_member)) {
  const path = relative(reviewWeb, member.source.path);
  if (isAbsolute(path) || path === '..' || path.startsWith(`..${sep}`)) {
    throw new Error(`Workspace member ${member.name} is outside review-web. Restore moon.work before committing; local moondiff is allowed only for temporary integration tests.`);
  }
}
const moondiff = modules.find(module => module.name === 'moonbit-community/moondiff');
if (!moondiff || moondiff.workspace_member || moondiff.source.kind !== 'registry') {
  throw new Error('review-web must resolve moondiff from a published registry version. Restore moon.work before committing.');
}
console.log(`Workspace check passed: review-web uses published moondiff@${moondiff.version}.`);
