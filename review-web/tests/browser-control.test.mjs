import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { performance } from 'node:perf_hooks';
import test from 'node:test';
import { beginControls, finishControls, createGate, RequestRecorder, requestsFor, waitUntil, trackRoute, aliasRequest, observeRouteHandlers } from './browser-control.mjs';
import { observeDocumentCommits } from './browser-lifecycle.mjs';
import { summarizeSamples } from './performance-report.mjs';

const request = (frame, { navigation = false, previous = null } = {}) => ({
  _type: 'Request', frame: () => frame, isNavigationRequest: () => navigation, redirectedFrom: () => previous,
  url: () => 'http://fixture/api/rpc',
  postDataJSON: () => ({ request: { $tag: 'PullGet', '0': { number: '1' } } }), failure: () => null });

function controlFrame(page, url = 'http://fixture/') {
  return { _type: 'Frame', _eventEmitter: new EventEmitter(), page: () => page, url: () => url };
}

function commit(frame, request, { url = frame.url(), error, newDocument = {} } = {}) {
  frame._eventEmitter.emit('navigated', { url, name: '', error,
    newDocument: request ? { request: { _object: request } } : newDocument });
}

function controlPage(unrouteAll = async () => {}) {
  const page = new EventEmitter();
  let closed = false;
  page.isClosed = () => closed;
  page.unrouteAll = unrouteAll;
  page.close = async () => { closed = true; page.emit('close'); };
  const main = controlFrame(page);
  page.frames = () => [main];
  page.mainFrame = () => main;
  page.evaluate = async () => ({ now: 42 });
  return page;
}

test('gates release idempotently and are cleaned up after exceptional work', async () => {
  const current = beginControls();
  const first = createGate('first'), second = createGate('unreleased on exception');
  first.release(); first.resolve();
  await first.promise;
  await assert.rejects(finishControls(current, [{ isClosed: () => false,
    unrouteAll: async () => { throw new Error('cleanup failure'); }, close: async () => {} }]), /cleanup failed/);
  await second.promise;
  assert.equal(second.released, true);
});

test('request checkpoints isolate generations, cancellation and timeout diagnostics', async () => {
  const current = beginControls(), page = controlPage();
  const recorder = new RequestRecorder(page);
  try {
    const old = request(); page.emit('request', old); page.emit('requestfinished', old);
    const after = recorder.checkpoint(), next = request(); page.emit('request', next);
    const barrier = createGate('held second generation');
    await assert.rejects(recorder.wait({ after, phase: 'received' }, { timeout: 20 }), error =>
      error.message.includes('held second generation') && error.message.includes('"generation":2'));
    next.failure = () => ({ errorText: 'net::ERR_ABORTED' }); page.emit('requestfailed', next);
    const cancelled = await recorder.wait({ after, phase: 'cancelled' });
    assert.equal(cancelled.generation, 2);
    assert.equal(recorder.matching({ after, phase: 'received' }).length, 0);
    barrier.release();
  } finally { recorder.dispose(); await finishControls(current, []); }
  assert.equal(page.listenerCount('request'), 0);
});

test('unexpected fixture failures are not treated as cancelled routes', async () => {
  const actual = request(); actual.failure = () => ({ errorText: 'net::ERR_CONNECTION_RESET' });
  const route = trackRoute({ request: () => actual, fulfill: async () => { throw new Error('bad fixture'); } });
  await assert.rejects(route.fulfill({}), /bad fixture/);
});

test('cleanup releases all gates and drains out-of-order responses before removing routes', async () => {
  const current = beginControls();
  const gates = [createGate('first response'), createGate('second response')];
  let removed = false;
  const page = controlPage(async options => {
    assert.deepEqual(options, { behavior: 'wait' });
    assert.deepEqual(recorder.unfinished(), []);
    removed = true;
  });
  const recorder = requestsFor(page), first = request(), second = request();
  page.emit('request', first); page.emit('request', second);
  recorder.mark(first, 'sent'); recorder.mark(first, 'response', { status: 200 });
  recorder.mark(second, 'sent');
  const cleanup = finishControls(current, [page]);
  assert(gates.every(gate => gate.released));
  assert.equal(removed, false);
  page.emit('requestfinished', second);
  assert.deepEqual(recorder.unfinished().map(record => record.id), [1]);
  page.emit('requestfinished', first);
  await cleanup;
  assert.equal(removed, true);
  for (const event of Object.keys(recorder.handlers)) assert.equal(page.listenerCount(event), 0);
});

