import { fixtureRequest, successFixture } from '../../tests/protocol-fixtures.mjs';

export function syntheticFixture({ files = 5, declarations = 24 } = {}) {
  const sha = 'a'.repeat(40), base = 'b'.repeat(40), sources = {};
  const metadata = Array.from({ length: files }, (_, i) => {
    const filename = i === 0 ? 'local_test.mbt' : `src/unrelated-${i}.mbt`;
    const old = Array.from({ length: declarations }, (_, n) => `fn value_${n}() -> Int {\n  ${n}\n}\n`).join('\n');
    const next = Array.from({ length: declarations }, (_, n) => `fn value_${n}() -> Int {\n  ${n + 1}\n}\n`).join('\n');
    sources[`${base}:${filename}`] = old; sources[`${sha}:${filename}`] = next;
    const oldLines = old.split('\n'), newLines = next.split('\n');
    return { filename, status: 'modified', additions: newLines.length, deletions: oldLines.length, changes: newLines.length + oldLines.length,
      patch: `@@ -1,${oldLines.length} +1,${newLines.length} @@\n${oldLines.map(x => `-${x}`).join('\n')}\n${newLines.map(x => `+${x}`).join('\n')}` };
  });
  return { sha, base, message: 'Independent rendering fixture', files: metadata, sources };
}

export function gate() {
  let resolve; const promise = new Promise(r => { resolve = r; });
  return { promise, resolve };
}

export async function installRenderingFixture(page, fixture, options = {}) {
  const state = { fixture, authenticated: false, viewed: {}, contentGate: null, writeGate: null, calls: [], ...options };
  await page.route('**/api/**', async route => {
    if (new URL(route.request().url()).pathname === '/api/auth/status') {
      return route.fulfill({ json: successFixture('auth.status', { authenticated: state.authenticated, csrf_token: 'fixture',
        ...(state.authenticated ? { login: 'reviewer', user_id: '1' } : {}) }) });
    }
    const { op, args } = fixtureRequest(route.request().postDataJSON());
    state.calls.push({ op, args });
    const f = state.fixture;
    let value;
    switch (op) {
      case 'github.commit.get': value = { sha: args.sha, html_url: `https://github.com/example/regions/commit/${args.sha}`, commit: { message: f.message }, parents: [{ sha: f.base }], stats: { additions: 1, deletions: 1, total: 2 }, files: f.files }; break;
      case 'github.pull.get': value = { title: f.message, html_url: 'https://github.com/example/regions/pull/1', base: { sha: f.base, repo: { full_name: 'example/regions' } }, head: { sha: f.sha, repo: { full_name: 'example/regions' } }, additions: 1, deletions: 1, changed_files: f.files.length }; break;
      case 'github.compare.get': value = { merge_base_commit: { sha: f.base } }; break;
      case 'github.pull.files': value = f.files; break;
      case 'github.content.get': {
        const pending = state.contentGate;
        if (pending && args.path === pending.path && args.ref === f.sha) {
          state.contentGate = null;
          await pending.promise;
        }
        const text = f.sources[`${args.ref}:${args.path}`];
        if (text === undefined) throw new Error(`Missing fixture source ${args.ref}:${args.path}`);
        value = { base64: Buffer.from(text).toString('base64'), size: Buffer.byteLength(text) };
        break;
      }
      case 'github.comments.list': value = { issue_comments: [], review_comments: state.comments ?? [], commit_comments: [] }; break;
      case 'github.pull.viewed.get': value = { base_sha: f.base, head_sha: f.sha, files: f.files.map(file => ({ path: file.filename, state: { $tag: state.viewed[file.filename] ? 'Viewed' : 'Unviewed' } })) }; break;
      case 'github.pull.file.viewed.set': {
        const pending = state.writeGate; state.writeGate = null;
        if (pending) await pending.promise;
        state.viewed[args.path] = args.viewed;
        value = { base_sha: f.base, head_sha: f.sha, file: { path: args.path, state: { $tag: args.viewed ? 'Viewed' : 'Unviewed' } } };
        break;
      }
      default: throw new Error(`Unhandled rendering fixture RPC ${op}`);
    }
    await route.fulfill({ json: successFixture(op, value) }).catch(() => {});
  });
  return state;
}

export async function navigate(page, path) {
  await page.evaluate(path => { history.pushState(null, '', path); dispatchEvent(new PopStateEvent('popstate')); }, path);
}
