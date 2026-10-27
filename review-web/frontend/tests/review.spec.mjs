import { cancelledRoute, createGate, installClock, trackRoute } from '../../tests/browser-control.mjs';
import { fixtureRequest, successFixture, metadataFallbackRoute } from '../../tests/protocol-fixtures.mjs';
import { createCommentBundlePairs } from '../../tests/comment-bundle-pairing.mjs';
import { checkToolbar } from "./toolbar.mjs";
import { clickLineCommentButton } from "./comment-actions.mjs";
import { holdRegionFrames, operationCheckpoint } from "./dom-timing.mjs";
import { navigate } from "./rendering-fixture.mjs";
import { settleRegions, installRenderProbe } from "../../tests/render-probe.mjs";
import { expect, test } from "../../tests/browser-test.mjs";
import { signInDialog, pagePosition, expectPagePosition, expectSignInDialog, closeSignInDialog } from './sign-in-dialog.mjs';

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

async function requestCommentDeletion(card, checkpoint) {
  const confirmation = card.getByRole("button", { name: "Confirm delete", exact: true });
  const actions = card.locator(".comment-delete-actions");
  // A preceding Cancel click can return before its regional DOM commit.
  if (checkpoint) {
    await expect(actions).toHaveCount(1);
    checkpoint.reach();
  }
  await expect(actions).toHaveCount(0);
  // Source loading can remount a fallback comment inline and discard its menu.
  // Retry only the confirmation request; the caller performs the actual deletion.
  await expect(async () => {
    if (await confirmation.isVisible()) return;
    const menu = card.getByRole("menu");
    if (!await menu.isVisible()) {
      await card.getByRole("button", { name: "More options", exact: true }).click({ timeout: 1_000 });
    }
    await menu.getByRole("menuitem", { name: "Delete", exact: true }).click({ timeout: 1_000 });
    await expect(confirmation).toBeVisible({ timeout: 1_000 });
  }).toPass({ timeout: 5_000, intervals: [100, 250, 500] });
}

async function cancelCommentDeletion(card, checkpoint) {
  await card.getByRole("button", { name: "Cancel deletion", exact: true }).click();
  const actions = card.locator(".comment-delete-actions");
  if (checkpoint) {
    await expect(actions).toHaveCount(1);
    checkpoint.reach();
  }
  await expect(actions).toHaveCount(0);
}

async function installApi(page, target = pullTarget(), options = {}) {
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

async function waitForSignedInComments(page) {
  await expect(page.getByRole('button', { name: 'Account: tester', exact: true })).toBeVisible();
  await expect(page.getByRole("button", { name: "Refresh" })).toBeEnabled();
}

const markdownFixture = [
  '## Markdown heading',
  '',
  '**Bold** and *italic*, ~~removed~~, `inline`.',
  'First line',
  'Second line',
  '',
  '> Quoted text',
  '',
  '- [x] Complete',
  '- [ ] Pending',
  '',
  '| Name | Result |',
  '| :--- | ---: |',
  '| Tests | Pass |',
  '',
  '```moonbit',
  'let html = "<escaped>"',
  'let long = "' + 'long code '.repeat(100) + '"',
  '```',
  '',
  '[Documentation](https://example.com/guide)',
  '',
  '<img src=x onerror="window.markdownAttack = true">',
  '',
  '[Unsafe](javascript:alert%281%29)',
].join('\n');

for (const authenticated of [false, true]) {
  test(`renders PR body and discussion Markdown for ${authenticated ? 'signed-in' : 'public'} readers`, async ({ page }) => {
    await installApi(page, pullTarget(), {
      authenticated,
      pullBody: markdownFixture,
      issueBody: markdownFixture,
      inlineBody: markdownFixture,
      replyBody: '**Reply formatting**',
    });
    await page.goto(reviewPath());
    const description = page.getByRole('region', { name: 'Pull request description' });
    await expect(description.locator('h2')).toHaveText('Markdown heading');
    const overall = page.locator('#comments .github-comment-body');
    const inline = page.locator('.review-thread .github-comment-body').first();
    await expect(inline.locator('h2')).toHaveText('Markdown heading');
    await expect(page.locator('.review-thread .github-comment-body strong').filter({ hasText: 'Reply formatting' })).toBeVisible();

    for (const body of [description.locator('.markdown-body'), overall, inline]) {
      await expect(body.locator('strong').first()).toHaveText('Bold');
      await expect(body.locator('em')).toHaveText('italic');
      await expect(body.locator('del')).toHaveText('removed');
      await expect(body.locator('blockquote')).toHaveText('Quoted text');
      await expect(body.locator('input[type=checkbox]')).toHaveCount(2);
      await expect(body.locator('input[type=checkbox]').first()).toBeChecked();
      await expect(body.locator('input[type=checkbox]').last()).not.toBeChecked();
      await expect(body.locator('input[type=checkbox]').first()).toBeDisabled();
      await expect(body.locator('table th')).toHaveText(['Name', 'Result']);
      await expect(body.locator('table td')).toHaveText(['Tests', 'Pass']);
      await expect(body.locator('pre code.language-moonbit')).toContainText('<escaped>');
      await expect(body.getByRole('link', { name: 'Documentation' })).toHaveAttribute('href', 'https://example.com/guide');
      await expect(body.locator('script, img[onerror], a[href^="javascript:"]')).toHaveCount(0);
      await expect(body.locator('p').filter({ hasText: 'First line' }).locator('br')).toHaveCount(2);
    }
    expect(await page.evaluate(() => window.markdownAttack)).toBeUndefined();

    for (const width of [1280, 480]) {
      await page.setViewportSize({ width, height: 900 });
      for (const body of [description.locator('.markdown-body'), inline]) {
        await expect(body).toHaveCSS('font-size', '14px');
        await expect(body).toHaveCSS('line-height', '21px');
        expect(await body.evaluate(node => node.scrollWidth <= node.clientWidth)).toBe(true);
        await expect(body.locator('table td').first()).toHaveCSS('font-family', await body.evaluate(node => getComputedStyle(node).fontFamily));
      }
    }
    await page.evaluate(() => { window.__fake.reviewComments[0].body = '**Updated Markdown**'; });
    await page.getByRole('button', { name: 'Refresh', exact: true }).click();
    await expect(page.locator('.review-thread .github-comment-body').first().locator('strong')).toHaveText('Updated Markdown');
  });
}

test('renders commit comment Markdown without changing commit message formatting', async ({ page }) => {
  await installApi(page, commitTarget(), { commitBody: '**Commit comment** with `code`' });
  await page.goto(reviewPath(commitTarget()));
  await expect(page.locator('.github-comment-body strong')).toHaveText('Commit comment');
  await expect(page.locator('.github-comment-body code')).toHaveText('code');
  await expect(page.locator('.commit-message-title')).toHaveText('Commit change');
  await expect(page.locator('.pull-description')).toHaveCount(0);
});

const markdownImagePng = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aXWQAAAAASUVORK5CYII=', 'base64');
const markdownImageSources = [
  'https://github.com/user-attachments/assets/image-id',
  'https://github.com/owner/repo/assets/123/image-id',
  'https://user-images.githubusercontent.com/123/image.png',
  'https://private-user-images.githubusercontent.com/123/image.png',
  'https://raw.githubusercontent.com/owner/repo/main/image.png',
  'https://camo.githubusercontent.com/image-id',
  'https://github-production-user-asset-6210df.s3.amazonaws.com/image.png',
];

test('Markdown images load exact approved sources in descriptions and all discussion regions', async ({ page }) => {
  const seen = [];
  await page.route(url => markdownImageSources.includes(url.href), async route => {
    seen.push(route.request().url());
    await route.fulfill({ contentType: 'image/png', body: markdownImagePng });
  });
  const body = markdownImageSources.map((src, i) => `![image ${i}](${src})`).join('\n');
  await installApi(page, pullTarget(), { pullBody: body, issueBody: body, inlineBody: body, replyBody: body });
  const response = await page.goto(reviewPath());
  expect(response.headers()['content-security-policy']).toContain('https://private-user-images.githubusercontent.com');
  for (const region of ['.pull-request-body', '#comments .github-comment-body', '.review-thread .github-comment-body']) {
    const body = page.locator(region).first();
    await expect(body.locator('.markdown-image[data-image-state="loaded"]')).toHaveCount(markdownImageSources.length);
    for (let i = 0; i < markdownImageSources.length; i++) {
      const image = body.getByRole('img', { name: `image ${i}`, exact: true });
      await expect(image).toBeVisible();
      await expect(image.locator('..').locator('.markdown-image-fallback')).toBeHidden();
      await expect(image.locator('../..')).toHaveAttribute('href', markdownImageSources[i]);
      await expect(image).toHaveAttribute('referrerpolicy', 'no-referrer');
    }
  }
  expect(new Set(seen)).toEqual(new Set(markdownImageSources));
});

test('Markdown images outside the allowlist produce links and zero image requests', async ({ page }) => {
  const sources = [
    'https://outside.example/image.png',
    'https://raw.githubusercontent.com.evil.example/image.png',
    'https://github.com/owner/repo/issues/1',
    'http://raw.githubusercontent.com/owner/repo/main/image.png',
    'https://raw.githubusercontent.com:444/owner/repo/main/image.png',
    'https://user@raw.githubusercontent.com/owner/repo/main/image.png',
  ];
  const seen = [];
  page.on('request', request => {
    const url = new URL(request.url());
    const avatar = url.hostname === 'avatars.githubusercontent.com' ||
      (url.hostname === 'github.com' && /^\/(reviewer|author)\.png$/.test(url.pathname));
    if (request.resourceType() === 'image' && !avatar) seen.push(request.url());
  });
  const body = sources.map((src, i) => `![outside ${i}](${src})`).concat([
    '![danger](javascript:alert%281%29)',
    '<img src="data:image/png;base64,abc" alt="data image" onerror="window.markdownAttack=true">',
    '<img src="jav&#x61script&#58alert(1)" alt="encoded protocol">',
  ]).join('\n\n');
  await installApi(page, pullTarget(), { pullBody: body, issueBody: body, inlineBody: body });
  await page.goto(reviewPath());
  const description = page.locator('.pull-request-body');
  await expect(description.getByRole('link')).toHaveCount(sources.length);
  for (let i = 0; i < sources.length; i++) await expect(description.getByRole('link', { name: `outside ${i}`, exact: true })).toHaveAttribute('href', sources[i]);
  await expect(description).toContainText('danger');
  await expect(description).toContainText('data image');
  await expect(page.locator('.markdown-body img')).toHaveCount(0);
  expect(seen).toEqual([]);
  expect(await page.evaluate(() => window.markdownAttack)).toBeUndefined();
});

test('Markdown images resolve the fork snapshot SHA and explicit GitHub branch paths', async ({ page }) => {
  const expected = [
    `https://raw.githubusercontent.com/contributor/project-fork/${head}/docs/image.png`,
    `https://raw.githubusercontent.com/contributor/project-fork/${head}/assets/root.png`,
    'https://raw.githubusercontent.com/upstream/project/main/image.png?raw=true',
    'https://raw.githubusercontent.com/other/repository/release/image.png?raw=true',
  ];
  const seen = [];
  await page.route('https://raw.githubusercontent.com/**', async route => {
    seen.push(route.request().url());
    await route.fulfill({ contentType: 'image/png', body: markdownImagePng });
  });
  const body = [
    '![relative](docs/image.png)',
    '![root](/assets/root.png)',
    '![branch](../blob/main/image.png?raw=true)',
    '![repository](../../../other/repository/blob/release/image.png?raw=true)',
  ].join('\n');
  await installApi(page, pullTarget(), { pullBody: body, issueBody: body, inlineBody: body });
  await page.goto(reviewPath());
  await expect(page.locator('.pull-request-body .markdown-image[data-image-state="loaded"]')).toHaveCount(4);
  await expect(page.locator('#comments .github-comment-body .markdown-image[data-image-state="loaded"]')).toHaveCount(4);
  await expect(page.locator('.review-thread .github-comment-body').first().locator('.markdown-image[data-image-state="loaded"]')).toHaveCount(4);
  expect(new Set(seen)).toEqual(new Set(expected));
  await page.evaluate(() => { window.__fake.currentHead = 'b'.repeat(40); });
  await page.getByRole('button', { name: 'Refresh', exact: true }).click();
  await expect(page.locator('.snapshot-stale')).toBeVisible();
  await expect(page.locator('.pull-request-body img').first()).toHaveAttribute('src', expected[0]);
  expect(seen.some(url => url.includes('/' + changedHead + '/'))).toBe(false);
});

test('Markdown images in commit comments use the pinned commit repository', async ({ page }) => {
  const expected = `https://raw.githubusercontent.com/upstream/project/${commitSha}/docs/image.png`;
  const seen = [];
  await page.route('https://raw.githubusercontent.com/**', async route => {
    seen.push(route.request().url());
    await route.fulfill({ contentType: 'image/png', body: markdownImagePng });
  });
  await installApi(page, commitTarget(), { commitBody: '![commit image](docs/image.png)' });
  await page.goto(reviewPath(commitTarget()));
  const image = page.locator('.github-comment-body').getByRole('img', { name: 'commit image', exact: true });
  await expect(image).toBeVisible();
  await expect(image).toHaveAttribute('src', expected);
  expect(seen).toEqual([expected]);
});

test('Markdown images sanitize HTML attributes and reuse wrapping links', async ({ page }) => {
  await page.route('https://camo.githubusercontent.com/**', route => route.fulfill({ contentType: 'image/png', body: markdownImagePng }));
  const body = [
    '[![wrapped](https://camo.githubusercontent.com/wrapped)](https://example.com/destination)',
    '',
    '<img src="https://camo.githubusercontent.com/html" alt="HTML &amp; caption" title="a &quot;title&quot;" width="40" height="20" srcset="https://outside.example/2x 2x" style="display:none" onerror="window.markdownAttack=true">',
    '<img src="https://camo.githubusercontent.com/empty" alt="" width="-1" height="0">',
  ].join('\n');
  await installApi(page, pullTarget(), { pullBody: body });
  await page.goto(reviewPath());
  const description = page.locator('.pull-request-body');
  await expect(description.locator('.markdown-image[data-image-state="loaded"]')).toHaveCount(3);
  await expect(description.locator('a a')).toHaveCount(0);
  await expect(description.getByRole('link').first()).toHaveAttribute('href', 'https://example.com/destination');
  const html = description.getByRole('img', { name: 'HTML & caption', exact: true });
  await expect(html).toHaveAttribute('title', 'a "title"');
  await expect(html).toHaveAttribute('width', '40');
  await expect(html).toHaveAttribute('height', '20');
  await expect(description.locator('img[onerror], img[srcset], img[style], img[width="-1"], img[height="0"]')).toHaveCount(0);
  await expect(description.locator('.markdown-image-fallback').last()).toHaveText('查看图片 · camo.githubusercontent.com');
  expect(await page.evaluate(() => window.markdownAttack)).toBeUndefined();
});

test('Markdown images keep stable links across CSP-allowed and rejected redirects', async ({ page }) => {
  const allowed = 'https://github.com/user-attachments/assets/allowed-redirect';
  const rejected = 'https://github.com/user-attachments/assets/rejected-redirect';
  const signed = 'https://github-production-user-asset-6210df.s3.amazonaws.com/image.png?signature=temporary';
  let signedRequests = 0, rejectedRequests = 0;
  // Playwright's page.route handles only the first URL of a redirect chain.
  // CDP intercepts each hop, so allowed targets stay entirely inside the fixture.
  const session = await page.context().newCDPSession(page);
  const interceptionErrors = [];
  await session.send('Fetch.enable', { patterns: [
    { urlPattern: 'https://github.com/user-attachments/assets/*redirect', resourceType: 'Image' },
    { urlPattern: 'https://github-production-user-asset-6210df.s3.amazonaws.com/image.png*', resourceType: 'Image' },
    { urlPattern: 'https://outside.example/*', resourceType: 'Image' },
  ] });
  session.on('Fetch.requestPaused', async ({ requestId, request }) => {
    try {
      if (request.url === allowed || request.url === rejected) {
        await session.send('Fetch.fulfillRequest', { requestId, responseCode: 302,
          responseHeaders: [{ name: 'Location', value: request.url === allowed ? signed : 'https://outside.example/redirected.png' }] });
      } else {
        if (request.url === signed) signedRequests++;
        else rejectedRequests++;
        await session.send('Fetch.fulfillRequest', { requestId, responseCode: 200,
          responseHeaders: [{ name: 'Content-Type', value: 'image/png' }], body: markdownImagePng.toString('base64') });
      }
    } catch (error) { interceptionErrors.push(String(error)); }
  });
  await installApi(page, pullTarget(), { pullBody: `![allowed](${allowed})\n![rejected](${rejected})` });
  await page.goto(reviewPath());
  const description = page.locator('.pull-request-body');
  await expect(description.getByRole('img', { name: 'allowed', exact: true })).toBeVisible();
  await expect(description.getByRole('link', { name: 'allowed', exact: true })).toHaveAttribute('href', allowed);
  await expect(description.getByRole('link', { name: 'rejected', exact: true })).toBeVisible();
  await expect(description.getByRole('link', { name: 'rejected', exact: true })).toHaveAttribute('href', rejected);
  await expect(description.locator('.markdown-image[data-image-state="link"]')).toHaveCount(1);
  await expect(description.locator('img')).toHaveCount(1);
  expect(signedRequests).toBe(1);
  expect(rejectedRequests).toBe(0);
  expect(await description.innerHTML()).not.toContain('signature=temporary');
  expect(interceptionErrors).toEqual([]);
  await session.detach();
});

for (const failure of [403, 404, 'invalid']) {
  test(`Markdown images degrade ${failure} responses once per mount`, async ({ page }) => {
    let requests = 0;
    await page.route('https://camo.githubusercontent.com/failure', async route => {
      requests++;
      await route.fulfill({ status: typeof failure === 'number' ? failure : 200, contentType: 'image/png', body: 'invalid image' });
    });
    await installApi(page, pullTarget(), { issueBody: '![unavailable](https://camo.githubusercontent.com/failure)' });
    await page.goto(reviewPath());
    const comment = page.locator('#comments .github-comment').first();
    await expect(comment.locator('.markdown-image[data-image-state="link"]')).toHaveCount(1);
    await expect(comment.getByRole('link', { name: 'unavailable', exact: true })).toBeVisible();
    await expect(comment.locator('.github-comment-body img')).toHaveCount(0);
    // A regional rerender of the same body must not restart the failed image.
    await comment.getByRole('button', { name: 'More options', exact: true }).click();
    await expect(comment.getByRole('menu')).toBeVisible();
    expect(requests).toBe(1);
  });
}

test('Markdown images show a link while pending and degrade at exactly ten seconds', async ({ page }) => {
  const clock = await installClock(page);
  await installRenderProbe(page);
  const response = createGate('image response after timeout');
  let requests = 0;
  await page.route('https://camo.githubusercontent.com/slow', async route => {
    requests++;
    await response.promise;
    await trackRoute(route).fulfill({ contentType: 'image/png', body: markdownImagePng });
  });
  await installApi(page, pullTarget(), { pullBody: '![slow image](https://camo.githubusercontent.com/slow)' });
  await page.goto(reviewPath());
  const timer = await clock.timer(10000);
  const description = page.locator('.pull-request-body');
  await expect(description.getByRole('link', { name: 'slow image', exact: true })).toBeVisible();
  await expect(description.locator('img')).toBeHidden();
  await clock.before(timer);
  await expect(description.locator('.markdown-image[data-image-state="pending"]')).toHaveCount(1);
  await clock.fire(timer);
  await expect(description.locator('img')).toHaveCount(0);
  await expect(description.getByRole('link', { name: 'slow image', exact: true })).toBeVisible();
  response.release();
  await settleRegions(page);
  await expect(description.locator('img')).toHaveCount(0);
  expect(requests).toBe(1);
});

test('Markdown images cancel removed-node timers and ignore old responses after refresh and route changes', async ({ page }) => {
  const clock = await installClock(page);
  await installRenderProbe(page);
  const response = createGate('retired image response');
  await page.route('https://camo.githubusercontent.com/retired', async route => {
    await response.promise;
    await trackRoute(route).fulfill({ contentType: 'image/png', body: markdownImagePng });
  });
  await page.route('https://camo.githubusercontent.com/current', route => route.fulfill({ contentType: 'image/png', body: markdownImagePng }));
  await installApi(page, pullTarget(), { issueBody: '![retired](https://camo.githubusercontent.com/retired)' });
  await page.goto(reviewPath());
  const timer = await clock.timer(10000);
  await page.evaluate(() => { window.__fake.issueComments[0].body = '![current](https://camo.githubusercontent.com/current)'; });
  await page.getByRole('button', { name: 'Refresh', exact: true }).click();
  await clock.until(() => page.locator('#comments .markdown-image[data-image-state="loaded"]').count(), 'replacement image loaded');
  expect((await clock.timers()).find(t => t.sequence === timer.sequence).state).toBe('cancelled');
  await page.evaluate(() => { window.__fake.issueComments[0].body = '![retired again](https://camo.githubusercontent.com/retired)'; });
  await page.getByRole('button', { name: 'Refresh', exact: true }).click();
  const next = await clock.timer(10000, { after: timer.sequence });
  await navigate(page, '/');
  await clock.until(async () => await page.locator('.markdown-body img').count() === 0, 'route retired image nodes');
  expect((await clock.timers()).filter(t => t.ms === 10000 && t.state === 'pending')).toEqual([]);
  expect((await clock.timers()).find(t => t.sequence === next.sequence).state).toBe('cancelled');
  response.release();
  await clock.jump(10001);
  await expect(page.locator('.markdown-body')).toHaveCount(0);
});

async function signInAndWaitForComments(page) {
  await page.getByRole("button", { name: "Sign in with GitHub" }).click();
  await waitForSignedInComments(page);
}

async function reactivatePage(page) {
  await page.evaluate(() => {
    window.__fake.documentFocused = false;
    dispatchEvent(new Event("blur"));
    window.__fake.documentHidden = true;
    document.dispatchEvent(new Event("visibilitychange"));
    window.__fake.documentHidden = false;
    document.dispatchEvent(new Event("visibilitychange"));
    window.__fake.documentFocused = true;
    dispatchEvent(new Event("focus"));
  });
}

function newLineCommentGutter(page, line) {
  const lineNumber = page.locator(".line-number-value", {
    hasText: new RegExp(`^${line}$`),
  });
  return page.locator("#moondiff-file-0 .review-gutter.new-line-number", { has: lineNumber });
}

function newLineCommentButton(page, line) {
  return newLineCommentGutter(page, line)
    .getByRole("button", { name: `Comment on line ${line}`, exact: true });
}

async function openNewLineComment(page, line) {
  await clickLineCommentButton(newLineCommentButton(page, line));
  await expect(page.locator(".inline-comment-editor-row textarea")).toBeVisible();
}

async function releaseListAfterLineCommentHover(page, button) {
  const gutter = button.locator("xpath=..");
  expect(await page.evaluate(() => ({
    scrollY,
    readingActive: Boolean(__moondiffMetrics.reading?.active),
  }))).toEqual({ scrollY: 0, readingActive: false });
  const before = await gutter.boundingBox();
  await expect(button).toHaveCSS("opacity", "1");
  await page.evaluate(() => window.__fake.releaseList());
  await expect.poll(async () => Math.abs((await gutter.boundingBox()).y - before.y)).toBeGreaterThan(before.height);
  // Re-hit-test the stationary pointer at the gutter's original coordinates.
  await page.mouse.move(before.x + before.width / 2, before.y + before.height / 2);
  await expect.poll(() => button.evaluate(el => el.parentElement.matches(":hover"))).toBe(false);
  await expect(button).toHaveCSS("opacity", "0");
  await expect(button).toHaveCSS("pointer-events", "none");
}

for (const phase of ["initial comment load", "background refresh"]) {
  for (const layout of ["Split", "Unified"]) {
    for (const side of ["old", "new"]) {
      test(`line comment click recovers from ${phase} after hover: ${layout} ${side}`, async ({ page }) => {
        await page.setViewportSize({ width: 1440, height: 1200 });
        await installRenderProbe(page);
        await installApi(page, pullTarget(), { authenticated: true });
        await page.addInitScript(phase => {
          if (phase === "initial comment load") window.__fake.delayNextList = true;
        }, phase);
        await page.goto(reviewPath());
        await page.addStyleTag({ content: "html { overflow-anchor: none !important; }" });
        const file = page.locator("#moondiff-file-0");
        await expect(file).toContainText("src/main.mbt");
        await page.getByRole("button", { name: layout, exact: true }).click();
        if (phase === "background refresh") {
          await waitForSignedInComments(page);
          await page.evaluate(() => {
            const state = window.__fake;
            state.reviewComments.push({ ...state.reviewComments[0], id: "99", line: 1, position: 1 });
            state.delayNextList = true;
          });
        }
        await settleRegions(page);
        await page.evaluate(() => window.scrollTo(0, 0));
        await settleRegions(page);
        if (phase === "background refresh") await reactivatePage(page);
        await expect.poll(() => page.evaluate(() => typeof window.__fake.releaseList)).toBe("function");
        const button = file.locator(`.${side}-line-number`)
          .getByRole("button", { name: "Comment on line 2", exact: true });
        await clickLineCommentButton(button, {
          afterHover: () => releaseListAfterLineCommentHover(page, button),
        });
        const row = file.locator(".inline-comment-editor-row");
        const editor = row.locator("textarea");
        await expect(page.locator(".comment-editor")).toHaveCount(1);
        await expect(editor).toBeVisible();
        await expect(editor).toBeFocused();
        await expect(row.locator(".comment-location")).toHaveText(`src/main.mbt · ${side === "old" ? "Old" : "New"} · 2`);
        await expectInlinePlacement(row.locator(".inline-discussion"), layout, side === "old" ? "left" : "right");
        await page.keyboard.type("Draft after layout change");
        await expect(editor).toHaveValue("Draft after layout change");
        await expect(editor).toBeFocused();
      });
    }
  }
}

test("anonymous public PR loads comments and a safe narrow diff without Analyze", async ({ page }) => {
  await installApi(page);
  await page.setViewportSize({ width: 420, height: 900 });
  await page.goto(reviewPath());
  await expect(page.getByText("Fork PR")).toBeVisible();
  await expect(page.getByRole("button", { name: "Sign in with GitHub" })).toBeVisible();
  await expect(page.getByText("Existing overall comment")).toBeVisible();
  await expect(page.getByText("Existing inline comment")).toBeVisible();
  await expect(page.getByText("Outdated inline comment")).toBeVisible();
  await expect(page.locator(".outdated-discussions .comment-location")).toContainText("Outdated");
  const commentArgs = await page.evaluate(() => window.__fake.calls
    .find(call => call.op === "github.comments.list").args);
  expect(commentArgs).toEqual({ owner: "upstream", repo: "project", kind: "pull", number: "17" });
  expect(Object.values(commentArgs)).not.toContain(null);
  await expect(page.locator("table.split.review-diff")).toBeVisible();
  await expect(page.getByRole("button", { name: /Analyze/u })).toHaveCount(0);
  await expect(page.locator(".diff-scroll [innerhtml]")).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Add overall comment" })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Reply" })).toHaveCount(0);
  await expect(page.locator(".line-comment-sign-in").first()).toBeAttached();
});

