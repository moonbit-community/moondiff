if (typeof importScripts === 'function') importScripts('config.js', 'target.js');
(() => {
  'use strict';
  const PREFIX = 'moondiff_target:';
  const pending = new Map();
  // Serialize storage mutations, including tab lifecycle events. Never store a
  // whole map snapshot: separate keys prevent concurrent opens losing entries.
  let mutation = Promise.resolve();
  function serialized(task) {
    const result = mutation.then(task, task);
    mutation = result.catch(() => {});
    return result;
  }
  function targetURL(route) { return new URL(route, MoondiffConfig.playgroundUrl).href; }
  function stillAtTarget(tab, url) {
    try {
      const current = new URL(tab.pendingUrl || tab.url);
      const expected = new URL(url);
      return current.origin === expected.origin && current.pathname === expected.pathname && !current.hash.startsWith('#/');
    } catch { return false; }
  }
  function validate(message, sender) {
    // Chrome keeps sender.url at the document's initial URL after pushState.
    // sender.tab.url reflects the current SPA target. Verify both its target
    // and the sending document's origin (which may originally be a repo home).
    const source = new URL(sender?.url);
    const target = MoondiffTarget.parseGitHubTarget(sender?.tab?.pendingUrl || sender?.tab?.url || sender?.url);
    const route = MoondiffTarget.targetPath(target);
    if (source.origin !== 'https://github.com' || source.username || source.password || sender?.frameId !== 0 || !Number.isInteger(sender?.tab?.id) || sender.tab.id < 0 || !route ||
      message?.v !== 1 || message.op !== 'playground.open' || message.args?.route !== route ||
      Object.keys(message).sort().join(',') !== 'args,op,v' || Object.keys(message.args).join(',') !== 'route') {
      throw new Error('Unsupported GitHub navigation.');
    }
    return route;
  }
  async function openOnce(sender, route, key) {
    const stored = (await chrome.storage.session.get(key))[key];
    const url = targetURL(route);
    if (stored) {
      try {
        const tab = await chrome.tabs.get(stored.tabId);
        if (stillAtTarget(tab, url)) {
          await chrome.tabs.update(tab.id, { active: true });
          return { tabId: tab.id, reused: true };
        }
      } catch { /* Closed tabs and inaccessible URLs cannot be reused. */ }
      await chrome.storage.session.remove(key);
    }
    const tab = await chrome.tabs.create({ url, active: true, openerTabId: sender.tab.id, windowId: sender.tab.windowId });
    await chrome.storage.session.set({ [key]: { tabId: tab.id, sourceTabId: sender.tab.id, url } });
    return { tabId: tab.id, reused: false };
  }
  function open(message, sender) {
    let route;
    try { route = validate(message, sender); } catch (error) { return Promise.reject(error); }
    const key = `${PREFIX}${sender.tab.id}:${route}`;
    if (pending.has(key)) return pending.get(key);
    const promise = serialized(() => openOnce(sender, route, key));
    pending.set(key, promise);
    promise.finally(() => { if (pending.get(key) === promise) pending.delete(key); }).catch(() => {});
    return promise;
  }
  function cleanTab(tabId, tab) {
    return serialized(async () => {
      const values = await chrome.storage.session.get(null);
      const remove = Object.entries(values).filter(([key, value]) => key.startsWith(PREFIX) &&
        ((!tab && value.sourceTabId === tabId) || (value.tabId === tabId && (!tab || !stillAtTarget(tab, value.url))))).map(([key]) => key);
      if (remove.length) await chrome.storage.session.remove(remove);
    });
  }
  const legacyKeys = ['github_access_token', 'github_access_expires_at', 'github_login', 'github_device_flow', 'github_refresh_token', 'github_refresh_expires_at'];
  async function initialize() {
    await chrome.storage.session.setAccessLevel?.({ accessLevel: 'TRUSTED_CONTEXTS' });
    await Promise.all([chrome.storage.session.remove(legacyKeys), chrome.storage.local.remove(legacyKeys)]);
  }
  initialize().catch(() => {});
  chrome.runtime.onInstalled.addListener(() => initialize().catch(() => {}));
  chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    open(message, sender).then(value => sendResponse({ ok: true, value }), error => sendResponse({ ok: false, error: { message: error.message } }));
    return true;
  });
  chrome.tabs.onRemoved.addListener(tabId => { cleanTab(tabId).catch(() => {}); });
  chrome.tabs.onUpdated.addListener((tabId, change, tab) => {
    if (change.url || change.status === 'loading') cleanTab(tabId, tab).catch(() => {});
  });
  globalThis.MoondiffWorker = Object.freeze({ open, cleanTab, stillAtTarget, initialize });
})();
