import { test, expect } from '@playwright/test';
import { successFixture } from '../../tests/protocol-fixtures.mjs';
import { installRenderProbe, renderCounts, settleRegions } from '../../tests/render-probe.mjs';
import { gate, installRenderingFixture, navigate, syntheticFixture } from './rendering-fixture.mjs';
import { holdRegionFrames } from './dom-timing.mjs';

const limited = { status: 429, code: 'rate_limit', detail: 'Rate limited' };

async function setup(page, { paused = false, allExpanded = false, nativeAnchor = 'none',
  algorithm = 'Token', layout = 'Split', initialComment, deferredLimit } = {}) {
  await installRenderProbe(page);
  const fixture = syntheticFixture({ files: 6, declarations: 16 });
  const state = await installRenderingFixture(page, fixture, {
    comments: initialComment ? [readingComment(fixture, initialComment)] : [],
    sourceGate: args => deferredLimit && fixture.files.findIndex(file => file.filename === args.path) >= 4
      ? deferredLimit.promise : undefined,
    sourceFailure: args => (paused || deferredLimit) && !state.authenticated &&
      fixture.files.findIndex(file => file.filename === args.path) >= 4 ? limited : undefined,
  });
  await page.goto('/example/regions/pull/1');
  await expect(page.locator('#moondiff-file-1 table').first()).toBeAttached();
  await expect(page.locator(deferredLimit ? '#moondiff-file-1 .loading-inline' : '.loading-inline')).toHaveCount(0);
  if (paused) await expect(page.locator('.rate-limit')).toBeAttached();
  if (allExpanded) {
    await page.locator('.file-card:not(.expanded) .file-toggle').evaluateAll(buttons => buttons.forEach(button => button.click()));
    await expect(page.locator('.file-card.expanded')).toHaveCount(6);
    await expect(page.locator('.loading-inline')).toHaveCount(0);
  }
  if (algorithm !== 'Token') await page.getByRole('button', { name: algorithm, exact: true }).click();
  if (layout !== 'Split') await page.getByRole('button', { name: layout, exact: true }).click();
  await settleRegions(page);
  const anchor = page.locator(`#moondiff-file-1 table.${layout.toLowerCase()}:visible tr`).filter({
    has: page.locator('.new-line-number .line-number-value', { hasText: /^6$/ }),
  }).first();
  await anchor.evaluate((element, nativeAnchor) => {
    document.documentElement.style.setProperty('overflow-anchor', nativeAnchor, 'important');
    window.scrollTo(0, scrollY + element.getBoundingClientRect().top - 180);
    window.readingNode = element;
    window.readingFocus = element.closest('.file-card').querySelector('.file-toggle');
    window.readingFocus.focus({ preventScroll: true });
  }, nativeAnchor);
  await settleRegions(page);
  const top = await anchor.evaluate(element => element.getBoundingClientRect().top);
  const auth = gate();
  await page.route('**/api/auth/device/start', async route => {
    const id = route.request().postDataJSON().attempt_id;
    await auth.promise;
    state.authenticated = true;
    await route.fulfill({ json: successFixture('auth.device.start', {
      attempt_id: id, authenticated: true, login: 'reviewer', user_id: '1', csrf_token: 'fixture',
      device_flow: { id, phase: 'completed', user_code: '', verification_uri: '',
        expires_at: 2_000_000_000, retry_after: 5, message: '' },
    }) });
  });
  const signIn = () => page.getByRole('button', { name: 'Sign in with GitHub', exact: true }).first().evaluate(button => button.click());
  return { fixture, state, anchor, top, auth, signIn };
}

function readingComment(fixture, body) {
  const path = fixture.files[1].filename;
  return { id: 78, body, path, html_url: 'https://github.com/example/regions/pull/1#discussion_r78',
    created_at: '2026-10-01T00:00:00Z', user: { login: 'reviewer' },
    commit_id: fixture.sha, original_commit_id: fixture.sha, line: 2, original_line: 2,
    position: fixture.sources[`${fixture.base}:${path}`].split('\n').length + 2,
    side: 'RIGHT', diff_hunk: fixture.files[1].patch };
}

