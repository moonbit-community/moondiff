import { test as base, expect } from '@playwright/test';
import { beginControls, finishControls, requestsFor, collectBrowserDiagnostics, observeRouteHandlers } from './browser-control.mjs';

// Passive request listeners preserve the browser HTTP-cache test's un-routed
// context. Gates created by fixtures are always released, including on failure.
export const test = base.extend({
  page: async ({ page }, use) => {
    const rate = Number(process.env.MOONDIFF_TEST_CPU_RATE ?? 1);
    if (![1, 6].includes(rate)) throw new Error('MOONDIFF_TEST_CPU_RATE must be 1 or 6');
    const session = rate === 6 ? await page.context().newCDPSession(page) : null;
    if (session) await session.send('Emulation.setCPUThrottlingRate', { rate });
    try { await use(page); } finally {
      if (session && !page.isClosed()) {
        await session.send('Emulation.setCPUThrottlingRate', { rate: 1 });
        await session.detach();
      }
    }
  },
  browserControls: [async ({ context }, use, info) => {
    const current = beginControls();
    observeRouteHandlers(context);
    const errors = [];
    const listeners = new Map();
    const pages = new Set();
    current.pages = pages;
    const observe = page => {
      if (pages.has(page)) return;
      pages.add(page);
      requestsFor(page);
      const handler = error => errors.push(String(error));
      listeners.set(page, handler);
      page.on('pageerror', handler);
    };
    context.on('page', observe);
    try {
      for (const page of context.pages()) observe(page);
      await use(current);
    } finally {
      const attachDiagnostics = async (diagnostics) => {
        for (const [i, state] of (diagnostics ?? await collectBrowserDiagnostics([...pages])).entries()) {
          try {
            await info.attach(`browser-state-${i}.json`, {
              body: JSON.stringify(state, null, 2), contentType: 'application/json',
            });
          } catch (error) { info.annotations.push({ type: 'diagnostic-error', description: String(error) }); }
        }
      };
      const failed = info.status !== info.expectedStatus;
      if (failed) await attachDiagnostics();
      try {
        await finishControls(current, pages, { context });
        if (info.status === info.expectedStatus) expect(errors, 'uncaught browser errors').toEqual([]);
      } catch (error) {
        await attachDiagnostics(error.diagnostics);
        await info.attach('browser-cleanup.json', { contentType: 'application/json', body: JSON.stringify({
          error: String(error), causes: error.errors?.map(String), gates: [...current.gates].map(gate => gate.snapshot()), browserErrors: errors,
          contextHandlers: error.contextHandlers,
        }, null, 2) });
        throw error;
      } finally {
        context.off('page', observe);
        for (const [page, handler] of listeners) page.off('pageerror', handler);
      }
    }
  }, { auto: true }],
});
export { expect };
