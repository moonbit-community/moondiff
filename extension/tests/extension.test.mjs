import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
  outputRoot,
  readBuildConfig,
} from "../scripts/build.mjs";
import { packageExtension } from "../scripts/package.mjs";

const PRODUCTION_BUILD_ENV = Object.freeze({
  MOONDIFF_GITHUB_CLIENT_ID: "Iv1.production-shaped-client",
  MOONDIFF_GITHUB_INSTALL_URL: "https://github.com/apps/moondiff-production/installations/new",
});

function readStoredZipEntry(archivePath, expectedName) {
  const archive = readFileSync(archivePath);
  let offset = 0;
  while (offset + 30 <= archive.length && archive.readUInt32LE(offset) === 0x04034b50) {
    const compressedSize = archive.readUInt32LE(offset + 18);
    const nameLength = archive.readUInt16LE(offset + 26);
    const extraLength = archive.readUInt16LE(offset + 28);
    const nameStart = offset + 30;
    const dataStart = nameStart + nameLength + extraLength;
    const name = archive.toString("utf8", nameStart, nameStart + nameLength);
    if (name === expectedName) return archive.subarray(dataStart, dataStart + compressedSize);
    offset = dataStart + compressedSize;
  }
  throw new Error(`ZIP entry not found: ${expectedName}`);
}

function storageArea(initial = {}) {
  const values = { ...initial };
  const accessLevels = [];
  return {
    values,
    accessLevels,
    async get(keys) {
      if (keys == null) return { ...values };
      if (typeof keys === "string") return { [keys]: values[keys] };
      if (Array.isArray(keys)) return Object.fromEntries(keys.map(key => [key, values[key]]));
      return Object.fromEntries(Object.keys(keys).map(key => [key, values[key] ?? keys[key]]));
    },
    async set(next) { Object.assign(values, next); },
    async remove(keys) {
      for (const key of Array.isArray(keys) ? keys : [keys]) delete values[key];
    },
    async setAccessLevel(options) { accessLevels.push(options); },
  };
}

const session = storageArea();
const local = storageArea();
const createdTabs = [];
const sentTabMessages = [];
const runtimeListeners = [];

globalThis.chrome = {
  runtime: {
    getURL: path => `chrome-extension://abcdefghijklmnop/${path}`,
    onMessage: { addListener: listener => runtimeListeners.push(listener) },
    onInstalled: { addListener() {} },
  },
  storage: { session, local },
  tabs: {
    async create(options) {
      createdTabs.push(options);
      return { id: 100 + createdTabs.length, ...options };
    },
    async sendMessage(tabId, message) {
      sentTabMessages.push({ tabId, message });
    },
  },
};
globalThis.MoondiffConfig = {
  clientId: "Iv1.unit-test",
  installUrl: "https://github.com/apps/moondiff-test/installations/new",
};

await import("../src/target.js");
await import("../src/service-worker.js");

const Target = globalThis.MoondiffTarget;
const Worker = globalThis.MoondiffWorker;
const reviewSender = {
  url: `${chrome.runtime.getURL("review.html")}#/acme/widgets/pull/7`,
  documentId: "review-document",
  tab: { id: 91, windowId: 6 },
};
const authenticationKeys = [
  "github_access_token",
  "github_access_expires_at",
  "github_login",
  "github_device_flow",
];

function storedDeviceFlow(flowId = "a".repeat(43), overrides = {}) {
  return {
    flowId,
    userCode: "ABCD-EFGH",
    deviceCode: "device-code-secret",
    expiresAt: Date.now() + 900_000,
    intervalSeconds: 5,
    nextPollAt: Date.now(),
    ...overrides,
  };
}

function deferred() {
  let resolve;
  const promise = new Promise(resolvePromise => { resolve = resolvePromise; });
  return { promise, resolve };
}

