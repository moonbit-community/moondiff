import { setTimeout as delay } from 'node:timers/promises';
import { performance } from 'node:perf_hooks';
import { observeDocumentCommits } from './browser-lifecycle.mjs';

const controls = new WeakMap();
const routeControls = new WeakMap();
let scope;
let frameSerial = 0;

const terminal = record => ['received', 'cancelled', 'failed', 'closed', 'retired']
  .some(phase => record.phases[phase] !== undefined);

// All deadlines in this module use Node's real clock, including when the page
// is paused. The callback may inspect the browser, but never advances its time.
export async function waitUntil(read, { label = 'condition', timeout = 5_000, diagnostic = () => ({}) } = {}) {
  let active = true;
  const polling = (async () => {
    while (active) {
      const value = await read();
      if (value) return value;
      if (active) await delay(10);
    }
  })();
  try {
    return await withRealTimeout(polling, timeout, `waiting for ${label}`);
  } catch (error) {
    active = false;
    if (error.name !== 'RealTimeoutError') throw error;
    let state;
    try { state = await withRealTimeout(Promise.resolve(diagnostic()), 1_000, 'timeout diagnostics'); }
    catch (error) { state = { diagnosticError: String(error) }; }
    throw new Error(`Timed out waiting for ${label}: ${JSON.stringify(state)}`, { cause: error });
  } finally { active = false; }
}

export async function withRealTimeout(operation, timeout, label) {
  let timer;
  try {
    return await Promise.race([operation, new Promise((_, reject) => {
      timer = setTimeout(() => {
        const error = new Error(`Timed out during ${label}`);
        error.name = 'RealTimeoutError';
        reject(error);
      }, timeout);
    })]);
  } finally { clearTimeout(timer); }
}

export function createGate(label = 'request barrier') {
  let resolve;
  let released = false;
  const promise = new Promise(r => { resolve = r; });
  const gate = {
    label, promise,
    get released() { return released; },
    release() { if (!released) { released = true; resolve(); } },
    snapshot: () => ({ label, released }),
  };
  gate.resolve = gate.release;
  scope?.gates.add(gate);
  if (scope?.closing) gate.release();
  return gate;
}

function describeRequest(request) {
  const url = new URL(request.url());
  let body;
  try { body = request.postDataJSON(); } catch { /* GET or non-JSON body */ }
  const operation = body?.request?.$tag ?? url.pathname;
  const args = body?.request?.['0'] ?? body ?? {};
  return { operation, target: url.host + url.pathname + url.search, args, url: request.url() };
}