for (const [errorText, phase] of [['net::ERR_ABORTED', 'cancelled'], ['net::ERR_CONNECTION_RESET', 'failed']]) {
  test(`cleanup accepts terminal ${phase} requests`, async () => {
    const current = beginControls();
    let removed = false;
    const page = controlPage(async () => {
      assert.deepEqual(recorder.unfinished(), []);
      removed = true;
    });
    const recorder = requestsFor(page), pending = request();
    page.emit('request', pending);
    const cleanup = finishControls(current, [page]);
    pending.failure = () => ({ errorText }); page.emit('requestfailed', pending);
    await cleanup;
    assert.equal(removed, true);
    assert.equal(page.isClosed(), false);
    assert.equal(recorder.matching({ phase }).length, 1);
    assert.equal(recorder.matching({ phase: 'received' }).length, 0);
  });
}

test('page closure ends cleanup without waiting for missing request events', async () => {
  const current = beginControls();
  let removed = false;
  const page = controlPage(async () => { removed = true; });
  const recorder = requestsFor(page);
  page.emit('request', request());
  const cleanup = finishControls(current, [page]);
  await page.close();
  await cleanup;
  assert.deepEqual(recorder.unfinished(), []);
  assert.equal(recorder.matching({ phase: 'closed' }).length, 1);
  assert.equal(page.listenerCount('close'), 0);
  assert.equal(removed, true, 'closed pages still drain their route handlers');
});

test('cleanup timeout diagnoses unfinished requests, closes the page and cleans subsequent pages', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const current = beginControls(), barrier = createGate('unresponsive fixture');
  const page = controlPage(async () => assert.fail('pending request must drain first'));
  const recorder = requestsFor(page);
  page.emit('request', request());
  let nextCleaned = false;
  const next = controlPage(async () => { nextCleaned = true; });
  const cleanup = assert.rejects(finishControls(current, [page, next]), error => {
    assert(error instanceof AggregateError);
    assert.equal(error.errors.length, 1);
    assert.match(error.errors[0].message, /in-flight request cleanup/);
    assert.match(error.errors[0].message, /"unfinished":\[\{"id":1/);
    assert.match(error.errors[0].message, /PullGet/);
    assert.match(error.errors[0].message, /unresponsive fixture/);
    assert.equal(error.diagnostics[0].unfinished.length, 1);
    assert.equal(error.diagnostics[0].requests[0].phases.closed, undefined);
    return true;
  });
  t.mock.timers.tick(5_000);
  await cleanup;
  assert.equal(barrier.released, true);
  assert.equal(page.isClosed(), true);
  assert.equal(nextCleaned, true);
  assert.equal(page.listenerCount('request'), 0);
});

test('request draining and route handlers share the five-second cleanup budget', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  let now = 0;
  t.mock.method(performance, 'now', () => now);
  const current = beginControls(), entered = Promise.withResolvers();
  const page = controlPage(async () => {
    assert.deepEqual(recorder.unfinished(), []);
    entered.resolve();
    await new Promise(() => {});
  });
  const recorder = requestsFor(page), pending = request();
  page.emit('request', pending);
  const cleanup = assert.rejects(finishControls(current, [page]), error => {
    assert.match(error.errors[0].message, /route handler cleanup/);
    assert.match(error.errors[0].message, /"unfinished":\[\]/);
    return true;
  });
  // Let the drain poll register before advancing Node's test clock.
  await Promise.resolve();
  now = 4_000;
  page.emit('requestfinished', pending);
  t.mock.timers.tick(4_000);
  await entered.promise;
  t.mock.timers.tick(999);
  assert.equal(page.isClosed(), false);
  t.mock.timers.tick(1);
  await cleanup;
  assert.equal(page.isClosed(), true);
});

