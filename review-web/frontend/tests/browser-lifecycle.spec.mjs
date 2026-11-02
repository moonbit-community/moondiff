import { createServer } from 'node:http';
import { once } from 'node:events';
import { execFile } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { test as base, expect } from '../../tests/browser-test.mjs';
import { createGate, finishControls, installClock, requestsFor, trackRoute } from '../../tests/browser-control.mjs';

const test = base.extend({
  lifecycleOrigin: async ({}, use) => {
    const server = createServer((request, response) => {
      const url = new URL(request.url, 'http://fixture');
      if (url.pathname === '/redirect') {
        response.writeHead(302, { location: '/doc/plain' }); response.end(); return;
      }
      response.setHeader('Content-Type', 'text/html');
      const target = url.searchParams.get('fetch');
      response.end(`<!doctype html><title>lifecycle fixture</title>${target ?
        `<script>window.controlAbort = new AbortController(); window.result = fetch(${JSON.stringify(target)},
          { signal: controlAbort.signal }).then(r => r.text()).catch(e => e.name)</script>` : ''}`);
    });
    server.listen(0, '127.0.0.1');
    await once(server, 'listening');
    try { await use(`http://127.0.0.1:${server.address().port}`); }
    finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
  },
});

for (const boundary of ['reload', 'navigation']) {
  test(`document lifecycle overlap: ${boundary} keeps the new same-URL request pending with a paused clock`, async ({ page, context, browserControls, lifecycleOrigin }) => {
    await installClock(page);
    const recorder = requestsFor(page), oldResponse = createGate('old document response');
    // This handshake deliberately survives gate release by finishControls. It
    // is always resolved in finally, including when the assertions fail.
    const nextResponse = Promise.withResolvers(), nextEntered = Promise.withResolvers();
    let count = 0;
    await page.route(url => url.pathname === '/lifecycle/request', async raw => {
      const route = trackRoute(raw);
      if (++count === 1) await oldResponse.promise;
      else { nextEntered.resolve(); await nextResponse.promise; }
      await route.fulfill({ body: 'mock response' });
    });
    const initial = `${lifecycleOrigin}/doc/initial?fetch=/lifecycle/request`;
    await page.goto(initial);
    const old = await recorder.wait({ operation: '/lifecycle/request', phase: 'entered' });
    // Release the old mock from the new navigation's route, making delivery
    // overlap document replacement without depending on a Chromium bug.
    await page.route('**/doc/**', async route => {
      oldResponse.release();
      await route.fallback();
    });
    const unroute = page.unrouteAll.bind(page);
    let removed = false;
    page.unrouteAll = async options => { removed = true; return unroute(options); };
    try {
      if (boundary === 'reload') await page.reload();
      else await page.goto(`${lifecycleOrigin}/doc/next?fetch=/lifecycle/request`);
      await nextEntered.promise;
      const next = await recorder.wait({ after: old.id, operation: '/lifecycle/request', phase: 'entered' });
      expect(next.frameId).toBe(old.frameId);
      expect(next.documentId).toBe(old.documentId + 1);
      expect(next.generation).toBe(old.generation + 1);
      expect(next.phases.retired).toBeUndefined();
      expect(['received', 'cancelled', 'retired'].some(phase => old.phases[phase] !== undefined)).toBe(true);
      const navigation = recorder.matching({ predicate: record => record.navigation }).at(-1);
      expect(navigation.documentId).toBe(next.documentId);
      expect(navigation.phases.retired).toBeUndefined();
      const frozenTime = await page.evaluate(() => Date.now());
      const cleanup = finishControls(browserControls, [page], { context });
      await page.evaluate(() => document.readyState);
      expect(recorder.unfinished()).toContain(next);
      expect(removed).toBe(false);
      nextResponse.resolve();
      await cleanup;
      expect(next.phases.received).toBeDefined();
      expect(next.phases.retired).toBeUndefined();
      expect(await page.evaluate(() => Date.now())).toBe(frozenTime);
      expect(await page.evaluate(() => window.result)).toBe('mock response');
      await finishControls(browserControls, [page], { context });
    } finally { nextResponse.resolve(); oldResponse.release(); page.unrouteAll = unroute; }
  });
}