export class RequestRecorder {
  constructor(page) {
    this.page = page;
    this.records = [];
    this.requests = new WeakMap();
    this.generations = new Map();
    this.frames = new Map();
    this.committedNavigations = new WeakMap();
    this.disposed = false;
    this.handlers = {
      request: request => this.enter(request),
      response: response => this.mark(response.request(), 'response', { status: response.status() }),
      requestfinished: request => this.mark(request, 'received'),
      requestfailed: request => {
        const error = request.failure()?.errorText ?? 'unknown failure';
        this.mark(request, /abort|cancel/i.test(error) ? 'cancelled' : 'failed', { error });
      },
      frameattached: frame => this.observeFrame(frame),
      framedetached: frame => this.detachFrame(frame),
      close: () => this.close(),
    };
    try {
      for (const [event, handler] of Object.entries(this.handlers)) page.on(event, handler);
      for (const frame of page.frames()) this.observeFrame(frame);
      if (page.isClosed()) this.close();
    } catch (error) { this.dispose(); throw error; }
  }
  observeFrame(frame) {
    if (this.disposed || this.frames.has(frame)) return;
    // A popup may already have committed before context's page event. Its
    // observed document is the initial one; never reconstruct unseen history.
    const state = { frameId: ++frameSerial, documentId: 1, url: frame.url(), detached: false };
    const dispose = observeDocumentCommits(frame, event => this.commit(frame, event));
    this.frames.set(frame, { state, dispose });
  }
  commit(frame, { url, request }) {
    const { state } = this.frames.get(frame);
    const previous = state.documentId;
    state.documentId++;
    state.url = url;
    // Only the request identified by this commit (and its redirect ancestors)
    // belongs to the new document. Other pending navigations remain pending.
    for (let navigation = request; navigation; navigation = navigation.redirectedFrom()) {
      const owner = { frameId: state.frameId, documentId: state.documentId, ownership: 'document' };
      this.committedNavigations.set(navigation, owner);
      const record = this.requests.get(navigation);
      if (record) Object.assign(record, owner);
    }
    for (const record of this.records) {
      if (record.frameId === state.frameId && record.documentId === previous) {
        this.retire(record, 'document-replaced', state.documentId);
      }
    }
  }
  retire(record, reason, replacementDocumentId = null) {
    if (terminal(record)) return;
    const at = performance.now();
    record.phases.retired = at;
    record.retirement = { reason, at, replacementDocumentId };
  }
  detachFrame(frame) {
    const entry = this.frames.get(frame);
    if (!entry || entry.state.detached) return;
    entry.state.detached = true;
    entry.dispose();
    for (const record of this.records) {
      if (record.frameId === entry.state.frameId) this.retire(record, 'frame-detached');
    }
  }
  close() {
    for (const record of this.unfinished()) {
      this.retire(record, 'page-closed');
      record.phases.closed = performance.now();
    }
    for (const frame of this.frames.keys()) this.detachFrame(frame);
  }
  enter(request, { observed = true } = {}) {
    if (this.requests.has(request)) return this.requests.get(request);
    const description = describeRequest(request);
    const key = JSON.stringify([description.operation, description.target, description.args]);
    const generation = (this.generations.get(key) ?? 0) + 1;
    this.generations.set(key, generation);
    let frame;
    try { frame = request.frame(); } catch { /* Service workers have no Frame. */ }
    const state = this.frames.get(frame)?.state;
    const navigation = request.isNavigationRequest?.() ?? false;
    const owner = this.committedNavigations.get(request) ?? {
      frameId: state?.frameId ?? null,
      documentId: state && !state.detached && observed && !navigation ? state.documentId : null,
      ownership: state && !state.detached && observed ? (navigation ? 'pending-navigation' : 'document') : 'unknown',
    };
    const record = { id: this.records.length + 1, ...description, generation, ...owner, navigation,
      phases: { entered: performance.now() } };
    this.records.push(record);
    this.requests.set(request, record);
    return record;
  }
  mark(request, phase, detail = {}) {
    // A late response seen without its request event cannot prove which
    // document initiated it. A commit can still identify a navigation exactly.
    const record = this.enter(request, { observed: false });
    record.phases[phase] = performance.now();
    Object.assign(record, detail);
    return record;
  }
  checkpoint() { return this.records.length; }
  matching({ after = 0, operation, target, generation, phase, predicate = () => true } = {}) {
    return this.records.filter(r => r.id > after &&
      (!operation || r.operation === operation) && (!target || r.target.includes(target)) &&
      (!generation || r.generation === generation) && (!phase || r.phases[phase] !== undefined) && predicate(r));
  }
  async wait(filter, { timeout = 5_000 } = {}) {
    return waitUntil(() => this.matching(filter)[0], {
      label: `request ${JSON.stringify(filter)}`, timeout, diagnostic: () => this.snapshot(),
    });
  }
  unfinished() {
    return this.records.filter(record => !terminal(record));
  }
  snapshot() {
    const requests = structuredClone(this.records);
    return { requests, unfinished: structuredClone(this.unfinished()),
      documents: structuredClone([...this.frames.values()].map(({ state }) => state)),
      routeHandlers: routeControls.get(this.page)?.snapshot(),
      gates: [...(scope?.gates ?? [])].map(g => g.snapshot()) };
  }
  dispose() {
    if (this.disposed) return;
    this.disposed = true;
    for (const [event, handler] of Object.entries(this.handlers)) this.page.off(event, handler);
    for (const { dispose } of this.frames.values()) dispose();
  }
}

export function requestsFor(page) {
  let control = controls.get(page);
  if (!control) {
    control = { requests: new RequestRecorder(page) };
    controls.set(page, control);
    observeRouteHandlers(page);
  }
  return control.requests;
}
export const clockFor = page => controls.get(page)?.clock;