async function expectNoAnonymousWrites(page) {
  await expect(page.locator('.comment-editor')).toHaveCount(0);
  await expect(page.getByRole('checkbox', { name: 'Viewed src/main.mbt', exact: true })).not.toBeChecked();
  expect(await page.evaluate(() => window.__fake.calls.filter(call =>
    call.op.startsWith('auth.device.') || call.op.endsWith('.create') ||
    call.op === 'github.pull.file.viewed.set'))).toEqual([]);
  expect(new URL(page.url()).pathname).toBe(reviewPath());
  expect(new URL(page.url()).hash).toBe('');
  expect(page.context().pages()).toHaveLength(1);
}

for (const layout of ['Split', 'Unified']) for (const width of [1280, 320]) for (const colorScheme of ['light', 'dark']) {
  test(`anonymous PR comment hints and sign-in dialog, ${layout}/${width}px/${colorScheme}`, async ({ page }, testInfo) => {
    await installApi(page);
    await page.emulateMedia({ colorScheme });
    await page.setViewportSize({ width, height: 650 });
    await page.goto(reviewPath());
    await page.getByRole('button', { name: layout, exact: true }).click();
    await expect(page.locator(`table.${layout.toLowerCase()}.review-diff`)).toBeVisible();
    for (const side of ['old', 'new']) {
      const gutter = page.locator(`#moondiff-file-0 .review-gutter.${side}-line-number`)
        .filter({ has: page.locator('.line-number-value', { hasText: /^2$/ }) });
      const button = gutter.getByRole('button', { name: 'Comment on line 2', exact: true });
      const hint = gutter.locator('.line-comment-sign-in');
      await page.mouse.move(0, 0);
      await expect(hint).toBeHidden();
      const rowGeometry = element => ({ height: element.closest('tr').getBoundingClientRect().height,
        widths: [...element.closest('tr').children].map(cell => cell.getBoundingClientRect().width) });
      const before = await gutter.evaluate(rowGeometry);
      await gutter.hover();
      await expect(button).toHaveCSS('opacity', '1');
      await expect(hint).toHaveText('Sign in to comment');
      await expect(hint).toBeVisible();
      await expect(hint).toHaveCSS('white-space', 'nowrap');
      const bounds = await hint.boundingBox();
      expect(bounds.x).toBeGreaterThanOrEqual(0);
      expect(bounds.x + bounds.width).toBeLessThanOrEqual(width);
      expect(await gutter.evaluate(rowGeometry)).toEqual(before);
      await page.mouse.move(0, 0);
      await expect(hint).toBeHidden();
      await page.keyboard.press('Tab');
      await button.focus();
      await expect(button).toHaveCSS('opacity', '1');
      await expect(hint).toBeVisible();
      const position = await pagePosition(page);
      await page.keyboard.press(side === 'old' ? 'Enter' : 'Space');
      await expectSignInDialog(page, 'Sign in to comment');
      await expectPagePosition(page, position);
      await expect(page.locator('.discussion-auth')).toBeHidden();
      await expectNoAnonymousWrites(page);
      await page.mouse.move(5, 5);
      await page.mouse.wheel(0, 400);
      await expectPagePosition(page, position);
      await page.screenshot({ path: testInfo.outputPath(`sign-in-${side}.png`) });
      const controls = signInDialog(page).locator('button, a[href]');
      await controls.last().focus();
      await page.keyboard.press('Tab');
      await expect(controls.first()).toBeFocused();
      await page.keyboard.press('Shift+Tab');
      await expect(controls.last()).toBeFocused();
      expect(await page.evaluate(() => document.activeElement.closest('dialog') !== null)).toBe(true);
      await closeSignInDialog(page, side === 'old' ? 'escape' : 'backdrop');
      await expect(button).toBeFocused();
      await expectPagePosition(page, position);
      await clickLineCommentButton(button);
      await expectSignInDialog(page, 'Sign in to comment');
      await expectNoAnonymousWrites(page);
      await closeSignInDialog(page);
      await expect(button).toBeFocused();
      await expectPagePosition(page, position);
    }
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  });
}

test('PR sign-in dialog commits independently of unrelated file paints', async ({ page }) => {
  await installApi(page);
  await page.goto(reviewPath());
  await expect(newLineCommentButton(page, 2)).toBeAttached();
  await settleRegions(page);
  const barrier = await holdRegionFrames(page, ['file:src/main.mbt']);
  try {
    await page.getByRole('button', { name: 'Unified', exact: true }).click();
    await barrier.blocked();
    await newLineCommentButton(page, 2).evaluate(button => button.click());
    await expectSignInDialog(page, 'Sign in to comment');
    await closeSignInDialog(page);
  } finally { await barrier.release(); }
});

for (const alreadyOpen of [false, true]) {
  test(`PR switch discards ${alreadyOpen ? 'open dialog and old focus' : 'delayed dialog open'}`, async ({ page }) => {
    await installApi(page);
    await page.goto(reviewPath());
    const button = newLineCommentButton(page, 2);
    await button.focus();
    await settleRegions(page);
    if (alreadyOpen) {
      await page.keyboard.press('Enter');
      await expectSignInDialog(page, 'Sign in to comment');
    }
    await button.evaluate(button => {
      window.oldEntryFocus = [];
      button.addEventListener('focus', () => oldEntryFocus.push('focus'));
    });
    const barrier = await holdRegionFrames(page, ['discussion']);
    try {
      if (!alreadyOpen) {
        await button.evaluate(button => button.click());
        await barrier.blocked();
        await expect(signInDialog(page)).toBeHidden();
      }
      await navigate(page, '/upstream/project/pull/18');
      await expect(page.locator('.file-card')).toHaveAttribute('data-navigation-generation', '2');
    } finally { await barrier.release(); }
    await settleRegions(page);
    await expect(signInDialog(page)).toBeHidden();
    expect(await page.evaluate(() => oldEntryFocus)).toEqual([]);
    await expect(page.locator('html')).not.toHaveCSS('overflow', 'hidden');
  });
}

test('rapid close and reopen rejects old Discussion callbacks', async ({ page }) => {
  await installApi(page);
  await page.goto(reviewPath());
  await newLineCommentButton(page, 2).focus();
  await page.keyboard.press('Enter');
  await expectSignInDialog(page, 'Sign in to comment');
  await settleRegions(page);
  const barrier = await holdRegionFrames(page, ['discussion']);
  try {
    await signInDialog(page).getByRole('button', { name: 'Close sign-in dialog' }).click();
    await barrier.blocked();
    await page.locator('.viewed-control input').evaluate(input => input.click());
  } finally { await barrier.release(); }
  await expect(signInDialog(page)).toBeVisible();
  await expect(signInDialog(page)).toHaveAccessibleName('Sign in to track viewed files');
  await closeSignInDialog(page);
  await expect(page.locator('.viewed-control input')).toBeFocused();
  await settleRegions(page);
  await expect(signInDialog(page)).toBeHidden();
  await expectNoAnonymousWrites(page);
});

test('PR dialog uses current auth after a delayed commit and continues sign-in while closed', async ({ page }, testInfo) => {
  await installApi(page);
  await page.goto(reviewPath());
  await expect(newLineCommentButton(page, 2)).toBeAttached();
  await settleRegions(page);
  await page.evaluate(() => { window.__fake.delayNextDevicePoll = true; });
  const barrier = await holdRegionFrames(page, ['discussion']);
  try {
    await page.getByRole('button', { name: 'Sign in with GitHub', exact: true }).click();
    await barrier.blocked();
    await expect.poll(() => page.evaluate(() => typeof window.__fake.releaseDevicePoll)).toBe('function');
    await page.getByRole('checkbox', { name: 'Viewed src/main.mbt', exact: true }).click();
    await expect(signInDialog(page)).toBeHidden();
  } finally { await barrier.release(); }
  try {
    await expectSignInDialog(page, 'Sign in to track viewed files', true);
    await expect(signInDialog(page).locator('.device-code')).toHaveText('ABCD-EFGH');
    await page.screenshot({ path: testInfo.outputPath('sign-in-authorization.png') });
    const node = await signInDialog(page).elementHandle();
    await closeSignInDialog(page, 'escape');
    await newLineCommentButton(page, 2).focus();
    const position = await pagePosition(page);
    await page.keyboard.press('Enter');
    await expectSignInDialog(page, 'Sign in to comment', true);
    expect(await signInDialog(page).evaluate((dialog, original) => dialog === original, node)).toBe(true);
    await expectPagePosition(page, position);
    await closeSignInDialog(page);
    expect(await page.evaluate(() => window.__fake.calls.filter(call => call.op === 'auth.device.start'))).toHaveLength(1);
    expect(await page.evaluate(() => window.__fake.calls.filter(call => call.op === 'auth.device.cancel'))).toHaveLength(0);
  } finally {
    await page.evaluate(() => window.__fake.releaseDevicePoll());
  }
  await waitForSignedInComments(page);
  await expect(signInDialog(page)).toBeHidden();
  await expect(page.locator('.comment-editor')).toHaveCount(0);
  await expect(page.locator('.viewed-control input')).not.toBeChecked();
  expect(await page.evaluate(() => window.__fake.calls.filter(call =>
    call.op.endsWith('.create') || call.op === 'github.pull.file.viewed.set'))).toEqual([]);
});