async function waitForTestSignal(promise, label) {
  let timer;
  try {
    await Promise.race([
      promise,
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error(`Timed out waiting for ${label}.`)), 2_000);
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}

function assertReportedRemainingSeconds(reported, deadline, maximum) {
  const remainingNow = Math.max(0, Math.ceil((deadline - Date.now()) / 1000));
  assert.ok(Number.isSafeInteger(reported), `Expected an integer remaining time, received ${reported}.`);
  assert.ok(reported >= remainingNow, `Reported ${reported}s, but the deadline still has ${remainingNow}s remaining.`);
  assert.ok(reported <= maximum, `Reported ${reported}s, exceeding the expected maximum of ${maximum}s.`);
}

async function resetAuthentication() {
  createdTabs.length = 0;
  sentTabMessages.length = 0;
  await session.remove(authenticationKeys);
  await local.remove(["github_refresh_token", "github_refresh_expires_at"]);
}

test.beforeEach(resetAuthentication);

test("target parser covers GitHub SPA route variants without broadening hosts", () => {
  assert.deepEqual(Target.parseGitHubTarget("https://github.com/acme/widgets/commit/abcdef1"), {
    owner: "acme", repo: "widgets", kind: "commit", sha: "abcdef1",
  });
  for (const suffix of ["", "/files", "/commits"]) {
    assert.deepEqual(Target.parseGitHubTarget(`https://github.com/acme/widgets/pull/17${suffix}`), {
      owner: "acme", repo: "widgets", kind: "pull", number: "17",
    });
  }
  for (const segment of ["commits", "changes"]) {
    const target = Target.parseGitHubTarget(`https://github.com/acme/widgets/pull/17/${segment}/abcdef1`);
    assert.equal(target.kind, "pull_commit");
    assert.equal(target.number, "17");
    assert.equal(target.sha, "abcdef1");
  }
  for (const value of [
    "http://github.com/acme/widgets/pull/17",
    "https://evil.example/acme/widgets/pull/17",
    "https://github.com/acme/widgets/pull/0",
    "https://github.com/acme/widgets/pull/017",
    "https://github.com/acme%2Fescape/widgets/commit/abcdef1",
    "https://github.com/acme/widgets/compare/abcdef1...abcdef2",
  ]) assert.equal(Target.parseGitHubTarget(value), null, value);
});

test("target hashes strictly round-trip commit, pull, and pull-commit routes", () => {
  const targets = [{
    owner: "acme", repo: "widgets", kind: "commit", sha: "abcdef1",
  }, {
    owner: "acme", repo: "widgets", kind: "pull", number: "17",
  }, {
    owner: "acme", repo: "widgets", kind: "pull_commit", number: "17", sha: "abcdef1",
  }];
  for (const target of targets) {
    assert.deepEqual(Target.parseTargetHash(Target.targetHash(target)), target);
  }
  for (const value of [
    "",
    "/acme/widgets/pull/17",
    "#acme/widgets/pull/17",
    "#/acme/widgets/pull/0",
    "#/acme/widgets/pull/017",
    "#/acme/widgets/pull/17/files",
    "#/acme/widgets/pull/17/changes/abcdef1",
    "#/acme/widgets/commit/abcdef",
    "#/acme/widgets/commit/abcdef1/extra",
    "#/acme%2Fescape/widgets/commit/abcdef1",
    "#/acme/widgets/commit/abcdef1?diff=split",
  ]) assert.equal(Target.parseTargetHash(value), null, value);
  assert.equal(Target.targetHash({ owner: "acme", repo: "widgets", kind: "pull", number: "0" }), "");
});

test("review.open uses the explicit route and only trusts sender.url as the GitHub origin", async () => {
  assert.equal(Worker.RPC_OPERATIONS.has("auth.login"), false);
  assert.equal(Worker.RPC_OPERATIONS.has("panel.open"), false);
  assert.equal(Worker.RPC_OPERATIONS.has("target.current"), false);
  assert.equal(Worker.RPC_OPERATIONS.has("review.open"), true);
  assert.equal(Worker.RPC_OPERATIONS.has("auth.device.start"), true);
  assert.equal(Worker.RPC_OPERATIONS.has("auth.device.poll"), true);
  assert.equal(Worker.RPC_OPERATIONS.has("auth.device.cancel"), true);
  const sender = {
    tab: { id: 44, windowId: 6, url: "https://github.com/acme/widgets/pull/8" },
    url: "https://github.com/acme/widgets/pull/7/files",
  };
  for (let click = 0; click < 2; click += 1) {
    const target = await Worker.handleMessage({
      v: 1,
      op: "review.open",
      args: { route: "#/acme/widgets/pull/8" },
    }, sender);
    assert.deepEqual(target, { owner: "acme", repo: "widgets", kind: "pull", number: "8" });
  }
  assert.equal(createdTabs.length, 2);
  for (const options of createdTabs) {
    assert.deepEqual(options, {
      url: `${chrome.runtime.getURL("review.html")}#/acme/widgets/pull/8`,
      active: true,
      windowId: 6,
      openerTabId: 44,
    });
  }
  await assert.rejects(
    Worker.handleMessage(
      { v: 1, op: "review.open", args: { owner: "attacker", repo: "ignored" } },
      sender,
    ),
    error => error.code === "invalid_arguments",
  );
  await assert.rejects(
    Worker.handleMessage(
      { v: 1, op: "review.open" },
      {
        tab: { id: 44, windowId: 6, url: "https://github.com/acme/widgets/pull/8" },
        url: "https://evil.example/unsupported",
      },
    ),
    error => error.code === "invalid_arguments",
  );
  await assert.rejects(
    Worker.handleMessage(
      { v: 1, op: "review.open", args: { route: "#/acme/widgets/pull/8" } },
      {
        tab: { id: 44, windowId: 6, url: "https://github.com/acme/widgets/pull/8" },
        url: "https://evil.example/unsupported",
      },
    ),
    error => error.code === "untrusted_sender",
  );
  for (const route of [
    "#/acme/widgets/pull/017",
    "#/acme/widgets/pull/8/files",
    "https://github.com/acme/widgets/pull/8",
  ]) {
    await assert.rejects(
      Worker.handleMessage({ v: 1, op: "review.open", args: { route } }, sender),
      error => error.code === "unsupported_github_page",
    );
  }
  assert.equal(createdTabs.length, 2);
});

test("RPC rejects untrusted review senders and unknown operations", async () => {
  await assert.rejects(
    Worker.handleMessage({ v: 1, op: "github.pull.get", args: {} }, { url: "https://github.com/acme/widgets/pull/9" }),
    error => error.code === "untrusted_sender",
  );
  await assert.rejects(
    Worker.handleMessage(
      { v: 1, op: "auth.status", args: {} },
      { url: chrome.runtime.getURL("panel.html") },
    ),
    error => error.code === "untrusted_sender",
  );
  await assert.rejects(
    Worker.handleMessage(
      { v: 1, op: "auth.status", args: {} },
      { url: `${chrome.runtime.getURL("review.html")}?unexpected=1` },
    ),
    error => error.code === "untrusted_sender",
  );
  await assert.rejects(
    Worker.handleMessage({ v: 1, op: "fetch.any.url", args: { url: "https://evil.example" } }, reviewSender),
    error => error.code === "operation_not_allowed",
  );
  await assert.rejects(
    Worker.handleMessage({ v: 1, op: "auth.status", args: { url: "https://evil.example" } }, reviewSender),
    error => error.code === "invalid_arguments",
  );
  await assert.rejects(
    Worker.handleMessage({ v: 1, op: "auth.status", args: {}, requestId: "bad id" }, reviewSender),
    error => error.code === "invalid_request_id",
  );
});

test("comment notifications validate the route and target the review opener", async () => {
  const route = "#/acme/widgets/pull/7";
  const result = await Worker.handleMessage({
    v: 1,
    op: "page.comments.changed",
    args: { route },
  }, {
    ...reviewSender,
    tab: { id: 91, openerTabId: 44, windowId: 6 },
  });
  assert.deepEqual(result, { notified: true });
  assert.deepEqual(sentTabMessages, [{
    tabId: 44,
    message: { v: 1, op: "page.comments.changed", args: { route } },
  }]);

  for (const invalidRoute of [
    "",
    "#/acme/widgets/pull/0",
    "#/acme/widgets/pull/017",
    "#/acme/widgets/pull/7/files",
  ]) {
    await assert.rejects(
      Worker.handleMessage({
        v: 1,
        op: "page.comments.changed",
        args: { route: invalidRoute },
      }, reviewSender),
      error => error.code === "invalid_target",
    );
  }
});

test("comment notifications silently skip a closed opener tab", async t => {
  const originalSendMessage = chrome.tabs.sendMessage;
  t.after(() => { chrome.tabs.sendMessage = originalSendMessage; });
  chrome.tabs.sendMessage = async () => {
    throw new Error("No tab with id: 44");
  };
  const result = await Worker.handleMessage({
    v: 1,
    op: "page.comments.changed",
    args: { route: "#/acme/widgets/pull/7" },
  }, {
    ...reviewSender,
    tab: { id: 91, openerTabId: 44, windowId: 6 },
  });
  assert.deepEqual(result, { notified: false });
});

test("repository and path validation blocks URL and path injection", async () => {
  await assert.rejects(
    Worker.handleMessage({
      v: 1,
      op: "github.commit.get",
      args: { owner: "acme/../../evil", repo: "widgets", sha: "abcdef1", page: 1 },
    }, reviewSender),
    error => error.code === "invalid_repository",
  );
  for (const path of ["/etc/passwd", "src/../secret", "src\\secret", "src//main.mbt", "src/\0bad"]) {
    assert.throws(() => Worker.validatePath(path), error => error.code === "invalid_path");
  }
  assert.equal(Worker.validatePath("src/main file.mbt"), "src/main file.mbt");
});

test("device authorization requests only the client id and keeps the device code private", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  globalThis.fetch = async (input, init) => {
    assert.equal(String(input), "https://github.com/login/device/code");
    assert.equal(init.method, "POST");
    assert.equal(new Headers(init.headers).get("accept"), "application/json");
    assert.deepEqual([...new URLSearchParams(init.body)], [["client_id", "Iv1.unit-test"]]);
    return Response.json({
      device_code: "0123456789012345678901234567890123456789",
      user_code: "ABCD-EFGH",
      verification_uri: "https://attacker.invalid/device",
      expires_in: 900,
      interval: 7,
    });
  };
  const status = await Worker.handleMessage(
    { v: 1, op: "auth.device.start", args: {} },
    reviewSender,
  );
  assert.equal(status.authenticated, false);
  assert.equal(status.device_flow.user_code, "ABCD-EFGH");
  assert.equal(status.device_flow.verification_uri, "https://github.com/login/device");
  assertReportedRemainingSeconds(
    status.device_flow.poll_after,
    session.values.github_device_flow.nextPollAt,
    7,
  );
  assert.match(status.device_flow.flow_id, /^[A-Za-z0-9_-]{43}$/u);
  assert.doesNotMatch(JSON.stringify(status), /0123456789012345678901234567890123456789/u);
  assert.equal(session.values.github_device_flow.deviceCode, "0123456789012345678901234567890123456789");
  assert.equal(session.values.github_device_flow.intervalSeconds, 7);
});