test('unexpected fixture errors fail cleanup and trigger page recovery', async () => {
  const current = beginControls(), failure = new Error('bad fixture');
  const page = controlPage(async () => { throw failure; });
  requestsFor(page);
  await assert.rejects(finishControls(current, [page]), error => {
    assert.deepEqual(error.errors, [failure]);
    return true;
  });
  assert.equal(page.isClosed(), true);
  assert.equal(page.listenerCount('request'), 0);
});

test('public source revisions have independent request generations', () => {
  const recorder = new RequestRecorder(controlPage());
  try {
    const old = request(), next = request();
    old.url = () => 'https://api.github.com/repos/example/repo/contents/main.mbt?ref=old';
    next.url = () => 'https://api.github.com/repos/example/repo/contents/main.mbt?ref=new';
    assert.equal(recorder.enter(old).generation, 1);
    assert.equal(recorder.enter(next).generation, 1);
    assert(recorder.enter(next).target.endsWith('?ref=new'));
  } finally { recorder.dispose(); }
});

test('wait deadlines use real time and sample summaries preserve all measurements', async () => {
  await assert.rejects(waitUntil(() => false, { timeout: 20, label: 'paused browser', diagnostic: () => ({ timer: 'cancelled' }) }), /paused browser.*cancelled/);
  assert.deepEqual(summarizeSamples([4, 1, 3, 2]), { count: 4, p50: 2.5, p95: 3.8499999999999996 });
  assert.throws(() => summarizeSamples([]), /nonempty/);
  assert.throws(() => summarizeSamples([NaN]), /finite/);
  await assert.rejects(waitUntil(() => new Promise(() => {}), { timeout: 20, label: 'unresponsive browser' }), /unresponsive browser/);
});

for (const response of [false, true]) test(`document replacement retires a ${response ? 'response without completion' : 'sent-only'} residue`, async () => {
  const current = beginControls(), page = controlPage(), recorder = requestsFor(page);
  const old = request(page.mainFrame());
  page.emit('request', old);
  recorder.mark(old, 'sent', { responseBytes: 123 });
  if (response) recorder.mark(old, 'response', { status: 200 });
  const record = recorder.enter(old), original = { ...record.phases };
  commit(page.mainFrame());
  assert.equal(record.documentId, 1);
  assert.equal(record.retirement.reason, 'document-replaced');
  assert.equal(record.retirement.replacementDocumentId, 2);
  for (const [phase, time] of Object.entries(original)) assert.equal(record.phases[phase], time);
  for (const phase of ['received', 'cancelled', 'failed']) assert.equal(record.phases[phase], undefined);
  assert.deepEqual(recorder.unfinished(), []);
  assert.equal(recorder.matching({ phase: 'received' }).reduce((sum, record) => sum + record.responseBytes, 0), 0);
  await finishControls(current, [page]);
});

test('same-URL requests in successive documents keep generations and independently block cleanup', async () => {
  const current = beginControls(), removed = Promise.withResolvers();
  const page = controlPage(async () => removed.resolve()), recorder = requestsFor(page), frame = page.mainFrame();
  const old = request(frame), navigation = request(frame, { navigation: true });
  page.emit('request', old); page.emit('request', navigation);
  assert.equal(recorder.enter(navigation).ownership, 'pending-navigation');
  commit(frame, navigation);
  const next = request(frame);
  page.emit('request', next);
  assert.deepEqual(recorder.records.map(record => record.generation), [1, 2, 3]);
  assert.deepEqual(recorder.records.map(record => record.documentId), [1, 2, 2]);
  assert.deepEqual(recorder.unfinished().map(record => record.id), [2, 3]);
  page.emit('requestfinished', navigation);
  const cleanup = finishControls(current, [page]);
  const alias = request(frame);
  aliasRequest(alias, old);
  recorder.mark(alias, 'sent');
  page.emit('response', { request: () => old, status: () => 200 });
  page.emit('requestfinished', old);
  assert.equal(recorder.records.length, 3);
  assert.equal(recorder.enter(alias), recorder.enter(old));
  assert.equal(recorder.enter(old).generation, 1);
  assert.deepEqual(recorder.unfinished().map(record => record.id), [3]);
  assert.equal(recorder.disposed, false);
  page.emit('requestfinished', next);
  await cleanup; await removed.promise;
  assert.equal(recorder.enter(old).retirement.reason, 'document-replaced');
});