async function expectReading(page, anchor, top) {
  await settleRegions(page);
  expect(await anchor.evaluate(element => element === window.readingNode)).toBe(true);
  expect(await page.evaluate(() => document.activeElement === window.readingFocus)).toBe(true);
  expect(Math.abs(await anchor.evaluate(element => element.getBoundingClientRect().top) - top)).toBeLessThan(2);
}

async function expectFinished(page) {
  await expect.poll(() => page.evaluate(() => globalThis.__moondiffMetrics.reading)).toMatchObject({
    active: false, metadata: false, listening: false, frame: 0,
  });
  await settleRegions(page);
}

async function activate(page) {
  await page.evaluate(() => {
    Object.defineProperty(document, 'hasFocus', { configurable: true, value: () => false });
    dispatchEvent(new Event('blur'));
    Object.defineProperty(document, 'hasFocus', { configurable: true, value: () => true });
    dispatchEvent(new Event('focus'));
  });
}

async function reactivate(page) {
  const response = page.waitForResponse('**/api/auth/status');
  await activate(page);
  await (await response).finished();
}

for (const order of ['old-first', 'new-first', 'old-pending', 'new-fails']) {
  test(`overlapping identity requests retire recovery: ${order}`, async ({ page }) => {
    const { anchor, top } = await setup(page);
    const requests = [];
    await page.route('**/api/auth/status', async route => {
      const pending = gate();
      const index = requests.length;
      requests.push(pending);
      await pending.promise;
      await route.fulfill(index === 1 && order === 'new-fails' ? {
        status: 503, json: { $tag: 'Failure', error: {
          status: 503, code: 'identity_unavailable', message: 'Identity check unavailable',
        } },
      } : { json: successFixture('auth.status', {
        authenticated: index === 0, csrf_token: 'fixture',
        ...(index === 0 ? { login: 'obsolete', user_id: '99' } : {}),
      }) }).catch(() => {});
    });
    await activate(page);
    await expect.poll(() => requests.length).toBe(1);
    await activate(page);
    await expect.poll(() => requests.length).toBe(2);
    if (order === 'old-first') requests[0].resolve();
    requests[1].resolve();
    if (order === 'new-first') {
      await settleRegions(page);
      requests[0].resolve();
    }
    await expectFinished(page);
    await expectReading(page, anchor, top);
    await expect(page.getByRole('button', { name: 'Account: obsolete' })).toHaveCount(0);
    requests[0].resolve();
  });
}

test('skipping capture at the page top permits the next reading recovery', async ({ page }) => {
  const { anchor } = await setup(page);
  await page.evaluate(() => scrollTo(0, 0));
  await settleRegions(page);
  await reactivate(page);
  await expect.poll(() => page.evaluate(() => __moondiffMetrics.reading?.metadata)).toBe(false);
  await anchor.evaluate(element => scrollTo(0, scrollY + element.getBoundingClientRect().top - 180));
  await settleRegions(page);
  const top = await anchor.evaluate(element => element.getBoundingClientRect().top);
  await page.route('**/api/auth/status', route => route.fulfill({
    status: 503, json: { $tag: 'Failure', error: {
      status: 503, code: 'identity_unavailable', message: 'Identity check unavailable',
    } },
  }));
  await reactivate(page);
  await expectReading(page, anchor, top);
  await expectFinished(page);
  expect((await renderCounts(page)).counters.reading_captured).toBe(1);
});