test("device authorization start reuses signed-in identity and a live flow", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  globalThis.fetch = async () => { throw new Error("an idempotent start must not contact GitHub"); };
  await session.set({
    github_access_token: "access-current",
    github_access_expires_at: Date.now() + 60_000,
    github_login: "octocat",
  });
  assert.deepEqual(
    await Worker.handleMessage({ v: 1, op: "auth.device.start", args: {} }, reviewSender),
    {
      authenticated: true,
      login: "octocat",
      install_url: "https://github.com/apps/moondiff-test/installations/new",
    },
  );

  await session.remove(["github_access_token", "github_access_expires_at", "github_login"]);
  const flow = storedDeviceFlow("r".repeat(43), {
    nextPollAt: Date.now() + 15_000,
  });
  await session.set({ github_device_flow: flow });
  const reused = await Worker.handleMessage(
    { v: 1, op: "auth.device.start", args: {} },
    reviewSender,
  );
  assert.equal(reused.device_flow.flow_id, flow.flowId);
  assertReportedRemainingSeconds(reused.device_flow.poll_after, flow.nextPollAt, 15);
});

test("concurrent device authorization starts share one GitHub request", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  const requestStarted = deferred();
  const response = deferred();
  let calls = 0;
  globalThis.fetch = async input => {
    assert.equal(String(input), "https://github.com/login/device/code");
    calls += 1;
    requestStarted.resolve();
    return response.promise;
  };
  const message = { v: 1, op: "auth.device.start", args: {} };
  const left = Worker.handleMessage(message, reviewSender);
  const right = Worker.handleMessage(message, reviewSender);
  await waitForTestSignal(requestStarted.promise, "the shared device authorization request");
  assert.equal(calls, 1);
  response.resolve(Response.json({
    device_code: "shared-device-code",
    user_code: "ABCD-EFGH",
    expires_in: 900,
    interval: 5,
  }));
  const [first, second] = await Promise.all([left, right]);
  assert.deepEqual(first, second);
  assert.equal(first.device_flow.flow_id, session.values.github_device_flow.flowId);
});

test("auth.status restores a live device authorization and removes an expired one", async () => {
  const live = storedDeviceFlow("b".repeat(43), {
    expiresAt: Date.now() + 125_000,
    nextPollAt: Date.now() + 12_000,
  });
  await session.set({ github_device_flow: live });
  const restored = await Worker.handleMessage({ v: 1, op: "auth.status", args: {} }, reviewSender);
  assert.equal(restored.device_flow.flow_id, live.flowId);
  assertReportedRemainingSeconds(restored.device_flow.expires_in, live.expiresAt, 125);
  assertReportedRemainingSeconds(restored.device_flow.poll_after, live.nextPollAt, 12);
  assert.doesNotMatch(JSON.stringify(restored), /device-code-secret/u);

  await session.set({ github_device_flow: storedDeviceFlow("c".repeat(43), { expiresAt: Date.now() - 1 }) });
  const expired = await Worker.handleMessage({ v: 1, op: "auth.status", args: {} }, reviewSender);
  assert.equal(expired.device_flow, undefined);
  assert.equal(session.values.github_device_flow, undefined);
});

test("an early device poll returns the remaining wait without contacting GitHub", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  const flow = storedDeviceFlow("d".repeat(43), { nextPollAt: Date.now() + 20_000 });
  await session.set({ github_device_flow: flow });
  globalThis.fetch = async () => { throw new Error("early polling must not fetch"); };
  const status = await Worker.handleMessage({
    v: 1,
    op: "auth.device.poll",
    args: { flow_id: flow.flowId },
  }, reviewSender);
  assert.equal(status.device_flow.flow_id, flow.flowId);
  assertReportedRemainingSeconds(status.device_flow.poll_after, flow.nextPollAt, 20);
});

