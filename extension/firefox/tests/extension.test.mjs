import assert from "node:assert/strict";
import {
  existsSync,
  readFileSync,
  readdirSync,
  statSync,
} from "node:fs";
import { basename, dirname, resolve } from "node:path";
import test from "node:test";
import vm from "node:vm";

import {
  buildExtension,
  outputRoot,
  readBuildConfig,
} from "../scripts/build.mjs";
import { packageExtension } from "../scripts/package.mjs";
import { extensionVersion } from "../scripts/version.mjs";

const source = name => readFileSync(resolve(import.meta.dirname, "../src", name), "utf8");
const plain = value => JSON.parse(JSON.stringify(value));

function event() {
  const listeners = [];
  return {
    addListener(listener) {
      listeners.push(listener);
    },
    fire(...args) {
      return listeners.map(listener => listener(...args));
    },
  };
}

function area(values = {}) {
  return {
    values,
    async get(key) {
      return key === null ? { ...values } : { [key]: values[key] };
    },
    async set(next) {
      Object.assign(values, next);
    },
    async remove(keys) {
      for (const key of Array.isArray(keys) ? keys : [keys]) delete values[key];
    },
  };
}

function harness(previous) {
  const session = previous?.session || area({ github_access_token: "old-session-secret" });
  const local = previous?.local || area({
    github_refresh_token: "old-local-secret",
    github_login: "old-user",
  });
  const tabs = previous?.tabs || new Map();
  const created = [];
  const updated = [];
  let nextId = Math.max(99, ...tabs.keys()) + 1;
  const browser = {
    storage: { session, local },
    runtime: { onMessage: event(), onInstalled: event() },
    tabs: {
      async create(options) {
        const tab = { id: nextId++, ...options };
        created.push(options);
        tabs.set(tab.id, tab);
        return tab;
      },
      async get(id) {
        if (!tabs.has(id)) throw new Error("closed");
        return tabs.get(id);
      },
      async update(id, options) {
        updated.push({ id, ...options });
        if (!tabs.has(id)) throw new Error("closed");
        Object.assign(tabs.get(id), options);
        return tabs.get(id);
      },
      onRemoved: event(),
      onUpdated: event(),
    },
  };
  const context = vm.createContext({
    URL,
    browser,
    MoondiffConfig: { playgroundUrl: "https://diff.example/" },
  });
  vm.runInContext(source("target.js"), context);
  vm.runInContext(source("background.js"), context);
  const sender = (url, id = 7) => ({
    frameId: 0,
    url,
    tab: { id, windowId: 1 },
  });
  const message = url => ({
    v: 1,
    op: "playground.open",
    args: {
      route: context.MoondiffTarget.targetPath(
        context.MoondiffTarget.parseGitHubTarget(url),
      ),
    },
  });
  const open = (url, id) => context.MoondiffBackground.open(message(url), sender(url, id));
  return {
    browser,
    context,
    created,
    local,
    message,
    open,
    sender,
    session,
    tabs,
    updated,
  };
}

const pr = "https://github.com/Acme/Widgets/pull/42";

test("target aliases normalize commits, PR tabs, query strings, anchors, and casing", () => {
  const { context: c } = harness();
  assert.equal(
    c.MoondiffTarget.targetPath(c.MoondiffTarget.parseGitHubTarget(
      "https://github.com/Acme/Widgets/commit/ABCDEF1?diff=split#comment",
    )),
    "/acme/widgets/commit/abcdef1",
  );
  for (const suffix of ["", "/files", "/commits", "/files?diff=split#discussion_r1"]) {
    assert.equal(
      c.MoondiffTarget.targetPath(c.MoondiffTarget.parseGitHubTarget(pr + suffix)),
      "/acme/widgets/pull/42",
    );
  }
  for (const suffix of ["/changes/ABCDEF1", "/commits/abcdef1"]) {
    assert.equal(
      c.MoondiffTarget.targetPath(c.MoondiffTarget.parseGitHubTarget(pr + suffix)),
      "/acme/widgets/pull/42/commits/abcdef1",
    );
  }
  for (const invalid of [
    "http://github.com/a/b/pull/1",
    "https://evil/a/b/pull/1",
    "https://github.com/a/b/pull/0",
    "https://user@github.com/a/b/pull/1",
  ]) {
    assert.equal(c.MoondiffTarget.parseGitHubTarget(invalid), null);
  }
  assert.equal(c.MoondiffTarget.parseTargetPath("#/a/b/pull/1"), null);
});