test('page-top activation does not block later rate-limit layout recovery', async ({ page }) => {
  const limit = gate();
  const { anchor } = await setup(page, { deferredLimit: limit });
  await page.evaluate(() => scrollTo(0, 0));
  await settleRegions(page);
  await reactivate(page);
  await expect.poll(() => page.evaluate(() => __moondiffMetrics.reading?.metadata)).toBe(false);
  await anchor.evaluate(element => scrollTo(0, scrollY + element.getBoundingClientRect().top - 180));
  await settleRegions(page);
  const top = await anchor.evaluate(element => element.getBoundingClientRect().top);
  limit.resolve();
  await expect(page.locator('.rate-limit')).toBeAttached();
  await expectReading(page, anchor, top);
  await expectFinished(page);
});

for (const algorithm of ['Token', 'Tree']) for (const layout of ['Split', 'Unified']) {
  for (const trigger of ['reactivation', 'manual refresh']) {
    test(`inline comment insertion, growth and deletion preserve the reading line: ${algorithm} ${layout} ${trigger}`, async ({ page }) => {
      const { fixture, state, anchor, top } = await setup(page, { algorithm, layout });
      const before = await renderCounts(page);
      for (const body of ['Comment above the reading line', 'A taller comment\n\n' + 'Additional paragraph\n\n'.repeat(12), null]) {
        const comments = gate();
        state.readGates = { 'github.comments.list': comments };
        state.comments = body ? [readingComment(fixture, body)] : [];
        if (trigger === 'reactivation') await reactivate(page);
        else await page.getByRole('button', { name: 'Refresh', exact: true }).evaluate(button => button.click());
        await expect.poll(() => page.evaluate(() => __moondiffMetrics.reading.active)).toBe(true);
        await settleRegions(page);
        expect(await page.evaluate(() => __moondiffMetrics.reading.row)).not.toBe('');
        comments.resolve();
        if (body) await expect(page.locator('#moondiff-file-1 tr').filter({ hasText: body.split('\n')[0] })).toHaveCount(1);
        else await expect(page.getByText('A taller comment', { exact: true })).toHaveCount(0);
        await expectFinished(page);
        await expectReading(page, anchor, top);
        const after = await renderCounts(page);
        for (const file of fixture.files.filter((_, index) => index !== 1)) {
          expect(after.files[file.filename]).toEqual(before.files[file.filename]);
        }
      }
    });
  }
  for (const change of ['insert', 'grow', 'delete']) {
    test(`modal login preserves the reading line after inline comment ${change}: ${algorithm} ${layout}`, async ({ page }) => {
      const { fixture, state, anchor, top, auth } = await setup(page, {
        algorithm, layout, initialComment: change === 'insert' ? undefined : 'Original comment',
      });
      const body = change === 'delete' ? null : 'Changed comment\n\n' + 'Additional paragraph\n\n'.repeat(change === 'grow' ? 12 : 0);
      state.comments = body ? [readingComment(fixture, body)] : [];
      const comments = gate(), viewed = gate();
      state.readGates = { 'github.comments.list': comments, 'github.pull.viewed.get': viewed };
      await page.locator('#moondiff-file-1 .viewed-control input').evaluate(input => {
        input.focus({ preventScroll: true });
        input.click();
      });
      const dialog = page.locator('#sign-in-dialog');
      await expect(dialog).toBeVisible();
      await dialog.getByRole('button', { name: 'Sign in with GitHub', exact: true }).click();
      await expect.poll(() => page.evaluate(() => __moondiffMetrics.reading.active)).toBe(true);
      expect(await page.evaluate(() => __moondiffMetrics.reading.row)).not.toBe('');
      auth.resolve();
      await expect(dialog).toBeHidden();
      // Close while Viewed is still disabled, so the existing dialog rule
      // deterministically restores the file toggle before background refreshes.
      viewed.resolve();
      await expect(page.locator('#moondiff-file-1 .viewed-control input')).toBeEnabled();
      const before = await renderCounts(page);
      comments.resolve();
      if (body) await expect(page.locator('#moondiff-file-1 tr').filter({ hasText: 'Changed comment' })).toHaveCount(1);
      else await expect(page.getByText('Original comment', { exact: true })).toHaveCount(0);
      await expectFinished(page);
      await expectReading(page, anchor, top);
      const after = await renderCounts(page);
      for (const file of fixture.files.filter((_, index) => index !== 1)) {
        expect(after.files[file.filename]).toEqual(before.files[file.filename]);
      }
    });
  }
}