test("authorization_pending advances the server-owned poll deadline", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  const flow = storedDeviceFlow("e".repeat(43), { nextPollAt: Date.now() - 1 });
  await session.set({ github_device_flow: flow });
  globalThis.fetch = async (input, init) => {
    assert.equal(String(input), "https://github.com/login/oauth/access_token");
    const body = new URLSearchParams(init.body);
    assert.deepEqual([...body.keys()].sort(), ["client_id", "device_code", "grant_type"]);
    assert.equal(body.get("device_code"), "device-code-secret");
    assert.equal(body.get("grant_type"), "urn:ietf:params:oauth:grant-type:device_code");
    return Response.json({ error: "authorization_pending" });
  };
  const pollStartedAt = Date.now();
  const status = await Worker.handleMessage({
    v: 1,
    op: "auth.device.poll",
    args: { flow_id: flow.flowId },
  }, reviewSender);
  assert.equal(status.device_flow.flow_id, flow.flowId);
  const deadline = session.values.github_device_flow.nextPollAt;
  assert.ok(deadline >= pollStartedAt + flow.intervalSeconds * 1000);
  assertReportedRemainingSeconds(status.device_flow.poll_after, deadline, flow.intervalSeconds);
});

test("slow_down raises the interval by at least five seconds", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  const flow = storedDeviceFlow("f".repeat(43), { intervalSeconds: 5, nextPollAt: Date.now() - 1 });
  await session.set({ github_device_flow: flow });
  globalThis.fetch = async () => Response.json({ error: "slow_down", interval: 8 });
  const pollStartedAt = Date.now();
  const status = await Worker.handleMessage({
    v: 1,
    op: "auth.device.poll",
    args: { flow_id: flow.flowId },
  }, reviewSender);
  const stored = session.values.github_device_flow;
  assert.equal(stored.intervalSeconds, 10);
  assert.ok(stored.nextPollAt >= pollStartedAt + stored.intervalSeconds * 1000);
  assertReportedRemainingSeconds(status.device_flow.poll_after, stored.nextPollAt, stored.intervalSeconds);
});

test("expired, denied, invalid, and disabled device flows fail stably and are cleared", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  const cases = [
    ["expired_token", "device_flow_expired"],
    ["token_expired", "device_flow_expired"],
    ["access_denied", "device_flow_denied"],
    ["incorrect_device_code", "device_flow_invalid"],
    ["device_flow_disabled", "device_flow_disabled"],
  ];
  for (let index = 0; index < cases.length; index += 1) {
    const [githubError, rpcCode] = cases[index];
    const flow = storedDeviceFlow(String.fromCharCode(103 + index).repeat(43), { nextPollAt: Date.now() - 1 });
    await session.set({ github_device_flow: flow });
    globalThis.fetch = async () => Response.json({ error: githubError });
    await assert.rejects(
      Worker.handleMessage({
        v: 1,
        op: "auth.device.poll",
        args: { flow_id: flow.flowId },
      }, reviewSender),
      error => error.code === rpcCode,
    );
    assert.equal(session.values.github_device_flow, undefined);
  }
});

test("concurrent device polls share one GitHub request", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  const flow = storedDeviceFlow("k".repeat(43), { nextPollAt: Date.now() - 1 });
  await session.set({ github_device_flow: flow });
  const fetchStarted = deferred();
  const fetchResponse = deferred();
  let calls = 0;
  globalThis.fetch = async () => {
    calls += 1;
    fetchStarted.resolve();
    return fetchResponse.promise;
  };
  const message = {
    v: 1,
    op: "auth.device.poll",
    args: { flow_id: flow.flowId },
  };
  const left = Worker.handleMessage(message, reviewSender);
  const right = Worker.handleMessage(message, reviewSender);
  await waitForTestSignal(fetchStarted.promise, "the shared device poll request");
  assert.equal(calls, 1);
  fetchResponse.resolve(Response.json({ error: "authorization_pending" }));
  const [first, second] = await Promise.all([left, right]);
  assert.deepEqual(first, second);
});

test("cancelling an in-flight poll prevents a late token response from being stored", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  const flow = storedDeviceFlow("l".repeat(43), { nextPollAt: Date.now() - 1 });
  await session.set({ github_device_flow: flow });
  const tokenRequestStarted = deferred();
  const tokenResponse = deferred();
  globalThis.fetch = async input => {
    if (String(input) === "https://github.com/login/oauth/access_token") {
      tokenRequestStarted.resolve();
      return tokenResponse.promise;
    }
    return Response.json({ login: "too-late" });
  };
  const pending = Worker.handleMessage({
    v: 1,
    op: "auth.device.poll",
    args: { flow_id: flow.flowId },
  }, reviewSender);
  await waitForTestSignal(tokenRequestStarted.promise, "the cancellable device token request");
  const cancelled = await Worker.handleMessage({
    v: 1,
    op: "auth.device.cancel",
    args: { flow_id: flow.flowId },
  }, reviewSender);
  assert.equal(cancelled.authenticated, false);
  tokenResponse.resolve(Response.json({
    access_token: "late-access",
    expires_in: 3600,
    refresh_token: "late-refresh",
    refresh_token_expires_in: 7200,
  }));
  await assert.rejects(pending, error => error.code === "device_flow_replaced");
  assert.equal(session.values.github_access_token, undefined);
  assert.equal(local.values.github_refresh_token, undefined);
});

test("starting while a live flow is polling reuses that flow", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  const oldFlow = storedDeviceFlow("q".repeat(43), { nextPollAt: Date.now() - 1 });
  await session.set({ github_device_flow: oldFlow });
  const oldTokenRequestStarted = deferred();
  const oldTokenResponse = deferred();
  let deviceCodeCalls = 0;
  globalThis.fetch = async input => {
    const url = String(input);
    if (url === "https://github.com/login/oauth/access_token") {
      oldTokenRequestStarted.resolve();
      return oldTokenResponse.promise;
    }
    if (url === "https://github.com/login/device/code") {
      deviceCodeCalls += 1;
      throw new Error("a live device flow must be reused");
    }
    return Response.json({ login: "too-late" });
  };
  const oldPoll = Worker.handleMessage({
    v: 1,
    op: "auth.device.poll",
    args: { flow_id: oldFlow.flowId },
  }, reviewSender);
  await waitForTestSignal(oldTokenRequestStarted.promise, "the replaceable device token request");
  const reused = await Worker.handleMessage(
    { v: 1, op: "auth.device.start", args: {} },
    reviewSender,
  );
  assert.equal(reused.device_flow.flow_id, oldFlow.flowId);
  assert.equal(deviceCodeCalls, 0);
  oldTokenResponse.resolve(Response.json({
    access_token: "old-access",
    expires_in: 3600,
    refresh_token: "old-refresh",
    refresh_token_expires_in: 7200,
  }));
  const signedIn = await oldPoll;
  assert.equal(signedIn.authenticated, true);
  assert.equal(session.values.github_access_token, "old-access");
  assert.equal(local.values.github_refresh_token, "old-refresh");
  assert.equal(session.values.github_device_flow, undefined);
});