test('Playwright lifecycle adapter recognizes redirects, about:blank, repeated commits and only committed navigation', async ({ page, lifecycleOrigin }) => {
  const recorder = requestsFor(page);
  const document = () => recorder.snapshot().documents.find(frame => !frame.detached);
  expect(document().documentId).toBe(1);
  await page.goto(`${lifecycleOrigin}/doc/plain`);
  const initial = document();
  expect(initial.documentId).toBe(2);
  await page.goto(`${lifecycleOrigin}/doc/plain#hash`);
  await page.evaluate(() => {
    history.pushState(null, '', '/doc/pushed');
    history.replaceState(null, '', '/doc/replaced');
    dispatchEvent(new PageTransitionEvent('pagehide', { persisted: true }));
    dispatchEvent(new PageTransitionEvent('pageshow', { persisted: true }));
  });
  expect(document().documentId).toBe(initial.documentId);
  await page.route('**/abort', route => route.abort('aborted'));
  await expect(page.goto(`${lifecycleOrigin}/abort`)).rejects.toThrow(/ERR_ABORTED/);
  expect(document().documentId).toBe(initial.documentId);
  await page.goto('about:blank');
  expect(document().documentId).toBe(initial.documentId + 1);
  const after = recorder.checkpoint();
  await page.goto(`${lifecycleOrigin}/redirect`);
  const redirects = recorder.matching({ after, predicate: record => record.navigation });
  expect(redirects).toHaveLength(2);
  for (const request of redirects) {
    expect(request.ownership).toBe('document');
    expect(request.documentId).toBe(initial.documentId + 2);
    expect(request.phases.retired).toBeUndefined();
  }
  await page.reload();
  expect(document().documentId).toBe(initial.documentId + 3);
  expect(document().frameId).toBe(initial.frameId);
});

test('iframe commits and removal and a closed popup isolate document ownership', async ({ page, context, browserControls, lifecycleOrigin }) => {
  const gate = createGate('all frame responses');
  await context.route('**/lifecycle/hold?*', async raw => {
    const route = trackRoute(raw);
    await gate.promise;
    await route.fulfill({ body: 'frame response' });
  });
  const doc = owner => `${lifecycleOrigin}/doc/hold?fetch=${encodeURIComponent(`/lifecycle/hold?owner=${owner}`)}`;
  await page.goto(doc('main'));
  const recorder = requestsFor(page);
  const main = await recorder.wait({ target: 'owner=main' });
  for (const owner of ['child', 'sibling']) {
    await page.evaluate(({ owner, url }) => {
      const iframe = document.createElement('iframe'); iframe.id = owner; iframe.src = url; document.body.append(iframe);
    }, { owner, url: doc(owner) });
  }
  const child = await recorder.wait({ target: 'owner=child' }), sibling = await recorder.wait({ target: 'owner=sibling' });
  const frame = page.frames().find(frame => frame.url() === doc('child'));
  await frame.goto(doc('next'));
  const next = await recorder.wait({ target: 'owner=next' });
  expect(next.frameId).toBe(child.frameId);
  expect(next.documentId).toBe(child.documentId + 1);
  expect(recorder.unfinished()).not.toContain(child);
  const detached = page.waitForEvent('framedetached', frame => frame.url() === doc('next'));
  await page.locator('#child').evaluate(node => node.remove());
  await detached;
  expect(recorder.unfinished()).not.toContain(next);
  const opened = context.waitForEvent('page');
  await page.evaluate(url => { window.open(url); }, doc('popup'));
  const popup = await opened, popupRecorder = requestsFor(popup);
  const pending = await popupRecorder.wait({ target: 'owner=popup' });
  expect(popupRecorder.snapshot().documents[0].documentId).toBe(1);
  await popup.close();
  expect(popupRecorder.unfinished()).not.toContain(pending);
  expect(browserControls.pages.has(popup)).toBe(true);
  expect(context.pages()).not.toContain(popup);
  for (const record of [main, sibling]) {
    expect(recorder.unfinished()).toContain(record);
    expect(record.phases.retired).toBeUndefined();
  }
  gate.release();
  await finishControls(browserControls, browserControls.pages, { context });
  expect(popupRecorder.disposed).toBe(true);
  expect(popup.listenerCount('request')).toBe(0);
});

test('document cleanup waits for full Page fallback and Context handlers in order', async ({ page, context, browserControls, lifecycleOrigin }) => {
  const pageReturn = Promise.withResolvers(), contextReturn = Promise.withResolvers();
  const pageEntered = Promise.withResolvers(), contextEntered = Promise.withResolvers();
  const pageCleanup = Promise.withResolvers(), contextCleanup = Promise.withResolvers();
  const order = [], unroutePage = page.unrouteAll.bind(page), unrouteContext = context.unrouteAll.bind(context);
  await context.route(url => url.pathname === '/lifecycle/fallback', async raw => {
    contextEntered.resolve(); order.push('context handler');
    await trackRoute(raw).fulfill({ body: 'fallback' });
    await contextReturn.promise;
    order.push('context returned');
  });
  await page.route(url => url.pathname === '/lifecycle/fallback', async route => {
    pageEntered.resolve(); await pageReturn.promise;
    await route.fallback(); order.push('page returned');
  });
  page.unrouteAll = async options => { order.push('page cleanup'); pageCleanup.resolve(); await unroutePage(options); };
  context.unrouteAll = async options => { order.push('context cleanup'); contextCleanup.resolve(); await unrouteContext(options); };
  try {
    await page.goto(`${lifecycleOrigin}/doc/fallback?fetch=/lifecycle/fallback`);
    await pageEntered.promise;
    // Establish genuine cancellation before destruction; retirement alone must
    // never excuse a throwing fulfill on a route Chromium already disposed.
    await page.evaluate(() => controlAbort.abort());
    await requestsFor(page).wait({ operation: '/lifecycle/fallback', phase: 'cancelled' });
    await page.goto('about:blank');
    const cleanup = finishControls(browserControls, [page], { context });
    await pageCleanup.promise;
    expect(order).toEqual(['page cleanup']);
    pageReturn.resolve();
    await contextEntered.promise; await contextCleanup.promise;
    expect(order.indexOf('page returned')).toBeLessThan(order.indexOf('context cleanup'));
    expect(order).not.toContain('context returned');
    contextReturn.resolve(); await cleanup;
    expect(order.at(-1)).toBe('context returned');
  } finally {
    pageReturn.resolve(); contextReturn.resolve();
    page.unrouteAll = unroutePage; context.unrouteAll = unrouteContext;
  }
});