test('redirect chains bind only to their committed document, including commits before request events', () => {
  const page = controlPage(), recorder = requestsFor(page), frame = page.mainFrame();
  try {
    const old = request(frame), first = request(frame, { navigation: true });
    const redirect = request(frame, { navigation: true, previous: first });
    const competing = request(frame, { navigation: true });
    for (const pending of [old, first, competing]) page.emit('request', pending);
    commit(frame, redirect);
    page.emit('request', redirect);
    assert.equal(recorder.enter(first).documentId, 2);
    assert.equal(recorder.enter(redirect).documentId, 2);
    assert.equal(recorder.enter(competing).documentId, null);
    assert.equal(recorder.enter(competing).phases.retired, undefined);
    commit(frame, undefined, { url: 'about:blank' });
    assert.equal(recorder.enter(redirect).retirement.replacementDocumentId, 3);
    assert.equal(recorder.enter(competing).phases.retired, undefined);
    assert.equal(recorder.snapshot().documents[0].documentId, 3);
  } finally { recorder.dispose(); }
});

test('same-document events and failed navigations leave current requests unfinished', async () => {
  const page = controlPage(), recorder = requestsFor(page), frame = page.mainFrame();
  try {
    const old = request(frame), navigation = request(frame, { navigation: true });
    page.emit('request', old); page.emit('request', navigation);
    page.emit('framenavigated', frame);
    for (const url of ['http://fixture/#hash', 'http://fixture/push', 'http://fixture/replace']) {
      frame._eventEmitter.emit('navigated', { url, name: '' });
    }
    page.emit('pagehide'); page.emit('pageshow');
    commit(frame, navigation, { error: 'net::ERR_ABORTED' });
    navigation.failure = () => ({ errorText: 'net::ERR_ABORTED' });
    page.emit('requestfailed', navigation);
    assert.deepEqual(recorder.unfinished(), [recorder.enter(old)]);
    await assert.rejects(recorder.wait({ phase: 'retired' }, { timeout: 20 }), /Timed out/);
    assert.equal(recorder.snapshot().documents[0].documentId, 1);
    // An actual later error-page commit is a separate document boundary.
    commit(frame, undefined, { url: 'chrome-error://chromewebdata/' });
    assert.equal(recorder.enter(old).retirement.reason, 'document-replaced');
  } finally { recorder.dispose(); }
});

test('iframe navigation, detach and popup closure cannot retire another owner or an unknown request', async () => {
  const current = beginControls(), page = controlPage(), popup = controlPage();
  const recorder = requestsFor(page), popupRecorder = requestsFor(popup);
  const child = controlFrame(page), sibling = controlFrame(page);
  page.emit('frameattached', child); page.emit('frameattached', sibling);
  const main = request(page.mainFrame()), nested = request(child), other = request(sibling);
  const unknown = request(), popupRequest = request(popup.mainFrame());
  for (const pending of [main, nested, other, unknown]) page.emit('request', pending);
  popup.emit('request', popupRequest);
  commit(child);
  assert.equal(recorder.enter(nested).retirement.reason, 'document-replaced');
  assert.deepEqual(recorder.unfinished(), [main, other, unknown].map(value => recorder.enter(value)));
  const next = request(child), pendingNavigation = request(child, { navigation: true });
  page.emit('request', next); page.emit('request', pendingNavigation);
  page.emit('framedetached', child);
  assert.equal(recorder.enter(next).retirement.reason, 'frame-detached');
  assert.equal(recorder.enter(pendingNavigation).retirement.reason, 'frame-detached');
  assert.equal(child._eventEmitter.listenerCount('navigated'), 0);
  await popup.close();
  assert.equal(popupRecorder.enter(popupRequest).retirement.reason, 'page-closed');
  commit(page.mainFrame());
  assert.deepEqual(recorder.unfinished(), [other, unknown].map(value => recorder.enter(value)));
  assert.equal(recorder.enter(unknown).ownership, 'unknown');
  for (const pending of [other, unknown]) page.emit('requestfinished', pending);
  await finishControls(current, [page, popup]);
  for (const frame of [page.mainFrame(), child, sibling, popup.mainFrame()]) {
    assert.equal(frame._eventEmitter.listenerCount('navigated'), 0);
  }
});