test("a new device code can be generated after explicitly cancelling the live flow", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  const oldFlow = storedDeviceFlow("s".repeat(43));
  await session.set({ github_device_flow: oldFlow });
  await Worker.handleMessage({
    v: 1,
    op: "auth.device.cancel",
    args: { flow_id: oldFlow.flowId },
  }, reviewSender);
  let calls = 0;
  globalThis.fetch = async input => {
    assert.equal(String(input), "https://github.com/login/device/code");
    calls += 1;
    return Response.json({
      device_code: "new-device-code",
      user_code: "WXYZ-1234",
      expires_in: 900,
      interval: 5,
    });
  };
  const replacement = await Worker.handleMessage(
    { v: 1, op: "auth.device.start", args: {} },
    reviewSender,
  );
  assert.equal(calls, 1);
  assert.notEqual(replacement.device_flow.flow_id, oldFlow.flowId);
});

test("successful device authorization stores rotated tokens, reads /user, and clears the flow", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  const flow = storedDeviceFlow("m".repeat(43), { nextPollAt: Date.now() - 1 });
  await session.set({ github_device_flow: flow });
  const urls = [];
  globalThis.fetch = async input => {
    urls.push(String(input));
    if (String(input) === "https://github.com/login/oauth/access_token") {
      return Response.json({
        access_token: "device-access",
        expires_in: 3600,
        refresh_token: "device-refresh",
        refresh_token_expires_in: 7200,
      });
    }
    return Response.json({ login: "octocat" });
  };
  const status = await Worker.handleMessage({
    v: 1,
    op: "auth.device.poll",
    args: { flow_id: flow.flowId },
  }, reviewSender);
  assert.deepEqual(urls, [
    "https://github.com/login/oauth/access_token",
    "https://api.github.com/user",
  ]);
  assert.deepEqual(status, {
    authenticated: true,
    login: "octocat",
    install_url: "https://github.com/apps/moondiff-test/installations/new",
  });
  assert.equal(session.values.github_access_token, "device-access");
  assert.equal(session.values.github_login, "octocat");
  assert.equal(local.values.github_refresh_token, "device-refresh");
  assert.equal(session.values.github_device_flow, undefined);
});

test("session and local credential stores are restricted to trusted contexts", async () => {
  session.accessLevels.length = 0;
  local.accessLevels.length = 0;
  await Worker.configureStorageAccess();
  assert.deepEqual(session.accessLevels, [{ accessLevel: "TRUSTED_CONTEXTS" }]);
  assert.deepEqual(local.accessLevels, [{ accessLevel: "TRUSTED_CONTEXTS" }]);
});

test("refresh rotation is merged and persists both rotated tokens", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  await session.remove(["github_access_token", "github_access_expires_at", "github_login"]);
  await local.set({
    github_refresh_token: "refresh-old",
    github_refresh_expires_at: Date.now() + 60_000,
  });
  let calls = 0;
  globalThis.fetch = async (input, init) => {
    calls += 1;
    assert.equal(String(input), "https://github.com/login/oauth/access_token");
    const body = new URLSearchParams(init.body);
    assert.deepEqual([...body.keys()].sort(), ["client_id", "grant_type", "refresh_token"]);
    assert.equal(body.get("refresh_token"), "refresh-old");
    assert.equal(body.has("client_secret"), false);
    return Response.json({
      access_token: "access-new",
      expires_in: 3600,
      refresh_token: "refresh-new",
      refresh_token_expires_in: 7200,
    });
  };
  const [left, right] = await Promise.all([
    Worker.refreshAccessToken(),
    Worker.refreshAccessToken(),
  ]);
  assert.equal(left, "access-new");
  assert.equal(right, "access-new");
  assert.equal(calls, 1);
  assert.equal(session.values.github_access_token, "access-new");
  assert.equal(local.values.github_refresh_token, "refresh-new");
});

test("an authenticated 401 refreshes and retries exactly once", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  await session.set({
    github_access_token: "access-old",
    github_access_expires_at: Date.now() + 60_000,
  });
  await local.set({
    github_refresh_token: "refresh-current",
    github_refresh_expires_at: Date.now() + 60_000,
  });
  const authorizations = [];
  let tokenCalls = 0;
  globalThis.fetch = async (input, init = {}) => {
    const url = String(input);
    if (url === "https://github.com/login/oauth/access_token") {
      tokenCalls += 1;
      return Response.json({
        access_token: "access-rotated",
        expires_in: 3600,
        refresh_token: "refresh-rotated",
        refresh_token_expires_in: 7200,
      });
    }
    authorizations.push(new Headers(init.headers).get("authorization"));
    if (authorizations.length === 1) return Response.json({ message: "Bad credentials" }, { status: 401, statusText: "Unauthorized" });
    return Response.json({ number: 7, head: { sha: "abcdef1" } });
  };
  const result = await Worker.dispatchGithub("github.pull.get", {
    owner: "acme", repo: "widgets", number: "7",
  });
  assert.equal(result.number, 7);
  assert.deepEqual(authorizations, ["Bearer access-old", "Bearer access-rotated"]);
  assert.equal(tokenCalls, 1);
});

test("cancelling one document during initial token refresh does not abort the shared refresh", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  await local.set({
    github_refresh_token: "refresh-shared",
    github_refresh_expires_at: Date.now() + 60_000,
  });
  const refreshStarted = deferred();
  const refreshResponse = deferred();
  let refreshSignal;
  let refreshCalls = 0;
  const apiCalls = [];
  globalThis.fetch = async (input, init = {}) => {
    const url = String(input);
    if (url === "https://github.com/login/oauth/access_token") {
      refreshCalls += 1;
      refreshSignal = init.signal;
      refreshStarted.resolve();
      return refreshResponse.promise;
    }
    apiCalls.push({ url, authorization: new Headers(init.headers).get("authorization") });
    return Response.json({ number: Number(url.split("/").at(-1)) });
  };
  const leftSender = { ...reviewSender, documentId: "refresh-left" };
  const rightSender = { ...reviewSender, documentId: "refresh-right" };
  const request = number => ({
    v: 1,
    op: "github.pull.get",
    args: { owner: "acme", repo: "widgets", number },
    requestId: "initial_refresh",
  });
  const left = Worker.handleMessage(request("7"), leftSender);
  const leftOutcome = left.catch(error => error);
  const right = Worker.handleMessage(request("8"), rightSender);
  await waitForTestSignal(refreshStarted.promise, "the initial shared refresh");
  await Worker.handleMessage({
    v: 1,
    op: "request.cancel",
    args: { requestId: "initial_refresh" },
  }, leftSender);
  assert.equal((await leftOutcome).name, "AbortError");
  assert.equal(refreshSignal.aborted, false);
  refreshResponse.resolve(Response.json({
    access_token: "access-shared",
    expires_in: 3600,
    refresh_token: "refresh-rotated",
    refresh_token_expires_in: 7200,
  }));
  assert.deepEqual(await right, { number: 8 });
  assert.equal(refreshCalls, 1);
  assert.deepEqual(apiCalls, [{
    url: "https://api.github.com/repos/acme/widgets/pulls/8",
    authorization: "Bearer access-shared",
  }]);
});

