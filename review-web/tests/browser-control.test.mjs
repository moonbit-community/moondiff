import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { performance } from 'node:perf_hooks';
import test from 'node:test';
import { beginControls, finishControls, createGate, RequestRecorder, requestsFor, waitUntil, trackRoute } from './browser-control.mjs';
import { summarizeSamples } from './performance-report.mjs';

const request = () => ({ url: () => 'http://fixture/api/rpc',
  postDataJSON: () => ({ request: { $tag: 'PullGet', '0': { number: '1' } } }), failure: () => null });

function controlPage(unrouteAll) {
  const page = new EventEmitter();
  let closed = false;
  page.isClosed = () => closed;
  page.unrouteAll = unrouteAll;
  page.close = async () => { closed = true; page.emit('close'); };
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
  const current = beginControls(), page = new EventEmitter();
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
  const page = controlPage(async () => assert.fail('closed pages must not remove routes'));
  const recorder = requestsFor(page);
  page.emit('request', request());
  const cleanup = finishControls(current, [page]);
  await page.close();
  await cleanup;
  assert.deepEqual(recorder.unfinished(), []);
  assert.equal(recorder.matching({ phase: 'closed' }).length, 1);
  assert.equal(page.listenerCount('close'), 0);
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
  const recorder = new RequestRecorder(new EventEmitter());
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
