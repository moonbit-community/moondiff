import { cancelledRoute } from '../../tests/browser-control.mjs';
import { fixtureRequest, successFixture, metadataFallbackRoute } from '../../tests/protocol-fixtures.mjs';
import { createCommentBundlePairs } from '../../tests/comment-bundle-pairing.mjs';

const head = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const changedHead = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
const base = "1111111111111111111111111111111111111111";
const mergeBase = "2222222222222222222222222222222222222222";
const commitSha = "cccccccccccccccccccccccccccccccccccccccc";
const parentSha = "dddddddddddddddddddddddddddddddddddddddd";
const patch = "@@ -1,3 +1,3 @@\n context\n-old value\n+new value\n tail";

function pullTarget() {
  return { owner: "upstream", repo: "project", kind: "pull", number: "17" };
}

function commitTarget() {
  return { owner: "upstream", repo: "project", kind: "commit", sha: commitSha };
}

function pullCommitTarget() {
  return { owner: "upstream", repo: "project", kind: "pull_commit", number: "17", sha: commitSha };
}

function reviewPath(target = pullTarget()) {
  const root = `/${target.owner}/${target.repo}`;
  if (target.kind === "commit") return `${root}/commit/${target.sha}`;
  if (target.kind === "pull") return `${root}/pull/${target.number}`;
  return `${root}/pull/${target.number}/commits/${target.sha}`;
}