test('delayed Viewed recovery preserves the original reading baseline', async ({ page }) => {
  const { fixture, state, anchor, top, auth, signIn } = await setup(page, { paused: true });
  const viewed = gate();
  state.readGates = { 'github.pull.viewed.get': viewed };
  state.viewed[fixture.files[0].filename] = true;
  await signIn();
  auth.resolve();
  await expect(page.locator('.rate-limit')).toHaveCount(0);
  await expect.poll(() => state.calls.filter(call => call.op === 'github.pull.viewed.get').length).toBe(1);
  await expectReading(page, anchor, top);
  viewed.resolve();
  await expect(page.locator('#moondiff-file-0')).toHaveClass('file-card');
  await expectReading(page, anchor, top);
  await expectFinished(page);
});

for (const order of [['toolbar', 'status'], ['status', 'toolbar']]) {
  test(`overlapping auth layouts preserve the first baseline: ${order.join(' then ')}`, async ({ page }) => {
    const { state, anchor, top, auth, signIn } = await setup(page, { paused: true });
    const barrier = await holdRegionFrames(page, ['toolbar', 'status']);
    await signIn();
    await barrier.blocked();
    await barrier.release([order[0]]);
    await page.getByText('Starting GitHub sign-in…').first().waitFor({ state: 'attached' });
    auth.resolve();
    await expect.poll(() => state.calls.some(call => call.op === 'github.pull.viewed.get')).toBe(true);
    await barrier.release([order[1]]);
    await expect(page.locator('.rate-limit')).toHaveCount(0);
    await expectReading(page, anchor, top);
    await expectFinished(page);
    const probe = await page.evaluate(() => __moondiffMetrics);
    expect(probe.counters.reading_captured).toBe(1);
    expect(probe.counters.reading_merged).toBeGreaterThan(0);
  });
}

test('Viewed, comments and merge batches share a baseline across immediate reactivation', async ({ page }) => {
  const { fixture, state, anchor, top, auth, signIn } = await setup(page);
  const viewed = gate(), comments = gate(), merge = gate();
  state.readGates = { 'github.pull.viewed.get': viewed, 'github.comments.list': comments, 'github.pull.merge.status': merge };
  state.comments = [{ id: 77, body: 'Delayed recovery comment', html_url: 'https://github.com/example/regions/pull/1#discussion_r77',
    created_at: '2026-10-01T00:00:00Z', user: { login: 'reviewer' }, path: fixture.files[0].filename,
    commit_id: fixture.sha, original_commit_id: fixture.sha, line: 2, original_line: 2, side: 'RIGHT', diff_hunk: fixture.files[0].patch }];
  await signIn(); auth.resolve();
  await expect(page.getByRole('button', { name: 'Account: reviewer' })).toBeAttached();
  await reactivate(page);
  await expectReading(page, anchor, top);
  viewed.resolve();
  await expect(page.locator('#moondiff-file-1 input[type="checkbox"]')).toBeEnabled();
  await expectReading(page, anchor, top);
  const beforeComments = await renderCounts(page);
  comments.resolve();
  await expect(page.getByText('Delayed recovery comment', { exact: true })).toBeAttached();
  await expectReading(page, anchor, top);
  const afterComments = await renderCounts(page);
  for (const file of fixture.files.slice(1)) expect(afterComments.files[file.filename]).toEqual(beforeComments.files[file.filename]);
  merge.resolve();
  await expectFinished(page);
  await expectReading(page, anchor, top);
  expect((await renderCounts(page)).counters.reading_captured).toBe(1);
});