test("same source and target coalesce concurrent opens without replacing tabs", async () => {
  const h = harness();
  const results = await Promise.all([
    h.open(pr),
    h.open(`${pr}/files`),
    h.open(`${pr}/commits`),
  ]);
  assert.equal(h.created.length, 1);
  assert.equal(new Set(results.map(result => result.tabId)).size, 1);
  await h.open(pr);
  assert.equal(h.updated.length, 1);
  await h.open(pr.replace("42", "43"));
  await h.open(pr, 8);
  assert.equal(h.created.length, 3);
  assert(h.updated.every(update => !("url" in update)));
  assert.deepEqual(plain(h.created[0]), {
    url: "https://diff.example/acme/widgets/pull/42",
    active: true,
    openerTabId: 7,
    windowId: 1,
  });
});

test("session mappings survive event-page restart and clean closed or navigated tabs", async () => {
  const h = harness();
  const first = await h.open(pr);
  const restarted = harness(h);
  assert.equal((await restarted.open(pr)).reused, true);
  assert.equal(restarted.created.length, 0);

  restarted.tabs.get(first.tabId).url = "https://diff.example/acme/widgets/pull/99";
  assert.equal((await restarted.open(pr)).reused, false);
  assert(restarted.updated.every(update => !("url" in update)));

  const created = restarted.created.length;
  restarted.tabs.clear();
  await restarted.context.MoondiffBackground.cleanTab(first.tabId);
  await restarted.open(pr);
  assert.equal(restarted.created.length, created + 1);
  await restarted.context.MoondiffBackground.cleanTab(7);
  assert.deepEqual(restarted.session.values, {});
});

test("in-flight navigation and inaccessible destination URLs are never reused", async () => {
  const h = harness();
  const first = await h.open(pr);
  h.tabs.get(first.tabId).pendingUrl = "https://elsewhere.example/";
  assert.equal((await h.open(pr)).reused, false);
  const second = [...h.tabs.keys()].at(-1);
  h.tabs.set(second, { id: second });
  assert.equal((await h.open(pr)).reused, false);
});

test("tab lifecycle listeners preserve same-path anchors and remove stale mappings", async () => {
  const h = harness();
  const first = await h.open(pr);
  const tab = h.tabs.get(first.tabId);
  tab.url += "?mode=split#comment-1";
  await Promise.all(h.browser.tabs.onUpdated.fire(first.tabId, { url: tab.url }, tab));
  assert.equal(Object.keys(h.session.values).filter(key => key.startsWith("moondiff_target:")).length, 1);

  tab.url = "https://diff.example/";
  await Promise.all(h.browser.tabs.onUpdated.fire(first.tabId, { status: "loading" }, tab));
  assert.equal(Object.keys(h.session.values).filter(key => key.startsWith("moondiff_target:")).length, 0);

  const replacement = await h.open(pr);
  await Promise.all(h.browser.tabs.onRemoved.fire(replacement.tabId));
  assert.equal(Object.keys(h.session.values).filter(key => key.startsWith("moondiff_target:")).length, 0);
});

test("invalid messages and senders are rejected and legacy credentials are removed", async () => {
  const h = harness();
  await h.context.MoondiffBackground.initialize();
  assert.deepEqual(h.local.values, {});
  assert.equal(h.session.values.github_access_token, undefined);

  const valid = { v: 1, op: "playground.open", args: { route: "/acme/widgets/pull/42" } };
  for (const sender of [
    { ...h.sender(pr), frameId: 1 },
    h.sender("https://evil.example/"),
    { ...h.sender(pr), tab: { id: -1, windowId: 1 } },
  ]) {
    await assert.rejects(h.context.MoondiffBackground.open(valid, sender));
  }
  await assert.rejects(h.context.MoondiffBackground.open(
    { v: 1, op: "github.commit.get", args: {} },
    h.sender(pr),
  ));
  await assert.rejects(h.context.MoondiffBackground.open(
    { ...valid, extra: true },
    h.sender(pr),
  ));
  await assert.rejects(h.context.MoondiffBackground.open(
    { ...valid, args: { route: "/acme/widgets/pull/99" } },
    h.sender(pr),
  ));
  assert.equal(h.created.length, 0);
});

