import { expect, test } from "../../playground/node_modules/@playwright/test/index.mjs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const extensionRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");

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

async function installHost(page, target = pullTarget(), options = {}) {
  await page.addInitScript(({ target, options, head, changedHead, base, mergeBase, commitSha, parentSha, patch }) => {
    let savedAuth = {};
    try {
      savedAuth = JSON.parse(sessionStorage.getItem("moondiff-fake-auth") || "{}");
    } catch {}
    const state = {
      target,
      calls: [],
      authenticated: options.authenticated ?? Boolean(savedAuth.authenticated),
      deviceFlow: savedAuth.deviceFlow || null,
      deviceStartCalls: savedAuth.deviceStartCalls || 0,
      devicePollCalls: savedAuth.devicePollCalls || 0,
      terminalUsed: Boolean(savedAuth.terminalUsed),
      authorize: false,
      currentHead: head,
      headRace: false,
      metadataCalls: 0,
      commentListCalls: 0,
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

    function saveAuth() {
      sessionStorage.setItem("moondiff-fake-auth", JSON.stringify({
        authenticated: state.authenticated,
        deviceFlow: state.deviceFlow,
        deviceStartCalls: state.deviceStartCalls,
        devicePollCalls: state.devicePollCalls,
        terminalUsed: state.terminalUsed,
      }));
    }

    function authStatus() {
      const status = state.authenticated
        ? { authenticated: true, login: "tester", install_url: "https://github.com/apps/moondiff-test/installations/new" }
        : { authenticated: false, install_url: "https://github.com/apps/moondiff-test/installations/new" };
      if (!state.authenticated && state.deviceFlow) status.device_flow = state.deviceFlow;
      return status;
    }

    function pullMetadata() {
      return {
        title: "Fork PR",
        html_url: "https://github.com/upstream/project/pull/17",
        base: { sha: base, repo: { full_name: "upstream/project" } },
        head: { sha: state.currentHead, repo: { full_name: "contributor/project-fork" } },
        additions: 1,
        deletions: 1,
        changed_files: 1,
      };
    }
    function file() {
      return {
        filename: "src/main.mbt",
        status: "modified",
        additions: 1,
        deletions: 1,
        changes: 2,
        patch,
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
      const text = ref === mergeBase || ref === parentSha
        ? "context\nold value\ntail"
        : "context\nnew value\ntail";
      return { base64: btoa(text), size: text.length, contentType: "text/plain" };
    }
    async function dispatch(message) {
      const { op, args = {} } = message;
      state.calls.push({ op, args });
      if (op === "target.current") return state.target;
      if (op === "request.cancel" || op === "page.comments.changed") return { ok: true };
      if (op === "auth.status") return authStatus();
      if (op === "auth.device.start") {
        state.deviceStartCalls += 1;
        state.deviceFlow = {
          flow_id: `flow-${state.deviceStartCalls}`,
          user_code: "ABCD-EFGH",
          verification_uri: "https://github.com/login/device",
          expires_in: 900,
          poll_after: options.pollAfter ?? 0,
        };
        saveAuth();
        return authStatus();
      }
      if (op === "auth.device.poll") {
        if (!state.deviceFlow || args.flow_id !== state.deviceFlow.flow_id) {
          throw Object.assign(new Error("This GitHub device authorization is no longer active."), { status: 409, code: "device_flow_replaced" });
        }
        state.devicePollCalls += 1;
        if (options.terminalError && !state.terminalUsed) {
          state.terminalUsed = true;
          state.deviceFlow = null;
          saveAuth();
          const denied = options.terminalError === "denied";
          throw Object.assign(
            new Error(denied ? "GitHub sign-in was denied. Start sign-in again to retry." : "The GitHub device code expired. Start sign-in again."),
            { status: denied ? 403 : 410, code: denied ? "device_flow_denied" : "device_flow_expired" },
          );
        }
        if (!state.authorize && state.devicePollCalls <= (options.pendingPolls ?? 0)) {
          state.deviceFlow = { ...state.deviceFlow, expires_in: state.deviceFlow.expires_in - 1 };
          saveAuth();
          return authStatus();
        }
        state.authenticated = true;
        state.deviceFlow = null;
        saveAuth();
        return authStatus();
      }
      if (op === "auth.device.cancel") {
        if (state.deviceFlow?.flow_id === args.flow_id) state.deviceFlow = null;
        saveAuth();
        return authStatus();
      }
      if (op === "auth.logout") {
        state.authenticated = false;
        state.deviceFlow = null;
        saveAuth();
        return authStatus();
      }
      if (op === "github.pull.get") {
        if (options.privateUntilAuth && !state.authenticated) {
          throw Object.assign(new Error("GitHub could not find this resource. For private repositories, sign in and install the GitHub App."), { status: 404, code: "not_found_or_not_installed" });
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
      if (op === "github.pull.files") return [file()];
      if (op === "github.commit.get") return commit();
      if (op === "github.content.get") return content(args.ref);
      if (op === "github.comments.list") {
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
        return state.target.kind === "pull"
          ? { issue_comments: state.issueComments, review_comments: state.reviewComments, commit_comments: [] }
          : { issue_comments: [], review_comments: [], commit_comments: state.commitComments };
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
        const created = { id: "23", body: args.body, html_url: "https://github.com/comment/23", created_at: "2026-08-18T09:03:00Z", user: { login: "tester" }, path: "src/main.mbt", line: 2, side: "RIGHT", position: 3, commit_id: state.currentHead, in_reply_to_id: String(args.comment_id) };
        state.reviewComments.push(created);
        return created;
      }
      throw Object.assign(new Error("Unhandled fake operation: " + op), { status: 400, code: "unhandled" });
    }
    window.chrome = {
      runtime: {
        async sendMessage(message) {
          try { return { ok: true, value: await dispatch(message) }; }
          catch (error) { return { ok: false, error: { status: error.status || 500, code: error.code || "fake_error", message: error.message } }; }
        },
      },
    };
  }, { target, options, head, changedHead, base, mergeBase, commitSha, parentSha, patch });
}

async function waitForSignedInComments(page) {
  await expect(page.getByText("Signed in as tester")).toBeVisible();
  await expect(page.getByRole("button", { name: "Refresh" })).toBeEnabled();
}

async function signInAndWaitForComments(page) {
  await page.getByRole("button", { name: "Sign in with GitHub" }).click();
  await waitForSignedInComments(page);
}

function newLineCommentGutter(page, line) {
  const lineNumber = page.locator(".line-number-value", {
    hasText: new RegExp(`^${line}$`),
  });
  return page.locator(".review-gutter.new-line-number", { has: lineNumber });
}

function newLineCommentButton(page, line) {
  return newLineCommentGutter(page, line)
    .getByRole("button", { name: `Comment on line ${line}` });
}

async function openNewLineComment(page, line) {
  await newLineCommentGutter(page, line).hover();
  const button = newLineCommentButton(page, line);
  await expect(button).toHaveCSS("opacity", "1");
  await button.click();
  await expect(page.locator(".inline-comment-editor-row textarea")).toBeVisible();
}

test("anonymous public PR loads comments and a safe narrow diff without Analyze", async ({ page }) => {
  await installHost(page);
  await page.setViewportSize({ width: 420, height: 900 });
  await page.goto("/panel.html");
  await expect(page.getByText("Fork PR")).toBeVisible();
  await expect(page.getByRole("button", { name: "Sign in with GitHub" })).toBeVisible();
  await expect(page.getByText("Existing overall comment")).toBeVisible();
  await expect(page.getByText("Existing inline comment")).toBeVisible();
  await expect(page.getByText("Outdated inline comment")).toBeVisible();
  await expect(page.getByRole("heading", { name: "Outdated discussion" })).toBeVisible();
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

test("extension validation failures use a neutral Moondiff error message", async ({ page }) => {
  await installHost(page, pullTarget(), {
    commentListError: {
      status: 400,
      code: "invalid_arguments",
      detail: "Missing RPC argument: sha",
    },
  });
  await page.goto("/panel.html");
  await expect(page.getByText("Fork PR")).toBeVisible();
  await expect(page.getByText(
    "Moondiff extension request failed (status 400, invalid_arguments): Missing RPC argument: sha",
  )).toBeVisible();
});

test("device sign-in displays and copies the code and only opens GitHub from the explicit link", async ({ page, context }) => {
  await context.grantPermissions(["clipboard-read", "clipboard-write"]);
  await context.route("https://github.com/login/device", route => route.fulfill({
    status: 200,
    contentType: "text/html",
    body: "<!doctype html><title>GitHub device verification</title>",
  }));
  await installHost(page, pullTarget(), { pendingPolls: 1_000, pollAfter: 1 });
  await page.goto("/panel.html");
  await page.getByRole("button", { name: "Sign in with GitHub" }).click();
  await expect(page.locator(".device-user-code")).toHaveText("ABCD-EFGH");
  await expect(page.locator("table.split.review-diff")).toBeVisible();
  await expect(page.getByRole("button", { name: "Add overall comment" })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Reply" })).toHaveCount(0);
  await expect(page.locator(".line-comment-button")).toHaveCount(0);
  expect(context.pages()).toHaveLength(1);

  await page.getByRole("button", { name: "Copy code" }).click();
  await expect(page.getByRole("button", { name: "Copied" })).toBeVisible();
  await expect.poll(() => page.evaluate(() => navigator.clipboard.readText())).toBe("ABCD-EFGH");

  const verification = page.getByRole("link", { name: /Open GitHub verification page/u });
  await expect(verification).toHaveAttribute("href", "https://github.com/login/device");
  await expect(verification).toHaveAttribute("target", "_blank");
  const popupPromise = page.waitForEvent("popup");
  await verification.click();
  const popup = await popupPromise;
  await expect.poll(() => popup.url()).toBe("https://github.com/login/device");
  await popup.close();
  await page.getByRole("button", { name: "Cancel" }).click();
  await expect(page.getByRole("button", { name: "Sign in with GitHub" })).toBeVisible();
});

test("device polling survives pending responses and signs in", async ({ page }) => {
  await installHost(page, pullTarget(), { pendingPolls: 2 });
  await page.goto("/panel.html");
  await page.getByRole("button", { name: "Sign in with GitHub" }).click();
  await expect(page.getByText("Signed in as tester")).toBeVisible();
  expect(await page.evaluate(() => window.__fake.devicePollCalls)).toBeGreaterThanOrEqual(3);
});

test("reloading the panel restores an unexpired device authorization", async ({ page }) => {
  await installHost(page, pullTarget(), { pendingPolls: 1_000, pollAfter: 1 });
  await page.goto("/panel.html");
  await page.getByRole("button", { name: "Sign in with GitHub" }).click();
  await expect(page.locator(".device-user-code")).toHaveText("ABCD-EFGH");
  await page.reload();
  await expect(page.locator(".device-user-code")).toHaveText("ABCD-EFGH");
  expect(await page.evaluate(() => window.__fake.deviceStartCalls)).toBe(1);
  await page.evaluate(() => { window.__fake.authorize = true; });
  await expect(page.getByText("Signed in as tester")).toBeVisible();
});

for (const terminalError of ["denied", "expired"]) {
  const article = terminalError === "expired" ? "an" : "a";
  test(`${article} ${terminalError} device authorization can be retried`, async ({ page }) => {
    await installHost(page, pullTarget(), { terminalError });
    await page.goto("/panel.html");
    await page.getByRole("button", { name: "Sign in with GitHub" }).click();
    await expect(page.getByText(new RegExp(terminalError, "iu"))).toBeVisible();
    await page.getByRole("button", { name: "Try sign-in" }).click();
    await expect(page.getByText("Signed in as tester")).toBeVisible();
    expect(await page.evaluate(() => window.__fake.deviceStartCalls)).toBe(2);
  });
}

test("login, overall comment, inline comment, reply, focus refresh, and view toggle", async ({ page }) => {
  await installHost(page);
  await page.goto("/panel.html");
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

  const before = await page.evaluate(() => window.__fake.commentListCalls);
  await page.evaluate(() => dispatchEvent(new Event("focus")));
  await expect.poll(() => page.evaluate(() => window.__fake.commentListCalls)).toBeGreaterThan(before);

  const beforeManual = await page.evaluate(() => window.__fake.commentListCalls);
  await page.getByRole("button", { name: "Refresh" }).click();
  await expect.poll(() => page.evaluate(() => window.__fake.commentListCalls)).toBeGreaterThan(beforeManual);

  await page.getByRole("button", { name: "Use unified view" }).click();
  await expect(page.locator("table.unified.review-diff")).toBeVisible();
});

test("private PR prompts for GitHub App access and retries after login", async ({ page }) => {
  await installHost(page, pullTarget(), { privateUntilAuth: true });
  await page.goto("/panel.html");
  await expect(page.getByText(/private repositories/u)).toBeVisible();
  await expect(page.getByRole("link", { name: /Install GitHub App/u })).toBeVisible();
  await page.getByRole("button", { name: "Sign in with GitHub" }).click();
  await expect(page.getByText("Fork PR")).toBeVisible();
  await expect(page.getByText("Signed in as tester")).toBeVisible();
});

test("PR head race preserves the draft and refreshes the snapshot without posting", async ({ page }) => {
  await installHost(page, pullTarget(), { authenticated: true });
  await page.goto("/panel.html");
  await waitForSignedInComments(page);
  await openNewLineComment(page, 2);
  await page.locator(".inline-comment-editor-row textarea").fill("Keep this draft");
  await page.evaluate(() => { window.__fake.headRace = true; });
  await page.locator(".inline-comment-editor-row").getByRole("button", { name: "Post comment" }).click();
  await expect(page.getByText(/head changed/u)).toBeVisible();
  await expect(page.locator(".inline-comment-editor-row textarea")).toHaveValue("Keep this draft");
  expect(await page.evaluate(() => window.__fake.calls.filter(call => call.op === "github.review.comment.create").length)).toBe(0);
});

for (const target of [commitTarget(), pullCommitTarget()]) {
  test(`${target.kind} posts canonical position comments to the URL repository`, async ({ page }) => {
    await installHost(page, target, { authenticated: true });
    await page.goto(`/panel.html?kind=${target.kind}`);
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

test("content script activates when GitHub SPA navigation first enters a pull request", async ({ page }) => {
  await page.route("https://github.com/**", route => route.fulfill({
    status: 200,
    contentType: "text/html",
    body: "<!doctype html><title>GitHub fixture</title><main>fixture</main>",
  }));
  await page.addInitScript(() => {
    const listeners = [];
    window.__content = { listeners, messages: [] };
    window.chrome = {
      runtime: {
        onMessage: { addListener(listener) { listeners.push(listener); } },
        async sendMessage(message) { window.__content.messages.push(message); return { ok: true }; },
      },
    };
  });
  await page.goto("https://github.com/acme/widgets");
  await page.addScriptTag({ path: resolve(extensionRoot, "src/target.js") });
  await page.addScriptTag({ path: resolve(extensionRoot, "src/content-script.js") });

  const buttonText = () => page.evaluate(() => document
    .getElementById("moondiff-extension-root")
    ?.shadowRoot?.querySelector("button")?.textContent);
  const hasButtonRoot = () => page.evaluate(() => Boolean(document.getElementById("moondiff-extension-root")));

  await expect.poll(hasButtonRoot).toBe(false);
  await page.evaluate(() => window.__content.listeners[0]({ v: 1, op: "page.comments.changed" }));
  await expect.poll(hasButtonRoot).toBe(false);

  await page.evaluate(() => {
    history.pushState(null, "", "/acme/widgets/pull/7/files");
    dispatchEvent(new Event("turbo:load"));
  });
  await expect.poll(buttonText).toBe("Open in Moondiff");
  await page.evaluate(() => {
    history.pushState(null, "", "/acme/widgets/issues/7");
    dispatchEvent(new PopStateEvent("popstate"));
  });
  await expect.poll(hasButtonRoot).toBe(false);

  await page.evaluate(() => {
    history.pushState(null, "", "/acme/widgets/pull/8/commits/abcdef1");
    dispatchEvent(new PopStateEvent("popstate"));
  });
  await expect.poll(buttonText).toBe("Open in Moondiff");
  await page.evaluate(() => document
    .getElementById("moondiff-extension-root")
    .shadowRoot.querySelector("button").click());
  expect(await page.evaluate(() => window.__content.messages.at(-1))).toEqual({ v: 1, op: "panel.open" });

  await page.evaluate(() => window.__content.listeners[0]({ v: 1, op: "page.comments.changed" }));
  await expect.poll(buttonText).toBe("GitHub 上有新评论，刷新查看");
});
