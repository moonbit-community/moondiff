import { setTimeout as delay } from 'node:timers/promises';
import { performance } from 'node:perf_hooks';

const controls = new WeakMap();
let scope;

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
    this.handlers = {
      request: request => this.enter(request),
      response: response => this.mark(response.request(), 'response', { status: response.status() }),
      requestfinished: request => this.mark(request, 'received'),
      requestfailed: request => {
        const error = request.failure()?.errorText ?? 'unknown failure';
        this.mark(request, /abort|cancel/i.test(error) ? 'cancelled' : 'failed', { error });
      },
      close: () => {
        for (const record of this.unfinished()) record.phases.closed = performance.now();
      },
    };
    for (const [event, handler] of Object.entries(this.handlers)) page.on(event, handler);
  }
  enter(request) {
    if (this.requests.has(request)) return this.requests.get(request);
    const description = describeRequest(request);
    const key = JSON.stringify([description.operation, description.target, description.args]);
    const generation = (this.generations.get(key) ?? 0) + 1;
    this.generations.set(key, generation);
    const record = { id: this.records.length + 1, ...description, generation, phases: { entered: performance.now() } };
    this.records.push(record);
    this.requests.set(request, record);
    return record;
  }
  mark(request, phase, detail = {}) {
    const record = this.enter(request);
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
    return this.records.filter(record => !['received', 'cancelled', 'failed', 'closed'].some(phase => record.phases[phase] !== undefined));
  }
  snapshot() {
    const requests = structuredClone(this.records);
    return { requests, unfinished: structuredClone(this.unfinished()),
      gates: [...(scope?.gates ?? [])].map(g => g.snapshot()) };
  }
  dispose() { for (const [event, handler] of Object.entries(this.handlers)) this.page.off(event, handler); }
}

export function requestsFor(page) {
  let control = controls.get(page);
  if (!control) { control = { requests: new RequestRecorder(page) }; controls.set(page, control); }
  return control.requests;
}
export const clockFor = page => controls.get(page)?.clock;

// Protocol-fixture proxies retain the identity of the actual network request.
export function aliasRequest(alias, request) {
  if (typeof request.frame !== 'function') return;
  const recorder = requestsFor(request.frame().page());
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

export async function browserDiagnostic(page) {
  const requests = requestsFor(page).snapshot();
  if (page.isClosed()) return { ...requests, closed: true };
  return { ...requests, browser: await page.evaluate(() => ({
    now: Date.now(), timers: globalThis.__moondiffTimerSnapshot?.(),
    state: globalThis.__moondiffTestState?.(),
    pendingMounts: [...(globalThis.__moondiffPendingPaints ?? [])].map(host => host.mount),
    layout: globalThis.__moondiffMetrics?.layout,
    text: document.body?.innerText.slice(0, 2_000),
  })) };
}

export function beginControls() { scope = { gates: new Set() }; return scope; }
export async function finishControls(current, pages) {
  current.closing = true;
  for (const gate of current.gates) gate.release();
  const errors = [];
  try {
    for (const page of pages) {
      const requests = controls.get(page)?.requests;
      const deadline = performance.now() + 5_000;
      try {
        if (!page.isClosed()) {
          // Keep routes installed until the browser finishes receiving every
          // response. Removing them while concurrent fulfills are still being
          // dispatched can let a request fall through to the real server.
          if (requests) await waitUntil(() => page.isClosed() || requests.unfinished().length === 0, {
            label: 'in-flight request cleanup', timeout: Math.max(0, deadline - performance.now()),
            diagnostic: () => requests.snapshot(),
          });
          if (!page.isClosed()) await withRealTimeout(page.unrouteAll({ behavior: 'wait' }),
            Math.max(0, deadline - performance.now()), 'route handler cleanup');
        }
      } catch (error) {
        errors.push(error.name === 'RealTimeoutError'
          ? new Error(`${error.message}: ${JSON.stringify(requests?.snapshot() ?? {})}`, { cause: error }) : error);
        if (!page.isClosed()) {
          try { await page.close(); } catch (error) { errors.push(error); }
        }
      } finally { requests?.dispose(); }
    }
  } finally { if (scope === current) scope = undefined; }
  if (errors.length) throw new AggregateError(errors, 'Browser control cleanup failed');
}