test('lifecycle adapter rejects incompatible internals and payloads without retiring requests', () => {
  assert.throws(() => observeDocumentCommits({}, () => {}), /Incompatible Playwright/);
  const frame = controlFrame(controlPage()), commits = [];
  const dispose = observeDocumentCommits(frame, event => commits.push(event));
  for (const event of [{}, { url: 'a', name: '', newDocument: null },
    { url: 'a', name: '', newDocument: { request: {} } }, { url: 'a', name: '', error: 123 }]) {
    assert.throws(() => frame._eventEmitter.emit('navigated', event), /Incompatible Playwright/);
  }
  assert.deepEqual(commits, []);
  dispose(); dispose();
  assert.equal(frame._eventEmitter.listenerCount('navigated'), 0);
});

test('retired requests do not excuse fixture errors or stand in for confirmed cancellation', async () => {
  const current = beginControls(), failure = new Error('handler still failed');
  const page = controlPage(async () => { throw failure; }), recorder = requestsFor(page);
  const pending = request(page.mainFrame());
  recorder.enter(pending); commit(page.mainFrame());
  pending.failure = () => ({ errorText: 'net::ERR_CONNECTION_RESET' });
  const route = trackRoute({ request: () => pending, fulfill: async () => { throw failure; } });
  await assert.rejects(route.fulfill({}), error => error === failure);
  await assert.rejects(finishControls(current, [page]), error => {
    assert.equal(error.errors[0], failure);
    assert.equal(error.diagnostics[0].requests[0].retirement.reason, 'document-replaced');
    return true;
  });
});

test('all pages drain before Page routes, fallback keeps Context routes, and repeated cleanup is inert', async () => {
  const current = beginControls(), order = [], pageHandler = Promise.withResolvers(), contextHandler = Promise.withResolvers();
  const enteredPage = Promise.withResolvers(), enteredContext = Promise.withResolvers();
  const first = controlPage(async () => { order.push('page'); enteredPage.resolve(); await pageHandler.promise; });
  const closed = controlPage(async () => { order.push('closed page'); });
  const context = { unrouteAll: async options => {
    assert.deepEqual(options, { behavior: 'wait' }); order.push('context'); enteredContext.resolve(); await contextHandler.promise;
  } };
  const recorder = requestsFor(first), pending = request(first.mainFrame());
  recorder.enter(pending); commit(first.mainFrame());
  requestsFor(closed); await closed.close();
  const cleanup = finishControls(current, [first, closed], { context });
  await enteredPage.promise;
  assert(!order.includes('context'));
  pageHandler.resolve();
  await enteredContext.promise;
  assert.equal(recorder.disposed, false);
  contextHandler.resolve(); await cleanup;
  await finishControls(current, [first, closed], { context });
  assert.deepEqual(order, ['page', 'closed page', 'context']);
  assert.equal(recorder.disposed, true);
});

test('closed Page handler failures and Context failures both survive aggregation', async () => {
  const current = beginControls(), errors = [new Error('closed page handler'), new Error('context handler')];
  const page = controlPage(async () => { throw errors[0]; });
  requestsFor(page); await page.close();
  const context = { unrouteAll: async () => { throw errors[1]; }, close: async () => {} };
  await assert.rejects(finishControls(current, [page], { context }), error => {
    assert.deepEqual(error.errors, errors); return true;
  });
});