test('all expanded files restore nondefault native anchoring between batches and at completion', async ({ page }) => {
  const { state, anchor, top, auth, signIn } = await setup(page, { allExpanded: true, nativeAnchor: 'auto' });
  const viewed = gate(); state.readGates = { 'github.pull.viewed.get': viewed };
  const style = () => page.evaluate(() => ({ value: document.documentElement.style.getPropertyValue('overflow-anchor'),
    priority: document.documentElement.style.getPropertyPriority('overflow-anchor') }));
  const barrier = await holdRegionFrames(page, ['toolbar']);
  await signIn(); await barrier.blocked();
  expect(await style()).toEqual({ value: 'none', priority: 'important' });
  auth.resolve(); await barrier.release();
  await expect(page.getByRole('button', { name: 'Account: reviewer' })).toBeAttached();
  await expectReading(page, anchor, top);
  await expect.poll(style).toEqual({ value: 'auto', priority: 'important' });
  expect(await page.evaluate(() => __moondiffMetrics.reading.active)).toBe(true);
  viewed.resolve(); await expectFinished(page); await expectReading(page, anchor, top);
  expect(await style()).toEqual({ value: 'auto', priority: 'important' });
});

test('source prefetch and Pending CI do not extend reading recovery', async ({ page }) => {
  const { state, anchor, top, auth, signIn, fixture } = await setup(page, { paused: true });
  const source = gate();
  state.sourceGate = () => source.promise;
  state.mergeStatus = { base_sha: fixture.base, head_sha: fixture.sha, open: true, draft: false, merged: false,
    mergeable: true, rebaseable: true, mergeable_state: 'clean', ci_summary: { $tag: 'Pending' }, ci_checks: [], ci_warnings: [] };
  await signIn(); auth.resolve();
  await expect(page.locator('.rate-limit')).toHaveCount(0);
  await expect.poll(() => state.activeSources).toBeGreaterThan(0);
  await expectFinished(page);
  await expectReading(page, anchor, top);
  source.resolve();
});

for (const kind of ['wheel', 'touchstart', 'pointerdown', 'keydown', 'input', 'click']) {
  test(`${kind} synchronously cancels recovery before delayed paints and responses`, async ({ page }) => {
    const { state, auth, signIn } = await setup(page, { paused: true });
    const viewed = gate(); state.readGates = { 'github.pull.viewed.get': viewed };
    const barrier = await holdRegionFrames(page, ['toolbar', 'status']);
    await signIn(); await barrier.blocked();
    await page.evaluate(kind => {
      dispatchEvent(new Event(kind, { bubbles: true }));
      if (__moondiffMetrics.reading.active) throw new Error('Reading cancellation was not synchronous');
      window.scrollTo(0, 350);
      window.recoveryScrolls = 0;
      const original = window.scrollTo;
      window.scrollTo = function (...args) { window.recoveryScrolls++; return original.apply(this, args); };
    }, kind);
    auth.resolve(); await barrier.release(); viewed.resolve();
    await expect(page.getByRole('button', { name: 'Account: reviewer' })).toBeAttached();
    await expectFinished(page);
    await reactivate(page); await settleRegions(page);
    expect(await page.evaluate(() => window.recoveryScrolls)).toBe(0);
    expect((await renderCounts(page)).counters.reading_captured).toBe(1);
  });
}

for (const destination of ['file', 'route', 'collapse']) {
  test(`${destination} cancels recovery and rejects late work`, async ({ page }) => {
    const { state, fixture, auth, signIn } = await setup(page);
    const viewed = gate(); state.readGates = { 'github.pull.viewed.get': viewed };
    await signIn(); auth.resolve();
    await expect(page.getByRole('button', { name: 'Account: reviewer' })).toBeAttached();
    if (destination === 'file') {
      await page.locator('[data-region="tree"] [aria-label="Open src/unrelated-3.mbt"]').evaluate(element => element.click());
    } else if (destination === 'route') {
      await navigate(page, `/example/regions/commit/${fixture.sha}`);
      await expect(page).toHaveURL(new RegExp(`/commit/${fixture.sha}$`));
    } else {
      state.viewed[fixture.files[1].filename] = true;
    }
    await settleRegions(page);
    const compensated = await page.evaluate(() => __moondiffMetrics.counters?.reading_compensated ?? 0);
    viewed.resolve();
    await expectFinished(page);
    if (destination === 'collapse') await expect(page.locator('#moondiff-file-1')).toHaveClass('file-card');
    expect(await page.evaluate(() => __moondiffMetrics.counters?.reading_compensated ?? 0)).toBe(compensated);
  });
}