test('closed pages remain registered and cleanup still waits for their Node handlers', async ({ context, browserControls, lifecycleOrigin }) => {
  const popup = await context.newPage(), recorder = requestsFor(popup);
  const handlerReturn = Promise.withResolvers(), delivered = Promise.withResolvers(), cleaning = Promise.withResolvers();
  let returned = false;
  const unroute = popup.unrouteAll.bind(popup);
  await popup.route(url => url.pathname === '/lifecycle/closed', async raw => {
    await trackRoute(raw).fulfill({ body: 'closed' }); delivered.resolve();
    await handlerReturn.promise; returned = true;
  });
  popup.unrouteAll = async options => { cleaning.resolve(); await unroute(options); };
  try {
    await popup.goto(`${lifecycleOrigin}/doc/closed?fetch=/lifecycle/closed`);
    await delivered.promise;
    await recorder.wait({ operation: '/lifecycle/closed', phase: 'received' });
    await popup.close();
    const cleanup = finishControls(browserControls, browserControls.pages, { context });
    await cleaning.promise;
    expect(returned).toBe(false);
    expect(recorder.disposed).toBe(false);
    handlerReturn.resolve(); await cleanup;
    expect(returned).toBe(true);
    expect(recorder.disposed).toBe(true);
  } finally { handlerReturn.resolve(); popup.unrouteAll = unroute; }
});

test('Page and Context callback exceptions after document replacement still fail the test runner', async ({}, info) => {
  // A child runner lets us assert real failing tests, including exceptions
  // emitted asynchronously by Playwright, without making this suite fail.
  const directory = info.outputPath('handler-errors');
  await mkdir(directory, { recursive: true });
  const config = join(directory, 'playwright.config.mjs');
  await writeFile(config, `export default ${JSON.stringify({
    testDir: directory, testMatch: 'handler-errors.spec.mjs', outputDir: join(directory, 'artifacts'),
    workers: 1, retries: 0, reporter: 'json', use: { browserName: 'chromium', channel: 'chromium' },
    // CI git metadata can contain this spec's source, including its timeout assertion.
    metadata: { note: 'Timed out in report metadata is not a test error' },
  })};`);
  await writeFile(join(directory, 'handler-errors.spec.mjs'), `
    import { test } from ${JSON.stringify(new URL('../../tests/browser-test.mjs', import.meta.url).href)};
    import { createGate } from ${JSON.stringify(new URL('../../tests/browser-control.mjs', import.meta.url).href)};
    for (const kind of ['Page', 'Context']) test(kind + ' handler error after replacement', async ({ page, context }) => {
      const entered = Promise.withResolvers(), gate = createGate('throw during cleanup');
      await page.route('http://lifecycle.test/', route => route.fulfill({ contentType: 'text/html',
        body: '<script>fetch("/pending").catch(() => {})</script>' }));
      await (kind === 'Page' ? page : context).route('http://lifecycle.test/pending', async () => {
        entered.resolve(); await gate.promise;
        throw new Error(kind + ' intentional handler failure');
      });
      await page.goto('http://lifecycle.test/');
      await entered.promise;
      await page.goto('about:blank');
    });
  `);
  const cli = fileURLToPath(new URL('../../node_modules/@playwright/test/cli.js', import.meta.url));
  const result = await promisify(execFile)(process.execPath, [cli, 'test', '--config', config], {
    timeout: 25_000, maxBuffer: 2_000_000,
  }).then(result => ({ ...result, code: 0 }), error => error);
  expect(result.code, result.stderr).toBe(1);
  const report = JSON.parse(result.stdout);
  expect(report.stats.unexpected).toBe(2);
  expect(report.errors).toEqual([]);
  const specs = report.suites.flatMap(suite => suite.specs);
  expect(specs).toHaveLength(2);
  for (const kind of ['Page', 'Context']) {
    const spec = specs.find(spec => spec.title === `${kind} handler error after replacement`);
    expect(spec?.tests, `${kind} child test`).toHaveLength(1);
    const [child] = spec.tests;
    expect(child.results).toHaveLength(1);
    const [result] = child.results;
    expect(result.status).toBe('failed');
    const errors = result.errors.map(error => error.message ?? error.value ?? '');
    expect(errors).toEqual(expect.arrayContaining([
      expect.stringMatching(new RegExp(`^Error: ${kind} intentional handler failure(?:\\n|$)`)),
    ]));
    expect(errors.join('\n')).not.toContain('Timed out');
  }
});