for (const width of [1280, 320]) {
  test(`PR dialog displays sign-in failure, retry, start progress and explicit cancellation at ${width}px`, async ({ page }, testInfo) => {
    await page.setViewportSize({ width, height: 650 });
    await installApi(page);
    await page.route('**/api/auth/device/start', handler => handler.fulfill({ status: 403,
      json: { $tag: 'Failure', error: { status: 403, code: 'sign_in_denied', message: 'Sign-in denied.' } } }), { times: 1 });
    await page.goto(reviewPath());
    const entry = newLineCommentButton(page, 2);
    await expect(entry).toBeAttached();
    await expect(page.locator('#moondiff-file-0 .diff-notice.fallback')).toBeVisible();
    await expect(page.getByText('Existing overall comment', { exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Refresh', exact: true })).toBeEnabled();
    await settleRegions(page);
    await entry.focus();
    const position = await pagePosition(page);
    await page.keyboard.press('Enter');
    await expectSignInDialog(page, 'Sign in to comment');
    await expectPagePosition(page, position);
    await signInDialog(page).getByRole('button', { name: 'Sign in with GitHub' }).click();
    await expect(signInDialog(page)).toContainText('Sign-in denied.');
    await expect(signInDialog(page).getByRole('button', { name: 'Try sign-in' })).toBeFocused();
    await page.screenshot({ path: testInfo.outputPath('sign-in-retry.png') });
    let start;
    const starting = new Promise(resolve => { start = resolve; });
    await page.route('**/api/auth/device/start', async handler => { await starting; await handler.fallback(); }, { times: 1 });
    await page.evaluate(() => { window.__fake.delayNextDevicePoll = true; });
    try {
      await signInDialog(page).getByRole('button', { name: 'Try sign-in' }).click();
      await expect(signInDialog(page)).toContainText('Starting GitHub sign-in…');
      await expectSignInDialog(page, 'Sign in to comment', true);
    } finally { start(); }
    await expect(signInDialog(page).locator('.device-code')).toHaveText('ABCD-EFGH');
    await expect.poll(() => page.evaluate(() => typeof window.__fake.releaseDevicePoll)).toBe('function');
    let cancel;
    const cancelling = new Promise(resolve => { cancel = resolve; });
    await page.route('**/api/auth/device/cancel', async handler => { await cancelling; await handler.fallback(); }, { times: 1 });
    try {
      await signInDialog(page).getByRole('button', { name: 'Cancel sign-in', exact: true }).click();
      await expect(signInDialog(page)).toContainText('Cancelling GitHub sign-in…');
      await expectSignInDialog(page, 'Sign in to comment', true);
      await expectPagePosition(page, position);
    } finally { cancel(); }
    await expect(signInDialog(page).getByRole('button', { name: 'Sign in with GitHub' })).toBeFocused();
    expect(await page.evaluate(() => window.__fake.calls.filter(call => call.op === 'auth.device.cancel'))).toHaveLength(1);
    await expectPagePosition(page, position);
    await closeSignInDialog(page);
    await expect(newLineCommentButton(page, 2)).toBeFocused();
    await page.evaluate(() => window.__fake.releaseDevicePoll());
  });
}

test('long sign-in failures scroll inside the dialog on a short narrow screen', async ({ page }) => {
  await installApi(page);
  await page.setViewportSize({ width: 320, height: 360 });
  await page.route('**/api/auth/device/start', handler => handler.fulfill({ status: 403,
    json: { $tag: 'Failure', error: { status: 403, code: 'sign_in_denied',
      message: 'Sign-in denied. '.repeat(100) } } }));
  await page.goto(reviewPath());
  const entry = newLineCommentButton(page, 2);
  await entry.focus();
  await page.keyboard.press('Enter');
  await expectSignInDialog(page, 'Sign in to comment');
  const position = await pagePosition(page);
  await signInDialog(page).getByRole('button', { name: 'Sign in with GitHub' }).click();
  await expect(signInDialog(page).getByRole('button', { name: 'Try sign-in' })).toBeFocused();
  const size = await signInDialog(page).evaluate(dialog => ({
    height: dialog.getBoundingClientRect().height, width: dialog.getBoundingClientRect().width,
    scrollHeight: dialog.scrollHeight, clientHeight: dialog.clientHeight,
    scrollWidth: dialog.scrollWidth, clientWidth: dialog.clientWidth,
  }));
  expect(size.height).toBeLessThanOrEqual(328);
  expect(size.width).toBeLessThanOrEqual(288);
  expect(size.scrollHeight).toBeGreaterThan(size.clientHeight);
  expect(size.scrollWidth).toBe(size.clientWidth);
  const retry = signInDialog(page).getByRole('button', { name: 'Try sign-in' });
  await expect(retry).toBeInViewport();
  await page.keyboard.press('Tab');
  await expect(signInDialog(page).getByRole('button', { name: 'Close sign-in dialog' })).toBeFocused();
  await expect(signInDialog(page).getByRole('button', { name: 'Close sign-in dialog' })).toBeInViewport();
  await page.keyboard.press('Shift+Tab');
  await expect(retry).toBeFocused();
  await expect(retry).toBeInViewport();
  await expectPagePosition(page, position);
  await closeSignInDialog(page, 'escape');
  await expect(entry).toBeFocused();
  await expectPagePosition(page, position);
});

test('PR sign-in success closes the dialog without scrolling, a draft or a Viewed write', async ({ page }) => {
  await installApi(page);
  await page.goto(reviewPath());
  const entry = newLineCommentButton(page, 2);
  await expect(entry).toBeAttached();
  await settleRegions(page);
  await entry.focus();
  const position = await pagePosition(page);
  await page.keyboard.press('Enter');
  await expectSignInDialog(page, 'Sign in to comment');
  await signInDialog(page).getByRole('button', { name: 'Sign in with GitHub' }).click();
  await waitForSignedInComments(page);
  await expect(signInDialog(page)).toBeHidden();
  await expect(entry).toBeFocused();
  await expectPagePosition(page, position);
  await expect(page.locator('.comment-editor')).toHaveCount(0);
  await expect(page.locator('.viewed-control input')).not.toBeChecked();
  expect(await page.evaluate(() => window.__fake.calls.filter(call =>
    call.op.endsWith('.create') || call.op === 'github.pull.file.viewed.set'))).toEqual([]);
});

test('closing the PR dialog focuses its file button when the original entry disappears', async ({ page }) => {
  await installApi(page);
  await page.goto(reviewPath());
  const entry = newLineCommentButton(page, 2);
  await expect(page.locator('#moondiff-file-0 .diff-notice.fallback')).toBeVisible();
  await expect(page.getByText('Existing overall comment', { exact: true })).toBeVisible();
  await settleRegions(page);
  await entry.focus();
  await page.keyboard.press('Enter');
  await expectSignInDialog(page, 'Sign in to comment');
  // Remove the absolute-positioned entry without changing the page's scroll
  // range, so this case isolates focus fallback from document resizing.
  await entry.evaluate(button => button.remove());
  await expect(entry).toHaveCount(0);
  const position = await pagePosition(page);
  await closeSignInDialog(page);
  await expect(page.locator('#moondiff-file-0 .file-toggle')).toBeFocused();
  await expectPagePosition(page, position);
});

test("shared file tree uses a wide sidebar and a narrow bottom drawer", async ({ page }) => {
  await installApi(page);
  await page.setViewportSize({ width: 1100, height: 900 });
  await page.goto(reviewPath());
  await expect(page.getByText("Fork PR")).toBeVisible();

  const sidebar = page.locator("#file-tree-sidebar");
  await expect(sidebar).toBeVisible();
  await expect(sidebar).toHaveAttribute("role", "complementary");
  expect(await sidebar.evaluate(element => element.getBoundingClientRect().width)).toBe(240);
  await expect(page.getByRole("button", { name: "Open file tree" })).toBeHidden();

  for (const width of [800, 768]) {
    await page.setViewportSize({ width, height: 900 });
    await expect(sidebar).toBeVisible();
    await expect(page.getByRole("button", { name: "Open file tree" })).toBeHidden();
    const layout = await page.evaluate(() => ({
      documentClientWidth: document.documentElement.clientWidth,
      documentScrollWidth: document.documentElement.scrollWidth,
    }));
    expect(layout.documentScrollWidth).toBeLessThanOrEqual(layout.documentClientWidth);
  }

  await page.setViewportSize({ width: 420, height: 900 });
  const openTree = page.getByRole("button", { name: "Open file tree" });
  await expect(openTree).toBeVisible();
  await expect(sidebar).toBeHidden();
  await openTree.click();
  await expect(sidebar).toBeVisible();
  await expect(sidebar).toHaveAttribute("role", "dialog");
  await expect(sidebar).toHaveAttribute("aria-modal", "true");
  const drawerClose = sidebar.locator("button.drawer-close");
  await expect(drawerClose).toBeFocused();
  await drawerClose.press("Escape");
  await expect(sidebar).toBeHidden();
  await expect(openTree).toBeFocused();

  await openTree.click();
  await expect(drawerClose).toBeFocused();
  await sidebar.getByRole("treeitem", { name: "Open src/main.mbt" }).click();
  await expect(sidebar).toBeHidden();
  await expect(openTree).toHaveAttribute("aria-expanded", "false");
  await expect(page.locator("#moondiff-file-0")).toBeVisible();
  await expect(page.locator("#moondiff-file-0 .file-toggle")).toBeFocused();
});

test("AST highlights inserted internal whitespace continuously in split and unified views", async ({ page }) => {
  const stable = "fn stable() {}";
  const added = "fn inserted() { let total = 1 }";
  await installApi(page, pullTarget(), {
    additions: 1,
    deletions: 0,
    oldSource: stable,
    newSource: `${stable}\n${added}`,
    patch: `@@ -1 +1,2 @@\n ${stable}\n+${added}`,
  });
  await page.goto(reviewPath());

  const ast = page.getByRole("button", { name: "Tree", exact: true });
  await ast.click();
  await expect(ast).toHaveAttribute("aria-pressed", "true");

  const splitHighlight = page.locator("table.split.review-diff b.wa", {
    hasText: "let total",
  });
  await expect(splitHighlight).toHaveCount(1);
  await expect(splitHighlight).toContainText("let total");

  await page.getByRole("button", { name: "Unified" }).click();
  const unifiedHighlight = page.locator("table.unified.review-diff b.wa", {
    hasText: "let total",
  });
  await expect(unifiedHighlight).toHaveCount(1);
  await expect(unifiedHighlight).toContainText("let total");
});

test("HTTP validation failures use a neutral Moondiff error message", async ({ page }) => {
  await installApi(page, pullTarget(), {
    authenticated: true,
    commentListError: {
      status: 400,
      code: "invalid_arguments",
      detail: "Missing RPC argument: sha",
    },
  });
  await page.goto(reviewPath());
  await expect(page.getByText("Fork PR")).toBeVisible();
  await expect(page.getByText(
    "Moondiff HTTP request failed (status 400, invalid_arguments): Missing RPC argument: sha",
  )).toBeVisible();
});

test("login, overall comment, inline comment, reply, reactivation refresh, and view toggle", async ({ page }) => {
  await installApi(page);
  await page.goto(reviewPath());
  await expect(page.getByText("Existing inline comment")).toBeVisible();
  await expect(page.locator("table.split.review-diff")).toBeVisible();
  await expect(page.getByRole("button", { name: "Add overall comment" })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Reply" })).toHaveCount(0);
  await expect(page.locator(".line-comment-sign-in").first()).toBeAttached();
  await signInAndWaitForComments(page);

  const lineCommentButton = newLineCommentButton(page, 2);
  await expect(lineCommentButton).toHaveCSS("opacity", "0");
  await newLineCommentGutter(page, 2).hover();
  await expect(lineCommentButton).toHaveCSS("opacity", "1");
  const [buttonBox, gutterBox] = await Promise.all([
    lineCommentButton.boundingBox(),
    newLineCommentGutter(page, 2).boundingBox(),
  ]);
  expect(buttonBox.height).toBeLessThanOrEqual(gutterBox.height);

  await page.getByRole("button", { name: "Add overall comment" }).click();
  await page.locator(".comment-editor textarea").fill("New overall comment");
  await page.getByRole("button", { name: "Post comment" }).click();
  await expect(page.getByText("New overall comment")).toBeVisible();


  await openNewLineComment(page, 2);
  await page.locator(".inline-comment-editor-row textarea").fill("New inline comment");
  await page.locator(".inline-comment-editor-row").getByRole("button", { name: "Post comment" }).click();
  await expect(page.getByText("New inline comment")).toBeVisible();
  const reviewCall = await page.evaluate(() => window.__fake.calls.find(call => call.op === "github.review.comment.create"));
  expect(reviewCall.args).toMatchObject({ path: "src/main.mbt", line: 2, side: "RIGHT", commit_id: head });

  await page.getByRole("button", { name: "Reply" }).first().click();
  await page.locator(".review-thread textarea").fill("Thread reply");
  await page.locator(".review-thread").getByRole("button", { name: "Post comment" }).click();
  await expect(page.getByText("Thread reply")).toBeVisible();

  const before = await page.evaluate(() => ({
    auth: window.__fake.calls.filter(call => call.op === "auth.status").length,
    comments: window.__fake.commentListCalls,
    callIndex: window.__fake.calls.length,
  }));
  await reactivatePage(page);
  await expect.poll(() => page.evaluate(() => ({
    auth: window.__fake.calls.filter(call => call.op === "auth.status").length,
    comments: window.__fake.commentListCalls,
  }))).toEqual({ auth: before.auth + 1, comments: before.comments + 1 });
  const refreshOrder = await page.evaluate(callIndex => window.__fake.calls
    .slice(callIndex)
    .filter(call => call.op === "auth.status" || call.op === "github.comments.list")
    .map(call => call.op), before.callIndex);
  expect(refreshOrder).toEqual(["auth.status", "github.comments.list"]);
  await page.evaluate(() => {
    document.dispatchEvent(new Event("visibilitychange"));
    dispatchEvent(new Event("focus"));
  });
  await page.getByRole("button", { name: "Refresh" }).click();
  await expect.poll(() => page.evaluate(() => ({
    auth: window.__fake.calls.filter(call => call.op === "auth.status").length,
    comments: window.__fake.commentListCalls,
  }))).toEqual({ auth: before.auth + 1, comments: before.comments + 2 });

  await page.getByRole("button", { name: "Unified" }).click();
  await expect(page.locator("table.unified.review-diff")).toBeVisible();
});

test("expired credentials during comment refresh offer sign-in and preserve comment entry points", async ({ page }) => {
  await installApi(page, pullTarget(), { authenticated: true });
  await page.goto(reviewPath());
  await waitForSignedInComments(page);

  await page.evaluate(() => {
    window.__fake.authenticationFailureOps.push("github.comments.list");
  });
  await page.getByRole("button", { name: "Refresh" }).click();

  await expect(page.locator(".auth-controls.error")).toContainText("GitHub session expired");
  await expect(page.getByRole("button", { name: "Try sign-in" })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Account: tester', exact: true })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Add overall comment" })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Reply" })).toHaveCount(0);
  await expect(page.locator(".line-comment-sign-in").first()).toBeAttached();
  await clickLineCommentButton(newLineCommentButton(page, 2));
  await expectSignInDialog(page, 'Sign in to comment');
  expect(await page.evaluate(() => window.__fake.calls.filter(call => call.op === 'auth.device.start'))).toHaveLength(0);

  await page.getByRole("button", { name: "Try sign-in" }).click();
  await waitForSignedInComments(page);
  await expect(page.getByRole("button", { name: "Add overall comment" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Reply" }).first()).toBeVisible();
  await expect(page.locator(".line-comment-button").first()).toBeAttached();
});

for (const kind of ["overall", "inline", "reply"]) {
  test(`${kind} expired draft stays editable through reauthorization without taking file search focus`, async ({ page }) => {
    await installApi(page, pullTarget(), { authenticated: true });
    await page.goto(reviewPath());
    await waitForSignedInComments(page);
    if (kind === "overall") await page.getByRole("button", { name: "Add overall comment" }).click();
    else if (kind === "inline") await openNewLineComment(page, 2);
    else await page.getByRole("button", { name: "Reply" }).first().click();
    const editor = page.locator(".comment-editor textarea");
    await editor.fill("Keep this draft through re-login");
    const id = await editor.getAttribute('data-draft-id');
    await page.evaluate(() => {
      window.__fake.authenticationFailureOps.push("github.comments.list");
      window.__fake.delayNextDevicePoll = true;
    });
    await reactivatePage(page);
    await expect(page.locator(".auth-controls.error")).toContainText("GitHub session expired");
    await expect(editor).toHaveAttribute('data-draft-id', id);
    await expect(editor).toBeEnabled();
    await editor.fill('Edited while expired');
    await editor.evaluate(element => element.select());
    expect(await editor.evaluate(element => element.value.slice(element.selectionStart, element.selectionEnd))).toBe('Edited while expired');
    await expect(page.getByRole('button', { name: 'Post comment' })).toBeDisabled();
    await expect(page.locator('.comment-editor')).toContainText('Sign in with GitHub before posting');
    await page.getByRole("button", { name: "Try sign-in" }).click();
    await expect.poll(() => page.evaluate(() => typeof window.__fake.releaseDevicePoll)).toBe("function");
    await editor.fill('Edited during sign-in');
    await page.getByRole("button", { name: "Search files", exact: true }).click();
    const search = page.getByRole("searchbox", { name: "Search changed files" });
    await search.fill("main");
    await page.evaluate(() => window.__fake.releaseDevicePoll());
    await waitForSignedInComments(page);
    await expect(page.getByRole('button', { name: 'Post comment' })).toBeEnabled();
    await expect(editor).toHaveValue('Edited during sign-in');
    await expect(editor).toHaveAttribute('data-draft-id', id);
    await expect(search).toBeFocused();
    await page.keyboard.type(".mbt");
    await expect(search).toHaveValue("main.mbt");
    expect(await page.evaluate(() => window.__fake.calls.filter(call => call.op.endsWith('.create')).length)).toBe(0);
  });
}

test("expired credentials during comment submission retain the draft for manual retry", async ({ page }) => {
  await installApi(page, pullTarget(), { authenticated: true });
  await page.goto(reviewPath());
  await waitForSignedInComments(page);
  await page.getByRole("button", { name: "Add overall comment" }).click();
  const editor = page.locator('.comment-editor textarea');
  await editor.fill("Keep this draft");
  await page.evaluate(() => { window.__fake.authenticationFailureOps.push("github.issue.comment.create"); });
  await page.getByRole("button", { name: "Post comment" }).click();
  await expect(page.locator(".auth-controls.error")).toContainText("GitHub session expired");
  await expect(editor).toHaveValue('Keep this draft');
  await expect(editor).toBeEnabled();
  await editor.fill('Edited retry');
  await page.getByRole("button", { name: "Try sign-in" }).click();
  await waitForSignedInComments(page);
  await expect(page.getByRole('button', { name: 'Post comment' })).toBeEnabled();
  await expect(editor).toHaveValue('Edited retry');
  expect(await page.evaluate(() => window.__fake.calls.filter(call => call.op.endsWith('.create')).length)).toBe(1);
  await page.getByRole("button", { name: "Post comment" }).click();
  await expect(page.getByText("Edited retry", { exact: true })).toBeVisible();
});

test('same-account recovery keeps the draft locked until snapshot validation finishes', async ({ page }) => {
  await installApi(page, pullTarget(), { authenticated: true });
  await page.goto(reviewPath());
  await waitForSignedInComments(page);
  await openNewLineComment(page, 2);
  const editor = page.locator('.comment-editor textarea');
  await editor.fill('Original anchor');
  await page.evaluate(() => window.__fake.authenticationFailureOps.push('github.comments.list'));
  await reactivatePage(page);
  await expect(page.locator('.auth-controls.error')).toContainText('GitHub session expired');
  let release, held = 0;
  const validation = new Promise(resolve => { release = resolve; });
  await page.route('**/api/rpc', async route => {
    route = metadataFallbackRoute(route);
    const message = fixtureRequest(route.request().postDataJSON());
    if (message.op !== 'github.pull.get') return route.fallback();
    const value = await page.evaluate(message => window.__dispatch(message), message);
    held++;
    await validation;
    await route.fulfill({ json: successFixture(message.op, value) }).catch(error => cancelledRoute(route, error));
  });
  await page.getByRole('button', { name: 'Try sign-in' }).click();
  await expect(page.getByRole('button', { name: 'Account: tester' })).toBeVisible();
  await expect.poll(() => held).toBeGreaterThan(0);
  await expect(page.getByRole('button', { name: 'Post comment' })).toBeDisabled();
  await editor.fill('Edited during snapshot validation');
  release();
  await expect(page.getByRole('button', { name: 'Post comment' })).toBeEnabled();
  await expect(editor).toHaveValue('Edited during snapshot validation');
  expect(await page.evaluate(() => window.__fake.calls.filter(call => call.op.endsWith('.create')).length)).toBe(0);
});

test("private PR prompts for GitHub App access and retries after login", async ({ page }) => {
  await installApi(page, pullTarget(), { privateUntilAuth: true });
  await page.goto(reviewPath());
  await expect(page.getByText(/private repositories/u)).toBeVisible();
  await expect(page.getByRole("link", { name: /Install GitHub App/u })).toBeVisible();
  await page.getByRole("button", { name: "Sign in with GitHub" }).click();
  await expect(page.getByText("Fork PR")).toBeVisible();
  await expect(page.getByRole('button', { name: 'Account: tester', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Account: tester' }).click();
  const installLink = page.getByRole('menuitem', { name: 'Install Moondiff Github App ↗' });
  await expect(installLink).toBeVisible();
  await expect(installLink).toHaveAttribute(
    "href",
    "https://github.com/apps/moondiff-test/installations/new",
  );
  await expect(installLink).toHaveAttribute("target", "_blank");
  await expect(installLink).toHaveAttribute("rel", "noopener noreferrer");
});

test("reactivation synchronizes cross-tab login and logout", async ({ page }) => {
  await installApi(page);
  await page.goto(reviewPath());
  await expect(page.getByRole("button", { name: "Sign in with GitHub" })).toBeVisible();

  await page.evaluate(() => { window.__fake.authenticated = true; });
  await reactivatePage(page);
  await expect(page.getByRole('button', { name: 'Account: tester', exact: true })).toBeVisible();
  await expect(page.getByRole("button", { name: "Add overall comment" })).toBeVisible();

  await page.evaluate(() => { window.__fake.authenticated = false; });
  await reactivatePage(page);
  await expect(page.getByRole("button", { name: "Sign in with GitHub" })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Account: tester', exact: true })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Add overall comment" })).toHaveCount(0);
});

test("cross-tab account switch clears the old draft and diff before reloading", async ({ page }) => {
  await installApi(page, pullTarget(), {
    authenticated: true,
    login: "alice",
    identitySpecificDiff: true,
    delayAccountSwitchPull: true,
  });
  await page.goto(reviewPath());
  await expect(page.getByRole('button', { name: 'Account: alice', exact: true })).toBeVisible();
  await expect(page.getByText("Fork PR for alice")).toBeVisible();
  await expect(page.getByText("new value for alice", { exact: false })).toBeVisible();
  await page.getByRole("button", { name: "Add overall comment" }).click();
  await page.locator(".comment-editor textarea").fill("Alice-only draft");
  const pullCallsBeforeSwitch = await page.evaluate(() => window.__fake.calls
    .filter(call => call.op === "github.pull.get").length);

  await page.evaluate(() => { window.__fake.login = "bob"; });
  await reactivatePage(page);
  await expect.poll(() => page.evaluate(() => window.__fake.accountSwitchPullDelayed)).toBe(true);
  await expect(page.getByText("Loading pull request metadata…")).toBeVisible();
  await expect(page.locator(".comment-editor textarea")).toHaveCount(0);
  await expect(page.getByText("Alice-only draft")).toHaveCount(0);
  await expect(page.getByText("Fork PR for alice")).toHaveCount(0);
  await expect(page.getByText("new value for alice", { exact: false })).toHaveCount(0);
  expect(await page.evaluate(() => window.__fake.calls
    .filter(call => call.op === "github.pull.get").length)).toBeGreaterThan(pullCallsBeforeSwitch);

  await page.evaluate(() => window.__fake.releaseAccountSwitchPull());
  await expect.poll(() => page.evaluate(() => window.__fake.accountSwitchPullReleased)).toBe(true);
  await expect(page.getByRole('button', { name: 'Account: bob', exact: true })).toBeVisible();
  await expect(page.getByText("Fork PR for bob")).toBeVisible();
  await expect(page.getByText("new value for bob", { exact: false })).toBeVisible();
});

test("cross-tab login on reactivation reloads a private repository", async ({ page }) => {
  await installApi(page, pullTarget(), { privateUntilAuth: true });
  await page.goto(reviewPath());
  await expect(page.getByText(/private repositories/u)).toBeVisible();
  const before = await page.evaluate(() => window.__fake.calls
    .filter(call => call.op === "github.pull.get").length);
  await page.evaluate(() => { window.__fake.authenticated = true; });
  await reactivatePage(page);
  await expect(page.getByText("Fork PR")).toBeVisible();
  await expect(page.getByRole('button', { name: 'Account: tester', exact: true })).toBeVisible();
  expect(await page.evaluate(() => window.__fake.calls
    .filter(call => call.op === "github.pull.get").length)).toBeGreaterThan(before);
});

test("cross-tab login supersedes a pending anonymous private-repository failure", async ({ page }) => {
  await installApi(page, pullTarget(), {
    privateUntilAuth: true,
    delayAnonymousPull: true,
  });
  await page.goto(reviewPath());
  await expect.poll(() => page.evaluate(() => window.__fake.anonymousPullDelayed)).toBe(true);

  await page.evaluate(() => { window.__fake.authenticated = true; });
  await reactivatePage(page);
  await expect(page.getByText("Fork PR")).toBeVisible();
  await expect(page.getByRole('button', { name: 'Account: tester', exact: true })).toBeVisible();
  await expect.poll(() => page.evaluate(() => window.__fake.calls
    .filter(call => call.op === "github.pull.get").length)).toBeGreaterThanOrEqual(2);

  await page.evaluate(async () => {
    window.__fake.releaseAnonymousPull();
    await new Promise(resolve => setTimeout(resolve, 0));
  });
  await expect.poll(() => page.evaluate(() => window.__fake.anonymousPullReleased)).toBe(true);
  await expect(page.getByText("Fork PR")).toBeVisible();
  await expect(page.getByRole('button', { name: 'Account: tester', exact: true })).toBeVisible();
  await expect(page.getByText(/private repositories/u)).toHaveCount(0);
});

test("PR head race preserves the draft until manually loading the snapshot", async ({ page }) => {
  await installApi(page, pullTarget(), { authenticated: true });
  await page.goto(reviewPath());
  await waitForSignedInComments(page);
  await openNewLineComment(page, 2);
  await page.locator(".inline-comment-editor-row textarea").fill("Keep this draft");
  await page.evaluate(() => { window.__fake.headRace = true; });
  await page.locator(".inline-comment-editor-row").getByRole("button", { name: "Post comment" }).click();
  await expect(page.locator(".snapshot-stale")).toContainText("PR updated");
  await expect(page.getByRole("button", { name: "Load latest" })).toBeDisabled();
  await expect(page.locator(".inline-comment-editor-row").getByRole("button", { name: "Post comment" })).toBeDisabled();
  await expect(page.locator(".inline-comment-editor-row textarea")).toHaveValue("Keep this draft");
  expect(await page.evaluate(() => window.__fake.calls.filter(call => call.op === "github.review.comment.create").length)).toBe(0);
  await page.locator(".inline-comment-editor-row textarea").fill("Still editable");
  await page.getByRole("button", { name: "Cancel", exact: true }).click();
  await page.getByRole("button", { name: "Load latest" }).click();
  await expect(page.locator(".snapshot-stale")).toHaveCount(0);
  await waitForSignedInComments(page);
  await openNewLineComment(page, 2);
  await page.locator(".comment-editor textarea").fill("New snapshot comment");
  await page.getByRole("button", { name: "Post comment", exact: true }).click();
  await expect(page.getByText("New snapshot comment", { exact: true })).toBeVisible();
  expect(await page.evaluate(() => window.__fake.calls.find(call => call.op === "github.review.comment.create").args.commit_id)).toBe(changedHead);
});

for (const target of [commitTarget(), pullCommitTarget()]) {
  test(`${target.kind} can post a new comment after same-account reauthorization`, async ({ page }) => {
    await installApi(page, target, { authenticated: true });
    let holdSources = true, releaseSources;
    const sources = new Promise(resolve => { releaseSources = resolve; });
    const sourceRequests = [];
    await page.route('**/api/rpc', async route => {
      route = metadataFallbackRoute(route);
      const request = fixtureRequest(route.request().postDataJSON());
      if (request.op === 'github.content.get') {
        sourceRequests.push(request.args);
        if (holdSources) await sources;
      }
      await route.fallback().catch(error => cancelledRoute(route, error));
    });
    await page.goto(reviewPath(target));
    await waitForSignedInComments(page);
    await expect(page.locator('.file-card')).toContainText('src/main.mbt');
    await expect.poll(() => sourceRequests.length).toBe(2);
    const commitReads = () => page.evaluate(() => window.__fake.calls.filter(call => call.op === 'github.commit.get').length);
    const before = await commitReads();
    await page.evaluate(() => { window.__fake.authenticationFailureOps.push('github.comments.list'); });
    await reactivatePage(page);
    await expect(page.locator('.auth-controls.error')).toContainText('GitHub session expired');
    await expect(page.locator('.comment-editor textarea')).toHaveCount(0);
    holdSources = false;
    await page.getByRole('button', { name: 'Try sign-in' }).click();
    await waitForSignedInComments(page);
    await expect.poll(() => sourceRequests.length).toBe(4);
    releaseSources();
    await expect(page.locator('table.split.review-diff')).toBeVisible();
    await expect(page.getByText('Checking the current PR version…', { exact: true })).toHaveCount(0);
    await openNewLineComment(page, 2);
    const body = `New ${target.kind} comment after sign-in`;
    await page.locator('.comment-editor textarea').fill(body);
    await expect(page.getByRole('button', { name: 'Post comment', exact: true })).toBeEnabled();
    await page.getByRole('button', { name: 'Post comment', exact: true }).click();
    await expect(page.getByText(body, { exact: true })).toBeVisible();
    expect(await commitReads()).toBe(before);
    expect(await page.evaluate(() => window.__fake.calls.filter(call => call.op === 'github.commit.comment.create').length)).toBe(1);
  });

  test(`${target.kind} posts canonical position comments to the URL repository`, async ({ page }) => {
    await installApi(page, target, { authenticated: true });
    await page.goto(reviewPath(target));
    await waitForSignedInComments(page);
    await expect(page.getByText("Existing commit comment")).toBeVisible();
    const commentArgs = await page.evaluate(() => window.__fake.calls
      .find(call => call.op === "github.comments.list").args);
    expect(commentArgs).toEqual(target);
    expect(Object.values(commentArgs)).not.toContain(null);
    await openNewLineComment(page, 2);
    await page.locator(".inline-comment-editor-row textarea").fill(`Comment for ${target.kind}`);
    await page.locator(".inline-comment-editor-row").getByRole("button", { name: "Post comment" }).click();
    await expect.poll(() => page.evaluate(() => window.__fake.calls
      .find(entry => entry.op === "github.commit.comment.create")?.args))
      .toMatchObject({ owner: "upstream", repo: "project", sha: commitSha, path: "src/main.mbt", position: 3 });
    await expect(page.getByText(`Comment for ${target.kind}`, { exact: true })).toBeVisible();
    if (target.kind === "pull_commit") {
      const metadataCall = await page.evaluate(() => window.__fake.calls.find(entry => entry.op === "github.commit.get"));
      expect(metadataCall.args).toMatchObject({ owner: "contributor", repo: "project-fork" });
    }
  });
}

test("inline cards anchor both sides once, keep replies, and place editors after discussions below the target", async ({ page }) => {
  await installApi(page, pullTarget(), { authenticated: true, login: "reviewer" });
  await page.addInitScript(() => {
    const root = window.__fake.reviewComments[0];
    window.__fake.reviewComments.push({ ...root, id: "40", side: "LEFT", position: 2, body: "Left thread" });
    window.__fake.reviewComments.push({ ...root, id: "41", body: "Second right thread" });
  });
  await page.goto(reviewPath());
  for (const layout of ["split", "unified", "split"]) {
    const toggle = page.getByRole("button", { name: layout === "split" ? "Split" : "Unified", exact: true });
    await toggle.click();
    await expect(toggle).toHaveAttribute("aria-pressed", "true");
    await expect(page.locator(`table.${layout}.review-diff`).first()).toBeVisible();
    for (const body of ["Existing inline comment", "Left thread", "Second right thread"]) {
      const card = page.locator(".inline-discussion-row").filter({ hasText: body });
      await expect(card).toHaveCount(1);
      await expect(card.locator(".comment-location")).toContainText("src/main.mbt");
      expect(await card.evaluate(row => {
        let target = row.previousElementSibling;
        while (target?.classList.contains("inline-discussion-row")) target = target.previousElementSibling;
        return target?.classList.contains("comment-target");
      })).toBe(true);
    }
  }
  await openNewLineComment(page, 2);
  const editor = page.locator(".inline-comment-editor-row");
  await expect(editor.locator(".comment-location")).toContainText("New · 2");
  expect(await editor.evaluate(row => {
    let previous = row.previousElementSibling;
    if (!previous?.classList.contains("inline-discussion-row")) return false;
    while (previous?.classList.contains("inline-discussion-row")) previous = previous.previousElementSibling;
    return previous?.classList.contains("comment-target");
  })).toBe(true);
  await editor.getByRole("button", { name: "Cancel", exact: true }).click();
  const own = page.locator(".github-comment").filter({ hasText: "Existing inline comment" });
  await expect(page.locator(".github-comment").filter({ hasText: "Existing reply" }).locator(".comment-delete")).toHaveCount(0);
  await requestCommentDeletion(own);
  await cancelCommentDeletion(own);
  await expect(own).toBeVisible();
  await requestCommentDeletion(own);
  await own.getByRole("button", { name: "Confirm delete" }).click();
  await expect(own).toHaveCount(0);
  await expect(page.locator(".inline-discussion-row").filter({ hasText: "Existing reply" })).toHaveCount(1);
  expect(await page.evaluate(() => window.__fake.calls.filter(c => c.op === "github.review.comment.delete").length)).toBe(1);
});

test("delete failures can retry without duplicate requests or stale refresh resurrection", async ({ page }) => {
  await installApi(page, pullTarget(), { authenticated: true, login: "reviewer" });
  await page.goto(reviewPath());
  const own = page.locator(".github-comment").filter({ hasText: "Existing overall comment" });
  await requestCommentDeletion(own);
  await page.evaluate(() => { window.__fake.deleteError = "Permission denied"; });
  await own.getByRole("button", { name: "Confirm delete" }).click();
  await expect(own.locator(".comment-error")).toContainText("GitHub denied this action");
  await page.evaluate(() => {
    window.__fake.deleteError = null;
    window.__fake.deleteDelay = true;
    window.__fake.delayNextList = true;
  });
  await page.getByRole("button", { name: "Refresh", exact: true }).click();
  await expect.poll(() => page.evaluate(() => !!window.__fake.releaseList)).toBe(true);
  await own.getByRole("button", { name: "Confirm delete" }).click();
  await expect(own.getByRole("button", { name: "Deleting…" })).toBeDisabled();
  await expect(own.getByRole("button", { name: "Cancel deletion" })).toBeDisabled();
  await expect.poll(() => page.evaluate(() => !!window.__fake.releaseDelete)).toBe(true);
  await page.evaluate(() => window.__fake.releaseDelete());
  await expect(own).toHaveCount(0);
  await page.evaluate(() => window.__fake.releaseList());
  await expect(own).toHaveCount(0);
  expect(await page.evaluate(() => window.__fake.calls.filter(c => c.op === "github.issue.comment.delete").length)).toBe(2);
});

test("comment menu supports keyboard navigation, dismissal and deletion confirmation", async ({ page }) => {
  await installApi(page, pullTarget(), { authenticated: true, login: "reviewer" });
  await page.goto(reviewPath());
  const card = page.locator(".github-comment").filter({ hasText: "Existing inline comment" });
  const more = card.getByRole("button", { name: "More options" });
  const menu = card.getByRole("menu");
  const link = menu.getByRole("menuitem", { name: /Open on GitHub/u });
  const deletion = menu.getByRole("menuitem", { name: "Delete", exact: true });
  await more.focus();
  await more.press("Enter");
  await expect(menu).toBeVisible();
  await expect(more).toHaveAttribute("aria-expanded", "true");
  await expect(link).toBeFocused();
  await expect(link).toHaveAttribute("href", "https://github.com/upstream/project/pull/17#discussion_r20");
  await expect(link).toHaveAttribute("target", "_blank");
  await page.keyboard.press("ArrowDown");
  await expect(deletion).toBeFocused();
  await page.keyboard.press("ArrowDown");
  await expect(link).toBeFocused();
  await page.keyboard.press("End");
  await expect(deletion).toBeFocused();
  await page.keyboard.press("Home");
  await expect(link).toBeFocused();
  await page.keyboard.press("Escape");
  await expect(menu).toBeHidden();
  await expect(more).toBeFocused();
  await expect(more).toHaveAttribute("aria-expanded", "false");
  await more.press("Space");
  await expect(menu).toBeVisible();
  await page.keyboard.press("Tab");
  await expect(menu).toBeHidden();
  await expect(more).not.toBeFocused();
  await more.press("ArrowUp");
  await expect(deletion).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(menu).toBeHidden();
  await expect(card.getByText("Delete this comment?", { exact: true })).toBeVisible();
  await cancelCommentDeletion(card);
  await more.click();
  await expect(menu).toBeVisible();
  await more.click();
  await expect(menu).toBeHidden();
  await more.click();
  await card.locator(".github-comment-body").click();
  await expect(menu).toBeHidden();
  await expect(more).toHaveAttribute("aria-expanded", "false");
  const thread = page.locator(".review-thread").filter({ hasText: "Existing inline comment" });
  await thread.getByRole("button", { name: "Reply", exact: true }).click();
  await more.click();
  await expect(deletion).toBeDisabled();
  await expect(link).toBeFocused();
  await page.keyboard.press("ArrowDown");
  await expect(link).toBeFocused();
  await page.keyboard.press("Escape");
  await thread.getByRole("button", { name: "Cancel", exact: true }).click();
});

async function expectInlinePlacement(card, layout, side) {
  await expect(card.locator("xpath=ancestor::table[1]")).toHaveClass(new RegExp(`\\b${layout.toLowerCase()}\\b`));
  await expect(card).toBeVisible();
  await expect.poll(() => card.evaluate((el, { layout, side }) => {
    const box = el.getBoundingClientRect();
    const diff = el.closest(".diff-scroll").getBoundingClientRect();
    const split = layout === "Split" && diff.width >= 720;
    const width = diff.width / (split ? 2 : 1);
    const x = split && side === "right" ? diff.width / 2 : 0;
    return Math.max(Math.abs(box.width - width), Math.abs(box.x - diff.x - x));
  }, { layout, side })).toBeLessThan(0.5);
}

for (const width of [1440, 420]) for (const colorScheme of ["light", "dark"]) {
  test(`comment cards and editors fit ${width}px in ${colorScheme} mode`, async ({ page }, testInfo) => {
    await page.setViewportSize({ width, height: 1000 });
    await page.emulateMedia({ colorScheme });
    await page.clock.setFixedTime("2026-08-18T10:01:00Z");
    await page.route("https://github.com/*.png?size=64", route => route.abort());
    await installApi(page, pullTarget(), { authenticated: true, login: "reviewer" });
    await page.addInitScript(() => {
      const root = window.__fake.reviewComments[0];
      window.__fake.reviewComments.push({ ...root, id: "40", side: "LEFT", position: 2, body: "Left thread\nhttps://example.com/" + "long".repeat(60) });
      window.__fake.reviewComments.push({ ...root, id: "41", body: "Unknown author and time", created_at: "invalid", user: undefined });
    });
    await page.goto(reviewPath());
    const right = page.locator(".inline-discussion-row").filter({ hasText: "Existing inline comment" });
    const left = page.locator(".inline-discussion-row").filter({ hasText: "Left thread" });
    const unknown = page.locator(".github-comment").filter({ hasText: "Unknown author and time" });
    await expect(right.locator("time").first()).toHaveText("2 hours ago");
    await expect(right.locator("time").first()).toHaveAttribute("title", "Tue, 18 Aug 2026 08:01:00 GMT");
    await expect(unknown.locator("time")).toHaveText("Unknown time");
    await expect(unknown.locator("time")).toHaveAttribute("title", "Unknown time");
    await expect(unknown.locator("strong")).toHaveText("ghost");
    await expect(unknown.locator(".comment-avatar-image")).toHaveCount(0);
    const avatar = right.locator(".comment-avatar").first();
    await expect(avatar).toHaveCSS("border-radius", "50%");
    await expect(avatar.locator(".comment-avatar-image")).toHaveCSS("background-image", 'url("https://github.com/reviewer.png?size=64")');
    expect(await avatar.locator(".comment-avatar-placeholder").evaluate(el => getComputedStyle(el, "::before").width)).toBe("10px");
    for (const layout of ["Split", "Unified"]) {
      await page.getByRole("button", { name: layout, exact: true }).click();
      for (const [row, side] of [[left, "left"], [right, "right"]]) {
        await expectInlinePlacement(row.locator(".inline-discussion"), layout, side);
      }
      const thread = right.locator(".review-thread");
      const boxes = await thread.locator(".github-comment").evaluateAll(els => els.map(el => {
        const { x, width } = el.getBoundingClientRect();
        return { x, width };
      }));
      expect(boxes[0]).toEqual(boxes[1]);
      for (const body of await page.locator(".github-comment-body").all()) {
        await expect(body).toHaveCSS("font-size", "14px");
        await expect(body).toHaveCSS("line-height", "21px");
        expect(await body.evaluate(el => el.scrollWidth <= el.clientWidth)).toBe(true);
      }
      for (const side of ["old", "new"]) {
        const gutter = page.locator(`#moondiff-file-0 .${side}-line-number`).filter({ has: page.locator(".line-number-value", { hasText: /^2$/u }) });
        await clickLineCommentButton(gutter.getByRole("button", { name: "Comment on line 2", exact: true }));
        const editor = page.locator(".inline-comment-editor-row .inline-discussion");
        await expect(editor.locator("textarea")).toBeFocused();
        await expect(editor.locator("textarea")).toHaveCSS("font-size", "14px");
        await expect(editor.getByRole("button", { name: "Post comment" })).toBeDisabled();
        await expectInlinePlacement(editor, layout, side === "new" ? "right" : "left");
        await editor.locator("textarea").fill("Ready to post");
        await expect(editor.getByRole("button", { name: "Post comment" })).toBeEnabled();
        await expect(editor.getByRole("button", { name: "Post comment" })).toHaveCSS("background-color", "rgb(31, 136, 61)");
        await editor.scrollIntoViewIfNeeded();
        await page.screenshot({ path: testInfo.outputPath(`${layout}-${side}-editor.png`) });
        await editor.getByRole("button", { name: "Cancel", exact: true }).click();
      }
      await thread.getByRole("button", { name: "Reply", exact: true }).click();
      await expect(thread.getByRole("button", { name: "Reply", exact: true })).toHaveCount(0);
      await expect(thread.locator("textarea")).toBeFocused();
      await thread.getByRole("button", { name: "Cancel", exact: true }).click();
      await right.getByRole("button", { name: "More options" }).first().click();
      const menu = right.getByRole("menu");
      await expect(menu).toBeVisible();
      const visible = await menu.evaluate(el => {
        const box = el.getBoundingClientRect();
        return box.left >= 0 && box.right <= innerWidth && box.top >= 0 && box.bottom <= innerHeight &&
          el.contains(document.elementFromPoint(box.left + 10, box.top + 10));
      });
      expect(visible).toBe(true);
      await page.screenshot({ path: testInfo.outputPath(`${layout}-menu.png`) });
      await page.keyboard.press("Escape");
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    }
  });
}

test("split comment width changes at a 720px diff container without remounting the draft", async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await installApi(page, pullTarget(), { authenticated: true });
  await page.goto(reviewPath());
  await openNewLineComment(page, 2);
  const editor = page.locator(".inline-comment-editor-row textarea");
  await editor.fill("Keep the caret");
  const original = await editor.elementHandle();
  await editor.evaluate(el => el.setSelectionRange(2, 7, "backward"));
  await expect(page.locator(".review-diff")).toHaveClass(/\bsplit\b/);
  for (const width of [720, 719, 720]) {
    await page.locator(".review-scroll").evaluate((el, width) => { el.style.width = `${width}px`; }, width);
    for (const item of await page.locator(".inline-discussion").all()) {
      await expect.poll(async () => (await item.boundingBox()).width).toBeCloseTo(width === 720 ? 360 : 719, 0);
    }
    expect(await editor.evaluate((el, original) => el === original, original)).toBe(true);
    await expect(editor).toBeFocused();
    expect(await editor.evaluate(el => [el.selectionStart, el.selectionEnd, el.selectionDirection])).toEqual([2, 7, "backward"]);
  }
});

for (const [target, body, operation] of [[commitTarget(), "Existing commit comment", "github.commit.comment.delete"], [pullTarget(), "Existing reply", "github.review.comment.delete"]]) {
  test(`delete ${body}`, async ({ page }) => {
    await installApi(page, target, { authenticated: true, login: body === "Existing reply" ? "author" : "reviewer" });
    await page.goto(reviewPath(target));
    const card = page.locator(".github-comment").filter({ hasText: body });
    await requestCommentDeletion(card);
    await card.getByRole("button", { name: "Confirm delete" }).click();
    await expect(card).toHaveCount(0);
    expect(await page.evaluate(op => window.__fake.calls.filter(c => c.op === op).length, operation)).toBe(1);
  });
}

for (const rate of [1, 6]) for (const layout of ["Split", "Unified"]) {
  test(`comment deletion waits for cancellation commit: ${layout}, ${rate}x CPU`, async ({ page }) => {
    await installApi(page, pullTarget(), { authenticated: true, login: "reviewer" });
    await page.goto(reviewPath());
    await page.getByRole("button", { name: layout, exact: true }).click();
    const card = page.locator(".github-comment").filter({ hasText: "Existing inline comment" });
    await expect(page.locator(".inline-discussion-row").filter({ has: card })).toBeVisible();
    await requestCommentDeletion(card);
    await settleRegions(page);
    const session = await page.context().newCDPSession(page);
    await session.send("Emulation.setCPUThrottlingRate", { rate });
    // Exercise both the cancel helper and a caller that only awaited the click.
    for (const useHelper of [true, false]) {
      const barrier = await holdRegionFrames(page, ["file:src/main.mbt"]);
      let cancellation, reopening, checkpoint;
      try {
        if (useHelper) {
          checkpoint = operationCheckpoint("cancellation must wait for its DOM commit");
          cancellation = checkpoint.track(cancelCommentDeletion(card, checkpoint));
        }
        else await card.getByRole("button", { name: "Cancel deletion", exact: true }).click();
        await barrier.blocked();
        await expect(card.getByRole("button", { name: "Confirm delete", exact: true })).toBeVisible();
        if (cancellation) await checkpoint.expectPending();
        else {
          checkpoint = operationCheckpoint("the old confirmation cannot satisfy a new deletion request");
          reopening = checkpoint.track(requestCommentDeletion(card, checkpoint));
          await checkpoint.expectPending();
          await expect(card.getByRole("menu")).toBeHidden();
        }
        expect(await page.evaluate(() => window.__fake.calls.filter(c => c.op.endsWith(".comment.delete")).length)).toBe(0);
      } finally {
        await barrier.release();
        if (cancellation) await cancellation;
        if (reopening) await reopening;
      }
      if (useHelper) {
        await expect(card.locator(".comment-delete-actions")).toHaveCount(0);
        await requestCommentDeletion(card);
      }
      await settleRegions(page);
    }
    await card.getByRole("button", { name: "Confirm delete", exact: true }).click();
    await expect(card).toHaveCount(0);
    expect(await page.evaluate(() => window.__fake.calls.filter(c => c.op === "github.review.comment.delete").length)).toBe(1);
    await session.send("Emulation.setCPUThrottlingRate", { rate: 1 });
  });
}

for (const layout of ["Split", "Unified"]) {
  test(`comment deletion recovers when source loading moves an open menu inline: ${layout}`, async ({ page }) => {
    const target = commitTarget();
    await installApi(page, target, { authenticated: true, login: "reviewer" });
    const source = await holdNextResponse(page, message => message.op === "github.content.get" && message.args.ref === commitSha);
    await page.goto(reviewPath(target));
    await source.started;
    await page.getByRole("button", { name: layout, exact: true }).click();
    const card = page.locator(".github-comment").filter({ hasText: "Existing commit comment" });
    await expect(page.locator(".file-discussions").filter({ has: card })).toBeVisible();
    let interruptions = 0;
    // Complete loading between opening the fallback menu and clicking Delete.
    await page.addLocatorHandler(card.getByRole("menu"), async () => {
      source.release();
      await source.completed;
      await expect(page.locator(".inline-discussion-row").filter({ has: card })).toBeVisible();
      await expect(card.getByRole("menu")).toBeHidden();
      interruptions += 1;
    }, { times: 1 });
    await requestCommentDeletion(card);
    expect(interruptions).toBe(1);
    expect(await page.evaluate(() => window.__fake.calls.filter(c => c.op === "github.commit.comment.delete").length)).toBe(0);
    await card.getByRole("button", { name: "Confirm delete" }).click();
    await expect(card).toHaveCount(0);
    expect(await page.evaluate(() => window.__fake.calls.filter(c => c.op === "github.commit.comment.delete").length)).toBe(1);
  });
}

test("filtered comments fall back with location, and return inline after filters change", async ({ page }) => {
  await installApi(page, pullTarget(), {
    authenticated: true,
    oldSource: "fn example() {\n  // old comment\n  1\n}",
    newSource: "fn example() {\n  // new comment\n  1\n}",
    patch: "@@ -1,4 +1,4 @@\n fn example() {\n-  // old comment\n+  // new comment\n   1\n }",
  });
  await page.addInitScript(() => { window.__fake.reviewComments[2].original_line = 17; });
  await page.goto(reviewPath());
  await expect(page.locator(".file-discussions").filter({ hasText: "Existing inline comment" })).toContainText("Not shown in current view");
  await expect(page.locator(".outdated-discussions .comment-location")).toContainText("17");
  await page.getByRole("checkbox", { name: "Ignore comments", exact: true }).click();
  await expect(page.locator(".inline-discussion-row").filter({ hasText: "Existing inline comment" })).toHaveCount(1);
  await page.getByRole("button", { name: "Tree", exact: true }).click();
  await page.getByRole("checkbox", { name: "Ignore comments", exact: true }).click();
  await expect(page.locator(".file-discussions").filter({ hasText: "Existing inline comment" })).toContainText("Not shown in current view");
  await page.getByRole("button", { name: "Token", exact: true }).click();
  await page.getByRole("checkbox", { name: "Ignore comments", exact: true }).click();
  await expect(page.locator(".inline-discussion-row").filter({ hasText: "Existing inline comment" })).toHaveCount(1);
});

for (const width of [1440, 420]) for (const colorScheme of ["light", "dark"]) {
  test(`long code soft wraps at ${width}px in ${colorScheme} mode`, async ({ page }) => {
    const oldLine = `  let identifier_${"long".repeat(100)} = "${"a".repeat(400)}"`;
    const newLine = oldLine.replace('= "a', '= "b');
    await installApi(page, pullTarget(), {
      oldSource: `fn main() {\n${oldLine}\n}`,
      newSource: `fn main() {\n${newLine}\n}`,
      patch: `@@ -1,3 +1,3 @@\n fn main() {\n-${oldLine}\n+${newLine}\n }`,
    });
    await page.setViewportSize({ width, height: 900 });
    await page.emulateMedia({ colorScheme });
    await page.goto(reviewPath());
    for (const name of ["Ignore comments", "Ignore tests"]) {
      const toggle = page.getByRole("checkbox", { name, exact: true });
      const control = toggle.locator("..");
      await expect(toggle).toBeChecked();
      for (const state of ["on", "off"]) {
        {
          const prefix = name === "Ignore comments" ? "ignore-comments" : "ignore-tests";
          await expect(control).toHaveText(name);
          await expect(toggle).toBeVisible();
          await expect(control.locator(`.${prefix}-label`)).toBeVisible();
          if (state === "on") {
            await expect(control).toHaveCSS("background-color", "rgb(238, 242, 254)");
            await expect(control).toHaveCSS("color", "rgb(42, 85, 204)");
          } else {
            await expect(control).not.toHaveCSS("background-color", "rgb(238, 242, 254)");
          }
        }
        await toggle.hover();
        for (const side of ["top", "right", "bottom", "left"]) {
          await expect(control).toHaveCSS(`border-${side}-width`, "0px");
        }
        const contrast = await control.evaluate(button => {
          const rgba = value => {
            const channels = value.match(/[\d.]+/g).map(Number);
            // color-mix() backgrounds serialize as normalized color(srgb ...).
            if (value.startsWith("color(srgb ")) return channels.map((v, i) => i < 3 ? v * 255 : v);
            return channels;
          };
          const background = element => {
            if (!element) return [255, 255, 255];
            const color = rgba(getComputedStyle(element).backgroundColor);
            const alpha = color[3] ?? 1;
            if (alpha === 1) return color.slice(0, 3);
            const beneath = background(element.parentElement);
            return color.slice(0, 3).map((v, i) => v * alpha + beneath[i] * (1 - alpha));
          };
          const luminance = values => values.slice(0, 3).map(v => v / 255).map(v => v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4).reduce((sum, v, i) => sum + v * [.2126, .7152, .0722][i], 0);
          const ratio = (a, b) => (Math.max(luminance(a), luminance(b)) + .05) / (Math.min(luminance(a), luminance(b)) + .05);
          const style = getComputedStyle(button);
          return ratio(rgba(style.color), background(button));
        });
        expect(contrast).toBeGreaterThanOrEqual(4.5);
        await toggle.click();
        await expect(toggle).toBeChecked({ checked: state !== "on" });
      }
    }
    for (const layout of ["split", "unified"]) {
      if (layout === "unified") await page.getByRole("button", { name: "Unified" }).click();
      const cell = page.locator(`table.${layout} td.add`).filter({ hasText: "identifier_" });
      await expect(cell).toBeVisible();
      const metrics = await cell.evaluate(cell => ({
        height: cell.getBoundingClientRect().height,
        lineHeight: parseFloat(getComputedStyle(cell).lineHeight),
        width: cell.clientWidth, scroll: cell.scrollWidth,
        tableWidth: cell.closest("table").getBoundingClientRect().width,
        containerWidth: cell.closest(".diff-scroll").clientWidth,
      }));
      expect(metrics.height).toBeGreaterThan(metrics.lineHeight * 2);
      expect(metrics.scroll).toBeLessThanOrEqual(metrics.width);
      expect(metrics.tableWidth).toBeLessThanOrEqual(metrics.containerWidth + 1);
      if (layout === "split") {
        const widths = await page.locator("table.split td.del, table.split td.add").evaluateAll(cells => cells.map(c => c.getBoundingClientRect().width));
        expect(Math.abs(widths[0] - widths[1])).toBeLessThan(1);
      }
    }
  });
}

test("declaration reordering preserves absolute comment lines across algorithms and layouts", async ({ page }) => {
  const oldLines = ["fn alpha() {", "  old_alpha()", "}", "fn beta() {", "  old_beta()", "}"];
  const newLines = ["fn beta() {", "  new_beta()", "}", "fn alpha() {", "  new_alpha()", "}"];
  await installApi(page, pullTarget(), {
    oldSource: oldLines.join("\n"), newSource: newLines.join("\n"),
    patch: "@@ -1,6 +1,6 @@\n" + oldLines.map(s => "-" + s).concat(newLines.map(s => "+" + s)).join("\n"),
  });
  await page.addInitScript(() => {
    const root = window.__fake.reviewComments[0];
    window.__fake.reviewComments = [
      { ...root, line: 5, position: 11, body: "New alpha location" },
      { ...root, id: "45", side: "LEFT", line: 2, position: 2, body: "Old alpha location" },
    ];
  });
  await page.goto(reviewPath());
  for (const algorithm of ["Token", "Tree"]) {
    await page.getByRole("button", { name: algorithm, exact: true }).click();
    for (const layout of ["split", "unified"]) {
      const toggle = page.getByRole("button", { name: layout === "split" ? "Split" : "Unified", exact: true });
      await toggle.click();
      await expect(toggle).toHaveAttribute("aria-pressed", "true");
      await expect(page.locator(`table.${layout}.review-diff`).first()).toBeVisible();
      for (const [body, code] of [["New alpha location", "new_alpha"], ["Old alpha location", "old_alpha"]]) {
        const card = page.locator(".inline-discussion-row").filter({ hasText: body });
        await expect(card).toHaveCount(1);
        await expect.poll(() => card.evaluate(row => {
          let target = row.previousElementSibling;
          while (target?.classList.contains("inline-discussion-row")) target = target.previousElementSibling;
          return target.textContent;
        })).toContain(code);
      }
    }
  }
});

for (const algorithm of ["Token", "Tree"]) {
  test(`Unified ${algorithm} neutral pairs retain both comment anchors, threads and drafts across layouts`, async ({ page }) => {
    const oldLines = ["fn alpha() {", "  call( x) // before", "", "  1", "}", "fn beta() { 0 }"];
    const newLines = ["fn beta() { 2 }", "fn alpha() {", "  call(x) // after", " \t ", "  2", "}"];
    await installApi(page, pullTarget(), {
      authenticated: true,
      oldSource: oldLines.join("\n"), newSource: newLines.join("\n"),
      patch: "@@ -1,6 +1,6 @@\n" + oldLines.map(line => "-" + line).concat(newLines.map(line => "+" + line)).join("\n"),
    });
    await page.addInitScript(() => {
      const root = window.__fake.reviewComments[0];
      window.__fake.reviewComments = [
        { ...root, side: "LEFT", line: 2, position: 2, body: "Old neutral location" },
        { ...root, id: "45", side: "RIGHT", line: 3, position: 9, body: "New neutral location" },
      ];
    });
    await page.goto(reviewPath());
    await page.getByRole("button", { name: algorithm, exact: true }).click();
    await page.getByRole("checkbox", { name: "Ignore comments", exact: true }).check();
    await page.getByRole("button", { name: "Unified", exact: true }).click();
    const file = page.locator("#moondiff-file-0");
    const merged = file.locator("tr.diff-neutral-pair").filter({ hasText: "call(x)" });
    await expect(merged).toHaveCount(1);
    await expect(merged.locator("td.ctx")).toHaveText(newLines[2]);
    await expect(merged.locator(".diff-prefix")).toHaveCount(0);
    await expect(merged.locator(".old-line-number .line-number-value")).toHaveText("2");
    await expect(merged.locator(".new-line-number .line-number-value")).toHaveText("3");
    await expect(merged).toHaveAttribute("data-change-block-start", /\d+/);
    const marker = await merged.getAttribute("data-change-block-start");
    for (const body of ["Old neutral location", "New neutral location"]) {
      const thread = file.locator(".inline-discussion-row").filter({ hasText: body });
      await expect(thread).toHaveCount(1);
      await expect.poll(() => thread.evaluate(row => {
        let source = row.previousElementSibling;
        while (source?.classList.contains("inline-discussion-row")) source = source.previousElementSibling;
        return source.classList.contains("diff-neutral-pair");
      })).toBe(true);
    }
    for (const [side, line] of [["old", 2], ["new", 3]]) {
      await clickLineCommentButton(merged.locator(`.${side}-line-number`).getByRole("button", {
        name: `Comment on line ${line}`, exact: true,
      }));
      const editor = file.locator(".inline-comment-editor-row textarea");
      const draft = `Draft on ${side} neutral line`;
      await expect(editor).toBeFocused();
      await editor.fill(draft);
      const draftId = await editor.getAttribute("data-draft-id");
      for (const layout of ["Split", "Unified"]) {
        await page.getByRole("button", { name: layout, exact: true }).click();
        await expect(file.locator(`table.${layout.toLowerCase()}`).first()).toBeVisible();
        await expect(editor).toHaveValue(draft);
        await expect(editor).toHaveAttribute("data-draft-id", draftId);
        const row = file.locator(".inline-comment-editor-row");
        await expect(row.locator(".comment-location")).toHaveText(`src/main.mbt · ${side === "old" ? "Old" : "New"} · ${line}`);
        for (const body of ["Old neutral location", "New neutral location"]) {
          await expect(file.locator(".inline-discussion-row").filter({ hasText: body })).toHaveCount(1);
        }
      }
      await file.locator(".inline-comment-editor-row").getByRole("button", { name: "Cancel", exact: true }).click();
      await expect(editor).toHaveCount(0);
      await expect(merged).toHaveAttribute("data-change-block-start", marker);
    }
  });
}

test("comments without a matching file stay in the overall discussion", async ({ page }) => {
  await installApi(page, commitTarget());
  await page.addInitScript(() => {
    // The worker protocol omits GitHub null fields before decoding in MoonBit.
    delete window.__fake.commitComments[0].path;
    delete window.__fake.commitComments[0].position;
  });
  await page.goto(reviewPath(commitTarget()));
  await expect(page.locator(".comments-overview").getByText("Existing commit comment")).toHaveCount(1);
});

test("filter choices reset on reload and a collapsed file keeps its draft in discussion", async ({ page }) => {
  await installApi(page, pullTarget(), { authenticated: true });
  await page.goto(reviewPath());
  await openNewLineComment(page, 2);
  await page.locator(".inline-comment-editor-row textarea").fill("Preserved draft");
  await page.getByRole("button", { name: "Collapse src/main.mbt", exact: true }).click();
  await expect(page.locator(".file-discussions textarea")).toHaveValue("Preserved draft");
  await expect(page.locator(".file-discussions").filter({ hasText: "Existing inline comment" })).toContainText("Not shown in current view");
  await page.getByRole("button", { name: "Expand src/main.mbt", exact: true }).click();
  await expect(page.locator(".inline-comment-editor-row textarea")).toHaveValue("Preserved draft");
  for (const name of ["Ignore comments", "Ignore tests"]) {
    await page.getByRole("checkbox", { name, exact: true }).click();
    await expect(page.getByRole("checkbox", { name, exact: true })).not.toBeChecked();
  }
  expect(page.url()).not.toContain("ignore");
  await page.reload();
  for (const name of ["Ignore comments", "Ignore tests"]) await expect(page.getByRole("checkbox", { name, exact: true })).toBeChecked();
});

test("expired credentials during deletion keep the card and offer sign-in", async ({ page }) => {
  await installApi(page, pullTarget(), { authenticated: true, login: "reviewer" });
  await page.goto(reviewPath());
  const card = page.locator(".github-comment").filter({ hasText: "Existing overall comment" });
  await requestCommentDeletion(card);
  await page.evaluate(() => window.__fake.authenticationFailureOps.push("github.issue.comment.delete"));
  await card.getByRole("button", { name: "Confirm delete" }).click();
  await expect(card.locator(".comment-error")).toContainText("请求已中断");
  await expect(page.locator(".auth-controls.error")).toContainText("GitHub session expired");
  await expect(page.getByRole("button", { name: "Try sign-in", exact: true })).toBeVisible();
  await expect(card.locator(".comment-delete")).toHaveCount(0);
  await expect(card).toBeVisible();
});


test("shared toolbar controls fit desktop and narrow screens in both themes", async ({ page }) => {
  await installApi(page, pullTarget());
  await page.goto(reviewPath());
  await expect(page.locator("table.split").first()).toBeVisible();
  await checkToolbar(page);
});

for (const external of [false, true]) {
  test(`reply draft survives ${external ? "external root deletion" : "blocked deletion"} across layouts`, async ({ page }) => {
    await installApi(page, pullTarget(), { authenticated: true, login: "reviewer" });
    await page.goto(reviewPath());
    const thread = page.locator(".review-thread").filter({ hasText: "Existing inline comment" });
    const own = thread.locator(".github-comment").filter({ hasText: "Existing inline comment" });
    await requestCommentDeletion(own);
    await thread.getByRole("button", { name: "Reply", exact: true }).click();
    await expect(own.getByRole("button", { name: "Confirm delete", exact: true })).toBeDisabled();
    await thread.locator("textarea").fill("Preserve this reply");
    if (external) {
      await page.evaluate(() => { window.__fake.reviewComments = window.__fake.reviewComments.filter(c => String(c.id) !== "20"); });
      await page.getByRole("button", { name: "Refresh", exact: true }).click();
      await expect(page.locator(".unavailable-reply-draft")).toBeVisible();
    }
    for (const algorithm of ["Token", "Tree"]) {
      await page.getByRole("button", { name: algorithm, exact: true }).click();
      for (const layout of ["Split", "Unified"]) {
        await page.getByRole("button", { name: layout, exact: true }).click();
        await expect(page.locator(".comment-editor")).toHaveCount(1);
        await expect(page.locator(".comment-editor textarea")).toHaveValue("Preserve this reply");
        if (external) {
          await expect(page.locator(".comment-editor textarea")).toBeEnabled();
          await expect(page.locator(".comment-editor").getByRole("button", { name: "Post comment" })).toBeDisabled();
          await expect(page.locator(".review-thread").filter({ hasText: "Existing reply" }).getByRole("button", { name: "Reply", exact: true })).toBeDisabled();
          await page.locator(".comment-editor textarea").evaluate(el => el.select());
          expect(await page.locator(".comment-editor textarea").evaluate(el => el.value.slice(el.selectionStart, el.selectionEnd))).toBe("Preserve this reply");
        }
      }
    }
    expect(await page.evaluate(() => window.__fake.calls.filter(c => c.op.endsWith(".delete") || c.op === "github.review.reply.create").length)).toBe(0);
    await page.locator(".comment-editor").getByRole("button", { name: "Cancel", exact: true }).click();
    await expect(page.locator(".comment-editor")).toHaveCount(0);
    if (!external) {
      await own.getByRole("button", { name: "Confirm delete", exact: true }).click();
      await expect(own).toHaveCount(0);
      await expect(page.locator(".review-thread").filter({ hasText: "Existing reply" }).getByRole("button", { name: "Reply", exact: true })).toBeDisabled();
    }
  });
}

test("one draft survives repeated clicks and every entry switch while posting", async ({ page }) => {
  await installApi(page, pullTarget(), { authenticated: true });
  await page.goto(reviewPath());
  await waitForSignedInComments(page);
  await page.getByRole("button", { name: "Add overall comment" }).click();
  const overallEditor = page.locator(".overall-comments textarea");
  await overallEditor.fill("Keep the overall draft");
  const overallDraftId = await overallEditor.getAttribute("data-draft-id");
  await newLineCommentGutter(page, 2).hover();
  await expect(newLineCommentButton(page, 2)).toBeDisabled();
  await expect(clickLineCommentButton(newLineCommentButton(page, 2))).rejects.toThrow(/not enabled/);
  await expect(page.locator(".comment-editor")).toHaveCount(1);
  await expect(overallEditor).toHaveAttribute("data-draft-id", overallDraftId);
  await expect(overallEditor).toHaveValue("Keep the overall draft");
  await expect(page.getByRole("button", { name: "Reply", exact: true }).first()).toBeDisabled();
  await page.getByRole("button", { name: "Cancel", exact: true }).click();
  await openNewLineComment(page, 2);
  await page.locator(".comment-editor textarea").fill("Do not lose this draft");
  const inlineDraftId = await page.locator(".comment-editor textarea").getAttribute("data-draft-id");
  await page.evaluate(() => {
    const state = window.__fake;
    state.reviewComments.push({ ...state.reviewComments[0], id: "99", body: "Draft refresh comment", line: 1, position: 1 });
    state.delayNextList = true;
  });
  await reactivatePage(page);
  await expect.poll(() => page.evaluate(() => typeof window.__fake.releaseList)).toBe("function");
  await page.evaluate(() => window.__fake.releaseList());
  await expect(page.getByText("Draft refresh comment", { exact: true })).toBeVisible();
  await expect(page.getByRole("button", { name: "Refresh", exact: true })).toBeEnabled();
  await settleRegions(page);
  await openNewLineComment(page, 2);
  await openNewLineComment(page, 2);
  await expect(page.locator(".comment-editor")).toHaveCount(1);
  await expect(page.locator(".comment-editor textarea")).toHaveAttribute("data-draft-id", inlineDraftId);
  await expect(page.locator(".comment-editor textarea")).toHaveValue("Do not lose this draft");
  await expect(page.getByRole("button", { name: "Add overall comment" })).toBeDisabled();
  await expect(page.getByRole("button", { name: "Reply", exact: true }).first()).toBeDisabled();
  await expect(page.locator(".inline-comment-editor-row textarea")).toHaveValue("Do not lose this draft");
  await page.evaluate(() => { window.__fake.delayCreate = true; });
  await page.getByRole("button", { name: "Post comment", exact: true }).click();
  await expect.poll(() => page.evaluate(() => typeof window.__fake.releaseCreate)).toBe("function");
  await expect(page.getByRole("button", { name: "Add overall comment" })).toBeDisabled();
  await expect(page.getByRole("button", { name: "Reply", exact: true }).first()).toBeDisabled();
  await expect(page.locator(".line-comment-button").first()).toBeDisabled();
  await page.evaluate(() => window.__fake.releaseCreate());
  await expect(page.getByText("Do not lose this draft", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Reply", exact: true }).first().click();
  await page.locator(".review-thread textarea").fill("Reply draft");
  const activeThread = page.locator(".review-thread").filter({ has: page.locator("textarea") });
  await expect(activeThread.getByRole("button", { name: "Reply", exact: true })).toHaveCount(0);
  for (const entry of await page.getByRole("button", { name: "Reply", exact: true }).all()) {
    await expect(entry).toBeDisabled();
  }
  await expect(page.locator(".review-thread textarea")).toHaveValue("Reply draft");
});

test("a base update during refresh preserves verified comments and the collapsed draft", async ({ page }) => {
  await installApi(page, pullTarget(), { authenticated: true });
  await page.goto(reviewPath());
  await waitForSignedInComments(page);
  await openNewLineComment(page, 2);
  await page.locator(".comment-editor textarea").fill("Old snapshot draft");
  const before = await page.evaluate(() => window.__fake.calls.filter(c => c.op === "github.pull.files").length);
  await page.evaluate(() => {
    window.__fake.updateDuringList = true;
    window.__fake.reviewComments[0].body = "Unverified replacement";
  });
  await page.getByRole("button", { name: "Refresh", exact: true }).click();
  await expect(page.locator(".snapshot-stale")).toBeVisible();
  await expect(page.getByText("Existing inline comment", { exact: true })).toBeVisible();
  await expect(page.getByText("Unverified replacement", { exact: true })).toHaveCount(0);
  expect(await page.evaluate(() => window.__fake.calls.filter(c => c.op === "github.pull.files").length)).toBe(before);
  await page.getByRole("button", { name: "Unified", exact: true }).click();
  await expect(page.locator(".comment-editor textarea")).toHaveValue("Old snapshot draft");
  await page.getByRole("button", { name: "Collapse src/main.mbt", exact: true }).click();
  await expect(page.locator(".file-discussions textarea")).toHaveValue("Old snapshot draft");
  await expect(page.getByRole("button", { name: "Post comment", exact: true })).toBeDisabled();
  await expect(page.getByRole("button", { name: "Load latest" })).toBeDisabled();
  await page.getByRole("button", { name: "Cancel", exact: true }).click();
  await page.getByRole("button", { name: "Load latest" }).click();
  await expect(page.locator(".snapshot-stale")).toHaveCount(0);
  await expect(page.getByText("Unverified replacement", { exact: true })).toBeVisible();
});

test("first comment list is withheld if the PR updates after diff validation", async ({ page }) => {
  await installApi(page, pullTarget(), { authenticated: true, updateDuringFirstList: true });
  await page.goto(reviewPath());
  await expect(page.locator(".snapshot-stale")).toBeVisible();
  await expect(page.getByText("Existing inline comment", { exact: true })).toHaveCount(0);
  const ops = await page.evaluate(() => window.__fake.calls.map(c => c.op));
  const firstList = ops.indexOf("github.comments.list");
  expect(ops.slice(0, firstList).filter(op => op === "github.pull.get").length).toBe(3);
  await page.getByRole("button", { name: "Load latest" }).click();
  await expect(page.getByText("Existing inline comment", { exact: true })).toBeVisible();
  await expect(page.locator(".snapshot-stale")).toHaveCount(0);
});

test("late list cannot replace a newer verified refresh", async ({ page }) => {
  await installApi(page, pullTarget(), { authenticated: true });
  await page.goto(reviewPath());
  await waitForSignedInComments(page);
  await page.evaluate(() => { window.__fake.delayNextList = true; });
  await page.getByRole("button", { name: "Refresh", exact: true }).click();
  await expect.poll(() => page.evaluate(() => typeof window.__fake.releaseList)).toBe("function");
  await page.evaluate(() => { window.__fake.reviewComments[0].body = "Newest verified comment"; });
  await reactivatePage(page);
  await expect(page.getByText("Newest verified comment", { exact: true })).toBeVisible();
  await page.evaluate(() => window.__fake.releaseList());
  await expect(page.getByRole("button", { name: "Refresh", exact: true })).toBeEnabled();
  await expect(page.getByText("Newest verified comment", { exact: true })).toBeVisible();
  await expect(page.getByText("Existing inline comment", { exact: true })).toHaveCount(0);
});

for (const kind of ["inline", "reply"]) {
  test(`${kind} stays Posting through the delayed list and final validation`, async ({ page }) => {
    await installApi(page, pullTarget(), { authenticated: true });
    await page.goto(reviewPath());
    await waitForSignedInComments(page);
    if (kind === "inline") await openNewLineComment(page, 2);
    else await page.getByRole("button", { name: "Reply", exact: true }).first().click();
    const body = `${kind} remains visible until GitHub synchronization finishes`;
    const editor = page.locator(".comment-editor textarea");
    await editor.fill(body);
    const draftId = await editor.getAttribute("data-draft-id");
    await editor.evaluate(node => { window.__postingEditor = node; });
    await page.evaluate(() => { window.__fake.delayCreate = true; });
    await page.getByRole("button", { name: "Post comment", exact: true }).click();
    await expect.poll(() => page.evaluate(() => typeof window.__fake.releaseCreate)).toBe("function");
    await page.evaluate(() => {
      window.__fake.delayNextList = true;
      window.__fake.releaseCreate();
    });
    await expect.poll(() => page.evaluate(() => typeof window.__fake.releaseList)).toBe("function");

    const file = page.locator("#moondiff-file-0");
    const formal = file.locator(".github-comment-body").filter({ hasText: body });
    async function expectPosting() {
      await expect(page.locator(".comment-editor")).toHaveCount(1);
      await expect(editor).toHaveAttribute("data-draft-id", draftId);
      await expect(editor).toHaveValue(body);
      await expect(editor).toBeDisabled();
      expect(await editor.evaluate(node => node === window.__postingEditor)).toBe(true);
      await expect(page.getByRole("button", { name: "Posting…", exact: true })).toBeDisabled();
      await expect(page.getByRole("button", { name: "Cancel", exact: true })).toBeDisabled();
      await expect(page.getByRole("button", { name: "Add overall comment" })).toBeDisabled();
      await expect(page.locator(".line-comment-button").first()).toBeDisabled();
      await expect(page.locator(".pending-review-receipt")).toHaveCount(0);
      await expect(page.locator(".comment-notice")).toHaveCount(0);
      await expect(formal).toHaveCount(0);
    }
    await expectPosting();
    await page.evaluate(body => {
      const file = document.querySelector("#moondiff-file-0");
      const frames = [];
      const record = () => frames.push({
        editor: file.querySelectorAll(".comment-editor").length,
        formal: [...file.querySelectorAll(".github-comment-body")]
          .filter(node => node.textContent === body).length,
      });
      const observer = new MutationObserver(record);
      observer.observe(file, { childList: true, subtree: true, characterData: true });
      record();
      window.__postingSwap = { frames, observer, record };
      const dispatch = window.__dispatch;
      window.__dispatch = async message => {
        if (message.op === "github.pull.get") {
          await new Promise(resolve => { window.__fake.releaseValidation = resolve; });
        }
        return dispatch(message);
      };
      window.__fake.releaseList();
    }, body);
    await expect.poll(() => page.evaluate(() => typeof window.__fake.releaseValidation)).toBe("function");
    await expectPosting();
    await page.evaluate(() => window.__fake.releaseValidation());
    await expect(formal).toBeVisible();
    await expect(editor).toHaveCount(0);
    await expect(page.locator(".comment-notice")).toHaveText("Comment published.");
    await expect(page.getByRole("button", { name: "Add overall comment" })).toBeEnabled();
    const frames = await page.evaluate(() => {
      window.__postingSwap.record();
      window.__postingSwap.observer.disconnect();
      return window.__postingSwap.frames;
    });
    expect(frames.every(frame => frame.editor + frame.formal === 1)).toBe(true);
    expect(await page.evaluate(kind => window.__fake.calls.filter(c =>
      c.op === (kind === "inline" ? "github.review.comment.create" : "github.review.reply.create")
    ).length, kind)).toBe(1);
  });
}

test("failed review synchronization retains Posting and retries without reposting", async ({ page }) => {
  await installApi(page, pullTarget(), { authenticated: true });
  await page.goto(reviewPath());
  await waitForSignedInComments(page);
  await openNewLineComment(page, 2);
  const body = "Published before synchronization failed";
  const editor = page.locator(".comment-editor");
  await editor.locator("textarea").fill(body);
  await page.evaluate(() => {
    const dispatch = window.__dispatch;
    window.__dispatch = async message => {
      if (message.op === "github.comments.list" && window.__fake.failSync) {
        throw Object.assign(new Error("Sync unavailable"), { status: 503 });
      }
      const result = await dispatch(message);
      if (message.op === "github.review.comment.create") window.__fake.failSync = true;
      return result;
    };
  });
  await editor.getByRole("button", { name: "Post comment", exact: true }).click();
  await expect(editor.locator(".comment-error"))
    .toHaveText("Comment published, but syncing failed. Refresh to retry.");
  await expect(editor.locator("textarea")).toHaveValue(body);
  await expect(editor.locator("textarea")).toBeDisabled();
  await expect(editor.getByRole("button", { name: "Posting…", exact: true })).toBeDisabled();
  await expect(editor.getByRole("button", { name: "Cancel", exact: true })).toBeDisabled();
  await page.evaluate(() => { window.__fake.failSync = false; });
  await page.getByRole("button", { name: "Refresh", exact: true }).click();
  await expect(page.locator(".github-comment-body").filter({ hasText: body })).toBeVisible();
  await expect(editor).toHaveCount(0);
  expect(await page.evaluate(() => window.__fake.calls.filter(c => c.op === "github.review.comment.create").length)).toBe(1);
});

test("Posting root preserves replies across collapse, layouts, refresh and root restoration", async ({ page }) => {
  await installApi(page, pullTarget(), { authenticated: true });
  await page.goto(reviewPath());
  await waitForSignedInComments(page);
  const body = "Root missing before its first verified list";
  const replies = ["First reply to the missing root", "Second reply to the missing root"];
  await page.evaluate(replies => {
    const dispatch = window.__dispatch;
    window.__dispatch = async message => {
      const result = await dispatch(message);
      if (message.op === "github.review.comment.create") {
        const state = window.__fake;
        state.missingRoot = result;
        state.reviewComments = state.reviewComments.filter(c => c.id !== result.id);
        state.reviewComments.push(...replies.map((body, index) => ({
          ...result, id: String(25 + index), body,
          html_url: `https://github.com/comment/${25 + index}`,
          in_reply_to_id: result.id,
        })));
        state.delayNextList = true;
      }
      return result;
    };
  }, replies);
  await openNewLineComment(page, 2);
  await page.locator(".inline-comment-editor-row textarea").fill(body);
  await page.locator(".inline-comment-editor-row").getByRole("button", { name: "Post comment" }).click();
  await expect.poll(() => page.evaluate(() => typeof window.__fake.releaseList)).toBe("function");
  await expect(page.getByRole("button", { name: "Posting…", exact: true })).toBeDisabled();
  await page.evaluate(() => window.__fake.releaseList());

  const file = page.locator("#moondiff-file-0");
  const thread = page.locator(".review-thread").filter({ hasText: replies[0] });
  async function expectPendingThread() {
    await expect(thread).toHaveCount(1);
    await expect(thread).toBeVisible();
    await expect(thread.locator(".github-comment-body")).toHaveText(replies);
    await expect(page.locator(".pending-review-receipt")).toHaveCount(0);
    await expect(page.locator(".comment-editor")).toHaveCount(1);
    await expect(page.locator(".comment-editor textarea")).toHaveValue(body);
    await expect(page.locator(".comment-editor textarea")).toBeDisabled();
    await expect(page.getByRole("button", { name: "Posting…", exact: true })).toBeDisabled();
    await expect(page.locator(".comment-editor .comment-error"))
      .toHaveText("Waiting for GitHub to sync this comment. Refresh to retry.");
  }
  for (const layout of ["Split", "Unified"]) {
    await page.getByRole("button", { name: layout, exact: true }).click();
    await expectPendingThread();
    await expect(file.locator(".inline-discussion-row").filter({ hasText: replies[0] })).toHaveCount(1);
    await page.getByRole("button", { name: "Collapse src/main.mbt", exact: true }).click();
    await expectPendingThread();
    await expect(page.locator(".file-discussions").filter({ hasText: replies[0] }))
      .toContainText("Not shown in current view");
    const lists = await page.evaluate(() => window.__fake.commentListCalls);
    await page.getByRole("button", { name: "Refresh", exact: true }).click();
    await expect.poll(() => page.evaluate(() => window.__fake.commentListCalls)).toBeGreaterThan(lists);
    await expectPendingThread();
    await page.getByRole("button", { name: "Expand src/main.mbt", exact: true }).click();
    await expectPendingThread();
    await expect(file.locator(".inline-discussion-row").filter({ hasText: replies[0] })).toHaveCount(1);
  }
  await page.evaluate(() => window.__fake.reviewComments.push(window.__fake.missingRoot));
  await page.getByRole("button", { name: "Refresh", exact: true }).click();
  await expect(thread.locator(".github-comment-body")).toHaveText([body, ...replies]);
  await expect(page.locator(".pending-review-receipt")).toHaveCount(0);
  await expect(thread).toHaveCount(1);
  await expect(thread).toBeVisible();
});

test("line creation after a PR update stays Posting and allows loading the latest snapshot", async ({ page }) => {
  await installApi(page, pullTarget(), { authenticated: true });
  await page.goto(reviewPath());
  await waitForSignedInComments(page);
  await openNewLineComment(page, 2);
  await page.locator(".comment-editor textarea").fill("Published on the old snapshot");
  await page.evaluate(() => { window.__fake.delayCreate = true; });
  await page.getByRole("button", { name: "Post comment", exact: true }).click();
  await expect.poll(() => page.evaluate(() => typeof window.__fake.releaseCreate)).toBe("function");
  await page.evaluate(value => { window.__fake.currentHead = value; }, changedHead);
  await page.getByRole("button", { name: "Refresh", exact: true }).click();
  await expect(page.locator(".snapshot-stale")).toBeVisible();
  await expect(page.getByRole("button", { name: "Load latest" })).toBeDisabled();
  await page.evaluate(() => window.__fake.releaseCreate());
  await expect(page.locator(".published-comment-link")).toBeVisible();
  await expect(page.locator(".comment-notice")).toHaveCount(0);
  await expect(page.locator(".pending-review-receipt")).toHaveCount(0);
  const editor = page.locator("#moondiff-file-0 .comment-editor");
  await expect(editor.locator("textarea")).toHaveValue("Published on the old snapshot");
  await expect(editor.locator("textarea")).toBeDisabled();
  await expect(editor.getByRole("button", { name: "Posting…", exact: true })).toBeDisabled();
  await expect(editor.locator(".comment-error"))
    .toHaveText("Comment published. PR updated. Load latest to see it.");
  await expect(page.getByRole("button", { name: "Load latest" })).toBeEnabled();
  await page.getByRole("button", { name: "Load latest" }).click();
  await expect(editor).toHaveCount(0);
  await expect(page.getByText("Published on the old snapshot", { exact: true })).toBeVisible();
});

test("manual snapshot loading waits for root deletion across layout changes", async ({ page }) => {
  await installApi(page, pullTarget(), { authenticated: true, login: "reviewer" });
  await page.goto(reviewPath());
  await expect(page.getByText("Existing inline comment", { exact: true })).toBeVisible();
  await page.evaluate(() => { window.__fake.updateDuringList = true; });
  await page.getByRole("button", { name: "Refresh", exact: true }).click();
  await expect(page.locator(".snapshot-stale")).toBeVisible();
  await page.evaluate(() => { window.__fake.deleteDelay = true; });
  const root = page.locator(".github-comment").filter({ hasText: "Existing inline comment" });
  await requestCommentDeletion(root);
  await root.getByRole("button", { name: "Confirm delete", exact: true }).click();
  await expect.poll(() => page.evaluate(() => typeof window.__fake.releaseDelete)).toBe("function");
  await expect(page.getByRole("button", { name: "Load latest" })).toBeDisabled();
  await page.getByRole("button", { name: "Unified", exact: true }).click();
  await page.evaluate(() => window.__fake.releaseDelete());
  await expect(page.getByText("Existing inline comment", { exact: true })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Load latest" })).toBeEnabled();
});


for (const kind of ["pull", "commit"]) {
  for (const layout of ["Split", "Unified"]) {
    for (const change of ["unchanged", "add same", "delete same", "add earlier", "delete earlier"]) {
      test(`inline draft retains DOM focus and selection after ${kind} ${layout} refresh: ${change}`, async ({ page }) => {
        const target = kind === "pull" ? pullTarget() : commitTarget();
        await installApi(page, target, { authenticated: true });
        await page.addInitScript(({ kind, change }) => {
          const field = kind === "pull" ? "reviewComments" : "commitComments";
          const template = window.__fake[field][0];
          const line = change.endsWith("earlier") ? 1 : 2;
          window.__refreshComment = {
            ...template, id: "99", body: "Refresh regression comment",
            line, position: line === 1 ? 1 : 3,
          };
          if (change.startsWith("delete")) window.__fake[field].push(window.__refreshComment);
        }, { kind, change });
        await page.goto(reviewPath(target));
        await waitForSignedInComments(page);
        await page.getByRole("button", { name: layout, exact: true }).click();
        await openNewLineComment(page, 2);
        const textarea = page.locator(".inline-comment-editor-row textarea");
        const original = await textarea.elementHandle();
        const body = "Keep this draft editable";
        await textarea.fill(body);
        // Exercise both a nonterminal caret and a backwards selection.
        const start = 5;
        const end = change === "unchanged" ? start : 9;
        const direction = end === start ? "forward" : "backward";
        await textarea.evaluate((el, { start, end, direction }) => {
          el.setSelectionRange(start, end, direction);
        }, { start, end, direction });
        await page.evaluate(({ kind, change }) => {
          const state = window.__fake;
          const field = kind === "pull" ? "reviewComments" : "commitComments";
          if (change.startsWith("add")) state[field].push(window.__refreshComment);
          if (change.startsWith("delete")) state[field] = state[field].filter(c => c.id !== "99");
          state.delayNextList = true;
        }, { kind, change });
        const calls = await page.evaluate(() => window.__fake.commentListCalls);
        await reactivatePage(page);
        await expect.poll(() => page.evaluate(() => typeof window.__fake.releaseList)).toBe("function");
        await expect(page.getByRole("button", { name: "Refresh", exact: true })).toBeDisabled();
        await page.evaluate(() => window.__fake.releaseList());
        await expect(page.getByRole("button", { name: "Refresh", exact: true })).toBeEnabled();
        expect(await page.evaluate(() => window.__fake.commentListCalls)).toBeGreaterThan(calls);
        await expect(page.getByText("Refresh regression comment", { exact: true }))
          .toHaveCount(change.startsWith("add") ? 1 : 0);
        expect(await textarea.evaluate((el, original) => el === original, original)).toBe(true);
        await expect(textarea).toBeFocused();
        await expect(textarea).toHaveValue(body);
        expect(await textarea.evaluate(el => [el.selectionStart, el.selectionEnd, el.selectionDirection]))
          .toEqual([start, end, direction]);
        await page.keyboard.type("INSERT");
        await expect(textarea).toHaveValue(body.slice(0, start) + "INSERT" + body.slice(end));
        await expect(textarea).toBeFocused();
        await expect(page.locator(".inline-comment-editor-row")).toHaveCount(1);
        expect(await textarea.evaluate(el => {
          const row = el.closest("tr");
          let previous = row.previousElementSibling;
          if (!previous?.classList.contains("inline-discussion-row")) return false;
          while (previous?.classList.contains("inline-discussion-row")) previous = previous.previousElementSibling;
          return previous?.classList.contains("comment-target");
        })).toBe(true);
      });
    }
  }
}

for (const layout of ["Split", "Unified"]) {
  for (const cancelled of [false, true]) {
    test(`inline draft survives ${cancelled ? "cancelled" : "active"} reading recovery: ${layout}`, async ({ page }) => {
      await page.setViewportSize({ width: 1440, height: 900 });
      await installRenderProbe(page);
      const oldLines = ["fn main() {", ...Array.from({ length: 80 }, (_, i) => `  let value_${i} = ${i}`), "}"];
      const newLines = ["fn main() {", ...Array.from({ length: 80 }, (_, i) => `  let value_${i} = ${i + 1}`), "}"];
      await installApi(page, pullTarget(), {
        authenticated: true,
        oldSource: oldLines.join("\n"), newSource: newLines.join("\n"),
        patch: `@@ -1,${oldLines.length} +1,${newLines.length} @@\n` +
          oldLines.map(line => "-" + line).concat(newLines.map(line => "+" + line)).join("\n"),
      });
      await page.goto(reviewPath());
      await waitForSignedInComments(page);
      await page.getByRole("button", { name: layout, exact: true }).click();
      await openNewLineComment(page, 40);
      const editor = page.locator(".inline-comment-editor-row textarea");
      const original = await editor.elementHandle();
      const body = "Keep this draft and its reading position";
      await editor.fill(body);
      const draftId = await editor.getAttribute("data-draft-id");
      const selection = await editor.evaluate(el => {
        el.setSelectionRange(5, 14, "backward");
        return [el.selectionStart, el.selectionEnd, el.selectionDirection];
      });
      await expect(editor).toBeFocused();
      const anchor = page.locator(`#moondiff-file-0 table.${layout.toLowerCase()}:visible tr[data-reading-row]`).filter({
        has: page.locator(".new-line-number .line-number-value", { hasText: /^35$/ }),
      });
      await anchor.evaluate(el => {
        document.documentElement.style.setProperty("overflow-anchor", "none", "important");
        el.scrollIntoView({ block: "start" });
      });
      await settleRegions(page);
      // Use the measured sticky headers so the requested row is the first
      // unobscured source row in either layout.
      await anchor.evaluate(el => {
        const headings = [
          document.querySelector(".hero-workspace"),
          document.querySelector(".change-titlebar"),
          el.closest(".file-card").querySelector(".file-heading"),
          el.closest(".semantic-section")?.querySelector(".semantic-section-title"),
        ].filter(Boolean);
        const edge = Math.max(...headings.map(heading => heading.getBoundingClientRect().bottom));
        window.scrollBy(0, el.getBoundingClientRect().top - edge - 1);
      });
      await settleRegions(page);
      const readingRow = await anchor.getAttribute("data-reading-row");
      await page.evaluate(position => {
        const state = window.__fake;
        state.reviewComments.push({
          ...state.reviewComments[0], id: "99", body: "Reading recovery insertion", line: 1, position,
        });
        state.delayNextList = true;
      }, oldLines.length + 1);
      await reactivatePage(page);
      await expect.poll(() => page.evaluate(() => typeof window.__fake.releaseList)).toBe("function");
      await expect.poll(() => page.evaluate(() => __moondiffMetrics.reading)).toMatchObject({
        active: true, listening: true, metadata: true, row: readingRow,
      });
      await expect(page.getByRole("button", { name: "Refresh", exact: true })).toBeDisabled();
      await settleRegions(page);
      if (cancelled) {
        const reading = await page.evaluate(() => {
          dispatchEvent(new Event("pointerdown", { bubbles: true }));
          return { ...__moondiffMetrics.reading };
        });
        expect(reading).toMatchObject({ active: false, listening: false, frame: 0 });
      }
      await expect(page.locator("html")).toHaveCSS("overflow-anchor", "none");
      const measure = el => ({
        top: el.getBoundingClientRect().top,
        rowHeight: el.getBoundingClientRect().height,
        scroll: scrollY,
        documentHeight: document.documentElement.scrollHeight,
        compensated: __moondiffMetrics.counters?.reading_compensated ?? 0,
      });
      const before = await anchor.evaluate(measure);
      expect(before.scroll).toBeGreaterThan(0);
      await page.evaluate(() => window.__fake.releaseList());
      await expect(page.getByText("Reading recovery insertion", { exact: true })).toBeVisible();
      await expect(page.getByRole("button", { name: "Refresh", exact: true })).toBeEnabled();
      await expect.poll(() => page.evaluate(() => __moondiffMetrics.reading)).toMatchObject({
        active: false, metadata: false, listening: false, frame: 0,
      });
      await settleRegions(page);
      const after = await anchor.evaluate(measure);
      const growth = after.documentHeight - before.documentHeight;
      const displacement = after.top - before.top;
      const scrollDelta = after.scroll - before.scroll;
      expect(growth).toBeGreaterThan(before.rowHeight);
      if (cancelled) {
        expect(displacement).toBeGreaterThan(before.rowHeight);
        expect(Math.abs(displacement - growth)).toBeLessThan(2);
        expect(Math.abs(scrollDelta)).toBeLessThan(2);
        expect(after.compensated).toBe(before.compensated);
      } else {
        expect(Math.abs(displacement)).toBeLessThan(2);
        expect(scrollDelta).toBeGreaterThan(before.rowHeight);
        expect(Math.abs(scrollDelta - growth)).toBeLessThan(2);
        expect(after.compensated).toBeGreaterThan(before.compensated);
      }
      await expect(page.locator(".comment-editor")).toHaveCount(1);
      expect(await editor.evaluate((el, original) => el === original, original)).toBe(true);
      await expect(editor).toHaveAttribute("data-draft-id", draftId);
      await expect(editor).toHaveValue(body);
      await expect(editor).toBeFocused();
      expect(await editor.evaluate(el => [el.selectionStart, el.selectionEnd, el.selectionDirection])).toEqual(selection);
    });
  }
}

for (const kind of ["overall", "reply", "inline", "collapsed"]) {
  for (const direction of ["forward", "backward"]) {
    test(`${kind} editor keeps its DOM and ${direction} selection during background insert/remove and composition`, async ({ page }) => {
      await installApi(page, pullTarget(), { authenticated: true });
      await page.goto(reviewPath());
      await waitForSignedInComments(page);
      if (kind === "overall") await page.getByRole("button", { name: "Add overall comment" }).click();
      else if (kind === "reply") await page.locator(".review-thread").filter({ hasText: "Existing inline comment" }).getByRole("button", { name: "Reply", exact: true }).click();
      else {
        await openNewLineComment(page, 2);
        if (kind === "collapsed") {
          await page.getByRole("button", { name: "Collapse src/main.mbt", exact: true }).click();
          await expect(page.locator(".file-discussions textarea")).toBeVisible();
        }
      }
      const editor = page.locator(".comment-editor textarea");
      await editor.fill("Keep composing text");
      await expect(editor).toHaveValue("Keep composing text");
      await expect(editor).toBeFocused();
      const original = await editor.elementHandle();
      await editor.evaluate((el, direction) => {
        el.setSelectionRange(5, 14, direction);
        el.dispatchEvent(new CompositionEvent("compositionstart", { bubbles: true, data: "文" }));
      }, direction);
      for (const insert of [true, false]) {
        await page.evaluate(({ insert, kind }) => {
          const s = window.__fake;
          const field = kind === "overall" ? "issueComments" : "reviewComments";
          if (insert) {
            const template = s[field][0];
            s[field].push({ ...template, id: "901", body: "Background addition", ...(kind === "reply" ? { in_reply_to_id: "20" } : {}) });
          } else s[field] = s[field].filter(c => c.id !== "901");
        }, { insert, kind });
        await reactivatePage(page);
        await expect(page.getByText("Background addition", { exact: true })).toHaveCount(insert ? 1 : 0);
        expect(await editor.evaluate((el, original) => el === original, original)).toBe(true);
        await expect(editor).toBeFocused();
        expect(await editor.evaluate(el => [el.selectionStart, el.selectionEnd, el.selectionDirection])).toEqual([5, 14, direction]);
      }
      await editor.evaluate(el => el.dispatchEvent(new CompositionEvent("compositionend", { bubbles: true, data: "文" })));
      await page.keyboard.type("NEXT");
      await expect(editor).toHaveValue("Keep NEXT text");
    });
  }
}

test("draft remount restores selection without taking toolbar focus and cleans up cancelled drafts", async ({ page }) => {
  await installRenderProbe(page);
  await installApi(page, pullTarget(), { authenticated: true });
  await page.goto(reviewPath());
  await waitForSignedInComments(page);
  await openNewLineComment(page, 2);
  let editor = page.locator(".comment-editor textarea");
  await editor.fill("Selection survives containers");
  const draftId = await editor.getAttribute("data-draft-id");
  await editor.evaluate(el => el.setSelectionRange(3, 12, "backward"));
  const collapse = page.getByRole("button", { name: "Collapse src/main.mbt", exact: true });
  await collapse.click();
  await expect(page.locator(".file-discussions textarea")).toHaveCount(1);
  expect(await editor.getAttribute("data-draft-id")).toBe(draftId);
  expect(await editor.evaluate(el => [el.selectionStart, el.selectionEnd, el.selectionDirection])).toEqual([3, 12, "backward"]);
  await expect(editor).not.toBeFocused();
  await editor.focus();
  // Programmatic toolbar click leaves the editor focused immediately before the update.
  await page.getByRole("button", { name: "Expand src/main.mbt", exact: true }).evaluate(el => el.click());
  await expect(page.locator(".inline-comment-editor-row textarea")).toHaveCount(1);
  await expect(editor).toBeFocused();
  expect(await editor.evaluate(el => [el.selectionStart, el.selectionEnd, el.selectionDirection])).toEqual([3, 12, "backward"]);
  await page.getByRole("button", { name: "Unified", exact: true }).click();
  await expect(editor).not.toBeFocused();
  expect(await editor.evaluate(el => [el.selectionStart, el.selectionEnd, el.selectionDirection])).toEqual([3, 12, "backward"]);
  await page.getByRole("button", { name: "Cancel", exact: true }).click();
  await expect.poll(() => page.evaluate(() => globalThis.__moondiffMetrics.editor.records)).toBe(0);
  await openNewLineComment(page, 2);
  await expect(editor).toBeFocused();
  expect(await editor.getAttribute("data-draft-id")).not.toBe(draftId);
  await expect(editor).toHaveValue("");
});

for (const change of ["modified", "inserted", "deleted"]) {
  test(`same-line ${change} declarations keep discussions and drafts visible when collapsed across algorithms and layouts`, async ({ page }) => {
    const before = "let first = 11; let second = 22";
    const after = "let first = 33; let second = 44";
    const oldSource = change === "inserted" ? "fn keep() {}" : change === "deleted" ? `${before}\nfn keep() {}` : before;
    const newSource = change === "deleted" ? "fn keep() {}" : change === "inserted" ? `${after}\nfn keep() {}` : after;
    const patch = change === "inserted" ? `@@ -1 +1,2 @@\n+${after}\n fn keep() {}`
      : change === "deleted" ? `@@ -1,2 +1 @@\n-${before}\n fn keep() {}`
      : `@@ -1 +1 @@\n-${before}\n+${after}`;
    await installApi(page, pullTarget(), { authenticated: true, oldSource, newSource, patch });
    await page.addInitScript(({ change }) => {
      window.__fake.reviewComments = [{
        ...window.__fake.reviewComments[0], line: 1,
        side: change === "deleted" ? "LEFT" : "RIGHT",
        position: change === "modified" ? 2 : 1,
      }];
    }, { change });
    await page.goto(reviewPath());
    await waitForSignedInComments(page);
    const sections = page.locator("details.semantic-section");
    await expect(sections).toHaveCount(2);
    const first = sections.nth(0), second = sections.nth(1);
    const firstSummary = first.locator("summary"), secondSummary = second.locator("summary");
    await expect(first).toHaveJSProperty("open", true);
    await expect(second).toHaveJSProperty("open", true);
    await firstSummary.click();
    await expect(first).toHaveJSProperty("open", false);
    await expect(second.locator(".review-thread")).toBeVisible();
    // Original reproduction: start a draft in the second occurrence after closing the first.
    const side = change === "deleted" ? "old" : "new";
    const anchor = second.locator(`.${side}-line-number button[aria-label="Comment on line 1"]`);
    await clickLineCommentButton(anchor);
    const editor = page.locator(".comment-editor textarea");
    await expect(editor).toHaveCount(1);
    await expect(second.locator("textarea")).toBeVisible();
    await expect(editor).toBeFocused();
    const body = "Same-line draft with selection\n" + "Keep the scroll position\n".repeat(30);
    await editor.fill(body);
    const draftId = await editor.getAttribute("data-draft-id");
    const interaction = el => [el.selectionStart, el.selectionEnd, el.selectionDirection, el.scrollTop];
    let saved = await editor.evaluate(el => {
      el.setSelectionRange(3, 12, "backward");
      el.scrollTop = 48;
      return [el.selectionStart, el.selectionEnd, el.selectionDirection, el.scrollTop];
    });
    expect(saved[3]).toBeGreaterThan(0);
    const expectPlacement = async container => {
      await expect(page.locator(".review-thread")).toHaveCount(1);
      await expect(container.locator(".review-thread")).toBeVisible();
      await expect(editor).toHaveCount(1);
      await expect(container.locator("textarea")).toBeVisible();
      await expect(editor).toHaveValue(body);
      await expect(editor).toHaveAttribute("data-draft-id", draftId);
      await expect.poll(() => editor.evaluate(interaction)).toEqual(saved);
    };
    for (const algorithm of ["Token", "Tree"]) {
      await page.getByRole("button", { name: algorithm, exact: true }).click();
      for (const layout of ["Split", "Unified"]) {
        await page.getByRole("button", { name: layout, exact: true }).click();
        await expect(second.locator("table")).toHaveClass(new RegExp(`\\b${layout.toLowerCase()}\\b`));
        await expect(sections).toHaveCount(2);
        await expect(firstSummary).toContainText("let first");
        await expect(secondSummary).toContainText("let second");
        await expect(first).toHaveJSProperty("open", false);
        await expect(second).toHaveJSProperty("open", true);
        await expectPlacement(second);
        if (algorithm === "Tree" && change === "modified") {
          for (const [index, oldValue, newValue] of [[0, "11", "33"], [1, "22", "44"]]) {
            await expect(sections.nth(index).locator("b.wd")).toHaveText(oldValue);
            await expect(sections.nth(index).locator("b.wa")).toHaveText(newValue);
          }
        }
        saved = await editor.evaluate((el, direction) => {
          el.setSelectionRange(3, 12, direction);
          el.scrollTop = 48;
          return [el.selectionStart, el.selectionEnd, el.selectionDirection, el.scrollTop];
        }, layout === "Split" ? "backward" : "forward");
        await secondSummary.click();
        await expect(second).toHaveJSProperty("open", false);
        await expect(first).toHaveJSProperty("open", false);
        await expectPlacement(page.locator(".file-discussions"));
        await expect(secondSummary).toBeFocused();
        await expect(editor).not.toBeFocused();

        await secondSummary.press("Enter");
        await expect(second).toHaveJSProperty("open", true);
        await expectPlacement(second);
        await expect(secondSummary).toBeFocused();
        await firstSummary.press("Space");
        await expect(first).toHaveJSProperty("open", true);
        await expectPlacement(first);
        await expect(firstSummary).toBeFocused();

        // A programmatic activation leaves the editor focused before the remount.
        await editor.focus();
        await firstSummary.evaluate(el => el.click());
        await expect(first).toHaveJSProperty("open", false);
        await expectPlacement(second);
        await expect(editor).toBeFocused();
        const original = await editor.elementHandle();
        const refreshedBody = `Refreshed ${algorithm} ${layout}`;
        await page.evaluate(body => { window.__fake.reviewComments[0].body = body; }, refreshedBody);
        await reactivatePage(page);
        await expect(second.locator(".github-comment-body")).toHaveText(refreshedBody);
        await expect(first).toHaveJSProperty("open", false);
        await expectPlacement(second);
        expect(await editor.evaluate((el, original) => el === original, original)).toBe(true);
        await expect(editor).toBeFocused();
      }
    }
    for (const filter of ["Ignore comments", "Ignore tests", "Ignore comments", "Ignore tests"]) {
      await page.getByRole("checkbox", { name: filter, exact: true }).click();
      await expect(first).toHaveJSProperty("open", false);
      await expectPlacement(second);
    }
    await page.getByRole("button", { name: "Collapse src/main.mbt", exact: true }).click();
    await expectPlacement(page.locator(".file-discussions"));
    await page.getByRole("button", { name: "Expand src/main.mbt", exact: true }).click();
    await expect(first).toHaveJSProperty("open", false);
    await expect(second).toHaveJSProperty("open", true);
    await expectPlacement(second);
    await editor.focus();
    await page.keyboard.type("NEXT");
    await expect(editor).toHaveValue(body.slice(0, 3) + "NEXT" + body.slice(12));
    await page.locator(".comment-editor").getByRole("button", { name: "Cancel", exact: true }).click();
    await secondSummary.click();
    await expect(second).toHaveJSProperty("open", false);
    await page.evaluate(value => { window.__fake.currentHead = value; }, changedHead);
    await page.getByRole("button", { name: "Refresh", exact: true }).click();
    await expect(page.getByRole("button", { name: "Load latest", exact: true })).toBeEnabled();
    await expect(first).toHaveJSProperty("open", false);
    await expect(second).toHaveJSProperty("open", false);
    await page.getByRole("button", { name: "Load latest", exact: true }).click();
    await expect(sections).toHaveCount(2);
    await expect(first).toHaveJSProperty("open", true);
    await expect(second).toHaveJSProperty("open", true);
  });
}

async function restorePage(page) {
  await page.evaluate(() => {
    dispatchEvent(new PageTransitionEvent('pagehide', { persisted: true }));
    dispatchEvent(new PageTransitionEvent('pageshow', { persisted: true }));
    dispatchEvent(new Event('focus'));
  });
}

async function holdNextResponse(page, predicate) {
  let release, entered, finished;
  const gate = new Promise(resolve => { release = resolve; });
  const started = new Promise(resolve => { entered = resolve; });
  const completed = new Promise(resolve => { finished = resolve; });
  let held = false;
  await page.route('**/api/**', async route => {
    if (held) return route.fallback();
    route = metadataFallbackRoute(route);
    const message = route.request().method() === 'GET' ? { op: 'auth.status' } : fixtureRequest(route.request().postDataJSON());
    if (!predicate(message)) return route.fallback();
    held = true;
    const value = await page.evaluate(message => window.__dispatch(message), message);
    entered(); await gate;
    await route.fulfill({ json: successFixture(message.op, value) }).catch(error => cancelledRoute(route, error));
    finished();
  });
  return { started, completed, release };
}

for (const kind of ['overall', 'inline', 'reply']) {
  test(`session expiry releases an interrupted ${kind} write and ignores its late response`, async ({ page }) => {
    await installApi(page, pullTarget(), { authenticated: true });
    await page.goto(reviewPath());
    await waitForSignedInComments(page);
    if (kind === 'overall') await page.getByRole('button', { name: 'Add overall comment' }).click();
    else if (kind === 'inline') await openNewLineComment(page, 2);
    else await page.getByRole('button', { name: 'Reply' }).first().click();
    const editor = page.locator('.comment-editor textarea');
    await editor.fill('Uncertain submitted body');
    const write = await holdNextResponse(page, message => message.op.endsWith('.create'));
    await page.getByRole('button', { name: 'Post comment' }).click();
    await write.started;
    await page.evaluate(() => window.__fake.authenticationFailureOps.push('github.comments.list'));
    await reactivatePage(page);
    await expect(page.locator('.auth-controls.error')).toContainText('GitHub session expired');
    await expect(editor).toBeEnabled();
    await editor.fill('New text after expiry');
    write.release();
    await write.completed;
    await expect(editor).toHaveValue('New text after expiry');
    await page.getByRole('button', { name: 'Try sign-in' }).click();
    await waitForSignedInComments(page);
    await expect(page.getByRole('button', { name: 'Post comment' })).toBeEnabled();
    await expect(editor).toHaveValue('New text after expiry');
    expect(await page.evaluate(() => window.__fake.calls.filter(call => call.op.endsWith('.create')).length)).toBe(1);
  });
}

for (const boundary of ['logout', 'account switch']) {
  test(`expiry and cancelled sign-in preserve route drafts until ${boundary}`, async ({ page }) => {
    await installApi(page, pullTarget(), { authenticated: true });
    await page.goto(reviewPath());
    await waitForSignedInComments(page);
    await page.getByRole('button', { name: 'Add overall comment' }).click();
    await page.locator('.comment-editor textarea').fill('Route seventeen');
    await navigate(page, '/upstream/project/pull/18');
    await expect(page.locator('.comment-editor textarea')).toHaveCount(0);
    await waitForSignedInComments(page);
    await page.getByRole('button', { name: 'Add overall comment' }).click();
    await page.locator('.comment-editor textarea').fill('Route eighteen');
    await page.evaluate(() => {
      window.__fake.authenticationFailureOps.push('github.comments.list');
      window.__fake.delayNextDevicePoll = true;
    });
    await reactivatePage(page);
    await page.getByRole('button', { name: 'Try sign-in' }).click();
    await expect.poll(() => page.evaluate(() => typeof window.__fake.releaseDevicePoll)).toBe('function');
    await page.getByRole('button', { name: 'Cancel sign-in' }).first().click();
    await expect(page.getByRole('button', { name: 'Sign in with GitHub', exact: true }).first()).toBeVisible();
    await page.evaluate(() => window.__fake.releaseDevicePoll());
    await expect(page.locator('.comment-editor textarea')).toHaveValue('Route eighteen');
    await navigate(page, reviewPath());
    await expect(page.locator('.comment-editor textarea')).toHaveValue('Route seventeen');
    await expect(page.getByRole('button', { name: 'Post comment' })).toBeDisabled();
    // A later verified status completes recovery without reusing the cancelled poll.
    await page.evaluate(() => {
      window.__fake.device = null;
      window.__fake.authenticated = true;
    });
    await reactivatePage(page);
    await expect(page.getByRole('button', { name: 'Post comment' })).toBeEnabled();
    if (boundary === 'logout') {
      await page.getByRole('button', { name: 'Account: tester' }).click();
      await page.getByRole('menuitem', { name: 'Sign out' }).click();
    } else {
      await page.evaluate(() => { window.__fake.login = 'another-user'; });
      await reactivatePage(page);
      await expect(page.getByRole('button', { name: 'Account: another-user' })).toBeVisible();
    }
    await expect(page.locator('.comment-editor textarea')).toHaveCount(0);
    await navigate(page, '/upstream/project/pull/18');
    await expect(page.getByText('Fork PR', { exact: true })).toBeVisible();
    await expect(page.locator('.comment-editor textarea')).toHaveCount(0);
  });
}

for (const collapsed of [false, true]) {
  for (const sessionFails of [false, true]) {
    test(`page restoration resumes only interrupted file sides: collapsed=${collapsed}, session failure=${sessionFails}`, async ({ page }) => {
      await installApi(page, pullTarget(), { authenticated: true });
      const held = await holdNextResponse(page, message => message.op === 'github.content.get' && message.args.ref === head);
      await page.goto(reviewPath());
      await held.started;
      await waitForSignedInComments(page);
      await page.getByRole('button', { name: 'Add overall comment' }).click();
      await page.locator('.comment-editor textarea').fill('Draft survives restoration');
      if (collapsed) await page.getByRole('button', { name: 'Collapse src/main.mbt', exact: true }).click();
      if (sessionFails) {
        await page.route('**/api/auth/status', route => route.fulfill({ status: 503, json: { $tag: 'Failure', error: { code: 'unavailable', status: 503, message: 'Temporary session failure' } } }), { times: 1 });
      }
      await restorePage(page);
      if (sessionFails) {
        await expect(page.getByRole('button', { name: 'Try sign-in' })).toBeVisible();
        expect(await page.evaluate(() => window.__fake.calls.filter(c => c.op === 'github.content.get').length)).toBe(2);
        await reactivatePage(page);
      }
      await waitForSignedInComments(page);
      await expect.poll(() => page.evaluate(() => window.__fake.calls.filter(c => c.op === 'github.content.get').map(c => c.args.ref).sort())).toEqual([mergeBase, head, head].sort());
      await expect(page.locator('.comment-editor textarea')).toHaveValue('Draft survives restoration');
      await expect(page.locator('#moondiff-file-0 .file-toggle')).toHaveAttribute('aria-expanded', String(!collapsed));
      if (collapsed) await page.getByRole('button', { name: 'Expand src/main.mbt', exact: true }).click();
      await expect(page.locator('table.split.review-diff')).toContainText('new value');
      const before = await page.evaluate(() => window.__fake.commentListCalls);
      await reactivatePage(page);
      await expect.poll(() => page.evaluate(() => window.__fake.commentListCalls)).toBeGreaterThan(before);
      held.release(); await held.completed;
      expect(await page.evaluate(() => window.__fake.calls.filter(c => c.op === 'github.content.get').length)).toBe(3);
      await expect(page.locator('.comment-editor textarea')).toHaveValue('Draft survives restoration');
    });
  }
}

for (const target of [pullTarget(), commitTarget(), pullCommitTarget()]) {
  test(`page restoration restarts interrupted ${target.kind} metadata`, async ({ page }) => {
    await installApi(page, target, { authenticated: true });
    const operation = target.kind === 'commit' ? 'github.commit.get' : 'github.pull.get';
    const held = await holdNextResponse(page, message => message.op === operation);
    await page.goto(reviewPath(target)); await held.started;
    await restorePage(page);
    await expect(page.locator('table.split.review-diff')).toContainText('new value');
    held.release(); await held.completed;
    await expect(page.locator('table.split.review-diff')).toContainText('new value');
  });
}

for (const boundary of ['navigation', 'account']) {
  test(`page restoration respects ${boundary} changes while its session is pending`, async ({ page }) => {
    await installApi(page, pullTarget(), { authenticated: true, identitySpecificDiff: true });
    const source = await holdNextResponse(page, message => message.op === 'github.content.get' && message.args.ref === head);
    await page.goto(reviewPath()); await source.started;
    await waitForSignedInComments(page);
    await page.getByRole('button', { name: 'Add overall comment' }).click();
    await page.locator('.comment-editor textarea').fill('Previous account draft');
    if (boundary === 'account') await page.evaluate(() => { window.__fake.login = 'bob'; });
    const session = await holdNextResponse(page, message => message.op === 'auth.status');
    await restorePage(page); await session.started;
    if (boundary === 'navigation') {
      await page.evaluate(path => { history.pushState(null, '', path); dispatchEvent(new PopStateEvent('popstate')); }, reviewPath(pullCommitTarget()));
      await expect(page.getByRole('button', { name: 'Account: tester', exact: true })).toBeVisible();
      await expect(page.locator('table.split.review-diff')).toContainText('new value for tester');
    }
    session.release(); await session.completed;
    if (boundary === 'account') {
      await expect(page.getByRole('button', { name: 'Account: bob', exact: true })).toBeVisible();
      await expect(page.locator('table.split.review-diff')).toContainText('new value for bob');
    }
    source.release(); await source.completed;
    await expect(page.locator('.comment-editor textarea')).toHaveCount(0);
    await expect(page.locator('table.split.review-diff')).toContainText(boundary === 'account' ? 'new value for bob' : 'new value for tester');
  });
}

for (const kind of ['overall', 'inline', 'reply', 'commit', 'head-check']) {
  test(`page restoration releases interrupted ${kind} submission without repeating the write`, async ({ page }) => {
    const target = kind === 'commit' ? commitTarget() : pullTarget();
    await installApi(page, target, { authenticated: true });
    await page.goto(reviewPath(target)); await waitForSignedInComments(page);
    if (kind === 'overall') await page.getByRole('button', { name: 'Add overall comment' }).click();
    else if (kind === 'reply') await page.getByRole('button', { name: 'Reply' }).first().click();
    else await openNewLineComment(page, 2);
    const editor = page.locator('.comment-editor textarea');
    await editor.fill('Interrupted draft');
    const held = await holdNextResponse(page, message => kind === 'head-check' ? message.op === 'github.pull.get' : message.op.endsWith('.create'));
    await page.getByRole('button', { name: 'Post comment', exact: true }).click(); await held.started;
    await expect(editor).toBeDisabled();
    await restorePage(page);
    await expect(editor).toBeEnabled();
    await expect(editor).toHaveValue('Interrupted draft');
    await expect(page.locator('.comment-editor .comment-error')).toHaveText('请求已中断，结果尚未确认，请检查后再重试');
    await expect(page.getByRole('button', { name: 'Post comment', exact: true })).toBeEnabled();
    const lists = await page.evaluate(() => window.__fake.commentListCalls);
    await reactivatePage(page);
    await expect.poll(() => page.evaluate(() => window.__fake.commentListCalls)).toBeGreaterThan(lists);
    held.release(); await held.completed;
    await editor.fill('Still editable after the late response');
    await expect(editor).toHaveValue('Still editable after the late response');
    expect(await page.evaluate(() => window.__fake.calls.filter(c => c.op.endsWith('.create')).length)).toBe(kind === 'head-check' ? 0 : 1);
  });
}

test('page restoration releases interrupted deletion and refreshes its uncertain result', async ({ page }) => {
  await installApi(page, pullTarget(), { authenticated: true, login: 'reviewer' });
  await page.goto(reviewPath());
  const own = page.locator('.github-comment').filter({ hasText: 'Existing overall comment' });
  await requestCommentDeletion(own);
  await page.evaluate(() => { window.__fake.deleteDelay = true; });
  await own.getByRole('button', { name: 'Confirm delete' }).click();
  await expect.poll(() => page.evaluate(() => !!window.__fake.releaseDelete)).toBe(true);
  await restorePage(page);
  await expect(own.locator('.comment-error')).toHaveText('请求已中断，结果尚未确认，请检查后再重试');
  await expect(own.getByRole('button', { name: 'Confirm delete' })).toBeEnabled();
  await expect(page.getByRole('button', { name: 'Refresh', exact: true })).toBeEnabled();
  await page.evaluate(() => window.__fake.releaseDelete());
  await expect(own).toBeVisible();
  await page.getByRole('button', { name: 'Refresh', exact: true }).click();
  await expect(own).toHaveCount(0);
  expect(await page.evaluate(() => window.__fake.calls.filter(c => c.op.endsWith('.comment.delete')).length)).toBe(1);
});

for (const algorithm of ["Token", "Tree"]) {
  for (const layout of ["Split", "Unified"]) {
    test(`${algorithm} ${layout}: navigating into a collapsed section preserves comment anchors and the draft`, async ({ page }) => {
      await page.setViewportSize({ width: 1280, height: 480 });
      const before = "let first = 11; let second = 22";
      const after = "let first = 33; let second = 44";
      await installApi(page, pullTarget(), {
        authenticated: true, oldSource: before, newSource: after,
        patch: `@@ -1 +1 @@\n-${before}\n+${after}`,
      });
      await page.addInitScript(() => {
        window.__fake.reviewComments = [{
          ...window.__fake.reviewComments[0], line: 1, side: "RIGHT", position: 2,
        }];
      });
      await page.goto(reviewPath());
      await waitForSignedInComments(page);
      await page.getByRole("button", { name: algorithm, exact: true }).click();
      await page.getByRole("button", { name: layout, exact: true }).click();
      const sections = page.locator("details.semantic-section");
      await expect(sections).toHaveCount(2);
      const first = sections.nth(0), second = sections.nth(1);
      await first.locator(".semantic-section-label").click();
      await expect(second.locator('.review-diff .syntax-variable').filter({ hasText: /^second$/ }).first()).toHaveText("second");
      await expect(second.locator('b.wa .syntax-number').filter({ hasText: /^44$/ })).toHaveCount(1);
      const anchor = second.locator('.new-line-number button[aria-label="Comment on line 1"]');
      await clickLineCommentButton(anchor);
      const editor = page.locator(".inline-comment-editor-row textarea");
      await editor.fill("Preserve this line-one draft");
      const draftId = await editor.getAttribute("data-draft-id");
      await editor.evaluate(element => element.setSelectionRange(2, 9, "backward"));
      // Global navigation follows the reading position, so place the second
      // declaration beneath its sticky heading before returning to the first.
      await second.evaluate(element => {
        const summary = element.querySelector("summary");
        const row = element.querySelector("[data-change-block-start]");
        const inset = parseFloat(getComputedStyle(summary).top) + summary.getBoundingClientRect().height + 8;
        window.scrollTo(0, window.scrollY + row.getBoundingClientRect().top - inset);
      });
      await page.locator(".change-titlebar").getByRole("button", { name: "Previous change", exact: true }).click();
      await expect(first).toHaveJSProperty("open", true);
      await expect(page.locator(".change-titlebar").getByRole("button", { name: "Previous change", exact: true })).toBeFocused();
      await expect(first.locator(".review-thread")).toHaveCount(1);
      await expect(page.locator(".review-thread")).toHaveCount(1);
      await expect(first.locator("textarea")).toHaveCount(1);
      await expect(editor).toHaveAttribute("data-draft-id", draftId);
      await expect(editor).toHaveValue("Preserve this line-one draft");
      expect(await editor.evaluate(element => [element.selectionStart, element.selectionEnd, element.selectionDirection])).toEqual([2, 9, "backward"]);
      await page.getByRole("button", { name: layout === "Split" ? "Unified" : "Split", exact: true }).click();
      await expect(first).toHaveJSProperty("open", true);
      await expect(first.locator("textarea")).toHaveCount(1);
      await expect(editor).toHaveAttribute("data-draft-id", draftId);
      await expect(first.locator('.new-line-number button[aria-label="Comment on line 1"]')).toHaveCount(1);
      await expect(first.locator('b.wa .syntax-number').filter({ hasText: /^33$/ })).toHaveCount(1);
    });
  }
}
