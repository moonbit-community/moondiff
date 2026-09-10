(() => {
  'use strict';
  const ROOT_ID = 'moondiff-extension-root';
  let scheduled = false;
  let opening = false;
  let host;
  let button;

  function renderButton() {
    if (!button) return;
    button.disabled = opening;
    if (opening) button.setAttribute('aria-busy', 'true');
    else button.removeAttribute('aria-busy');
  }

  async function open(event) {
    if (!event.isTrusted || opening) return;
    // GitHub may have navigated since the button was inserted.
    const route = MoondiffTarget.targetPath(MoondiffTarget.parseGitHubTarget(location.href));
    if (!route) { schedule(); return; }
    opening = true;
    renderButton();
    try {
      await chrome.runtime.sendMessage({ v: 1, op: 'playground.open', args: { route } });
    } catch {
      // Restore the button so the user can retry a worker/startup failure.
    } finally {
      opening = false;
      renderButton();
    }
  }

  function ensureButton() {
    if (host?.isConnected) return;
    host = document.getElementById(ROOT_ID) || document.createElement('div');
    host.id = ROOT_ID;
    if (!host.shadowRoot) host.attachShadow({ mode: 'open' });
    const style = document.createElement('style');
    style.textContent = `
      :host { all: initial; }
      button {
        position: fixed;
        right: 20px;
        bottom: 20px;
        z-index: 2147483647;
        max-width: min(310px, calc(100vw - 32px));
        border: 1px solid rgba(255,255,255,.18);
        border-radius: 999px;
        padding: 10px 16px;
        color: #fff;
        background: #171717;
        box-shadow: 0 8px 26px rgba(0,0,0,.28);
        font: 600 13px/1.25 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;
        cursor: pointer;
      }
      button:hover { background: #2b2b2b; transform: translateY(-1px); }
      button:focus-visible { outline: 3px solid #54aeff; outline-offset: 2px; }
      button:disabled { cursor: progress; opacity: .72; transform: none; }
    `;
    button = document.createElement('button');
    button.type = 'button';
    button.textContent = 'Open in Moondiff';
    button.setAttribute('aria-label', 'Open this change in Moondiff');
    button.addEventListener('click', open);
    host.shadowRoot.replaceChildren(style, button);
    document.documentElement.append(host);
    renderButton();
  }

  function sync() {
    scheduled = false;
    const target = MoondiffTarget.targetPath(MoondiffTarget.parseGitHubTarget(location.href));
    if (!target) {
      host?.remove();
      host = undefined;
      button = undefined;
      return;
    }
    // GitHub can replace page elements without changing the URL.
    ensureButton();
  }

  function schedule() {
    if (!scheduled) { scheduled = true; queueMicrotask(sync); }
  }
  for (const event of ['popstate', 'hashchange', 'turbo:load', 'pjax:end']) addEventListener(event, schedule);
  globalThis.navigation?.addEventListener('navigate', () => setTimeout(schedule, 0));
  new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
  sync();
})();
