// Test-only adapters between GitHub-shaped fixture data and the v2 wire schema.
const operations = {
  'github.commit.get': ['CommitGet', 'Commit'],
  'github.pull.viewed.get': ['PullViewedGet', 'PullViewed'],
  'github.pull.file.viewed.set': ['PullFileViewedSet', 'FileViewed'],
  'github.pull.get': ['PullGet', 'Pull'],
  'github.compare.get': ['CompareGet', 'Compare'],
  'github.pull.files': ['PullFiles', 'Files'],
  'github.content.get': ['ContentGet', 'Content'],
  'github.comments.list': ['CommentsList', 'Comments'],
  'github.issue.comment.create': ['IssueCommentCreate', 'IssueComment'],
  'github.review.comment.create': ['ReviewCommentCreate', 'ReviewComment'],
  'github.commit.comment.create': ['CommitCommentCreate', 'CommitComment'],
  'github.review.reply.create': ['ReviewReplyCreate', 'ReviewComment'],
  'github.issue.comment.delete': ['IssueCommentDelete', 'Deleted'],
  'github.review.comment.delete': ['ReviewCommentDelete', 'Deleted'],
  'github.commit.comment.delete': ['CommitCommentDelete', 'Deleted'],
};
const tagged = (name, value) => ({ $tag: name, '0': value });
const enumCase = name => ({ $tag: name[0].toUpperCase() + name.slice(1).toLowerCase() });
export function rpcRequest(op, args) {
  const p = { ...args };
  if (op === 'github.content.get') { p.revision = p.ref; delete p.ref; }
  if (op === 'github.comments.list') {
    p.target = p.kind === 'pull' ? { $tag: 'Pull', number: p.number } : p.kind === 'pull_commit' ? { $tag: 'PullCommit', number: p.number, sha: p.sha } : { $tag: 'Commit', sha: p.sha };
    delete p.kind; delete p.number; delete p.sha;
  }
  if (op === 'github.review.comment.create') p.side = enumCase(p.side);
  return { v: 2, request: tagged(operations[op]?.[0] || op, p) };
}
export function fixtureRequest(envelope) {
  if (envelope.v !== 2) throw new Error('Expected v2 request');
  const op = Object.keys(operations).find(op => operations[op][0] === envelope.request.$tag);
  if (!op) throw new Error('Unknown request');
  const args = { ...envelope.request['0'] };
  if (op === 'github.content.get') { args.ref = args.revision; delete args.revision; }
  if (op === 'github.comments.list') {
    const { $tag, ...target } = args.target;
    args.kind = { Commit: 'commit', Pull: 'pull', PullCommit: 'pull_commit' }[$tag];
    Object.assign(args, target); delete args.target;
  }
  if (op === 'github.review.comment.create') args.side = args.side.$tag.toUpperCase();
  return { op, args };
}
const pick = (value, keys) => Object.fromEntries(keys.split(' ').filter(k => value[k] != null).map(k => [k, value[k]]));
const file = v => pick(v, 'filename previous_filename status additions deletions changes patch');
const comment = (v, kind) => {
  const value = pick(v, 'id body html_url created_at user ' + (kind === 'IssueComment' ? '' : kind === 'ReviewComment' ? 'path line original_line side position commit_id in_reply_to_id' : 'path position line'));
  value.id = String(value.id);
  if (value.in_reply_to_id != null) value.in_reply_to_id = String(value.in_reply_to_id);
  if (value.user) value.user = pick(value.user, 'login');
  if (value.side) value.side = typeof value.side === 'string' ? enumCase(value.side) : value.side;
  return value;
};
export function modeledValue(kind, value) {
  switch (kind) {
    case 'Commit': return { ...pick(value, 'sha html_url'), commit: pick(value.commit, 'message'), parents: value.parents.map(v => pick(v, 'sha')), stats: pick(value.stats, 'additions deletions total'), files: value.files.map(file) };
    case 'Pull': return { ...pick(value, 'title html_url additions deletions changed_files'), ...Object.fromEntries(['base', 'head'].map(k => [k, { sha: value[k].sha, ...(value[k].repo ? { repo: pick(value[k].repo, 'full_name') } : {}) }])) };
    case 'Compare': return { merge_base_commit: pick(value.merge_base_commit, 'sha') };
    case 'Files': return value.map(file);
    case 'Content': return { base64: value.base64, size: value.size, content_type: value.content_type || value.contentType || 'application/octet-stream' };
    case 'Comments': return { issue_comments: value.issue_comments.map(v => comment(v, 'IssueComment')), review_comments: value.review_comments.map(v => comment(v, 'ReviewComment')), commit_comments: value.commit_comments.map(v => comment(v, 'CommitComment')) };
    case 'IssueComment': case 'ReviewComment': case 'CommitComment': return comment(value, kind);
    case 'PullViewed': case 'FileViewed': return value;
    case 'Deleted': return pick(value, 'deleted');
    default: throw new Error(`Unknown result ${kind}`);
  }
}
export function authValue(value) {
  const status = pick(value, 'authenticated csrf_token login user_id install_url device_flow');
  if (status.device_flow) status.device_flow = { ...status.device_flow, phase: enumCase(status.device_flow.phase) };
  return status;
}
export function successFixture(op, value) {
  if (op === 'auth.logout') value = null;
  else if (op === 'auth.status') value = authValue(value);
  else if (op.startsWith('auth.device.')) value = { request_id: value.attempt_id || value.authorization_id, status: authValue(value) };
  else { const kind = operations[op][1]; value = tagged(kind, modeledValue(kind, value)); }
  return { $tag: 'Success', value };
}
// Keep assertions about device phases readable while checking the wire wrapper.
export function readStatus(value) {
  return { ...value, ...(value.device_flow ? { device_flow: { ...value.device_flow, phase: value.device_flow.phase.$tag.toLowerCase() } } : {}) };
}
export function readResponse(response, device = false) {
  if (!['Success', 'Failure'].includes(response.$tag)) throw new Error('Invalid response wrapper');
  if (response.$tag === 'Failure') return { ok: false, error: response.error };
  if (device) return { ok: true, value: readStatus(response.value.status), request_id: response.value.request_id };
  return { ok: true, value: response.value['0'] };
}
