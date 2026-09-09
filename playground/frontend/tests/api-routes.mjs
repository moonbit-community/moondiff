import { fixtureRequest, successFixture } from '../../tests/protocol-fixtures.mjs';
// Reuse GitHub fixtures through the public same-origin RPC contract.
export function fixtureURL({ request }) {
  const a = request['0'];
  const base = `https://api.github.com/repos/${a.owner}/${a.repo}`;
  switch (request.$tag) {
    case 'CommitGet': return `${base}/commits/${a.sha}?per_page=100&page=${a.page}`;
    case 'PullGet': return `${base}/pulls/${a.number}`;
    case 'CompareGet': return `${base}/compare/${a.base}...${a.head}`;
    case 'PullFiles': return `${base}/pulls/${a.number}/files?per_page=100&page=${a.page}`;
    case 'ContentGet': return `https://raw.githubusercontent.com/${a.owner}/${a.repo}/${a.revision}/${a.path.split('/').map(encodeURIComponent).join('/')}`;
    default: return '';
  }
}
function normalize(value) {
  if (Array.isArray(value)) return value.map(normalize);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).filter(([,v]) => v !== null).map(([k,v]) => [k, normalize(v)]));
  return value;
}
export async function routeGithub(page, kind, handler, options) {
  let remaining = options?.times ?? Infinity;
  await page.route('**/api/rpc', async route => {
    const message = fixtureRequest(route.request().postDataJSON());
    const url = fixtureURL(route.request().postDataJSON());
    const matches = kind === 'content' ? message.op === 'github.content.get' : Boolean(url) && message.op !== 'github.content.get';
    if (!matches || remaining-- <= 0) return route.fallback();
    await handler({
      request: () => ({ url: () => url, allHeaders: () => route.request().allHeaders() }),
      abort: (...args) => route.abort(...args),
      async fulfill({ status = 200, contentType, body }) {
        let value;
        if (status >= 400) {
          let message = String(body || 'GitHub request failed');
          try { message = JSON.parse(message).message || message; } catch {}
          const code = status === 401 ? 'authentication_required' : status === 404 ? 'not_found_or_not_installed' : `github_http_${status}`;
          return route.fulfill({ status, json: { $tag: 'Failure', error: { status, code, message } } });
        }
        if (kind === 'content') { const bytes = Buffer.from(body || ''); value = { base64: bytes.toString('base64'), size: bytes.length, contentType }; }
        else value = normalize(JSON.parse(body));
        await route.fulfill({ status: 200, json: successFixture(message.op, value) });
      },
    });
  });
}
export async function anonymousApi(page) {
  await page.route('**/api/auth/status', route => route.fulfill({ json: { $tag: 'Success', value: { authenticated: false, csrf_token: 'fixture', install_url: 'https://github.com/apps/test/installations/new' } } }));
  await page.route('**/api/rpc', route => {
    const { op } = fixtureRequest(route.request().postDataJSON());
    if (op === 'github.comments.list') return route.fulfill({ json: successFixture(op, { issue_comments: [], review_comments: [], commit_comments: [] }) });
    return route.fallback();
  });
}
