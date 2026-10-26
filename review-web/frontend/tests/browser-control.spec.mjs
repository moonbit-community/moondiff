import { test, expect } from '../../tests/browser-test.mjs';
import { createGate, requestsFor, trackRoute, installClock, finishControls, waitUntil } from '../../tests/browser-control.mjs';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { settleRegions } from '../../tests/render-probe.mjs';
import { syntheticFixture, installRenderingFixture } from './rendering-fixture.mjs';
import { holdRegionFrames } from './dom-timing.mjs';
import { scrollAndWait } from '../../tests/scroll-control.mjs';

test('cleanup drains concurrent out-of-order mock responses before removing routes', async ({ page, browserControls }) => {
  const realRequests = [];
  const server = createServer((request, response) => {
    if (request.url.startsWith('/control/')) realRequests.push(request.url);
    response.setHeader('Content-Type', 'text/html');
    response.end('<!doctype html><title>route cleanup fixture</title>');
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const unrouteAll = page.unrouteAll.bind(page);
  try {
    await page.goto(`http://127.0.0.1:${server.address().port}`);
    const recorder = requestsFor(page), after = recorder.checkpoint();
    const gates = [createGate('first mock response'), createGate('second mock response')];
    const entered = [], outcomes = {}, received = [], removals = [];
    let cleaned = false;
    page.on('requestfinished', request => {
      if (request.url().includes('/control/')) received.push({ name: request.url().split('/').at(-1), cleaned });
    });
    await page.route('**/control/*', async route => {
      route = trackRoute(route);
      const name = route.request().url().split('/').at(-1);
      entered.push(name);
      await gates[name === 'first' ? 0 : 1].promise;
      if (name === 'first') await recorder.wait({ after, target: '/control/second', phase: 'received' });
      outcomes[name] = await route.fulfill({ json: { mock: name } });
    });
    for (const name of ['first', 'second']) {
      await page.evaluate(name => {
        window.controlResults ??= {};
        controlResults[name] = fetch(`/control/${name}`).then(response => response.json());
      }, name);
      await recorder.wait({ after, target: `/control/${name}`, phase: 'entered' });
    }
    await waitUntil(() => entered.length === 2, { label: 'both concurrent route handlers entered' });
    page.unrouteAll = async options => {
      removals.push({ options, unfinished: recorder.snapshot().unfinished, received: received.map(record => record.name) });
      await unrouteAll(options);
    };
    await finishControls(browserControls, [page]);
    cleaned = true;
    expect(gates.every(gate => gate.released)).toBe(true);
    expect(outcomes).toEqual({ first: 'sent', second: 'sent' });
    expect(received).toEqual([{ name: 'second', cleaned: false }, { name: 'first', cleaned: false }]);
    expect(removals).toEqual([{ options: { behavior: 'wait' }, unfinished: [], received: ['second', 'first'] }]);
    expect(await page.evaluate(() => Promise.all([controlResults.first, controlResults.second])))
      .toEqual([{ mock: 'first' }, { mock: 'second' }]);
    expect(realRequests).toEqual([]);
    expect(recorder.matching({ after, target: '/control/', phase: 'received' })).toHaveLength(2);
    expect(recorder.matching({ after, target: '/control/', phase: 'cancelled' })).toHaveLength(0);
    expect(recorder.matching({ after, target: '/control/', phase: 'failed' })).toHaveLength(0);
  } finally {
    page.unrouteAll = unrouteAll;
    await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  }
});

test('request barriers record receipt, isolate generations and observe confirmed cancellation', async ({ page }) => {
  await page.goto('/');
  const recorder = requestsFor(page);
  let barrier = createGate('first response');
  await page.route('**/api/control', async route => {
    route = trackRoute(route);
    const held = barrier;
    await held.promise;
    await route.fulfill({ json: { accepted: held.label } });
  });
  const start = () => page.evaluate(() => {
    window.controlAbort = new AbortController();
    window.controlFetch = fetch('/api/control', { signal: controlAbort.signal }).then(r => r.json(), error => ({ error: error.name }));
  });
  const first = recorder.checkpoint();
  await start(); await recorder.wait({ after: first, target: '/api/control', phase: 'entered' });
  barrier.release(); barrier.release();
  const received = await recorder.wait({ after: first, target: '/api/control', phase: 'received' });
  expect(received.phases.sent).toBeDefined();
  expect(received.phases.response).toBeDefined();
  expect(received.responseBytes).toBe(Buffer.byteLength(JSON.stringify({ accepted: 'first response' })));
  expect(await page.evaluate(() => window.controlFetch)).toEqual({ accepted: 'first response' });
  const second = recorder.checkpoint();
  barrier = createGate('cancelled second response');
  await start(); await recorder.wait({ after: second, target: '/api/control', phase: 'entered' });
  await expect(recorder.wait({ after: second, target: '/api/control', phase: 'received' }, { timeout: 30 })).rejects.toThrow(/cancelled second response/);
  await page.evaluate(() => window.controlAbort.abort());
  const cancelled = await recorder.wait({ after: second, target: '/api/control', phase: 'cancelled' });
  expect(cancelled.generation).toBe(received.generation + 1);
  barrier.release();
  expect(await page.evaluate(() => window.controlFetch)).toEqual({ error: 'AbortError' });
  expect(recorder.matching({ after: second, target: '/api/control', phase: 'received' })).toHaveLength(0);
});

test('Clock respects one millisecond deadlines, cancellation and long jumps', async ({ page }) => {
  const clock = await installClock(page);
  await page.goto('about:blank');
  await page.evaluate(() => {
    window.clockEvents = [];
    setTimeout(() => clockEvents.push('due'), 100);
    const cancelled = setTimeout(() => clockEvents.push('cancelled'), 250);
    clearTimeout(cancelled);
  });
  const timer = await clock.timer(100, { render: false });
  await clock.before(timer);
  expect(await page.evaluate(() => clockEvents)).toEqual([]);
  expect(await clock.now()).toBe(timer.due - 1);
  await clock.fire(timer);
  expect(await page.evaluate(() => clockEvents)).toEqual(['due']);
  await clock.jump(86_400_000);
  expect(await page.evaluate(() => clockEvents)).toEqual(['due']);
  expect((await clock.timers()).find(t => t.ms === 250).state).toBe('cancelled');
  await expect(settleRegions(page)).rejects.toThrow(/requires instrumentRenderProbe/);
});

test('business probe reports accepted generations and returns detached snapshots', async ({ page }) => {
  const fixture = syntheticFixture({ files: 1, declarations: 1 });
  await installRenderingFixture(page, fixture, { authenticated: true });
  await page.goto('/example/regions/pull/1');
  await expect(page.locator('.viewed-control input').first()).toBeEnabled();
  await settleRegions(page);
  const before = await page.evaluate(() => __moondiffTestState());
  expect(before.application.generation).toBeGreaterThan(0);
  expect(before.application.viewed.ready).toBe(true);
  await page.evaluate(() => {
    const copy = __moondiffTestState();
    copy.cache.length = 0;
    copy.application.viewed.ready = false;
    copy.candidates.push('mutated');
  });
  expect(await page.evaluate(() => __moondiffTestState())).toEqual(before);
  const barrier = await holdRegionFrames(page, ['file:local_test.mbt']);
  try {
    await page.locator('.file-toggle').evaluate(button => button.click());
    await barrier.blocked();
    await expect(settleRegions(page, 30)).rejects.toThrow(/did not become idle/);
    expect(await page.evaluate(() => globalThis.__moondiffSettleFrame === undefined)).toBe(true);
  } finally { await barrier.release(); }
  await settleRegions(page);
});

test('failed native scroll actions remove their listeners and frame wait', async ({ page }) => {
  await page.goto('about:blank');
  await expect(scrollAndWait(page, async () => { throw new Error('failed input action'); })).rejects.toThrow(/failed input action/);
  expect(await page.evaluate(() => globalThis.__moondiffScrollWait === undefined)).toBe(true);
});