test("cancelling one document during a 401 retry does not abort the shared refresh", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  await session.set({
    github_access_token: "access-stale",
    github_access_expires_at: Date.now() + 60_000,
  });
  await local.set({
    github_refresh_token: "refresh-shared",
    github_refresh_expires_at: Date.now() + 60_000,
  });
  const bothRejected = deferred();
  const refreshStarted = deferred();
  const refreshResponse = deferred();
  let staleCalls = 0;
  let refreshCalls = 0;
  let refreshSignal;
  globalThis.fetch = async (input, init = {}) => {
    const url = String(input);
    if (url === "https://github.com/login/oauth/access_token") {
      refreshCalls += 1;
      refreshSignal = init.signal;
      refreshStarted.resolve();
      return refreshResponse.promise;
    }
    const authorization = new Headers(init.headers).get("authorization");
    if (authorization === "Bearer access-stale") {
      staleCalls += 1;
      if (staleCalls === 2) bothRejected.resolve();
      return Response.json(
        { message: "Bad credentials" },
        { status: 401, statusText: "Unauthorized" },
      );
    }
    return Response.json({ number: Number(url.split("/").at(-1)) });
  };
  const leftSender = { ...reviewSender, documentId: "retry-left" };
  const rightSender = { ...reviewSender, documentId: "retry-right" };
  const request = number => ({
    v: 1,
    op: "github.pull.get",
    args: { owner: "acme", repo: "widgets", number },
    requestId: "retry_refresh",
  });
  const left = Worker.handleMessage(request("7"), leftSender);
  const leftOutcome = left.catch(error => error);
  const right = Worker.handleMessage(request("8"), rightSender);
  await waitForTestSignal(bothRejected.promise, "both stale-token requests");
  await waitForTestSignal(refreshStarted.promise, "the shared 401 refresh");
  await Worker.handleMessage({
    v: 1,
    op: "request.cancel",
    args: { requestId: "retry_refresh" },
  }, leftSender);
  assert.equal((await leftOutcome).name, "AbortError");
  assert.equal(refreshSignal.aborted, false);
  refreshResponse.resolve(Response.json({
    access_token: "access-after-401",
    expires_in: 3600,
    refresh_token: "refresh-after-401",
    refresh_token_expires_in: 7200,
  }));
  assert.deepEqual(await right, { number: 8 });
  assert.equal(refreshCalls, 1);
});

test("logout aborts and drains a shared refresh before clearing credentials", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  await local.set({
    github_refresh_token: "refresh-before-logout",
    github_refresh_expires_at: Date.now() + 60_000,
  });
  const refreshStarted = deferred();
  const refreshResponse = deferred();
  let refreshSignal;
  globalThis.fetch = async (input, init = {}) => {
    if (String(input) === "https://github.com/login/oauth/access_token") {
      refreshSignal = init.signal;
      refreshStarted.resolve();
      // Deliberately ignore abort so the test covers a late response.
      return refreshResponse.promise;
    }
    throw new Error("the GitHub request must not continue after logout");
  };
  const pending = Worker.handleMessage({
    v: 1,
    op: "github.pull.get",
    args: { owner: "acme", repo: "widgets", number: "7" },
    requestId: "logout_refresh",
  }, reviewSender);
  const pendingOutcome = pending.catch(error => error);
  await waitForTestSignal(refreshStarted.promise, "the refresh being logged out");
  const logout = Worker.handleMessage(
    { v: 1, op: "auth.logout", args: {} },
    reviewSender,
  );
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.equal(refreshSignal.aborted, true);
  refreshResponse.resolve(Response.json({
    access_token: "late-access",
    expires_in: 3600,
    refresh_token: "late-refresh",
    refresh_token_expires_in: 7200,
  }));
  assert.deepEqual(await logout, {
    authenticated: false,
    install_url: "https://github.com/apps/moondiff-test/installations/new",
  });
  const refreshError = await pendingOutcome;
  assert.equal(refreshError.code, "authentication_required");
  assert.equal(session.values.github_access_token, undefined);
  assert.equal(session.values.github_login, undefined);
  assert.equal(local.values.github_refresh_token, undefined);
});

test("Contents API enforces the one MiB limit before returning base64", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  await session.remove(["github_access_token", "github_access_expires_at"]);
  await local.remove(["github_refresh_token", "github_refresh_expires_at"]);
  globalThis.fetch = async () => new Response(new Uint8Array(Worker.MAX_SOURCE_BYTES + 1));
  await assert.rejects(
    Worker.dispatchGithub("github.content.get", {
      owner: "acme", repo: "widgets", path: "src/main.mbt", ref: "abcdef1",
    }),
    error => error.status === 413 && error.code === "source_too_large",
  );
});

test("request.cancel aborts an in-flight GitHub operation", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  await session.remove(["github_access_token", "github_access_expires_at"]);
  await local.remove(["github_refresh_token", "github_refresh_expires_at"]);
  globalThis.fetch = async (_input, { signal } = {}) => new Promise((resolve, reject) => {
    if (signal?.aborted) {
      reject(new DOMException("Aborted", "AbortError"));
      return;
    }
    signal?.addEventListener("abort", () => reject(new DOMException("Aborted", "AbortError")), { once: true });
  });
  const tabOnlySender = { url: reviewSender.url, tab: reviewSender.tab };
  const pending = Worker.handleMessage({
    v: 1,
    op: "github.pull.get",
    args: { owner: "acme", repo: "widgets", number: "7" },
    requestId: "generation_7",
  }, tabOnlySender);
  await Worker.handleMessage({
    v: 1,
    op: "request.cancel",
    args: { requestId: "generation_7" },
  }, tabOnlySender);
  await assert.rejects(pending, error => error.name === "AbortError");
});