for (const failure of ['sign-in', 'snapshot']) {
  test(`${failure} failure settles protection without losing the reading line`, async ({ page }) => {
    const { anchor, top, auth, signIn } = await setup(page, { paused: true });
    if (failure === 'sign-in') {
      await page.route('**/api/auth/device/start', route => route.fulfill({ status: 403, json: {
        $tag: 'Failure', error: { status: 403, code: 'sign_in_denied', message: 'Sign-in denied.' },
      } }));
    } else {
      await page.route('**/api/rpc', route => {
        if (route.request().postDataJSON().request.$tag !== 'PullSnapshotGet') return route.fallback();
        return route.fulfill({ status: 503, json: { $tag: 'Failure', error: {
          status: 503, code: 'unavailable', message: 'Validation unavailable',
        } } });
      });
    }
    await signIn(); auth.resolve();
    await expect(page.locator('.rate-limit')).toBeAttached();
    await expectFinished(page);
    await expectReading(page, anchor, top);
  });
}

test('cancelling sign-in invalidates pending auth callbacks and permits a new recovery', async ({ page }) => {
  const { state, auth, signIn } = await setup(page, { paused: true });
  await page.route('**/api/auth/device/cancel', route => route.fulfill({ json: successFixture('auth.device.cancel', {
    authorization_id: route.request().postDataJSON().authorization_id, authenticated: false, csrf_token: 'fixture',
  }) }));
  await signIn();
  await page.getByRole('button', { name: 'Cancel sign-in', exact: true }).first().evaluate(button => button.click());
  await expectFinished(page);
  auth.resolve(); await settleRegions(page);
  expect(await page.evaluate(() => __moondiffMetrics.reading.active)).toBe(false);
  state.authenticated = false;
  await page.getByRole('button', { name: 'Sign in with GitHub', exact: true }).first().evaluate(button => button.click());
  await expect(page.getByRole('button', { name: 'Account: reviewer' })).toBeAttached();
  await expectFinished(page);
  expect((await renderCounts(page)).counters.reading_captured).toBe(2);
});

test('reactivation completing device authorization releases its cancelled poll work', async ({ page }) => {
  const { state, anchor, top, signIn } = await setup(page);
  await page.route('**/api/auth/device/start', route => {
    const id = route.request().postDataJSON().attempt_id;
    return route.fulfill({ json: successFixture('auth.device.start', {
      attempt_id: id, authenticated: false, csrf_token: 'fixture',
      device_flow: { id, phase: 'pending', user_code: 'ABCD-EFGH', verification_uri: 'https://github.com/login/device',
        expires_at: 2_000_000_000, retry_after: 60, message: '' },
    }) });
  });
  await signIn();
  await expect(page.getByText('ABCD-EFGH').first()).toBeAttached();
  await expectReading(page, anchor, top);
  state.authenticated = true;
  await reactivate(page);
  await expect(page.getByRole('button', { name: 'Account: reviewer' })).toBeAttached();
  await expectFinished(page);
  await expectReading(page, anchor, top);
});

