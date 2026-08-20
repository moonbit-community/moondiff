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
const opened = [];
const panelOptions = [];
const runtimeListeners = [];

globalThis.chrome = {
  runtime: {
    getURL: path => `chrome-extension://abcdefghijklmnop/${path}`,
    onMessage: { addListener: listener => runtimeListeners.push(listener) },
    onInstalled: { addListener() {} },
  },
  storage: { session, local },
  sidePanel: {
    async setOptions(options) { panelOptions.push(options); },
    async open(options) { opened.push(options); },
    async setPanelBehavior() {},
  },
  tabs: {
    async query() { return [{ id: 12, url: "https://github.com/acme/widgets/pull/7/files" }]; },
    async sendMessage() {},
    onUpdated: { addListener() {} },
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
const panelSender = { url: chrome.runtime.getURL("panel.html") };
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

async function resetAuthentication() {
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
    "https://github.com/acme%2Fescape/widgets/commit/abcdef1",
    "https://github.com/acme/widgets/compare/abcdef1...abcdef2",
  ]) assert.equal(Target.parseGitHubTarget(value), null, value);
});

test("panel open reparses sender.tab.url and RPC rejects untrusted or unknown operations", async () => {
  assert.equal(Worker.RPC_OPERATIONS.has("auth.login"), false);
  assert.equal(Worker.RPC_OPERATIONS.has("auth.device.start"), true);
  assert.equal(Worker.RPC_OPERATIONS.has("auth.device.poll"), true);
  assert.equal(Worker.RPC_OPERATIONS.has("auth.device.cancel"), true);
  const target = await Worker.handleMessage(
    { v: 1, op: "panel.open" },
    { tab: { id: 44, url: "https://github.com/acme/widgets/pull/9/files" }, url: "https://github.com/acme/widgets/pull/9/files" },
  );
  assert.deepEqual(target, { owner: "acme", repo: "widgets", kind: "pull", number: "9" });
  assert.deepEqual(opened.at(-1), { tabId: 44 });
  assert.deepEqual(panelOptions.at(-1), { tabId: 44, path: "panel.html", enabled: true });
  await assert.rejects(
    Worker.handleMessage(
      { v: 1, op: "panel.open", args: { owner: "attacker", repo: "ignored" } },
      { tab: { id: 44, url: "https://github.com/acme/widgets/pull/9/files" } },
    ),
    error => error.code === "invalid_arguments",
  );
  await assert.rejects(
    Worker.handleMessage({ v: 1, op: "github.pull.get", args: {} }, { url: "https://github.com/acme/widgets/pull/9" }),
    error => error.code === "untrusted_sender",
  );
  await assert.rejects(
    Worker.handleMessage({ v: 1, op: "fetch.any.url", args: { url: "https://evil.example" } }, panelSender),
    error => error.code === "operation_not_allowed",
  );
  await assert.rejects(
    Worker.handleMessage({ v: 1, op: "auth.status", args: { url: "https://evil.example" } }, panelSender),
    error => error.code === "invalid_arguments",
  );
  await assert.rejects(
    Worker.handleMessage({ v: 1, op: "auth.status", args: {}, requestId: "bad id" }, panelSender),
    error => error.code === "invalid_request_id",
  );
});

test("repository and path validation blocks URL and path injection", async () => {
  await assert.rejects(
    Worker.handleMessage({
      v: 1,
      op: "github.commit.get",
      args: { owner: "acme/../../evil", repo: "widgets", sha: "abcdef1", page: 1 },
    }, panelSender),
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
    panelSender,
  );
  assert.equal(status.authenticated, false);
  assert.equal(status.device_flow.user_code, "ABCD-EFGH");
  assert.equal(status.device_flow.verification_uri, "https://github.com/login/device");
  assert.equal(status.device_flow.poll_after, 7);
  assert.match(status.device_flow.flow_id, /^[A-Za-z0-9_-]{43}$/u);
  assert.doesNotMatch(JSON.stringify(status), /0123456789012345678901234567890123456789/u);
  assert.equal(session.values.github_device_flow.deviceCode, "0123456789012345678901234567890123456789");
  assert.equal(session.values.github_device_flow.intervalSeconds, 7);
});

test("auth.status restores a live device authorization and removes an expired one", async () => {
  const live = storedDeviceFlow("b".repeat(43), {
    expiresAt: Date.now() + 125_000,
    nextPollAt: Date.now() + 12_000,
  });
  await session.set({ github_device_flow: live });
  const restored = await Worker.handleMessage({ v: 1, op: "auth.status", args: {} }, panelSender);
  assert.equal(restored.device_flow.flow_id, live.flowId);
  assert.ok(restored.device_flow.expires_in >= 124 && restored.device_flow.expires_in <= 125);
  assert.ok(restored.device_flow.poll_after >= 11 && restored.device_flow.poll_after <= 12);
  assert.doesNotMatch(JSON.stringify(restored), /device-code-secret/u);

  await session.set({ github_device_flow: storedDeviceFlow("c".repeat(43), { expiresAt: Date.now() - 1 }) });
  const expired = await Worker.handleMessage({ v: 1, op: "auth.status", args: {} }, panelSender);
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
  }, panelSender);
  assert.equal(status.device_flow.flow_id, flow.flowId);
  assert.ok(status.device_flow.poll_after >= 19 && status.device_flow.poll_after <= 20);
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
  const status = await Worker.handleMessage({
    v: 1,
    op: "auth.device.poll",
    args: { flow_id: flow.flowId },
  }, panelSender);
  assert.equal(status.device_flow.flow_id, flow.flowId);
  assert.ok(status.device_flow.poll_after >= 4);
  assert.ok(session.values.github_device_flow.nextPollAt > Date.now());
});

