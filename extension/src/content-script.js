(() => {
  'use strict';
  let lastTarget = '';
  let scheduled = false;
  function sync() {
    scheduled = false;
    const target = MoondiffTarget.targetPath(MoondiffTarget.parseGitHubTarget(location.href));
    if (target === lastTarget) return;
    lastTarget = target;
    if (!target) return;
    chrome.runtime.sendMessage({ v: 1, op: 'playground.open', args: { route: target } }).then(response => {
      if (!response?.ok && lastTarget === target) lastTarget = '';
    }).catch(() => {
      // Allow retry on the next real navigation after a worker/startup failure.
      if (lastTarget === target) lastTarget = '';
    });
  }
  function schedule() {
    if (!scheduled) { scheduled = true; queueMicrotask(sync); }
  }
  for (const event of ['popstate', 'hashchange', 'turbo:load', 'pjax:end']) addEventListener(event, schedule);
  globalThis.navigation?.addEventListener('navigate', () => setTimeout(schedule, 0));
  new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
  sync();
})();
