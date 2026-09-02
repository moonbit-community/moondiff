if (typeof importScripts === "function") {
  importScripts("config.js", "target.js");
}

(function installMoondiffWorker(root) {
  "use strict";

  const API_VERSION = "2026-03-10";
  const MAX_SOURCE_BYTES = 1_048_576;
  const MAX_COMMENT_BYTES = 65_536;
  const SESSION_ACCESS = "github_access_token";
  const SESSION_EXPIRES = "github_access_expires_at";
  const SESSION_LOGIN = "github_login";
  const SESSION_DEVICE_FLOW = "github_device_flow";
  const LOCAL_REFRESH = "github_refresh_token";
  const LOCAL_REFRESH_EXPIRES = "github_refresh_expires_at";
  const DEVICE_VERIFICATION_URI = "https://github.com/login/device";
  const DEVICE_GRANT_TYPE = "urn:ietf:params:oauth:grant-type:device_code";
  const DEVICE_START_MAX_AGE_MS = 60_000;

  const RPC_OPERATIONS = new Set([
    "review.open",
    "page.comments.changed",
    "request.cancel",
    "auth.status",
    "auth.device.start",
    "auth.device.poll",
    "auth.device.cancel",
    "auth.logout",
    "github.commit.get",
    "github.pull.get",
    "github.compare.get",
    "github.pull.files",
    "github.content.get",
    "github.comments.list",
    "github.issue.comment.create",
    "github.review.comment.create",
    "github.commit.comment.create",
    "github.review.reply.create",
  ]);

  class RpcError extends Error {
    constructor(status, code, message) {
      super(message);
      this.name = "RpcError";
      this.status = status;
      this.code = code;
    }
  }

  const controllers = new Map();
  const devicePollPromises = new Map();
  let refreshPromise;
  let deviceMutation = Promise.resolve();

  function config() {
    const value = root.MoondiffConfig;
    if (!value?.clientId || !value?.installUrl) {
      throw new RpcError(500, "extension_not_configured", "This extension build is missing its GitHub App configuration.");
    }
    return value;
  }

  function requireObject(value) {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      throw new RpcError(400, "invalid_arguments", "RPC arguments must be an object.");
    }
    return value;
  }

  function exactKeys(value, required, optional = []) {
    requireObject(value);
    const allowed = new Set([...required, ...optional]);
    for (const key of Object.keys(value)) {
      if (!allowed.has(key)) {
        throw new RpcError(400, "invalid_arguments", `Unexpected RPC argument: ${key}`);
      }
    }
    for (const key of required) {
      if (!(key in value)) {
        throw new RpcError(400, "invalid_arguments", `Missing RPC argument: ${key}`);
      }
    }
    return value;
  }

  function validOwner(owner) {
    return typeof owner === "string" && root.MoondiffTarget.validators.OWNER.test(owner);
  }

  function validRepo(repo) {
    return typeof repo === "string" && root.MoondiffTarget.validators.REPO.test(repo);
  }

  function validSha(sha) {
    return typeof sha === "string" && root.MoondiffTarget.validators.SHA.test(sha);
  }

  function validNumber(number) {
    return typeof number === "string" && root.MoondiffTarget.validators.NUMBER.test(number);
  }

  function validateRepository(args) {
    if (!validOwner(args.owner) || !validRepo(args.repo)) {
      throw new RpcError(400, "invalid_repository", "The repository owner or name is invalid.");
    }
  }

  function validatePath(path) {
    if (
      typeof path !== "string" ||
      path.length === 0 ||
      path.length > 4096 ||
      path.startsWith("/") ||
      path.includes("\\") ||
      /[\0-\x1f\x7f]/.test(path) ||
      path.split("/").some(part => !part || part === "." || part === "..")
    ) {
      throw new RpcError(400, "invalid_path", "The repository path is invalid.");
    }
    return path;
  }

  function validateBody(body) {
    if (typeof body !== "string" || !body.trim() || new TextEncoder().encode(body).length > MAX_COMMENT_BYTES) {
      throw new RpcError(400, "invalid_comment", "A comment must contain between 1 and 65,536 UTF-8 bytes.");
    }
    return body;
  }

  function validatePositiveInteger(value, label) {
    if (!Number.isSafeInteger(value) || value <= 0) {
      throw new RpcError(400, "invalid_arguments", `${label} must be a positive integer.`);
    }
    return value;
  }

  function validateCommentId(value) {
    const text = String(value);
    if (!/^[1-9][0-9]*$/.test(text)) {
      throw new RpcError(400, "invalid_arguments", "The comment id is invalid.");
    }
    return text;
  }

  function repositoryPath(args) {
    validateRepository(args);
    return `/repos/${encodeURIComponent(args.owner)}/${encodeURIComponent(args.repo)}`;
  }

  function encodeRepositoryPath(path) {
    return validatePath(path).split("/").map(encodeURIComponent).join("/");
  }

  function apiUrl(path) {
    const url = new URL(path, "https://api.github.com");
    if (url.origin !== "https://api.github.com") {
      throw new RpcError(400, "invalid_api_path", "The GitHub API path is invalid.");
    }
    return url;
  }

  function base64Url(bytes) {
    let binary = "";
    for (const byte of bytes) binary += String.fromCharCode(byte);
    return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/u, "");
  }

  function randomFlowId() {
    const bytes = new Uint8Array(32);
    crypto.getRandomValues(bytes);
    return base64Url(bytes);
  }

  function withDeviceMutation(task) {
    const run = deviceMutation.then(task, task);
    deviceMutation = run.catch(() => {});
    return run;
  }

  async function configureStorageAccess() {
    await Promise.all([
      chrome.storage.session.setAccessLevel?.({ accessLevel: "TRUSTED_CONTEXTS" }),
      chrome.storage.local.setAccessLevel?.({ accessLevel: "TRUSTED_CONTEXTS" }),
    ]);
  }

  async function clearCredentials() {
    await Promise.all([
      chrome.storage.session.remove([SESSION_ACCESS, SESSION_EXPIRES, SESSION_LOGIN]),
      chrome.storage.local.remove([LOCAL_REFRESH, LOCAL_REFRESH_EXPIRES]),
    ]);
  }

  async function clearAuthentication() {
    await withDeviceMutation(async () => {
      await Promise.all([
        clearCredentials(),
        chrome.storage.session.remove(SESSION_DEVICE_FLOW),
      ]);
    });
  }

  async function persistTokens(payload, login) {
    if (typeof payload.access_token !== "string" || !payload.access_token) {
      throw new RpcError(502, "oauth_exchange_failed", payload.error_description || payload.error || "GitHub did not return an access token.");
    }
    const now = Date.now();
    const session = {
      [SESSION_ACCESS]: payload.access_token,
      [SESSION_EXPIRES]: now + Math.max(0, Number(payload.expires_in || 0)) * 1000,
    };
    if (login) session[SESSION_LOGIN] = login;
    await chrome.storage.session.set(session);
    if (typeof payload.refresh_token === "string" && payload.refresh_token) {
      await chrome.storage.local.set({
        [LOCAL_REFRESH]: payload.refresh_token,
        [LOCAL_REFRESH_EXPIRES]: now + Math.max(0, Number(payload.refresh_token_expires_in || 0)) * 1000,
      });
    }
  }

  async function oauthPost(url, parameters, signal) {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams(parameters),
      signal,
    });
    const payload = await response.json().catch(() => ({}));
    return { response, payload };
  }

  async function tokenRequest(parameters, signal) {
    const { response, payload } = await oauthPost(
      "https://github.com/login/oauth/access_token",
      parameters,
      signal,
    );
    if (!response.ok || payload.error) {
      throw new RpcError(response.status || 502, "oauth_exchange_failed", payload.error_description || payload.error || "GitHub OAuth token exchange failed.");
    }
    return payload;
  }

  async function refreshAccessToken(signal) {
    if (refreshPromise) return refreshPromise;
    refreshPromise = (async () => {
      const local = await chrome.storage.local.get([LOCAL_REFRESH, LOCAL_REFRESH_EXPIRES]);
      const token = local[LOCAL_REFRESH];
      if (!token || Number(local[LOCAL_REFRESH_EXPIRES] || 0) <= Date.now()) {
        await clearCredentials();
        throw new RpcError(401, "authentication_required", "Sign in with GitHub to continue.");
      }
      const app = config();
      const payload = await tokenRequest({
        client_id: app.clientId,
        grant_type: "refresh_token",
        refresh_token: token,
      }, signal);
      await persistTokens(payload);
      return payload.access_token;
    })();
    try {
      return await refreshPromise;
    } finally {
      refreshPromise = undefined;
    }
  }

  async function accessToken(signal) {
    const session = await chrome.storage.session.get([SESSION_ACCESS, SESSION_EXPIRES]);
    if (session[SESSION_ACCESS] && Number(session[SESSION_EXPIRES] || 0) > Date.now() + 30_000) {
      return session[SESSION_ACCESS];
    }
    const local = await chrome.storage.local.get([LOCAL_REFRESH, LOCAL_REFRESH_EXPIRES]);
    if (local[LOCAL_REFRESH] && Number(local[LOCAL_REFRESH_EXPIRES] || 0) > Date.now()) {
      return refreshAccessToken(signal);
    }
    if (session[SESSION_ACCESS]) return session[SESSION_ACCESS];
    return null;
  }

  async function githubFetch(path, options = {}, retry = true) {
    const token = await accessToken(options.signal);
    const headers = new Headers(options.headers || {});
    headers.set("Accept", options.accept || "application/vnd.github+json");
    headers.set("X-GitHub-Api-Version", API_VERSION);
    if (token) headers.set("Authorization", `Bearer ${token}`);
    const { accept: _accept, ...requestOptions } = options;
    const response = await fetch(apiUrl(path), {
      ...requestOptions,
      headers,
    });
    if (response.status === 401 && token && retry) {
      await refreshAccessToken(options.signal);
      return githubFetch(path, options, false);
    }
    return response;
  }

  async function githubError(response) {
    const payload = await response.clone().json().catch(() => ({}));
    let message = payload.message || response.statusText || "GitHub request failed.";
    let code = `github_http_${response.status}`;
    if (response.status === 403 && response.headers.get("x-ratelimit-remaining") === "0") {
      code = "rate_limit";
      message = "GitHub API rate limit exceeded. Sign in or try again after the reset time.";
    } else if (response.status === 401) {
      code = "authentication_required";
      message = "Your GitHub session expired. Sign in again.";
    } else if (response.status === 403) {
      code = "permission_denied";
    } else if (response.status === 404) {
      code = "not_found_or_not_installed";
      message = "GitHub could not find this resource. For private repositories, sign in and install the GitHub App.";
    } else if (response.status === 422) {
      code = "invalid_comment_anchor";
    }
    return new RpcError(response.status, code, message);
  }

  async function githubJson(path, options = {}) {
    const response = await githubFetch(path, options);
    if (!response.ok) throw await githubError(response);
    return response.json();
  }

  async function githubJsonPages(path, signal) {
    const results = [];
    for (let page = 1; page <= 100; page += 1) {
      const separator = path.includes("?") ? "&" : "?";
      const values = await githubJson(`${path}${separator}per_page=100&page=${page}`, { signal });
      if (!Array.isArray(values)) throw new RpcError(502, "invalid_github_response", "GitHub returned an invalid paginated response.");
      results.push(...values);
      if (values.length < 100) return results;
    }
    throw new RpcError(422, "pagination_limit", "GitHub returned more comment pages than Moondiff can safely load.");
  }

  // MoonBit's JavaScript JSON codec represents Int64 values as decimal
  // strings, and optional fields as absent keys. Keep that detail inside the
  // extension RPC boundary instead of leaking GitHub's nullable JSON shape
  // into the shared review model.
  function commentForProtocol(comment) {
    if (!comment || typeof comment !== "object" || Array.isArray(comment)) {
      throw new RpcError(502, "invalid_github_response", "GitHub returned an invalid comment.");
    }
    const normalized = {};
    for (const [key, value] of Object.entries(comment)) {
      if (value === null || value === undefined) continue;
      normalized[key] = key === "id" || key === "in_reply_to_id"
        ? String(value)
        : value;
    }
    return normalized;
  }

  function authForProtocol(authenticated, login, installUrl, flow) {
    const status = { authenticated, install_url: installUrl };
    if (typeof login === "string" && login) status.login = login;
    if (!authenticated && flow) {
      const now = Date.now();
      status.device_flow = {
        flow_id: flow.flowId,
        user_code: flow.userCode,
        verification_uri: DEVICE_VERIFICATION_URI,
        expires_in: Math.max(0, Math.ceil((flow.expiresAt - now) / 1000)),
        poll_after: Math.max(0, Math.ceil((flow.nextPollAt - now) / 1000)),
      };
    }
    return status;
  }

  function isStartingDeviceFlow(flow) {
    return Boolean(
      flow &&
      typeof flow === "object" &&
      !Array.isArray(flow) &&
      flow.starting === true &&
      typeof flow.flowId === "string" &&
      Number.isFinite(flow.startedAt),
    );
  }

  function isStoredDeviceFlow(flow) {
    return Boolean(
      flow &&
      typeof flow === "object" &&
      !Array.isArray(flow) &&
      flow.starting !== true &&
      typeof flow.flowId === "string" &&
      typeof flow.userCode === "string" &&
      typeof flow.deviceCode === "string" &&
      Number.isFinite(flow.expiresAt) &&
      Number.isSafeInteger(flow.intervalSeconds) &&
      flow.intervalSeconds > 0 &&
      Number.isFinite(flow.nextPollAt),
    );
  }

  async function storedDeviceFlow() {
    const stored = await chrome.storage.session.get(SESSION_DEVICE_FLOW);
    return stored[SESSION_DEVICE_FLOW] || null;
  }

  async function clearDeviceFlowIfCurrent(flowId) {
    const current = await storedDeviceFlow();
    if (current?.flowId !== flowId) return false;
    await chrome.storage.session.remove(SESSION_DEVICE_FLOW);
    return true;
  }

  async function resumableDeviceFlow() {
    return withDeviceMutation(async () => {
      const flow = await storedDeviceFlow();
      if (isStoredDeviceFlow(flow)) {
        if (flow.expiresAt > Date.now()) return flow;
        await chrome.storage.session.remove(SESSION_DEVICE_FLOW);
        return null;
      }
      if (isStartingDeviceFlow(flow) && Date.now() - flow.startedAt <= DEVICE_START_MAX_AGE_MS) {
        return null;
      }
      if (flow) await chrome.storage.session.remove(SESSION_DEVICE_FLOW);
      return null;
    });
  }

  function validateFlowId(flowId) {
    if (typeof flowId !== "string" || !/^[A-Za-z0-9_-]{43}$/u.test(flowId)) {
      throw new RpcError(400, "invalid_arguments", "The device authorization flow id is invalid.");
    }
    return flowId;
  }

  function positiveInteger(value, fallback) {
    const number = Number(value);
    return Number.isSafeInteger(number) && number > 0 ? number : fallback;
  }

  function deviceFlowError(error, description) {
    const message = typeof description === "string" && description
      ? description
      : "GitHub device authorization failed.";
    if (error === "expired_token" || error === "token_expired") {
      return new RpcError(410, "device_flow_expired", "The GitHub device code expired. Start sign-in again.");
    }
    if (error === "access_denied") {
      return new RpcError(403, "device_flow_denied", "GitHub sign-in was denied. Start sign-in again to retry.");
    }
    if (error === "incorrect_device_code" || error === "bad_verification_code") {
      return new RpcError(400, "device_flow_invalid", "The GitHub device code is no longer valid. Start sign-in again.");
    }
    if (error === "device_flow_disabled") {
      return new RpcError(400, "device_flow_disabled", "Device Flow is not enabled for this GitHub App.");
    }
    if (error === "incorrect_client_credentials") {
      return new RpcError(500, "device_flow_client_invalid", "This extension build has an invalid GitHub App client ID.");
    }
    if (error === "unsupported_grant_type") {
      return new RpcError(500, "device_flow_grant_invalid", "GitHub rejected the Device Flow grant type.");
    }
    return new RpcError(502, "device_flow_failed", message);
  }

  async function startDeviceAuthorization(signal) {
    const app = config();
    const flowId = randomFlowId();
    await withDeviceMutation(() => chrome.storage.session.set({
      [SESSION_DEVICE_FLOW]: { starting: true, flowId, startedAt: Date.now() },
    }));
    let response;
    let payload;
    try {
      ({ response, payload } = await oauthPost(
        "https://github.com/login/device/code",
        { client_id: app.clientId },
        signal,
      ));
    } catch (error) {
      await withDeviceMutation(() => clearDeviceFlowIfCurrent(flowId));
      throw error;
    }
    if (!response.ok || payload.error) {
      await withDeviceMutation(() => clearDeviceFlowIfCurrent(flowId));
      throw deviceFlowError(
        payload.error,
        payload.error_description || `GitHub device authorization failed with HTTP ${response.status}.`,
      );
    }
    const expiresIn = positiveInteger(payload.expires_in, 0);
    const intervalSeconds = positiveInteger(payload.interval, 5);
    if (
      typeof payload.device_code !== "string" ||
      !payload.device_code ||
      typeof payload.user_code !== "string" ||
      !/^[A-Za-z0-9]{4}-[A-Za-z0-9]{4}$/u.test(payload.user_code) ||
      expiresIn === 0
    ) {
      await withDeviceMutation(() => clearDeviceFlowIfCurrent(flowId));
      throw new RpcError(502, "invalid_github_response", "GitHub returned an invalid device authorization response.");
    }
    const now = Date.now();
    const flow = {
      flowId,
      userCode: payload.user_code,
      deviceCode: payload.device_code,
      expiresAt: now + expiresIn * 1000,
      intervalSeconds,
      nextPollAt: now + intervalSeconds * 1000,
    };
    const installed = await withDeviceMutation(async () => {
      const current = await storedDeviceFlow();
      if (!isStartingDeviceFlow(current) || current.flowId !== flowId) return false;
      await chrome.storage.session.set({ [SESSION_DEVICE_FLOW]: flow });
      return true;
    });
    if (!installed) {
      throw new RpcError(409, "device_flow_replaced", "A newer GitHub device authorization replaced this request.");
    }
    return authForProtocol(false, null, app.installUrl, flow);
  }

  async function githubUserWithToken(token, signal) {
    const response = await fetch(apiUrl("/user"), {
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${token}`,
        "X-GitHub-Api-Version": API_VERSION,
      },
      signal,
    });
    if (!response.ok) throw await githubError(response);
    return response.json();
  }

  async function pendingDeviceStatus(flowId, payload, slowDown) {
    return withDeviceMutation(async () => {
      const flow = await storedDeviceFlow();
      if (!isStoredDeviceFlow(flow) || flow.flowId !== flowId) {
        throw new RpcError(409, "device_flow_replaced", "This GitHub device authorization is no longer active.");
      }
      if (flow.expiresAt <= Date.now()) {
        await chrome.storage.session.remove(SESSION_DEVICE_FLOW);
        throw deviceFlowError("expired_token");
      }
      const reportedInterval = positiveInteger(payload.interval, 0);
      const intervalSeconds = slowDown
        ? Math.max(flow.intervalSeconds + 5, reportedInterval)
        : Math.max(flow.intervalSeconds, reportedInterval);
      const updated = {
        ...flow,
        intervalSeconds,
        nextPollAt: slowDown
          ? Date.now() + intervalSeconds * 1000
          : Math.max(flow.nextPollAt, Date.now()),
      };
      await chrome.storage.session.set({ [SESSION_DEVICE_FLOW]: updated });
      return authForProtocol(false, null, config().installUrl, updated);
    });
  }

  async function pollDeviceAuthorizationOnce(flowId, signal) {
    const app = config();
    const reservation = await withDeviceMutation(async () => {
      const flow = await storedDeviceFlow();
      if (!isStoredDeviceFlow(flow) || flow.flowId !== flowId) {
        throw new RpcError(409, "device_flow_replaced", "This GitHub device authorization is no longer active.");
      }
      const now = Date.now();
      if (flow.expiresAt <= now) {
        await chrome.storage.session.remove(SESSION_DEVICE_FLOW);
        throw deviceFlowError("expired_token");
      }
      if (flow.nextPollAt > now) return { flow, fetch: false };
      const reserved = {
        ...flow,
        nextPollAt: now + flow.intervalSeconds * 1000,
      };
      await chrome.storage.session.set({ [SESSION_DEVICE_FLOW]: reserved });
      return { flow: reserved, fetch: true };
    });
    if (!reservation.fetch) {
      return authForProtocol(false, null, app.installUrl, reservation.flow);
    }
    const { response, payload } = await oauthPost(
      "https://github.com/login/oauth/access_token",
      {
        client_id: app.clientId,
        device_code: reservation.flow.deviceCode,
        grant_type: DEVICE_GRANT_TYPE,
      },
      signal,
    );
    if (payload.error === "authorization_pending") {
      return pendingDeviceStatus(flowId, payload, false);
    }
    if (payload.error === "slow_down") {
      return pendingDeviceStatus(flowId, payload, true);
    }
    if (!response.ok || payload.error) {
      if (payload.error) {
        await withDeviceMutation(() => clearDeviceFlowIfCurrent(flowId));
        throw deviceFlowError(payload.error, payload.error_description);
      }
      throw new RpcError(
        response.status || 502,
        "device_flow_failed",
        `GitHub device authorization failed with HTTP ${response.status}.`,
      );
    }
    if (typeof payload.access_token !== "string" || !payload.access_token) {
      await withDeviceMutation(() => clearDeviceFlowIfCurrent(flowId));
      throw new RpcError(502, "invalid_github_response", "GitHub did not return a user access token.");
    }
    const user = await githubUserWithToken(payload.access_token, signal);
    const loginName = typeof user.login === "string" && user.login ? user.login : null;
    return withDeviceMutation(async () => {
      const current = await storedDeviceFlow();
      if (!isStoredDeviceFlow(current) || current.flowId !== flowId) {
        throw new RpcError(409, "device_flow_replaced", "This GitHub device authorization is no longer active.");
      }
      await persistTokens(payload, loginName);
      await chrome.storage.session.remove(SESSION_DEVICE_FLOW);
      return authForProtocol(true, loginName, app.installUrl);
    });
  }

  function pollDeviceAuthorization(flowId, signal) {
    validateFlowId(flowId);
    const existing = devicePollPromises.get(flowId);
    if (existing) return existing;
    const pending = pollDeviceAuthorizationOnce(flowId, signal)
      .finally(() => devicePollPromises.delete(flowId));
    devicePollPromises.set(flowId, pending);
    return pending;
  }

  async function cancelDeviceAuthorization(flowId) {
    validateFlowId(flowId);
    await withDeviceMutation(() => clearDeviceFlowIfCurrent(flowId));
    return authStatus();
  }

  async function authStatus(signal) {
    const app = config();
    let token;
    try {
      token = await accessToken(signal);
    } catch (error) {
      if (error?.status !== 401) throw error;
      token = null;
    }
    if (!token) {
      const flow = await resumableDeviceFlow();
      return authForProtocol(false, null, app.installUrl, flow);
    }
    const session = await chrome.storage.session.get(SESSION_LOGIN);
    let loginName = session[SESSION_LOGIN] || null;
    if (!loginName) {
      const user = await githubJson("/user", { signal });
      loginName = typeof user.login === "string" ? user.login : null;
      if (loginName) await chrome.storage.session.set({ [SESSION_LOGIN]: loginName });
    }
    return authForProtocol(true, loginName, app.installUrl);
  }

  function bytesToBase64(bytes) {
    let binary = "";
    const chunk = 0x8000;
    for (let offset = 0; offset < bytes.length; offset += chunk) {
      binary += String.fromCharCode(...bytes.subarray(offset, offset + chunk));
    }
    return btoa(binary);
  }

  async function dispatchGithub(operation, rawArgs, signal) {
    const args = requireObject(rawArgs);
    if (operation === "github.commit.get") {
      exactKeys(args, ["owner", "repo", "sha", "page"]);
      const base = repositoryPath(args);
      if (!validSha(args.sha)) throw new RpcError(400, "invalid_sha", "The commit SHA is invalid.");
      validatePositiveInteger(args.page, "page");
      return githubJson(`${base}/commits/${encodeURIComponent(args.sha)}?per_page=100&page=${args.page}`, { signal });
    }
    if (operation === "github.pull.get") {
      exactKeys(args, ["owner", "repo", "number"]);
      const base = repositoryPath(args);
      if (!validNumber(args.number)) throw new RpcError(400, "invalid_pull_number", "The pull request number is invalid.");
      return githubJson(`${base}/pulls/${args.number}`, { signal });
    }
    if (operation === "github.compare.get") {
      exactKeys(args, ["owner", "repo", "base", "head"]);
      const base = repositoryPath(args);
      if (!validSha(args.base) || !validSha(args.head)) throw new RpcError(400, "invalid_sha", "The comparison revision is invalid.");
      return githubJson(`${base}/compare/${encodeURIComponent(args.base)}...${encodeURIComponent(args.head)}`, { signal });
    }
    if (operation === "github.pull.files") {
      exactKeys(args, ["owner", "repo", "number", "page"]);
      const base = repositoryPath(args);
      if (!validNumber(args.number)) throw new RpcError(400, "invalid_pull_number", "The pull request number is invalid.");
      validatePositiveInteger(args.page, "page");
      return githubJson(`${base}/pulls/${args.number}/files?per_page=100&page=${args.page}`, { signal });
    }
    if (operation === "github.content.get") {
      exactKeys(args, ["owner", "repo", "path", "ref"]);
      const base = repositoryPath(args);
      const path = encodeRepositoryPath(args.path);
      if (!validSha(args.ref)) throw new RpcError(400, "invalid_sha", "The content revision is invalid.");
      const response = await githubFetch(`${base}/contents/${path}?ref=${encodeURIComponent(args.ref)}`, {
        accept: "application/vnd.github.raw+json",
        signal,
      });
      if (!response.ok) throw await githubError(response);
      const declared = Number(response.headers.get("content-length") || 0);
      if (declared > MAX_SOURCE_BYTES) throw new RpcError(413, "source_too_large", "Cannot render: one side is larger than 1 MiB.");
      const bytes = new Uint8Array(await response.arrayBuffer());
      if (bytes.length > MAX_SOURCE_BYTES) throw new RpcError(413, "source_too_large", "Cannot render: one side is larger than 1 MiB.");
      return {
        base64: bytesToBase64(bytes),
        size: bytes.length,
        contentType: response.headers.get("content-type") || "application/octet-stream",
      };
    }
    if (operation === "github.comments.list") {
      exactKeys(args, ["owner", "repo", "kind"], ["number", "sha"]);
      const base = repositoryPath(args);
      if (!["pull", "commit", "pull_commit"].includes(args.kind)) throw new RpcError(400, "invalid_target", "The comment target is invalid.");
      if (args.kind === "pull") {
        exactKeys(args, ["owner", "repo", "kind", "number"]);
        if (!validNumber(args.number)) throw new RpcError(400, "invalid_target", "The pull request comment target is invalid.");
        const [issue_comments, review_comments] = await Promise.all([
          githubJsonPages(`${base}/issues/${args.number}/comments`, signal),
          githubJsonPages(`${base}/pulls/${args.number}/comments`, signal),
        ]);
        return {
          issue_comments: issue_comments.map(commentForProtocol),
          review_comments: review_comments.map(commentForProtocol),
          commit_comments: [],
        };
      }
      if (args.kind === "commit") {
        exactKeys(args, ["owner", "repo", "kind", "sha"]);
        if (!validSha(args.sha)) throw new RpcError(400, "invalid_target", "The commit comment target is invalid.");
      } else {
        exactKeys(args, ["owner", "repo", "kind", "number", "sha"]);
        if (!validNumber(args.number) || !validSha(args.sha)) throw new RpcError(400, "invalid_target", "The pull commit target is invalid.");
      }
      const commit_comments = await githubJsonPages(`${base}/commits/${encodeURIComponent(args.sha)}/comments`, signal);
      return {
        issue_comments: [],
        review_comments: [],
        commit_comments: commit_comments.map(commentForProtocol),
      };
    }
    const jsonHeaders = { "Content-Type": "application/json" };
    if (operation === "github.issue.comment.create") {
      exactKeys(args, ["owner", "repo", "number", "body"]);
      const base = repositoryPath(args);
      if (!validNumber(args.number)) throw new RpcError(400, "invalid_pull_number", "The pull request number is invalid.");
      const comment = await githubJson(`${base}/issues/${args.number}/comments`, {
        method: "POST", headers: jsonHeaders, body: JSON.stringify({ body: validateBody(args.body) }), signal,
      });
      return commentForProtocol(comment);
    }
    if (operation === "github.review.comment.create") {
      exactKeys(args, ["owner", "repo", "number", "commit_id", "path", "line", "side", "body"]);
      const base = repositoryPath(args);
      if (!validNumber(args.number) || !validSha(args.commit_id)) throw new RpcError(400, "invalid_target", "The pull request review target is invalid.");
      validatePath(args.path);
      validatePositiveInteger(args.line, "line");
      if (!["LEFT", "RIGHT"].includes(args.side)) throw new RpcError(400, "invalid_side", "The review side is invalid.");
      const comment = await githubJson(`${base}/pulls/${args.number}/comments`, {
        method: "POST", headers: jsonHeaders, body: JSON.stringify({
          body: validateBody(args.body), commit_id: args.commit_id, path: args.path, line: args.line, side: args.side,
        }), signal,
      });
      return commentForProtocol(comment);
    }
    if (operation === "github.commit.comment.create") {
      exactKeys(args, ["owner", "repo", "sha", "path", "position", "body"]);
      const base = repositoryPath(args);
      if (!validSha(args.sha)) throw new RpcError(400, "invalid_sha", "The commit SHA is invalid.");
      validatePath(args.path);
      validatePositiveInteger(args.position, "position");
      const comment = await githubJson(`${base}/commits/${encodeURIComponent(args.sha)}/comments`, {
        method: "POST", headers: jsonHeaders, body: JSON.stringify({
          body: validateBody(args.body), path: args.path, position: args.position,
        }), signal,
      });
      return commentForProtocol(comment);
    }
    if (operation === "github.review.reply.create") {
      exactKeys(args, ["owner", "repo", "number", "comment_id", "body"]);
      const base = repositoryPath(args);
      if (!validNumber(args.number)) throw new RpcError(400, "invalid_pull_number", "The pull request number is invalid.");
      const commentId = validateCommentId(args.comment_id);
      const comment = await githubJson(`${base}/pulls/${args.number}/comments/${commentId}/replies`, {
        method: "POST", headers: jsonHeaders, body: JSON.stringify({ body: validateBody(args.body) }), signal,
      });
      return commentForProtocol(comment);
    }
    throw new RpcError(400, "operation_not_allowed", "This GitHub operation is not allowed.");
  }

  function isReviewSender(sender) {
    if (typeof sender?.url !== "string" || !chrome?.runtime?.getURL) return false;
    return sender.url.split("#", 1)[0] === chrome.runtime.getURL("review.html");
  }

  async function openReview(sender) {
    const openerTabId = sender?.tab?.id;
    const windowId = sender?.tab?.windowId;
    const target = root.MoondiffTarget.parseGitHubTarget(sender?.url || "");
    const route = root.MoondiffTarget.targetHash(target);
    if (
      !Number.isInteger(openerTabId) ||
      openerTabId < 0 ||
      !Number.isInteger(windowId) ||
      windowId < 0 ||
      !route
    ) {
      throw new RpcError(400, "unsupported_github_page", "This is not a supported GitHub pull request or commit page.");
    }
    await chrome.tabs.create({
      url: `${chrome.runtime.getURL("review.html")}${route}`,
      active: true,
      windowId,
      openerTabId,
    });
    return target;
  }

  async function notifyPage(sender, route) {
    const target = root.MoondiffTarget.parseTargetHash(route);
    if (!target || root.MoondiffTarget.targetHash(target) !== route) {
      throw new RpcError(400, "invalid_target", "The comment notification route is invalid.");
    }
    const openerTabId = sender?.tab?.openerTabId;
    if (!Number.isInteger(openerTabId) || openerTabId < 0) {
      return { notified: false };
    }
    try {
      await chrome.tabs.sendMessage(openerTabId, {
        v: 1,
        op: "page.comments.changed",
        args: { route },
      });
      return { notified: true };
    } catch {
      return { notified: false };
    }
  }

  function serializeError(error) {
    if (error?.name === "AbortError") return { status: 499, code: "cancelled", message: "The request was cancelled." };
    return {
      status: Number.isInteger(error?.status) ? error.status : 500,
      code: typeof error?.code === "string" ? error.code : "internal_error",
      message: error?.message || String(error),
    };
  }

  async function handleMessage(message, sender = {}) {
    if (!message || message.v !== 1 || typeof message.op !== "string" || !RPC_OPERATIONS.has(message.op)) {
      throw new RpcError(400, "operation_not_allowed", "This RPC operation is not allowed.");
    }
    exactKeys(message, ["v", "op"], ["args", "requestId"]);
    if (message.requestId !== undefined && (
      typeof message.requestId !== "string" ||
      !/^[A-Za-z0-9_-]{1,80}$/u.test(message.requestId)
    )) {
      throw new RpcError(400, "invalid_request_id", "The RPC request id is invalid.");
    }
    if (message.op === "review.open") {
      exactKeys(message.args || {}, []);
      return openReview(sender);
    }
    if (!isReviewSender(sender)) throw new RpcError(403, "untrusted_sender", "Only the Moondiff review page may use this operation.");
    if (message.op === "page.comments.changed") {
      const args = exactKeys(message.args || {}, ["route"]);
      return notifyPage(sender, args.route);
    }
    if (message.op === "request.cancel") {
      exactKeys(message.args || {}, ["requestId"]);
      controllers.get(message.args.requestId)?.abort();
      return { cancelled: true };
    }
    if (message.op === "auth.status") {
      exactKeys(message.args || {}, []);
      return authStatus();
    }
    if (message.op === "auth.device.start") {
      exactKeys(message.args || {}, []);
      return startDeviceAuthorization();
    }
    if (message.op === "auth.device.poll") {
      const args = exactKeys(message.args || {}, ["flow_id"]);
      return pollDeviceAuthorization(args.flow_id);
    }
    if (message.op === "auth.device.cancel") {
      const args = exactKeys(message.args || {}, ["flow_id"]);
      return cancelDeviceAuthorization(args.flow_id);
    }
    if (message.op === "auth.logout") {
      exactKeys(message.args || {}, []);
      await clearAuthentication();
      return authForProtocol(false, null, config().installUrl);
    }
    const requestId = message.requestId || null;
    const controller = new AbortController();
    if (requestId) controllers.set(requestId, controller);
    try {
      return await dispatchGithub(message.op, message.args, controller.signal);
    } finally {
      if (requestId) controllers.delete(requestId);
    }
  }

  root.MoondiffWorker = Object.freeze({
    API_VERSION,
    MAX_SOURCE_BYTES,
    RPC_OPERATIONS,
    RpcError,
    authStatus,
    cancelDeviceAuthorization,
    configureStorageAccess,
    dispatchGithub,
    handleMessage,
    pollDeviceAuthorization,
    randomFlowId,
    refreshAccessToken,
    serializeError,
    startDeviceAuthorization,
    commentForProtocol,
    validatePath,
  });

  if (typeof chrome !== "undefined" && chrome.runtime?.onMessage) {
    configureStorageAccess().catch(() => {});
    chrome.runtime.onInstalled.addListener(() => {
      configureStorageAccess().catch(() => {});
    });
    chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
      handleMessage(message, sender)
        .then(value => sendResponse({ ok: true, value }))
        .catch(error => sendResponse({ ok: false, error: serializeError(error) }));
      return true;
    });
  }
})(globalThis);
