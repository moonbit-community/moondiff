import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import vm from 'node:vm';
import test from 'node:test';
import { buildExtension, readBuildConfig, outputRoot } from '../scripts/build.mjs';
const source = name => readFileSync(resolve(import.meta.dirname, '../src', name), 'utf8');
function event() { const listeners = []; return { addListener(fn) { listeners.push(fn); }, fire(...args) { for (const fn of listeners) fn(...args); } }; }
function area(values = {}) { return { values,
  async get(key) { return key === null ? { ...values } : { [key]: values[key] }; },
  async set(next) { Object.assign(values, next); },
  async remove(keys) { for (const key of Array.isArray(keys) ? keys : [keys]) delete values[key]; },
  async setAccessLevel() {},
}; }
function harness(previous) {
  const session = previous?.session || area();
  const local = previous?.local || area({ github_refresh_token: 'old-secret' });
  const tabs = previous?.tabs || new Map();
  const created = [], updated = [];
  let nextId = Math.max(99, ...tabs.keys()) + 1;
  const chrome = {
    storage: { session, local },
    runtime: { onMessage: event(), onInstalled: event() },
    tabs: {
      async create(options) { const tab = { id: nextId++, ...options }; created.push(options); tabs.set(tab.id, tab); return tab; },
      async get(id) { if (!tabs.has(id)) throw new Error('closed'); return tabs.get(id); },
      async update(id, options) { updated.push({ id, ...options }); if (!tabs.has(id)) throw new Error('closed'); Object.assign(tabs.get(id), options); return tabs.get(id); },
      onRemoved: event(), onUpdated: event(),
    },
  };
  const context = vm.createContext({ URL, chrome, MoondiffConfig: { playgroundUrl: 'https://diff.example/' } });
  vm.runInContext(source('target.js'), context);
  vm.runInContext(source('service-worker.js'), context);
  const sender = (url, id = 7) => ({ frameId: 0, url, tab: { id, windowId: 1 } });
  const open = (url, id) => context.MoondiffWorker.open({ v: 1, op: 'playground.open', args: { route: context.MoondiffTarget.targetPath(context.MoondiffTarget.parseGitHubTarget(url)) } }, sender(url, id));
  return { context, session, local, tabs, chrome, open, sender, created, updated };
}
const pr = 'https://github.com/Acme/Widgets/pull/42';

test('target aliases normalize commits, PR tabs, query strings, anchors and casing', () => {
  const { context: c } = harness();
  for (const suffix of ['', '/files', '/commits', '/files?diff=split#discussion_r1']) assert.equal(c.MoondiffTarget.targetPath(c.MoondiffTarget.parseGitHubTarget(pr + suffix)), '/acme/widgets/pull/42');
  for (const suffix of ['/changes/ABCDEF1', '/commits/abcdef1']) assert.equal(c.MoondiffTarget.targetPath(c.MoondiffTarget.parseGitHubTarget(pr + suffix)), '/acme/widgets/pull/42/commits/abcdef1');
  for (const invalid of ['http://github.com/a/b/pull/1', 'https://evil/a/b/pull/1', 'https://github.com/a/b/pull/0', 'https://user@github.com/a/b/pull/1']) assert.equal(c.MoondiffTarget.parseGitHubTarget(invalid), null);
  assert.equal(c.MoondiffTarget.parseTargetPath('#/a/b/pull/1'), null);
});

test('same source and target coalesce concurrent events; different changes never replace tabs', async () => {
  const h = harness();
  const results = await Promise.all([h.open(pr), h.open(pr + '/files'), h.open(pr + '/commits')]);
  assert.equal(h.created.length, 1); assert.equal(new Set(results.map(r => r.tabId)).size, 1);
  await h.open(pr); assert.equal(h.updated.length, 1);
  await h.open(pr.replace('42', '43')); await h.open(pr, 8);
  assert.equal(h.created.length, 3);
  assert(h.updated.every(update => !('url' in update)));
  assert.equal(h.created[0].url, 'https://diff.example/acme/widgets/pull/42');
  assert.equal(h.created[0].active, true);
});

test('session mappings survive worker restart and remove closed or navigated targets', async () => {
  const h = harness(); const first = await h.open(pr);
  const next = harness(h); assert.equal((await next.open(pr)).reused, true); assert.equal(next.created.length, 0);
  next.tabs.get(first.tabId).url = 'https://diff.example/acme/widgets/pull/99';
  assert.equal((await next.open(pr)).reused, false);
  assert(next.updated.every(update => !('url' in update)));
  const created = next.created.length;
  next.tabs.clear(); await next.context.MoondiffWorker.cleanTab(first.tabId);
  await next.open(pr); assert.equal(next.created.length, created + 1);
  await next.context.MoondiffWorker.cleanTab(7); assert.deepEqual(next.session.values, {});
});