test("request.cancel only aborts a matching request from the same document", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  await session.remove(["github_access_token", "github_access_expires_at"]);
  await local.remove(["github_refresh_token", "github_refresh_expires_at"]);
  const fetches = new Map();
  const bothStarted = deferred();
  globalThis.fetch = async (input, { signal } = {}) => new Promise((resolve, reject) => {
    const entry = { resolve, signal };
    fetches.set(String(input), entry);
    if (fetches.size === 2) bothStarted.resolve();
    if (signal?.aborted) {
      reject(new DOMException("Aborted", "AbortError"));
      return;
    }
    signal?.addEventListener(
      "abort",
      () => reject(new DOMException("Aborted", "AbortError")),
      { once: true },
    );
  });
  const leftSender = { ...reviewSender, documentId: "document-left" };
  const rightSender = { ...reviewSender, documentId: "document-right" };
  const left = Worker.handleMessage({
    v: 1,
    op: "github.pull.get",
    args: { owner: "acme", repo: "widgets", number: "7" },
    requestId: "shared_request",
  }, leftSender);
  const leftOutcome = left.catch(error => error);
  const right = Worker.handleMessage({
    v: 1,
    op: "github.pull.get",
    args: { owner: "acme", repo: "widgets", number: "8" },
    requestId: "shared_request",
  }, rightSender);
  await waitForTestSignal(bothStarted.promise, "both isolated requests to start");

  await Worker.handleMessage({
    v: 1,
    op: "request.cancel",
    args: { requestId: "shared_request" },
  }, leftSender);
  await waitForTestSignal(leftOutcome, "the isolated left request to abort");
  const leftError = await leftOutcome;
  assert.equal(leftError.name, "AbortError");
  const rightFetch = fetches.get("https://api.github.com/repos/acme/widgets/pulls/8");
  assert.equal(rightFetch.signal.aborted, false);
  rightFetch.resolve(Response.json({ number: 8 }));
  assert.deepEqual(await right, { number: 8 });
});

test("finishing an older reused request id does not remove the current controller", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  await session.remove(["github_access_token", "github_access_expires_at"]);
  await local.remove(["github_refresh_token", "github_refresh_expires_at"]);
  const fetches = new Map();
  const bothStarted = deferred();
  globalThis.fetch = async (input, { signal } = {}) => new Promise((resolve, reject) => {
    const entry = { resolve, signal };
    fetches.set(String(input), entry);
    if (fetches.size === 2) bothStarted.resolve();
    if (signal?.aborted) {
      reject(new DOMException("Aborted", "AbortError"));
      return;
    }
    signal?.addEventListener(
      "abort",
      () => reject(new DOMException("Aborted", "AbortError")),
      { once: true },
    );
  });
  const first = Worker.handleMessage({
    v: 1,
    op: "github.pull.get",
    args: { owner: "acme", repo: "widgets", number: "7" },
    requestId: "reused_request",
  }, reviewSender);
  const second = Worker.handleMessage({
    v: 1,
    op: "github.pull.get",
    args: { owner: "acme", repo: "widgets", number: "8" },
    requestId: "reused_request",
  }, reviewSender);
  const secondOutcome = second.catch(error => error);
  await waitForTestSignal(bothStarted.promise, "both reused-id requests to start");

  fetches.get("https://api.github.com/repos/acme/widgets/pulls/7")
    .resolve(Response.json({ number: 7 }));
  assert.deepEqual(await first, { number: 7 });
  await Worker.handleMessage({
    v: 1,
    op: "request.cancel",
    args: { requestId: "reused_request" },
  }, reviewSender);
  await waitForTestSignal(secondOutcome, "the current reused-id request to abort");
  assert.equal((await secondOutcome).name, "AbortError");
});

test("comment RPC normalizes GitHub ids and nullable fields for MoonBit", () => {
  assert.deepEqual(Worker.commentForProtocol({
    id: 42,
    body: "hello",
    line: null,
    in_reply_to_id: 7,
    user: null,
  }), {
    id: "42",
    body: "hello",
    in_reply_to_id: "7",
  });
});

test("comment list RPC accepts only the exact fields for each target kind", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  const requests = [];
  globalThis.fetch = async input => {
    requests.push(String(input));
    return Response.json([]);
  };
  const repository = { owner: "acme", repo: "widgets" };
  const cases = [{
    args: { ...repository, kind: "pull", number: "17" },
    expected: [
      "https://api.github.com/repos/acme/widgets/issues/17/comments?per_page=100&page=1",
      "https://api.github.com/repos/acme/widgets/pulls/17/comments?per_page=100&page=1",
    ],
  }, {
    args: { ...repository, kind: "commit", sha: "abcdef1" },
    expected: [
      "https://api.github.com/repos/acme/widgets/commits/abcdef1/comments?per_page=100&page=1",
    ],
  }, {
    args: { ...repository, kind: "pull_commit", number: "17", sha: "abcdef1" },
    expected: [
      "https://api.github.com/repos/acme/widgets/commits/abcdef1/comments?per_page=100&page=1",
    ],
  }];

  for (const { args, expected } of cases) {
    requests.length = 0;
    assert.deepEqual(await Worker.dispatchGithub("github.comments.list", args), {
      issue_comments: [],
      review_comments: [],
      commit_comments: [],
    });
    assert.deepEqual(requests.sort(), expected.sort());
  }
});