test('retired requests, Page handlers and Context handlers share one five-second deadline', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  let now = 0;
  t.mock.method(performance, 'now', () => now);
  const current = beginControls(), pageHandler = Promise.withResolvers(), entered = Promise.withResolvers();
  const page = controlPage(async () => { await pageHandler.promise; });
  const recorder = requestsFor(page), pending = request(page.mainFrame());
  recorder.enter(pending); commit(page.mainFrame());
  const context = { unrouteAll: async () => { entered.resolve(); await new Promise(() => {}); }, close: async () => {} };
  const cleanup = assert.rejects(finishControls(current, [page], { context }), error => {
    assert.match(error.errors[0].message, /browserContext route handler cleanup/); return true;
  });
  now = 4_000; pageHandler.resolve();
  await entered.promise;
  t.mock.timers.tick(999); assert.equal(page.isClosed(), false);
  t.mock.timers.tick(1);
  await cleanup;
  assert.equal(page.isClosed(), true);
});

test('current-document leaks still time out after history, synthetic lifecycle and an uncommitted navigation', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const current = beginControls(), page = controlPage(), recorder = requestsFor(page), frame = page.mainFrame();
  const pending = request(frame), navigation = request(frame, { navigation: true });
  recorder.enter(pending); recorder.mark(pending, 'sent'); recorder.mark(pending, 'response', { status: 200 });
  recorder.enter(navigation);
  page.emit('framenavigated', frame); page.emit('pagehide'); page.emit('pageshow');
  frame._eventEmitter.emit('navigated', { url: 'http://fixture/history#hash', name: '' });
  commit(frame, navigation, { error: 'net::ERR_ABORTED' });
  navigation.failure = () => ({ errorText: 'net::ERR_ABORTED' }); page.emit('requestfailed', navigation);
  const cleanup = assert.rejects(finishControls(current, [page]), error => {
    const [snapshot] = error.diagnostics;
    assert.equal(snapshot.documents[0].documentId, 1);
    assert.equal(snapshot.unfinished.length, 1);
    assert.equal(snapshot.unfinished[0].ownership, 'document');
    assert.equal(snapshot.unfinished[0].phases.retired, undefined);
    assert.match(error.errors[0].message, /in-flight request cleanup/);
    return true;
  });
  t.mock.timers.tick(5_000);
  await cleanup;
});

test('a retired request cannot hide a stuck handler on a closed page', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const current = beginControls(), entered = Promise.withResolvers();
  const page = controlPage(async () => { entered.resolve(); await new Promise(() => {}); });
  const recorder = requestsFor(page), pending = request(page.mainFrame());
  recorder.enter(pending); await page.close();
  const cleanup = assert.rejects(finishControls(current, [page]), error => {
    assert.match(error.errors[0].message, /page route handler cleanup/);
    assert.deepEqual(error.diagnostics[0].unfinished, []);
    return true;
  });
  await entered.promise;
  t.mock.timers.tick(5_000);
  await cleanup;
  assert.equal(page.listenerCount('request'), 0);
});

test('diagnostics and forced recovery stay bounded and preserve the pre-close failure snapshot', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const current = beginControls(), diagnosing = Promise.withResolvers(), closing = Promise.withResolvers();
  const page = controlPage(), recorder = requestsFor(page);
  page.evaluate = async () => { diagnosing.resolve(); await new Promise(() => {}); };
  page.close = async () => { closing.resolve(); await new Promise(() => {}); };
  recorder.enter(request(page.mainFrame()));
  const cleanup = assert.rejects(finishControls(current, [page]), error => {
    assert.equal(error.errors.length, 2);
    assert.match(error.errors[1].message, /forced browser cleanup/);
    assert.equal(error.diagnostics[0].unfinished.length, 1);
    assert.equal(error.diagnostics[0].requests[0].phases.closed, undefined);
    assert.match(error.diagnostics[0].diagnosticError, /browser cleanup diagnostics/);
    return true;
  });
  t.mock.timers.tick(5_000);
  await diagnosing.promise;
  t.mock.timers.tick(1_000);
  await closing.promise;
  t.mock.timers.tick(1_000);
  await cleanup;
  assert.equal(page.listenerCount('request'), 0);
  assert.equal(page.mainFrame()._eventEmitter.listenerCount('navigated'), 0);
});