// Observe callbacks registered through the public API; installing this wrapper
// adds no routes and does not disable HTTP caching. Playwright's own wait skips
// callbacks whose Route previously threw, even if a fixture caught cancellation
// and is still doing work. Track the entire callback, including that tail and
// handlers removed by unroute/dispose or by a { times: 1 } registration.
export function observeRouteHandlers(owner) {
  if (routeControls.has(owner) || typeof owner.route !== 'function') return;
  const originalRoute = owner.route, originalUnroute = owner.unroute;
  const wrappers = new WeakMap(), active = new Set(), errors = [];
  const route = async function (url, handler, options) {
    let wrapped = wrappers.get(handler);
    if (!wrapped) {
      wrapped = async (...args) => {
        const complete = Promise.withResolvers();
        const invocation = { complete: complete.promise, url: args[0].request().url(), at: performance.now() };
        active.add(invocation);
        try { return await handler(...args); }
        catch (error) { errors.push(error); throw error; }
        finally { active.delete(invocation); complete.resolve(); }
      };
      wrappers.set(handler, wrapped);
    }
    return originalRoute.call(this, url, wrapped, options);
  };
  const unroute = function (url, handler) {
    return originalUnroute.call(this, url, wrappers.get(handler) ?? handler);
  };
  owner.route = route; owner.unroute = unroute;
  routeControls.set(owner, {
    snapshot: () => ({ active: [...active].map(({ url, at }) => ({ url, at })), errors: errors.map(String) }),
    async drain() {
      while (active.size) await Promise.all([...active].map(invocation => invocation.complete));
      if (errors.length) throw new AggregateError(errors, 'Route callbacks failed');
    },
    dispose() {
      if (owner.route === route) owner.route = originalRoute;
      if (owner.unroute === unroute) owner.unroute = originalUnroute;
    },
  });
}

// Protocol-fixture proxies retain the identity of the actual network request.
export function aliasRequest(alias, request) {
  if (typeof request.frame !== 'function') return;
  let page;
  try { page = request.frame().page(); } catch { return; }
  const recorder = requestsFor(page);
  recorder.requests.set(alias, recorder.enter(request));
}

// A route failure is tolerated only with evidence that its request was
// cancelled or that its page closed. Other fixture errors must fail the test.
export async function cancelledRoute(route, error) {
  const request = route.request();
  let page;
  try { page = request.frame().page(); } catch { /* no frame for service workers */ }
  if (page?.isClosed()) return 'closed';
  if (!request.failure()) {
    await waitUntil(() => request.failure() || page?.isClosed(), {
      label: 'confirmed route cancellation', timeout: 1_000,
      diagnostic: () => ({ url: request.url(), error: String(error) }),
    });
  }
  if (page?.isClosed()) return 'closed';
  if (/abort|cancel/i.test(request.failure()?.errorText ?? '')) return 'cancelled';
  throw error;
}

const wrappedRoutes = new WeakMap();
export function trackRoute(route) {
  if (wrappedRoutes.has(route)) return wrappedRoutes.get(route);
  const wrapped = new Proxy(route, { get(target, key) {
    const value = Reflect.get(target, key, target);
    if (['fulfill', 'continue', 'abort'].includes(key)) return async (...args) => {
      const request = target.request();
      let page;
      try { page = request.frame().page(); } catch { /* worker request */ }
      if (key === 'fulfill' && page) {
        const options = args[0];
        const body = options.json !== undefined ? JSON.stringify(options.json) : options.body;
        // Record the actual fixture payload before delivery. A report counts
        // these bytes only after requestfinished confirms browser receipt.
        if (body !== undefined) requestsFor(page).enter(request).responseBytes = Buffer.byteLength(body);
      }
      try {
        await value.apply(target, args);
        if (/abort|cancel/i.test(request.failure()?.errorText ?? '')) {
          if (page) requestsFor(page).mark(request, 'cancelled');
          return 'cancelled';
        }
        if (key === 'fulfill' && page) requestsFor(page).mark(request, 'sent');
        return key === 'fulfill' ? 'sent' : undefined;
      } catch (error) {
        const outcome = await cancelledRoute(target, error);
        if (page) requestsFor(page).mark(request, outcome);
        return outcome;
      }
    };
    return typeof value === 'function' ? value.bind(target) : value;
  } });
  wrappedRoutes.set(route, wrapped);
  wrappedRoutes.set(wrapped, wrapped);
  return wrapped;
}

