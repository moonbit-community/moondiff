(function installMoondiffButton() {
  "use strict";

  const ROOT_ID = "moondiff-extension-root";
  let lastHref = "";
  let dirty = false;
  let opening = false;
  let host;
  let button;

  function ensureButton() {
    if (host?.isConnected) return;
    host = document.getElementById(ROOT_ID) || document.createElement("div");
    host.id = ROOT_ID;
    if (!host.shadowRoot) host.attachShadow({ mode: "open" });
    host.shadowRoot.replaceChildren();
    const style = document.createElement("style");
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
      button[data-dirty="true"] { border-color: #d29922; background: #6e4b00; }
      button:disabled { cursor: progress; opacity: .72; transform: none; }
    `;
    button = document.createElement("button");
    button.type = "button";
    button.addEventListener("click", event => {
      if (!event.isTrusted || opening) return;
      if (dirty) {
        location.reload();
        return;
      }
      opening = true;
      renderButton();
      (async () => {
        try {
          await chrome.runtime.sendMessage({ v: 1, op: "review.open" });
        } catch {
          // The button becomes available again so the user can retry.
        } finally {
          opening = false;
          renderButton();
        }
      })();
    });
    host.shadowRoot.append(style, button);
    document.documentElement.append(host);
    renderButton();
  }

  function renderButton() {
    if (!button) return;
    button.dataset.dirty = String(dirty);
    button.disabled = opening;
    if (opening) button.setAttribute("aria-busy", "true");
    else button.removeAttribute("aria-busy");
    button.textContent = dirty
      ? "GitHub 上有新评论，刷新查看"
      : "Open in Moondiff";
    button.setAttribute(
      "aria-label",
      dirty ? "GitHub has new comments; refresh this page" : "Open this change in Moondiff",
    );
  }

  function syncRoute() {
    if (lastHref === location.href) return;
    lastHref = location.href;
    dirty = false;
    const target = globalThis.MoondiffTarget?.parseGitHubTarget(location.href);
    if (!target) {
      host?.remove();
      host = undefined;
      button = undefined;
      return;
    }
    ensureButton();
    renderButton();
  }

  chrome.runtime.onMessage.addListener(message => {
    if (message?.v === 1 && message?.op === "page.comments.changed") {
      const target = globalThis.MoondiffTarget?.parseGitHubTarget(location.href);
      const changed = globalThis.MoondiffTarget?.parseTargetHash(message?.args?.route);
      if (!globalThis.MoondiffTarget?.sameTarget(target, changed)) return;
      dirty = true;
      ensureButton();
      renderButton();
    }
  });

  for (const event of ["popstate", "hashchange", "turbo:load", "pjax:end"]) {
    addEventListener(event, () => queueMicrotask(syncRoute));
  }
  if (globalThis.navigation?.addEventListener) {
    globalThis.navigation.addEventListener("navigate", () => setTimeout(syncRoute, 0));
  }
  new MutationObserver(syncRoute).observe(document.documentElement, {
    childList: true,
    subtree: true,
  });
  syncRoute();
})();