async function installApi(page, target = pullTarget(), options = {}) {
  await page.route('https://github.com/*.png?size=64', route => route.abort());
  const commentPairs = createCommentBundlePairs();
  await page.addInitScript(({ target, options, head, changedHead, base, mergeBase, commitSha, parentSha, patch }) => {
    let savedAuth = {};
    try {
      savedAuth = JSON.parse(sessionStorage.getItem("moondiff-fake-auth") || "{}");
    } catch {}
    const initialLogin = options.login ?? savedAuth.login ?? "tester";
    const state = {
      target,
      calls: [],
      authenticated: options.authenticated ?? Boolean(savedAuth.authenticated),
      login: initialLogin,
      terminalUsed: Boolean(savedAuth.terminalUsed),
      device: null,
      currentHead: head,
      currentBase: base,
      headRace: false,
      metadataCalls: 0,
      commentListCalls: 0,
      anonymousPullDelayed: false,
      anonymousPullReleased: false,
      releaseAnonymousPull: null,
      accountSwitchPullDelayed: false,
      accountSwitchPullReleased: false,
      releaseAccountSwitchPull: null,
      documentHidden: false,
      documentFocused: true,
      authenticationFailureOps: [],
      issueComments: [{
        id: "10",
        body: options.issueBody ?? "Existing overall comment",
        html_url: "https://github.com/upstream/project/issues/17#issuecomment-10",
        created_at: "2026-08-18T08:00:00Z",
        user: { login: "reviewer" },
      }],
      reviewComments: [{
        id: "20",
        body: options.inlineBody ?? "Existing inline comment",
        html_url: "https://github.com/upstream/project/pull/17#discussion_r20",
        created_at: "2026-08-18T08:01:00Z",
        user: { login: "reviewer" },
        path: "src/main.mbt",
        line: 2,
        side: "RIGHT",
        position: 3,
        commit_id: head,
      }, {
        id: "21",
        body: options.replyBody ?? "Existing reply",
        html_url: "https://github.com/upstream/project/pull/17#discussion_r21",
        created_at: "2026-08-18T08:02:00Z",
        user: { login: "author" },
        path: "src/main.mbt",
        line: 2,
        side: "RIGHT",
        position: 3,
        commit_id: head,
        in_reply_to_id: "20",
      }, {
        id: "24",
        body: "Outdated inline comment",
        html_url: "https://github.com/upstream/project/pull/17#discussion_r24",
        created_at: "2026-08-18T08:03:00Z",
        user: { login: "reviewer" },
        path: "src/main.mbt",
        line: 2,
        side: "RIGHT",
        commit_id: head,
      }],
      commitComments: [{
        id: "30",
        body: options.commitBody ?? "Existing commit comment",
        html_url: "https://github.com/upstream/project/commit/example#commitcomment-30",
        created_at: "2026-08-18T08:03:00Z",
        user: { login: "reviewer" },
        path: "src/main.mbt",
        position: 3,
        line: 2,
      }],
    };
    window.__fake = state;
    Object.defineProperty(document, "hidden", {
      configurable: true,
      get: () => state.documentHidden,
    });
    document.hasFocus = () => state.documentFocused;

    function saveAuth() {
      sessionStorage.setItem("moondiff-fake-auth", JSON.stringify({
        authenticated: state.authenticated,
        login: state.login,
        terminalUsed: state.terminalUsed,
      }));
    }

    function authStatus() {
      const status = state.authenticated
        ? { authenticated: true, user_id: state.login, login: state.login, install_url: "https://github.com/apps/moondiff-test/installations/new" }
        : { authenticated: false, install_url: "https://github.com/apps/moondiff-test/installations/new" };
      if (state.device) status.device_flow = state.device;
      status.csrf_token = "fixture";
      return status;
    }

    function pullMetadata() {
      return {
        title: options.identitySpecificDiff ? `Fork PR for ${state.login}` : "Fork PR",
        body: options.pullBody ?? null,
        user: { login: "pull-author" },
        html_url: "https://github.com/upstream/project/pull/17",
        base: { sha: state.currentBase, repo: { full_name: "upstream/project" } },
        head: { sha: state.currentHead, repo: { full_name: "contributor/project-fork" } },
        additions: options.additions ?? 1,
        deletions: options.deletions ?? 1,
        changed_files: 1,
        commits: 0,
      };
    }
    function file() {
      const additions = options.additions ?? 1;
      const deletions = options.deletions ?? 1;
      const identityPatch = options.identitySpecificDiff
        ? patch.replace("+new value", `+new value for ${state.login}`)
        : patch;
      return {
        filename: "src/main.mbt",
        status: "modified",
        additions,
        deletions,
        changes: additions + deletions,
        patch: options.patch ?? identityPatch,
      };
    }
    function commit() {
      return {
        sha: commitSha,
        html_url: "https://github.com/upstream/project/commit/" + commitSha,
        commit: { message: "Commit change" },
        parents: [{ sha: parentSha }],
        stats: { additions: 1, deletions: 1, total: 2 },
        files: [file()],
      };
    }
    function content(ref) {
      const oldSource = options.oldSource ?? "context\nold value\ntail";
      const defaultNewSource = options.identitySpecificDiff
        ? `context\nnew value for ${state.login}\ntail`
        : "context\nnew value\ntail";
      const newSource = options.newSource ?? defaultNewSource;
      const text = ref === mergeBase || ref === parentSha ? oldSource : newSource;
      return { base64: btoa(text), size: text.length, contentType: "text/plain" };
    }
    async function dispatch(message) {
      const { op, args = {} } = message;
      state.calls.push({ op, args });
      if (op === "auth.status") return authStatus();
      if (op === "auth.device.start") {
        state.device = { id: args.attempt_id, phase: 'pending', user_code: 'ABCD-EFGH', verification_uri: 'https://github.com/login/device', expires_at: Date.now() / 1000 + 900, retry_after: 0, message: '' };
        return { ...authStatus(), attempt_id: args.attempt_id };
      }
      if (op === "auth.device.poll") {
        const flow = state.device;
        if (state.delayNextDevicePoll) {
          state.delayNextDevicePoll = false;
          await new Promise(resolve => { state.releaseDevicePoll = resolve; });
        }
        if (!state.device || state.device.id !== args.authorization_id) {
          return { ...authStatus(), device_flow: { ...flow, phase: 'cancelled' }, authorization_id: args.authorization_id };
        }
        state.authenticated = true;
        const device_flow = { ...state.device, phase: 'completed' };
        state.device = null;
        saveAuth();
        return { ...authStatus(), device_flow, authorization_id: args.authorization_id };
      }
      if (op === "auth.device.cancel") {
        state.device = null;
        return { ...authStatus(), authorization_id: args.authorization_id };
      }
      if (op === "auth.logout") {
        state.authenticated = false;
        saveAuth();
        return authStatus();
      }
      const authenticationFailureIndex = state.authenticationFailureOps.indexOf(op);
      if (authenticationFailureIndex >= 0) {
        state.authenticationFailureOps.splice(authenticationFailureIndex, 1);
        state.authenticated = false;
        saveAuth();
        throw Object.assign(new Error("Your GitHub session expired. Sign in again."), {
          status: 401,
          code: "authentication_required",
        });
      }
      if (op.endsWith(".create") && state.delayCreate) {
        state.delayCreate = false;
        await new Promise(resolve => { state.releaseCreate = resolve; });
      }
      if (op === "github.pull.get") {
        if (options.delayAnonymousPull && !state.authenticated && !state.anonymousPullDelayed) {
          state.anonymousPullDelayed = true;
          return new Promise((_, reject) => {
            state.releaseAnonymousPull = () => {
              state.releaseAnonymousPull = null;
              state.anonymousPullReleased = true;
              reject(Object.assign(new Error("GitHub could not find this resource. For private repositories, sign in and install the GitHub App."), {
                status: 404,
                code: "not_found_or_not_installed",
              }));
            };
          });
        }
        if (options.privateUntilAuth && !state.authenticated) {
          throw Object.assign(new Error("GitHub could not find this resource. For private repositories, sign in and install the GitHub App."), { status: 404, code: "not_found_or_not_installed" });
        }
        if (
          options.delayAccountSwitchPull &&
          state.authenticated &&
          state.login !== initialLogin &&
          !state.accountSwitchPullDelayed
        ) {
          state.accountSwitchPullDelayed = true;
          return new Promise(resolve => {
            state.releaseAccountSwitchPull = () => {
              state.releaseAccountSwitchPull = null;
              state.accountSwitchPullReleased = true;
              state.metadataCalls += 1;
              resolve(pullMetadata());
            };
          });
        }
        state.metadataCalls += 1;
        if (state.headRace) {
          state.currentHead = changedHead;
          state.headRace = false;
          state.reviewComments[0].commit_id = changedHead;
          state.reviewComments[1].commit_id = changedHead;
        }
        return pullMetadata();
      }
      if (op === "github.compare.get") return { merge_base_commit: { sha: mergeBase } };
      if (op === "github.pull.merge.status") return { base_sha: state.currentBase, head_sha: state.currentHead, open: true, draft: false, merged: false, mergeable: true, rebaseable: true, mergeable_state: "clean", ci_checks: [], ci_warnings: [] };
      if (op === "github.pull.rebase.merge") return { merged: true, sha: "d".repeat(40), message: "Pull request successfully merged" };
      if (op === "github.pull.viewed.get") return { base_sha: state.currentBase, head_sha: state.currentHead, files: [{ path: file().filename, state: { $tag: "Unviewed" } }] };
      if (op === "github.pull.files") return [file()];
      if (op === "github.commit.get") return commit();
      if (op === "github.content.get") return content(args.ref);
      if (op === "github.comments.list") {
        if (state.updateDuringList || options.updateDuringFirstList && state.commentListCalls === 0) {
          state.currentBase = changedHead;
          state.updateDuringList = false;
        }
        if (options.commentListError) {
          throw Object.assign(new Error(options.commentListError.detail), {
            status: options.commentListError.status,
            code: options.commentListError.code,
          });
        }
        if (options.privateUntilAuth && !state.authenticated) {
          throw Object.assign(new Error("Sign in and install the GitHub App for private repositories."), { status: 404, code: "not_found_or_not_installed" });
        }
        state.commentListCalls += 1;
        if (state.delayNextList) {
          state.delayNextList = false;
          const snapshot = structuredClone(state.target.kind === "pull"
            ? { issue_comments: state.issueComments, review_comments: state.reviewComments, commit_comments: [] }
            : { issue_comments: [], review_comments: [], commit_comments: state.commitComments });
          await new Promise(resolve => { state.releaseList = resolve; });
          return snapshot;
        }
        return state.target.kind === "pull"
          ? { issue_comments: state.issueComments, review_comments: state.reviewComments, commit_comments: [] }
          : { issue_comments: [], review_comments: [], commit_comments: state.commitComments };
      }
      if (op.endsWith(".comment.delete")) {
        if (state.deleteDelay) await new Promise(resolve => { state.releaseDelete = resolve; });
        if (state.deleteError) throw Object.assign(new Error(state.deleteError), { status: 403, code: "permission_denied" });
        const field = op.includes(".issue.") ? "issueComments" : op.includes(".review.") ? "reviewComments" : "commitComments";
        state[field] = state[field].filter(comment => comment.id !== args.comment_id);
        return { deleted: true };
      }
      if (op === "github.issue.comment.create") {
        const created = { id: "11", body: args.body, html_url: "https://github.com/comment/11", created_at: "2026-08-18T09:00:00Z", user: { login: "tester" } };
        state.issueComments.push(created);
        return created;
      }
      if (op === "github.review.comment.create") {
        const created = { id: "22", body: args.body, html_url: "https://github.com/comment/22", created_at: "2026-08-18T09:01:00Z", user: { login: "tester" }, path: args.path, line: args.line, side: args.side, position: 3, commit_id: args.commit_id };
        state.reviewComments.push(created);
        return created;
      }
      if (op === "github.commit.comment.create") {
        const created = { id: "31", body: args.body, html_url: "https://github.com/comment/31", created_at: "2026-08-18T09:02:00Z", user: { login: "tester" }, path: args.path, position: args.position, line: 2 };
        state.commitComments.push(created);
        return created;
      }
      if (op === "github.review.reply.create") {
        const root = state.reviewComments.find(c => String(c.id) === String(args.comment_id));
        if (!root || root.in_reply_to_id != null) throw Object.assign(new Error("Reply target must be an existing root"), { status: 422 });
        const created = { id: "23", body: args.body, html_url: "https://github.com/comment/23", created_at: "2026-08-18T09:03:00Z", user: { login: "tester" }, path: "src/main.mbt", line: 2, side: "RIGHT", position: 3, commit_id: state.currentHead, in_reply_to_id: String(args.comment_id) };
        state.reviewComments.push(created);
        return created;
      }
      throw Object.assign(new Error("Unhandled fake operation: " + op), { status: 400, code: "unhandled" });
    }
    window.__dispatch = dispatch;
  }, { target, options, head, changedHead, base, mergeBase, commitSha, parentSha, patch });
  await page.route('https://api.github.com/repos/**', async route => {
    const url = new URL(route.request().url());
    const [, , owner, repo, ...resource] = url.pathname.split('/');
    if (!((owner === 'upstream' && repo === 'project') ||
      (owner === 'contributor' && repo === 'project-fork'))) {
      throw new Error(`Unexpected review fixture GitHub repository ${owner}/${repo}`);
    }
    const path = resource.join('/');
    const common = { owner, repo };
    let message, commentKind, commentTarget, issueGeneration, source = false;
    if (path.startsWith('contents/')) {
      source = true;
      message = { op: 'github.content.get', args: { ...common,
        path: path.slice('contents/'.length).split('/').map(decodeURIComponent).join('/'), ref: url.searchParams.get('ref') } };
    } else if (/^issues\/\d+\/comments$/.test(path)) {
      commentKind = 'issue_comments';
      commentTarget = { owner, repo, number: path.split('/')[1] };
      message = { op: 'github.comments.list', args: { ...commentTarget, kind: 'pull' } };
      issueGeneration = commentPairs.begin(commentTarget);
    } else if (/^pulls\/\d+\/comments$/.test(path)) {
      commentKind = 'review_comments';
      commentTarget = { owner, repo, number: path.split('/')[1] };
      message = { op: 'github.comments.list', args: { ...commentTarget, kind: 'pull' } };
    } else if (/^commits\/[^/]+\/comments$/.test(path)) {
      commentKind = 'commit_comments'; message = { op: 'github.comments.list', args: target };
    } else if (/^pulls\/\d+\/files$/.test(path)) {
      message = { op: 'github.pull.files', args: { ...common, number: path.split('/')[1], page: Number(url.searchParams.get('page') || 1) } };
    } else if (/^pulls\/\d+$/.test(path)) {
      message = { op: 'github.pull.get', args: { ...common, number: path.split('/')[1] } };
    } else if (/^commits\/[^/]+$/.test(path)) {
      message = { op: 'github.commit.get', args: { ...common, sha: path.split('/')[1], page: Number(url.searchParams.get('page') || 1) } };
    } else if (path.startsWith('compare/')) {
      const [compareBase, compareHead] = path.slice('compare/'.length).split('...');
      message = { op: 'github.compare.get', args: { ...common, base: compareBase, head: compareHead } };
    } else {
      throw new Error(`Unhandled review fixture GitHub URL ${url}`);
    }
    let payload;
    try {
      if (commentKind === 'review_comments') {
        const value = await commentPairs.consume(commentTarget);
        payload = { ok: true, value };
      } else {
        payload = await page.evaluate(async message => {
          try { return { ok: true, value: await window.__dispatch(message) }; }
          catch (error) { return { ok: false, error: { status: error.status || 500, message: error.message } }; }
        }, message);
        if (commentKind === 'issue_comments') {
          if (payload.ok) commentPairs.publish(issueGeneration, payload.value);
          else commentPairs.cancel(issueGeneration, new Error(payload.error.message));
        }
      }
    } catch (error) {
      if (issueGeneration) commentPairs.cancel(issueGeneration, error);
      payload = { ok: false, error: { status: 500, message: `Review fixture comment pairing failed: ${error.message}` } };
    }
    const headers = { 'Access-Control-Allow-Origin': '*' };
    if (!payload.ok) {
      await route.fulfill({ status: payload.error.status, json: { message: payload.error.message }, headers }).catch(error => cancelledRoute(route, error));
    } else if (source) {
      await route.fulfill({ body: Buffer.from(payload.value.base64, 'base64'), contentType: 'text/plain', headers }).catch(error => cancelledRoute(route, error));
    } else {
      await route.fulfill({ json: commentKind ? payload.value[commentKind] : payload.value, headers }).catch(error => cancelledRoute(route, error));
    }
  });
  await page.route('**/api/**', async route => {
    route = metadataFallbackRoute(route);
    const path = new URL(route.request().url()).pathname;
    const message = path.startsWith('/api/auth/device/') ? { op: 'auth.device.' + path.split('/').at(-1), args: route.request().postDataJSON() } : path === '/api/auth/status' ? { op: 'auth.status' } : path === '/api/auth/logout' ? { op: 'auth.logout' } : fixtureRequest(route.request().postDataJSON());
    const payload = await page.evaluate(async message => {
      try { return { ok: true, value: await window.__dispatch(message) }; }
      catch (error) { return { ok: false, error: { status: error.status || 500, code: error.code || 'fake_error', message: error.message } }; }
    }, message);
    await route.fulfill({ status: payload.ok ? 200 : payload.error.status, json: payload.ok ? successFixture(message.op, payload.value) : { $tag: 'Failure', error: payload.error } });
  });


}

function commentCard(page, kind, id) {
  return page.locator('.github-comment').filter({
    has: page.locator(`.comment-body-toggle[aria-controls$="${kind}:${id}"]`),
  });
}

const commentLines = (label, count) => Array.from({ length: count }, (_, i) => `${label} ${i + 1}`).join('\n');

export { head, changedHead, base, mergeBase, commitSha, parentSha, patch, pullTarget, commitTarget, pullCommitTarget, reviewPath, installApi, commentCard, commentLines };