export async function installClock(page, { time = '2026-08-18T01:00:00Z' } = {}) {
  if (clockFor(page)) return clockFor(page);
  requestsFor(page);
  const instant = new Date(time);
  await page.clock.install({ time: new Date(instant.getTime() - 3_600_000) });
  await page.clock.pauseAt(instant);
  // Observe every timeout, forwarding all scheduling and cancellation to Clock.
  // No callbacks or IDs are replaced based on a particular delay value.
  await page.addInitScript(() => {
    const schedule = globalThis.setTimeout.bind(globalThis);
    const cancel = globalThis.clearTimeout.bind(globalThis);
    const timers = [];
    globalThis.__moondiffTimerSnapshot = () => timers.map(({ id, context, ...timer }) => ({ ...timer, context: { ...context } }));
    globalThis.setTimeout = (callback, ms = 0, ...args) => {
      const business = globalThis.__moondiffBusiness;
      const timer = { sequence: timers.length + 1, ms, at: Date.now(), due: Date.now() + Number(ms), state: 'pending',
        context: { generation: business?.generation, viewedReadSerial: business?.viewed.readSerial, mergeSerial: business?.merge.serial } };
      timer.id = schedule((...values) => { timer.state = 'fired'; return callback(...values); }, ms, ...args);
      timers.push(timer);
      return timer.id;
    };
    globalThis.clearTimeout = id => {
      const timer = timers.find(timer => timer.id === id && timer.state === 'pending');
      if (timer) timer.state = 'cancelled';
      return cancel(id);
    };
  });
  const clock = {
    page,
    now: () => page.evaluate(() => Date.now()),
    timers: () => page.evaluate(() => globalThis.__moondiffTimerSnapshot?.() ?? []),
    async timer(ms, { after = 0, state = 'pending', render = true, predicate = () => true } = {}) {
      return this.until(async () => (await this.timers()).findLast(t => t.sequence > after && t.ms === ms && t.state === state && predicate(t)),
        `registered ${ms}ms timer`, { render });
    },
    async before(timer) {
      const remaining = timer.due - await this.now() - 1;
      if (remaining < 0) throw new Error(`Timer deadline already passed: ${JSON.stringify(timer)}`);
      if (remaining) await page.clock.runFor(remaining);
    },
    async fire(timer) {
      const remaining = timer.due - await this.now();
      if (remaining < 0) throw new Error(`Timer deadline already passed: ${JSON.stringify(timer)}`);
      if (remaining) await page.clock.runFor(remaining);
    },
    advance: ms => page.clock.runFor(ms),
    jump: ms => page.clock.fastForward(ms),
    frames: (count = 1) => page.clock.runFor(16 * count),
    async until(read, label = 'browser condition', { timeout = 5_000, render = true } = {}) {
      // Only tick when the instrumented renderer has work. A slow real response
      // never consumes retry time while its request is pending.
      return waitUntil(async () => {
        const value = await read();
        if (value) return value;
        if (render && await page.evaluate(() => {
          const layout = globalThis.__moondiffMetrics?.layout;
          return (globalThis.__moondiffPendingPaints?.size ?? 0) > 0 ||
            layout?.frame || layout?.dirty || layout?.callbacks;
        })) await this.frames();
        return false;
      }, { label, timeout, diagnostic: () => browserDiagnostic(page) });
    },
  };
  controls.get(page).clock = clock;
  return clock;
}

export async function browserDiagnostic(page, requests = requestsFor(page).snapshot()) {
  if (page.isClosed()) return { ...requests, closed: true };
  return { ...requests, browser: await page.evaluate(() => ({
    now: Date.now(), timers: globalThis.__moondiffTimerSnapshot?.(),
    state: globalThis.__moondiffTestState?.(),
    pendingMounts: [...(globalThis.__moondiffPendingPaints ?? [])].map(host => host.mount),
    layout: globalThis.__moondiffMetrics?.layout,
    text: document.body?.innerText.slice(0, 2_000),
  })) };
}

export async function collectBrowserDiagnostics(pages, snapshots = pages.map(page => controls.get(page)?.requests.snapshot() ?? {})) {
  // Snapshot every request before evaluating any page or closing anything.
  const diagnostics = snapshots.map((snapshot, page) => ({ page, ...snapshot }));
  try {
    await withRealTimeout(Promise.all(pages.map(async (page, i) => {
      try { Object.assign(diagnostics[i], await browserDiagnostic(page, snapshots[i])); }
      catch (error) { diagnostics[i].diagnosticError = String(error); }
    })), 1_000, 'browser cleanup diagnostics');
  } catch (error) {
    for (const state of diagnostics) state.diagnosticError ??= String(error);
  }
  return structuredClone(diagnostics);
}

export function beginControls() {
  scope = { gates: new Set(), cleanedPages: new Set(), cleanedContexts: new Set(), errors: [] };
  return scope;
}

