import { fixtureRequest, successFixture } from '../../tests/protocol-fixtures.mjs';
import { checkToolbar } from "./toolbar.mjs";
import { expect, test } from "@playwright/test";

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

async function requestCommentDeletion(card) {
  await card.getByRole("button", { name: "More options", exact: true }).click();
  await card.getByRole("menuitem", { name: "Delete", exact: true }).click();
}

async function installApi(page, target = pullTarget(), options = {}) {
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
        body: "Existing overall comment",
        html_url: "https://github.com/upstream/project/issues/17#issuecomment-10",
        created_at: "2026-08-18T08:00:00Z",
        user: { login: "reviewer" },
      }],
      reviewComments: [{
        id: "20",
        body: "Existing inline comment",
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
        body: "Existing reply",
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
        body: "Existing commit comment",
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
        html_url: "https://github.com/upstream/project/pull/17",
        base: { sha: state.currentBase, repo: { full_name: "upstream/project" } },
        head: { sha: state.currentHead, repo: { full_name: "contributor/project-fork" } },
        additions: options.additions ?? 1,
        deletions: options.deletions ?? 1,
        changed_files: 1,
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
  await page.route('**/api/**', async route => {
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
  await expect(page.getByText("Signed in as tester")).toBeVisible();
  await expect(page.getByRole("button", { name: "Refresh" })).toBeEnabled();
}

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

async function clickLineCommentButton(button) {
  await expect(async () => {
    await button.scrollIntoViewIfNeeded({ timeout: 1_000 });
    await button.locator("xpath=..").hover({ timeout: 1_000 });
    await button.click({ timeout: 1_000 });
  }).toPass({ timeout: 5_000, intervals: [100, 250, 500] });
}

async function openNewLineComment(page, line) {
  await clickLineCommentButton(newLineCommentButton(page, line));
  await expect(page.locator(".inline-comment-editor-row textarea")).toBeVisible();
}

async function releaseListAfterLineCommentHover(page, button) {
  const race = { interruptions: 0 };
  const gutter = button.locator("xpath=..");
  // Trigger only after hover, immediately before the click's actionability check.
  await page.addLocatorHandler(button.and(page.locator(".review-gutter:hover > .line-comment-button")), async () => {
    const before = await gutter.boundingBox();
    await expect(button).toHaveCSS("opacity", "1");
    await page.evaluate(() => window.__fake.releaseList());
    await expect.poll(async () => Math.abs((await gutter.boundingBox()).y - before.y)).toBeGreaterThan(before.height);
    // Re-hit-test the stationary pointer at the gutter's original coordinates.
    await page.mouse.move(before.x + before.width / 2, before.y + before.height / 2);
    await expect.poll(() => button.evaluate(el => el.parentElement.matches(":hover"))).toBe(false);
    await expect(button).toHaveCSS("opacity", "0");
    await expect(button).toHaveCSS("pointer-events", "none");
    race.interruptions += 1;
  }, { times: 1, noWaitAfter: true });
  return race;
}

for (const phase of ["initial comment load", "background refresh"]) {
  for (const layout of ["Split", "Unified"]) {
    for (const side of ["old", "new"]) {
      test(`line comment click recovers from ${phase} after hover: ${layout} ${side}`, async ({ page }) => {
        await page.setViewportSize({ width: 1440, height: 1200 });
        await installApi(page, pullTarget(), { authenticated: true });
        await page.addInitScript(phase => {
          if (phase === "initial comment load") window.__fake.delayNextList = true;
        }, phase);
        await page.goto(reviewPath());
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
          await reactivatePage(page);
        }
        await expect.poll(() => page.evaluate(() => typeof window.__fake.releaseList)).toBe("function");
        const button = file.locator(`.${side}-line-number`)
          .getByRole("button", { name: "Comment on line 2", exact: true });
        const race = await releaseListAfterLineCommentHover(page, button);
        await clickLineCommentButton(button);
        expect(race.interruptions).toBe(1);
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
  await expect(page.locator(".line-comment-button")).toHaveCount(0);
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
  await expect(page.locator(".line-comment-button")).toHaveCount(0);
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
  await page.waitForTimeout(50);
  expect(await page.evaluate(() => ({
    auth: window.__fake.calls.filter(call => call.op === "auth.status").length,
    comments: window.__fake.commentListCalls,
  }))).toEqual({ auth: before.auth + 1, comments: before.comments + 1 });

  const beforeManual = await page.evaluate(() => window.__fake.commentListCalls);
  await page.getByRole("button", { name: "Refresh" }).click();
  await expect.poll(() => page.evaluate(() => window.__fake.commentListCalls)).toBeGreaterThan(beforeManual);

  await page.getByRole("button", { name: "Unified" }).click();
  await expect(page.locator("table.unified.review-diff")).toBeVisible();
});

test("expired credentials during comment refresh offer sign-in and hide authoring", async ({ page }) => {
  await installApi(page, pullTarget(), { authenticated: true });
  await page.goto(reviewPath());
  await waitForSignedInComments(page);

  await page.evaluate(() => {
    window.__fake.authenticationFailureOps.push("github.comments.list");
  });
  await page.getByRole("button", { name: "Refresh" }).click();

  await expect(page.locator(".auth-controls.error")).toContainText("GitHub session expired");
  await expect(page.getByRole("button", { name: "Try sign-in" })).toBeVisible();
  await expect(page.getByText("Signed in as tester")).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Add overall comment" })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Reply" })).toHaveCount(0);
  await expect(page.locator(".line-comment-button")).toHaveCount(0);

  await page.getByRole("button", { name: "Try sign-in" }).click();
  await waitForSignedInComments(page);
  await expect(page.getByRole("button", { name: "Add overall comment" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Reply" }).first()).toBeVisible();
  await expect(page.locator(".line-comment-button").first()).toBeAttached();
});

test("expired credentials during comment submission preserve the draft for retry", async ({ page }) => {
  await installApi(page, pullTarget(), { authenticated: true });
  await page.goto(reviewPath());
  await waitForSignedInComments(page);

  await page.getByRole("button", { name: "Add overall comment" }).click();
  await page.locator(".comment-editor textarea").fill("Keep this draft");
  await page.evaluate(() => {
    window.__fake.authenticationFailureOps.push("github.issue.comment.create");
  });
  await page.getByRole("button", { name: "Post comment" }).click();

  await expect(page.locator(".auth-controls.error")).toContainText("GitHub session expired");
  await expect(page.getByRole("button", { name: "Try sign-in" })).toBeVisible();
  await expect(page.locator(".comment-editor textarea")).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Add overall comment" })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Reply" })).toHaveCount(0);
  await expect(page.locator(".line-comment-button")).toHaveCount(0);

  await page.getByRole("button", { name: "Try sign-in" }).click();
  await waitForSignedInComments(page);
  await expect(page.locator(".comment-editor textarea")).toHaveValue("Keep this draft");
  await page.getByRole("button", { name: "Post comment" }).click();
  await expect(page.getByText("Keep this draft", { exact: true })).toBeVisible();
});

test("private PR prompts for GitHub App access and retries after login", async ({ page }) => {
  await installApi(page, pullTarget(), { privateUntilAuth: true });
  await page.goto(reviewPath());
  await expect(page.getByText(/private repositories/u)).toBeVisible();
  await expect(page.getByRole("link", { name: /Install GitHub App/u })).toBeVisible();
  await page.getByRole("button", { name: "Sign in with GitHub" }).click();
  await expect(page.getByText("Fork PR")).toBeVisible();
  await expect(page.getByText("Signed in as tester")).toBeVisible();
  const installLink = page.getByRole("link", { name: /Install GitHub App/u });
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
  await expect(page.getByText("Signed in as tester")).toBeVisible();
  await expect(page.getByRole("button", { name: "Add overall comment" })).toBeVisible();

  await page.evaluate(() => { window.__fake.authenticated = false; });
  await reactivatePage(page);
  await expect(page.getByRole("button", { name: "Sign in with GitHub" })).toBeVisible();
  await expect(page.getByText("Signed in as tester")).toHaveCount(0);
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
  await expect(page.getByText("Signed in as alice")).toBeVisible();
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
  await expect(page.getByText("Signed in as bob")).toBeVisible();
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
  await expect(page.getByText("Signed in as tester")).toBeVisible();
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
  await expect(page.getByText("Signed in as tester")).toBeVisible();
  await expect.poll(() => page.evaluate(() => window.__fake.calls
    .filter(call => call.op === "github.pull.get").length)).toBeGreaterThanOrEqual(2);

  await page.evaluate(async () => {
    window.__fake.releaseAnonymousPull();
    await new Promise(resolve => setTimeout(resolve, 0));
  });
  await expect.poll(() => page.evaluate(() => window.__fake.anonymousPullReleased)).toBe(true);
  await expect(page.getByText("Fork PR")).toBeVisible();
  await expect(page.getByText("Signed in as tester")).toBeVisible();
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
    const call = await page.evaluate(() => window.__fake.calls.find(entry => entry.op === "github.commit.comment.create"));
    expect(call.args).toMatchObject({ owner: "upstream", repo: "project", sha: commitSha, path: "src/main.mbt", position: 3 });
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
  await own.getByRole("button", { name: "Cancel deletion" }).click();
  await expect(own).toBeVisible();
  await requestCommentDeletion(own);
  await own.getByRole("button", { name: "Confirm delete" }).click();
  await expect(own).toHaveCount(0);
  await expect(page.locator(".inline-discussion-row").filter({ hasText: "Existing reply" })).toHaveCount(1);
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
  await card.getByRole("button", { name: "Cancel deletion" }).click();
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
  await expect(card.locator(".comment-error")).toContainText("Your GitHub session expired");
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
    state.reviewComments.push({ ...state.reviewComments[0], id: "99", line: 1, position: 1 });
    state.delayNextList = true;
  });
  await reactivatePage(page);
  await expect.poll(() => page.evaluate(() => typeof window.__fake.releaseList)).toBe("function");
  const race = await releaseListAfterLineCommentHover(page, newLineCommentButton(page, 2));
  await openNewLineComment(page, 2);
  expect(race.interruptions).toBe(1);
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

test("line creation after a PR update shows a receipt without inserting an unverified anchor", async ({ page }) => {
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
  await expect(page.locator(".comment-notice")).toHaveText("Comment published.");
  await expect(page.getByText("Published on the old snapshot", { exact: true })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Load latest" })).toBeEnabled();
  await page.getByRole("button", { name: "Load latest" }).click();
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
  await expect.poll(() => page.evaluate(() => globalThis.__moondiffEditorInteraction.records.size)).toBe(0);
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
    const message = route.request().method() === 'GET' ? { op: 'auth.status' } : fixtureRequest(route.request().postDataJSON());
    if (held || !predicate(message)) return route.fallback();
    held = true;
    const value = await page.evaluate(message => window.__dispatch(message), message);
    entered(); await gate;
    await route.fulfill({ json: successFixture(message.op, value) }).catch(() => {});
    finished();
  });
  return { started, completed, release };
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
      await expect(page.getByText('Signed in as tester')).toBeVisible();
      await expect(page.locator('table.split.review-diff')).toContainText('new value for tester');
    }
    session.release(); await session.completed;
    if (boundary === 'account') {
      await expect(page.getByText('Signed in as bob')).toBeVisible();
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
      const anchor = second.locator('.new-line-number button[aria-label="Comment on line 1"]');
      await clickLineCommentButton(anchor);
      const editor = page.locator(".inline-comment-editor-row textarea");
      await editor.fill("Preserve this line-one draft");
      const draftId = await editor.getAttribute("data-draft-id");
      await editor.evaluate(element => element.setSelectionRange(2, 9, "backward"));
      // File-level navigation follows the reading position, so place the second
      // declaration beneath its sticky heading before returning to the first.
      await second.evaluate(element => {
        const summary = element.querySelector("summary");
        const row = element.querySelector("[data-change-block-start]");
        const inset = parseFloat(getComputedStyle(summary).top) + summary.getBoundingClientRect().height + 8;
        window.scrollTo(0, window.scrollY + row.getBoundingClientRect().top - inset);
      });
      await page.locator("#moondiff-file-0 .file-heading").getByRole("button", { name: "Previous change", exact: true }).click();
      await expect(first).toHaveJSProperty("open", true);
      await expect(page.locator("#moondiff-file-0 .file-heading").getByRole("button", { name: "Previous change", exact: true })).toBeFocused();
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
    });
  }
}
