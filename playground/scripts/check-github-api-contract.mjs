import { appendFileSync } from 'node:fs';

const origin = 'https://moondiff.example';
const base = 'https://api.github.com';
const repository = '/repos/moonbitlang/core';

class Indeterminate extends Error {}

function check(condition, message) {
  if (!condition) throw new Error(message);
}

async function request(path, { source = false } = {}) {
  const response = await fetch(base + path, {
    method: 'GET',
    headers: {
      Origin: origin,
      Accept: source ? 'application/vnd.github.raw+json' : 'application/vnd.github+json',
    },
    redirect: 'manual',
    signal: AbortSignal.timeout(15_000),
  });
  const bytes = Buffer.from(await response.arrayBuffer());
  const message = (() => {
    try { return JSON.parse(bytes.toString()).message || ''; } catch { return ''; }
  })();
  if (response.status === 429 ||
    (response.status === 403 && (
      response.headers.get('x-ratelimit-remaining') === '0' ||
      response.headers.has('retry-after') || /rate limit/i.test(message)
    ))) {
    throw new Indeterminate(`GitHub rate limit on ${path} (HTTP ${response.status})`);
  }
  check(response.ok, `${path}: HTTP ${response.status} ${message}`);
  const allowed = response.headers.get('access-control-allow-origin');
  check(allowed === '*' || allowed === origin, `${path}: CORS origin is unavailable`);
  const exposed = response.headers.get('access-control-expose-headers') || '';
  check(exposed.toLowerCase().includes('x-ratelimit-remaining'), `${path}: rate-limit header is not exposed to browsers`);
  if (source) {
    check(bytes.length > 0 && bytes.length <= 1_048_576, `${path}: source size is invalid`);
    return bytes;
  }
  check(bytes.length <= 8_388_608, `${path}: JSON exceeds 8 MiB`);
  try { return JSON.parse(bytes.toString()); }
  catch { throw new Error(`${path}: invalid JSON`); }
}

function shape(value, fields, label) {
  check(value && typeof value === 'object' && !Array.isArray(value), `${label}: expected an object`);
  for (const [field, type] of Object.entries(fields)) {
    check(typeof value[field] === type, `${label}: missing ${field} (${type})`);
  }
}

async function checkGithubApiContract() {
  const commit = await request(`${repository}/commits/main?per_page=100&page=1`);
  shape(commit, { sha: 'string', html_url: 'string' }, 'commit');
  shape(commit.commit, { message: 'string' }, 'commit.commit');
  check(Array.isArray(commit.parents) && Array.isArray(commit.files), 'commit: missing arrays');
  const sha = commit.sha;
  check(/^[a-f\d]{40,64}$/i.test(sha), 'commit: invalid SHA');

  const pulls = await request(`${repository}/pulls?state=all&per_page=1`);
  check(Array.isArray(pulls) && pulls.length > 0, 'pull list is empty');
  const number = pulls[0].number;
  check(Number.isInteger(number) && number > 0, 'pull number is invalid');
  const pull = await request(`${repository}/pulls/${number}`);
  shape(pull, { title: 'string', html_url: 'string', changed_files: 'number' }, 'pull');
  shape(pull.base, { sha: 'string' }, 'pull.base');
  shape(pull.head, { sha: 'string' }, 'pull.head');

  const compare = await request(`${repository}/compare/${sha}...${sha}`);
  shape(compare.merge_base_commit, { sha: 'string' }, 'compare.merge_base_commit');

  const files = await request(`${repository}/pulls/${number}/files?per_page=100&page=1`);
  check(Array.isArray(files), 'pull files: expected an array');
  if (files.length) shape(files[0], { filename: 'string', status: 'string' }, 'pull file');

  const source = await request(`${repository}/contents/README.md?ref=${sha}`, { source: true });
  let sourceMetadata;
  try { sourceMetadata = JSON.parse(source.toString('utf8')); } catch {}
  check(!(sourceMetadata && typeof sourceMetadata === 'object' &&
    'encoding' in sourceMetadata && 'content' in sourceMetadata),
  'source: GitHub returned content metadata instead of raw bytes');

  for (const [label, path] of [
    ['issue comments', `${repository}/issues/${number}/comments?per_page=100&page=1`],
    ['review comments', `${repository}/pulls/${number}/comments?per_page=100&page=1`],
    ['commit comments', `${repository}/commits/${sha}/comments?per_page=100&page=1`],
  ]) {
    const comments = await request(path);
    check(Array.isArray(comments), `${label}: expected an array`);
    if (comments.length) shape(comments[0], { id: 'number', body: 'string', html_url: 'string', created_at: 'string' }, label);
  }
}

let result;
try {
  await checkGithubApiContract();
  result = 'PASS: public GitHub REST data shapes and CORS are compatible without an API version header.';
} catch (error) {
  if (error instanceof Indeterminate) {
    result = `INDETERMINATE: ${error.message}`;
    console.warn(`::warning::${result}`);
  } else {
    result = `FAIL: ${error.message}`;
    process.exitCode = 1;
  }
}
console.log(result);
if (process.env.GITHUB_STEP_SUMMARY) {
  appendFileSync(process.env.GITHUB_STEP_SUMMARY, `## Public GitHub contract check\n\n${result}\n`);
}