test("comment list RPC rejects null, missing, mistyped, cross-kind, and unknown fields before fetch", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  let fetchCalls = 0;
  globalThis.fetch = async () => {
    fetchCalls += 1;
    return Response.json([]);
  };
  const repository = { owner: "acme", repo: "widgets" };
  const invalid = [
    { ...repository, kind: "pull", number: "17", sha: "abcdef1" },
    { ...repository, kind: "pull", number: "17", sha: null },
    { ...repository, kind: "commit", sha: "abcdef1", number: "17" },
    { ...repository, kind: "commit", sha: "abcdef1", number: null },
    { ...repository, kind: "pull" },
    { ...repository, kind: "commit" },
    { ...repository, kind: "pull_commit", number: "17" },
    { ...repository, kind: "pull_commit", sha: "abcdef1" },
    { ...repository, kind: "pull", number: null },
    { ...repository, kind: "commit", sha: null },
    { ...repository, kind: "pull_commit", number: null, sha: "abcdef1" },
    { ...repository, kind: "pull_commit", number: "17", sha: null },
    { ...repository, kind: "pull", number: 17 },
    { ...repository, kind: "commit", sha: 1234567 },
    { ...repository, kind: "pull", number: "0" },
    { ...repository, kind: "commit", sha: "not-a-sha" },
    { ...repository, kind: "pull_commit", number: "0", sha: "abcdef1" },
    { ...repository, kind: null, number: "17" },
    { ...repository, kind: "tag", sha: "abcdef1" },
    { ...repository, kind: "pull", number: "17", extra: true },
    { owner: "acme", kind: "pull", number: "17" },
    { repo: "widgets", kind: "pull", number: "17" },
    { ...repository, number: "17" },
    { owner: null, repo: "widgets", kind: "pull", number: "17" },
    { owner: "acme", repo: null, kind: "pull", number: "17" },
  ];

  for (const args of invalid) {
    await assert.rejects(
      Worker.dispatchGithub("github.comments.list", args),
      error => error.status === 400,
      JSON.stringify(args),
    );
  }
  assert.equal(fetchCalls, 0);
});

test("GitHub permission failures use a stable extension error code", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  globalThis.fetch = async () => Response.json(
    { message: "Resource not accessible by integration" },
    { status: 403, statusText: "Forbidden" },
  );
  await assert.rejects(
    Worker.dispatchGithub("github.comments.list", {
      owner: "acme", repo: "widgets", kind: "commit", sha: "abcdef1",
    }),
    error => error.status === 403 && error.code === "permission_denied",
  );
});

test("build config requires valid GitHub App values", () => {
  assert.throws(() => readBuildConfig({}), /Missing MOONDIFF_GITHUB_CLIENT_ID/u);
  assert.throws(() => readBuildConfig({
    MOONDIFF_GITHUB_CLIENT_ID: "Iv1.formal-client",
  }), /Missing MOONDIFF_GITHUB_INSTALL_URL/u);
  assert.deepEqual(readBuildConfig(PRODUCTION_BUILD_ENV), {
    clientId: PRODUCTION_BUILD_ENV.MOONDIFF_GITHUB_CLIENT_ID,
    installUrl: PRODUCTION_BUILD_ENV.MOONDIFF_GITHUB_INSTALL_URL,
  });
  assert.throws(() => readBuildConfig(PRODUCTION_BUILD_ENV, "release"), /Unknown extension build mode/u);
});

test("Web Store packaging rejects every form of the built-in test GitHub App config", () => {
  const temporary = mkdtempSync(join(tmpdir(), "moondiff-package-rejection-test-"));
  const destination = join(temporary, "extension.zip");
  try {
    assert.throws(() => packageExtension({
      destination,
      env: { MOONDIFF_EXTENSION_ALLOW_TEST_CONFIG: "1" },
      log: { write() {} },
    }), /ALLOW_TEST_CONFIG is not allowed in webstore builds/u);
    assert.throws(() => packageExtension({
      destination,
      env: {
        ...PRODUCTION_BUILD_ENV,
        MOONDIFF_GITHUB_CLIENT_ID: "Iv1.moondiff-test-client",
      },
      log: { write() {} },
    }), /test GitHub App client ID is not allowed/u);
    for (const installUrl of [
      "https://github.com/apps/moondiff-test/installations/new",
      "https://github.com/apps/moondiff-test/installations/new/?from=fixture",
    ]) {
      assert.throws(() => packageExtension({
        destination,
        env: {
          ...PRODUCTION_BUILD_ENV,
          MOONDIFF_GITHUB_INSTALL_URL: installUrl,
        },
        log: { write() {} },
      }), /test GitHub App installation URL is not allowed/u);
    }
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
});

test("Web Store package remains MV3-local and source-map free", () => {
  const temporary = mkdtempSync(join(tmpdir(), "moondiff-zip-test-"));
  try {
    const destination = join(temporary, "nested", "extension.zip");
    const { entries } = packageExtension({
      destination,
      env: PRODUCTION_BUILD_ENV,
      log: { write() {} },
    });
    assert.ok(entries.includes("manifest.json"));
    assert.ok(entries.includes("icons/icon-128.png"));
    assert.ok(entries.includes("review.html"));
    assert.ok(entries.includes("review-bootstrap.js"));
    assert.equal(entries.includes("panel.html"), false);
    assert.equal(entries.includes("panel-bootstrap.js"), false);
    assert.ok(entries.every(name => !name.endsWith(".map") && !name.includes(".dist-")));
    const manifest = JSON.parse(readStoredZipEntry(destination, "manifest.json").toString("utf8"));
    assert.equal(manifest.manifest_version, 3);
    assert.equal(manifest.minimum_chrome_version, "116");
    assert.deepEqual(manifest.permissions, ["storage"]);
    assert.equal("side_panel" in manifest, false);
    assert.equal(manifest.permissions.includes("sidePanel"), false);
    assert.deepEqual(manifest.host_permissions, [
      "https://api.github.com/*",
      "https://github.com/login/device/code",
      "https://github.com/login/oauth/access_token",
    ]);
    assert.deepEqual(manifest.content_scripts, [{
      matches: ["https://github.com/*"],
      js: ["target.js", "content-script.js"],
      run_at: "document_idle",
    }]);
    assert.equal(manifest.permissions.includes("identity"), false);
    assert.match(manifest.content_security_policy.extension_pages, /script-src 'self'/u);
    const configSource = readFileSync(join(outputRoot, "config.js"), "utf8");
    assert.doesNotMatch(configSource, /clientSecret|client_secret|MOONDIFF_GITHUB_CLIENT_SECRET/u);
    for (const name of entries.filter(name => name.endsWith(".js") || name.endsWith(".html"))) {
      const source = readFileSync(join(outputRoot, name), "utf8");
      assert.doesNotMatch(source, /\beval\s*\(|new\s+Function\b|sourceMappingURL/u, name);
      assert.doesNotMatch(source, /clientSecret|client_secret|MOONDIFF_GITHUB_CLIENT_SECRET/u, name);
      assert.doesNotMatch(source, /launchWebAuthFlow|chromiumapp\.org|Register callback/u, name);
      if (name.endsWith(".html")) assert.doesNotMatch(source, /<script[^>]+src=["']https?:/u, name);
    }
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
});
