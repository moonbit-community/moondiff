import { createHash } from 'node:crypto';
import { cpSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

// Hash the final bytes so a URL changes exactly when its content changes.
export function writeStaticAssets(publicDir, staticDir, client) {
  cpSync(publicDir, staticDir, { recursive: true });
  let html = readFileSync(join(staticDir, 'index.html'), 'utf8');
  for (const [name, extension, content] of [
    ['index', 'js', client],
    ['styles', 'css', readFileSync(join(staticDir, 'styles.css'))],
  ]) {
    const hash = createHash('sha256').update(content).digest('hex');
    const original = `${name}.${extension}`;
    const versioned = `${name}.${hash}.${extension}`;
    const reference = `"/${original}"`;
    if (!html.includes(reference)) throw new Error(`Missing ${original} reference in index.html.`);
    writeFileSync(join(staticDir, versioned), content);
    html = html.replaceAll(reference, `"/${versioned}"`);
    rmSync(join(staticDir, original), { force: true });
  }
  writeFileSync(join(staticDir, 'index.html'), html);
}
