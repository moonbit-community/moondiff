"use strict";

const pending = new Map();
let sequence = 0;
let latestGeneration = 0;

function rpc(op, args = {}, requestId) {
  return chrome.runtime.sendMessage({ v: 1, op, args, requestId }).then(response => {
    if (response?.ok) return response.value;
    const error = new Error(response?.error?.message || "The extension request failed.");
    error.status = response?.error?.status || 0;
    error.code = response?.error?.code || "extension_error";
    throw error;
  });
}

function cancelOlderRequests(generation) {
  if (!Number.isInteger(generation) || generation <= latestGeneration) return;
  latestGeneration = generation;
  for (const [requestId, entry] of pending) {
    if (entry.generation > 0 && entry.generation < generation) {
      rpc("request.cancel", { requestId }).catch(() => {});
      entry.reject(Object.assign(new Error("A newer diff replaced this request."), {
        name: "AbortError",
        status: 499,
      }));
      pending.delete(requestId);
    }
  }
}

function hostRequest(op, args, options = {}) {
  const generation = Number.isInteger(options.generation) ? options.generation : 0;
  cancelOlderRequests(generation);
  const requestId = `review_${Date.now().toString(36)}_${(sequence += 1).toString(36)}`;
  return new Promise((resolve, reject) => {
    pending.set(requestId, { generation, reject });
    rpc(op, args, requestId).then(resolve, reject).finally(() => pending.delete(requestId));
  });
}

function showBootstrapError(error) {
  const app = document.getElementById("app");
  app.replaceChildren();
  const review = document.createElement("main");
  review.className = "review-bootstrap-error";
  const heading = document.createElement("h1");
  heading.textContent = "Moondiff could not open this page";
  const message = document.createElement("p");
  message.textContent = error?.message || String(error);
  review.append(heading, message);
  app.append(review);
}

try {
  const target = globalThis.MoondiffTarget.parseTargetHash(location.hash);
  if (!target) throw new Error("Open Moondiff from a supported GitHub pull request or commit page.");
  globalThis.__MOONDIFF_EXTENSION_HOST__ = Object.freeze({
    target,
    request: hostRequest,
    notifyCommentsChanged() {
      rpc("page.comments.changed", { route: location.hash }).catch(() => {});
    },
  });
  addEventListener("focus", () => {
    document.dispatchEvent(new Event("visibilitychange"));
  });
  await import("./index.js");
} catch (error) {
  showBootstrapError(error);
}