test('in-flight tab navigation and inaccessible tab URLs are never reused', async () => {
  const h = harness(); const first = await h.open(pr);
  h.tabs.get(first.tabId).pendingUrl = 'https://elsewhere.example/';
  assert.equal((await h.open(pr)).reused, false);
  const second = [...h.tabs.keys()].at(-1); h.tabs.set(second, { id: second });
  assert.equal((await h.open(pr)).reused, false);
});

test('tab update cleanup preserves mappings for same path query and comment changes', async () => {
  const h = harness(); const first = await h.open(pr);
  const tab = h.tabs.get(first.tabId); tab.url += '?mode=split#comment-1';
  await h.context.MoondiffWorker.cleanTab(first.tabId, tab);
  assert.equal(Object.keys(h.session.values).length, 1);
  tab.url = 'https://diff.example/'; await h.context.MoondiffWorker.cleanTab(first.tabId, tab);
  assert.equal(Object.keys(h.session.values).length, 0);
});

test('untrusted frames, mismatched targets, and old RPCs are rejected; upgrade deletes credentials', async () => {
  const h = harness(); await h.context.MoondiffWorker.initialize(); assert.equal(h.local.values.github_refresh_token, undefined);
  for (const sender of [{ ...h.sender(pr), frameId: 1 }, h.sender('https://evil.example/')]) {
    await assert.rejects(h.context.MoondiffWorker.open({ v: 1, op: 'playground.open', args: { route: '/acme/widgets/pull/42' } }, sender));
  }
  await assert.rejects(h.context.MoondiffWorker.open({ v: 1, op: 'github.commit.get', args: {} }, h.sender(pr)));
  await assert.rejects(h.context.MoondiffWorker.open({ v: 1, op: 'playground.open', args: { route: '/acme/widgets/pull/99' } }, h.sender(pr)));
  assert.equal(h.created.length, 0);
});

test('content script auto-opens only normalized target transitions across initial load and SPA', async () => {
  const calls = []; const listeners = new Map(); let mutation;
  const location = { href: pr };
  const context = vm.createContext({ URL, location, queueMicrotask, setTimeout,
    document: { documentElement: {} }, chrome: { runtime: { async sendMessage(message) { calls.push(message); return { ok: true }; } } },
    addEventListener(name, fn) { listeners.set(name, fn); },
    MutationObserver: class { constructor(fn) { mutation = fn; } observe() {} },
  });
  vm.runInContext(source('target.js'), context); vm.runInContext(source('content-script.js'), context);
  assert.equal(calls.length, 1);
  for (const suffix of ['/files', '/commits', '?diff=split#comment']) { location.href = pr + suffix; mutation(); await new Promise(queueMicrotask); }
  assert.equal(calls.length, 1);
  location.href = pr.replace('42', '43'); listeners.get('turbo:load')(); mutation(); await new Promise(queueMicrotask);
  assert.equal(calls.length, 2);
  location.href = 'https://github.com/acme/widgets'; mutation(); await new Promise(queueMicrotask);
  location.href = pr; listeners.get('popstate')(); await new Promise(queueMicrotask); assert.equal(calls.length, 3);
});

test('build validates root deployment URL and emits only redirect assets and minimal permissions', () => {
  assert.equal(readBuildConfig({ MOONDIFF_PLAYGROUND_URL: 'http://localhost:4173/' }).playgroundUrl, 'http://localhost:4173/');
  for (const url of ['http://example.com/', 'https://diff.example/sub/', 'https://diff.example/?x=1', 'https://user:pass@diff.example/', 'https://diff.example/#x']) assert.throws(() => readBuildConfig({ MOONDIFF_PLAYGROUND_URL: url }));
  assert.throws(() => readBuildConfig({ MOONDIFF_PLAYGROUND_URL: 'http://localhost:4173/' }, 'webstore'));
  assert.throws(() => readBuildConfig({}));
  buildExtension({ env: { MOONDIFF_PLAYGROUND_URL: 'https://diff.example/' }, mode: 'webstore', log: { write() {} } });
  const manifest = JSON.parse(readFileSync(resolve(outputRoot, 'manifest.json')));
  assert.deepEqual(manifest.permissions, ['storage']); assert.deepEqual(manifest.host_permissions, ['https://diff.example/*']);
  assert(!readdirSync(outputRoot).some(name => /review|index\.js|styles/.test(name)));
  assert(!readFileSync(resolve(outputRoot, 'service-worker.js'), 'utf8').includes('fetch('));
});

test('SPA uses the current tab URL while validating the original sending document origin', async () => {
  const h = harness();
  const message = { v: 1, op: 'playground.open', args: { route: '/acme/widgets/pull/42' } };
  const sender = h.sender('https://github.com/acme/widgets'); sender.tab.url = pr;
  assert.equal((await h.context.MoondiffWorker.open(message, sender)).reused, false);
  await assert.rejects(h.context.MoondiffWorker.open(message, { ...sender, url: 'https://evil.example' }));
  await assert.rejects(h.context.MoondiffWorker.open(message, { ...sender, tab: { ...sender.tab, url: pr.replace('42', '99') } }));
});