test('device authorization retires a hung identity check without a failure notice', async ({ page }) => {
  const { state, anchor, top, signIn } = await setup(page);
  const poll = gate(), status = gate();
  let polling = false, checking = false;
  await page.route('**/api/auth/device/start', route => {
    const id = route.request().postDataJSON().attempt_id;
    return route.fulfill({ json: successFixture('auth.device.start', {
      attempt_id: id, authenticated: false, csrf_token: 'fixture',
      device_flow: { id, phase: 'pending', user_code: 'ABCD-EFGH', verification_uri: 'https://github.com/login/device',
        expires_at: 2_000_000_000, retry_after: 1, message: '' },
    }) });
  });
  await page.route('**/api/auth/device/poll', async route => {
    const id = route.request().postDataJSON().authorization_id;
    polling = true;
    await poll.promise;
    state.authenticated = true;
    await route.fulfill({ json: successFixture('auth.device.poll', {
      authorization_id: id, authenticated: true, login: 'reviewer', user_id: '1', csrf_token: 'fixture',
      device_flow: { id, phase: 'completed', user_code: '', verification_uri: '',
        expires_at: 2_000_000_000, retry_after: 5, message: '' },
    }) });
  });
  await signIn();
  await expect(page.getByText('ABCD-EFGH').first()).toBeAttached();
  await expect.poll(() => polling).toBe(true);
  await page.route('**/api/auth/status', async route => {
    checking = true;
    await status.promise;
    await route.fulfill({ json: successFixture('auth.status', {
      authenticated: false, csrf_token: 'obsolete',
    }) }).catch(() => {});
  });
  await activate(page);
  await expect.poll(() => checking).toBe(true);
  poll.resolve();
  await expect(page.getByRole('button', { name: 'Account: reviewer' })).toBeAttached();
  await expectFinished(page);
  await expectReading(page, anchor, top);
  status.resolve();
  await settleRegions(page);
  await expect(page.getByRole('button', { name: 'Account: reviewer' })).toBeAttached();
  await expect(page.getByText(/Connection interrupted|Identity check unavailable/)).toHaveCount(0);
});

test('cancelled recovery releases its reading DOM while a response is still gated', async ({ page }) => {
  const { state, auth, signIn } = await setup(page);
  const viewed = gate(); state.readGates = { 'github.pull.viewed.get': viewed };
  await signIn(); auth.resolve();
  await expect(page.getByRole('button', { name: 'Account: reviewer' })).toBeAttached();
  await expect.poll(() => state.calls.some(call => call.op === 'github.pull.viewed.get')).toBe(true);
  expect(await page.evaluate(() => __moondiffMetrics.reading.active)).toBe(true);
  await page.evaluate(() => {
    window.retiredReading = new WeakRef(window.readingNode.closest('.file-card'));
    delete window.readingNode;
    delete window.readingFocus;
  });
  await navigate(page, '/');
  await expect(page.locator('.file-card')).toHaveCount(0);
  await expectFinished(page);
  const session = await page.context().newCDPSession(page);
  await session.send('HeapProfiler.collectGarbage');
  expect(await page.evaluate(() => window.retiredReading.deref() === undefined)).toBe(true);
  viewed.resolve(); await settleRegions(page);
  expect(await page.evaluate(() => __moondiffMetrics.reading.active)).toBe(false);
  await session.detach();
});

test('sign-in through the modal captures the loaded file behind its backdrop', async ({ page }) => {
  const { state, fixture, anchor, top, auth } = await setup(page);
  const viewed = gate(); state.readGates = { 'github.pull.viewed.get': viewed };
  state.viewed[fixture.files[0].filename] = true;
  await page.locator('#moondiff-file-1 .viewed-control input').evaluate(input => {
    input.focus({ preventScroll: true });
    input.click();
  });
  const dialog = page.locator('#sign-in-dialog');
  await expect(dialog).toBeVisible();
  await dialog.getByRole('button', { name: 'Sign in with GitHub', exact: true }).click();
  await expect.poll(() => page.evaluate(() => __moondiffMetrics.reading.active)).toBe(true);
  auth.resolve();
  await expect(dialog).toBeHidden();
  await expectReading(page, anchor, top);
  viewed.resolve();
  await expectFinished(page);
  await expectReading(page, anchor, top);
});