test('a direct Page cleanup can be followed by Context cleanup without removing Page routes twice', async () => {
  const current = beginControls(), order = [];
  const page = controlPage(async () => order.push('page'));
  const context = { unrouteAll: async () => order.push('context') };
  requestsFor(page);
  await finishControls(current, [page]);
  await finishControls(current, [page], { context });
  await finishControls(current, [page], { context });
  assert.deepEqual(order, ['page', 'context']);
});

test('public route observation preserves unroute identity and disposables without registering extra routes', async () => {
  const current = beginControls(), page = controlPage(), registrations = [], removed = [];
  page.unroute = async (url, handler) => removed.push({ url, handler });
  page.route = async (url, handler, options) => {
    registrations.push({ url, handler, options });
    return { dispose: () => page.unroute(url, handler) };
  };
  const originalRoute = page.route, originalUnroute = page.unroute;
  observeRouteHandlers(page); observeRouteHandlers(page);
  assert.equal(registrations.length, 0);
  const handler = async () => {}, disposable = await page.route('/one', handler, { times: 1 });
  await page.unroute('/one', handler);
  await disposable.dispose();
  assert.equal(registrations.length, 1);
  assert.deepEqual(registrations[0].options, { times: 1 });
  for (const removedHandler of removed) assert.equal(removedHandler.handler, registrations[0].handler);
  await finishControls(current, [page]);
  assert.equal(page.route, originalRoute);
  assert.equal(page.unroute, originalUnroute);
});

test('callback tails remain pending when native unrouteAll has already returned', async () => {
  const current = beginControls(), page = controlPage(), tail = Promise.withResolvers(), removing = Promise.withResolvers();
  let callback, returned = false;
  page.route = async (_, handler) => { callback = handler; };
  page.unroute = async () => {};
  page.unrouteAll = async () => removing.resolve();
  const recorder = requestsFor(page), pending = request(page.mainFrame());
  recorder.enter(pending); commit(page.mainFrame());
  await page.route('/request', async () => { await tail.promise; returned = true; }, { times: 1 });
  const invocation = callback({ request: () => pending });
  const cleanup = finishControls(current, [page]);
  await removing.promise;
  assert.equal(returned, false);
  assert.equal(recorder.disposed, false);
  assert.equal(recorder.snapshot().routeHandlers.active.length, 1);
  tail.resolve();
  await invocation; await cleanup;
  assert.equal(returned, true);
  assert.equal(recorder.disposed, true);
});

test('even a closed-target-shaped callback error is retained when native unroute reports closure', async () => {
  const current = beginControls(), failure = new Error('Target page, context or browser has been closed');
  const page = controlPage(async () => { throw failure; });
  let callback;
  page.route = async (_, handler) => { callback = handler; };
  page.unroute = async () => {};
  const recorder = requestsFor(page), pending = request(page.mainFrame());
  recorder.enter(pending); await page.close();
  await page.route('/request', async () => { throw failure; });
  await assert.rejects(callback({ request: () => pending }), error => error === failure);
  await assert.rejects(finishControls(current, [page]), error => {
    assert.equal(error.errors[0].errors[0], failure);
    assert.match(error.diagnostics[0].routeHandlers.errors[0], /Target page/);
    return true;
  });
});

test('an unobserved request first seen in a response cannot be assigned to the current document', () => {
  const page = controlPage(), recorder = requestsFor(page), pending = request(page.mainFrame());
  try {
    page.emit('response', { request: () => pending, status: () => 200 });
    const record = recorder.enter(pending);
    commit(page.mainFrame());
    assert.equal(record.ownership, 'unknown');
    assert.equal(record.documentId, null);
    assert.deepEqual(recorder.unfinished(), [record]);
  } finally { recorder.dispose(); }
});