async function removeRoutes(owner, kind, remaining) {
  await withRealTimeout((async () => {
    const outcomes = await Promise.allSettled([
      Promise.resolve().then(() => owner.unrouteAll({ behavior: 'wait' })),
      routeControls.get(owner)?.drain(),
    ]);
    const errors = outcomes.flatMap((outcome, i) => {
      if (outcome.status === 'fulfilled') return [];
      // A closed target's interception-pattern update is expected only after
      // the full callback drain. Callback errors are never filtered this way.
      if (i === 0 && owner.isClosed?.() &&
          [
            'Target page, context or browser has been closed',
            `${kind}.unrouteAll: Target page, context or browser has been closed`,
          ].includes(outcome.reason.message)) return [];
      return [outcome.reason];
    });
    if (errors.length === 1) throw errors[0];
    if (errors.length) throw new AggregateError(errors, `${kind} route cleanup failed`);
  })(), remaining(), `${kind} route handler cleanup`);
}

export function finishControls(current, pages, { context } = {}) {
  current.closing = true;
  for (const gate of current.gates) gate.release();
  // Serialize repeated calls, while allowing the automatic fixture to clean a
  // Context after a test explicitly cleaned just its Page using the old API.
  const run = () => drainControls(current, pages, context);
  const cleanup = current.cleanup ? current.cleanup.then(run, run) : run();
  current.cleanup = cleanup;
  return cleanup;
}

async function drainControls(current, pages, context) {
  const deadline = performance.now() + 5_000;
  const remaining = () => Math.max(0, deadline - performance.now());
  const attempted = new Set();
  const capture = error => {
    // Preserve the first failure's evidence, before page.close can give every
    // request a terminal phase. The fixture attaches this saved snapshot.
    current.failurePages ??= [...pages];
    current.failureSnapshots ??= current.failurePages.map(page => controls.get(page)?.requests.snapshot() ?? {});
    current.contextHandlers ??= routeControls.get(context)?.snapshot();
    current.errors.push(error);
  };
  try {
    // The registry can grow if an in-flight handler opens a popup during drain.
    for (;;) {
      const pending = [...pages].filter(page => !current.cleanedPages.has(page) && !attempted.has(page));
      if (!pending.length) break;
      pending.forEach(page => attempted.add(page));
      const drained = await Promise.all(pending.map(async page => {
        const requests = controls.get(page)?.requests;
        try {
          if (requests) await waitUntil(() => requests.unfinished().length === 0, {
            label: 'in-flight request cleanup', timeout: remaining(), diagnostic: () => requests.snapshot(),
          });
          return true;
        } catch (error) { capture(error); return false; }
      }));
      // Page handlers may fall back to Context handlers. Keep Context routes
      // installed until all Page handlers return, including closed pages.
      await Promise.all(pending.map(async (page, i) => {
        if (!drained[i]) return;
        try { await removeRoutes(page, 'page', remaining); }
        catch (error) {
          const snapshot = controls.get(page)?.requests.snapshot() ?? {};
          capture(error.name === 'RealTimeoutError'
            ? new Error(`${error.message}: ${JSON.stringify(snapshot)}`, { cause: error }) : error);
        }
      }));
    }
    if (context && !current.cleanedContexts.has(context)) {
      try { await removeRoutes(context, 'browserContext', remaining); }
      catch (error) { capture(error); }
      finally { current.cleanedContexts.add(context); routeControls.get(context)?.dispose(); }
    }
    if (current.errors.length && !current.diagnostics) {
      current.diagnostics = await collectBrowserDiagnostics(current.failurePages, current.failureSnapshots);
      // Recovery also has a real deadline; an unresponsive target cannot hang
      // teardown indefinitely after its original failure has been recorded.
      const recovery = [...pages].filter(page => !page.isClosed()).map(page => () => page.close());
      if (context) recovery.push(() => context.close());
      const recovered = await Promise.allSettled(recovery.map(close => withRealTimeout(
        Promise.resolve().then(close), 1_000, 'forced browser cleanup')));
      for (const result of recovered) if (result.status === 'rejected') current.errors.push(result.reason);
    }
  } finally {
    for (const page of attempted) {
      controls.get(page)?.requests.dispose();
      routeControls.get(page)?.dispose();
      current.cleanedPages.add(page);
    }
    if (scope === current) scope = undefined;
  }
  if (current.errors.length) {
    const error = new AggregateError(current.errors, 'Browser control cleanup failed');
    error.diagnostics = current.diagnostics;
    error.contextHandlers = current.contextHandlers;
    throw error;
  }
}