test("SPA messages use the current tab URL and retain the GitHub document origin", async () => {
  const h = harness();
  const message = { v: 1, op: "playground.open", args: { route: "/acme/widgets/pull/42" } };
  const sender = h.sender("https://github.com/acme/widgets");
  sender.tab.url = pr;
  assert.equal((await h.context.MoondiffBackground.open(message, sender)).reused, false);
  await assert.rejects(h.context.MoondiffBackground.open(
    message,
    { ...sender, url: "https://evil.example" },
  ));
  await assert.rejects(h.context.MoondiffBackground.open(
    message,
    { ...sender, tab: { ...sender.tab, url: pr.replace("42", "99") } },
  ));
});

test("runtime messages return native Promise responses for success and failure", async () => {
  const h = harness();
  const response = h.browser.runtime.onMessage.fire(h.message(pr), h.sender(pr))[0];
  assert.equal(typeof response?.then, "function");
  assert.deepEqual(plain(await response), {
    ok: true,
    value: { tabId: 100, reused: false },
  });

  const rejected = h.browser.runtime.onMessage.fire(
    { v: 1, op: "playground.open", args: { route: "/acme/widgets/pull/99" } },
    h.sender(pr),
  )[0];
  assert.equal(typeof rejected?.then, "function");
  assert.deepEqual(plain(await rejected), {
    ok: false,
    error: { message: "Unsupported GitHub navigation." },
  });
  const background = source("background.js");
  assert(!background.includes("sendResponse"));
  assert(!background.includes("chrome."));
});

test("build emits the Firefox 140 AMO manifest with minimal permissions", () => {
  assert.equal(
    readBuildConfig({ MOONDIFF_PLAYGROUND_URL: "http://localhost:4173/" }).playgroundUrl,
    "http://localhost:4173/",
  );
  for (const url of [
    "http://example.com/",
    "https://diff.example/sub/",
    "https://diff.example/?x=1",
    "https://user:pass@diff.example/",
    "https://diff.example/#x",
  ]) {
    assert.throws(() => readBuildConfig({ MOONDIFF_PLAYGROUND_URL: url }));
  }
  assert.throws(() => readBuildConfig(
    { MOONDIFF_PLAYGROUND_URL: "http://localhost:4173/" },
    "amo",
  ));
  assert.throws(() => readBuildConfig({}));
  assert.throws(() => readBuildConfig(
    { MOONDIFF_PLAYGROUND_URL: "https://diff.example/" },
    "webstore",
  ));

  buildExtension({
    env: { MOONDIFF_PLAYGROUND_URL: "https://diff.example/" },
    mode: "amo",
    log: { write() {} },
  });
  const manifest = JSON.parse(readFileSync(resolve(outputRoot, "manifest.json")));
  assert.equal(manifest.manifest_version, 3);
  assert.equal(manifest.version, extensionVersion);
  assert.deepEqual(manifest.permissions, ["storage"]);
  assert.deepEqual(manifest.host_permissions, ["https://diff.example/*"]);
  assert.deepEqual(manifest.background, {
    scripts: ["config.js", "target.js", "background.js"],
  });
  assert.deepEqual(manifest.content_scripts, [{
    matches: ["https://github.com/*"],
    js: ["target.js", "content-script.js"],
    run_at: "document_idle",
  }]);
  assert.deepEqual(manifest.browser_specific_settings, {
    gecko: {
      id: "moondiff@moonbit-community.github.io",
      strict_min_version: "140.0",
      data_collection_permissions: { required: ["browsingActivity"] },
    },
  });
  assert.equal(manifest.minimum_chrome_version, undefined);
  assert.equal(manifest.background.service_worker, undefined);
  assert.equal(manifest.browser_specific_settings.gecko_android, undefined);
  assert(!readdirSync(outputRoot).some(name => /review|index\.js|styles/.test(name)));
  assert(!readFileSync(resolve(outputRoot, "background.js"), "utf8").includes("fetch("));
});

test("AMO packaging lints first and writes the versioned Firefox ZIP", async () => {
  const { destination } = await packageExtension({
    env: { MOONDIFF_PLAYGROUND_URL: "https://diff.example/" },
    log: { write() {} },
  });
  assert.equal(basename(destination), `moondiff-firefox-${extensionVersion}.zip`);
  assert.equal(dirname(destination), resolve(import.meta.dirname, "../artifacts"));
  assert(existsSync(destination));
  assert(statSync(destination).size > 0);
  assert.deepEqual([...readFileSync(destination).subarray(0, 4)], [0x50, 0x4b, 0x03, 0x04]);
});