test("slow_down raises the interval by at least five seconds", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  const flow = storedDeviceFlow("f".repeat(43), { intervalSeconds: 5, nextPollAt: Date.now() - 1 });
  await session.set({ github_device_flow: flow });
  globalThis.fetch = async () => Response.json({ error: "slow_down", interval: 8 });
  const status = await Worker.handleMessage({
    v: 1,
    op: "auth.device.poll",
    args: { flow_id: flow.flowId },
  }, panelSender);
  assert.equal(session.values.github_device_flow.intervalSeconds, 10);
  assert.ok(status.device_flow.poll_after >= 9);
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
      }, panelSender),
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
  let resolveFetch;
  let calls = 0;
  globalThis.fetch = async () => {
    calls += 1;
    return new Promise(resolve => { resolveFetch = resolve; });
  };
  const message = {
    v: 1,
    op: "auth.device.poll",
    args: { flow_id: flow.flowId },
  };
  const left = Worker.handleMessage(message, panelSender);
  const right = Worker.handleMessage(message, panelSender);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(calls, 1);
  resolveFetch(Response.json({ error: "authorization_pending" }));
  const [first, second] = await Promise.all([left, right]);
  assert.deepEqual(first, second);
});

test("cancelling an in-flight poll prevents a late token response from being stored", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  const flow = storedDeviceFlow("l".repeat(43), { nextPollAt: Date.now() - 1 });
  await session.set({ github_device_flow: flow });
  let resolveToken;
  globalThis.fetch = async input => {
    if (String(input) === "https://github.com/login/oauth/access_token") {
      return new Promise(resolve => { resolveToken = resolve; });
    }
    return Response.json({ login: "too-late" });
  };
  const pending = Worker.handleMessage({
    v: 1,
    op: "auth.device.poll",
    args: { flow_id: flow.flowId },
  }, panelSender);
  while (!resolveToken) await new Promise(resolve => setImmediate(resolve));
  const cancelled = await Worker.handleMessage({
    v: 1,
    op: "auth.device.cancel",
    args: { flow_id: flow.flowId },
  }, panelSender);
  assert.equal(cancelled.authenticated, false);
  resolveToken(Response.json({
    access_token: "late-access",
    expires_in: 3600,
    refresh_token: "late-refresh",
    refresh_token_expires_in: 7200,
  }));
  await assert.rejects(pending, error => error.code === "device_flow_replaced");
  assert.equal(session.values.github_access_token, undefined);
  assert.equal(local.values.github_refresh_token, undefined);
});

test("starting a replacement flow prevents the old poll from storing a late token", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  const oldFlow = storedDeviceFlow("q".repeat(43), { nextPollAt: Date.now() - 1 });
  await session.set({ github_device_flow: oldFlow });
  let resolveOldToken;
  globalThis.fetch = async input => {
    const url = String(input);
    if (url === "https://github.com/login/oauth/access_token") {
      return new Promise(resolve => { resolveOldToken = resolve; });
    }
    if (url === "https://github.com/login/device/code") {
      return Response.json({
        device_code: "new-device-code",
        user_code: "WXYZ-1234",
        expires_in: 900,
        interval: 5,
      });
    }
    return Response.json({ login: "too-late" });
  };
  const oldPoll = Worker.handleMessage({
    v: 1,
    op: "auth.device.poll",
    args: { flow_id: oldFlow.flowId },
  }, panelSender);
  while (!resolveOldToken) await new Promise(resolve => setImmediate(resolve));
  const replacement = await Worker.handleMessage(
    { v: 1, op: "auth.device.start", args: {} },
    panelSender,
  );
  assert.notEqual(replacement.device_flow.flow_id, oldFlow.flowId);
  resolveOldToken(Response.json({
    access_token: "old-access",
    expires_in: 3600,
    refresh_token: "old-refresh",
    refresh_token_expires_in: 7200,
  }));
  await assert.rejects(oldPoll, error => error.code === "device_flow_replaced");
  assert.equal(session.values.github_access_token, undefined);
  assert.equal(local.values.github_refresh_token, undefined);
  assert.equal(session.values.github_device_flow.flowId, replacement.device_flow.flow_id);
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
  }, panelSender);
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
  const pending = Worker.handleMessage({
    v: 1,
    op: "github.pull.get",
    args: { owner: "acme", repo: "widgets", number: "7" },
    requestId: "generation_7",
  }, panelSender);
  await Worker.handleMessage({
    v: 1,
    op: "request.cancel",
    args: { requestId: "generation_7" },
  }, panelSender);
  await assert.rejects(pending, error => error.name === "AbortError");
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
    assert.ok(entries.every(name => !name.endsWith(".map") && !name.includes(".dist-")));
    const manifest = JSON.parse(readStoredZipEntry(destination, "manifest.json").toString("utf8"));
    assert.equal(manifest.manifest_version, 3);
    assert.equal(manifest.minimum_chrome_version, "116");
    assert.deepEqual(manifest.permissions, ["sidePanel", "storage"]);
    assert.deepEqual(manifest.host_permissions, [
      "https://api.github.com/*",
      "https://github.com/login/device/code",
      "https://github.com/login/oauth/access_token",
    ]);
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
