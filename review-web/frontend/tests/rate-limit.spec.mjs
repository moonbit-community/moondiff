import { test, expect } from '../../tests/browser-test.mjs';
import { successFixture } from '../../tests/protocol-fixtures.mjs';
import { settleRegions } from '../../tests/render-probe.mjs';
import { gate, installRenderingFixture, syntheticFixture } from './rendering-fixture.mjs';

const sources = state => state.calls.filter(call => call.op === 'github.content.get');
const card = (page, index) => page.locator(`#moondiff-file-${index}`);
const toggle = (page, index) => card(page, index).locator('.file-toggle').evaluate(button => button.click());
const limited = { status: 429, code: 'rate_limit', detail: 'Rate limited' };
const anonymousMessage = 'GitHub is limiting anonymous requests. Sign in to continue.';
const authenticatedMessage = 'GitHub is limiting requests. Please refresh this page later.';
const routes = {
  PR: f => '/example/regions/pull/1',
  Commit: f => `/example/regions/commit/${f.sha}`,
  PullCommit: f => `/example/regions/pull/1/commits/${f.sha}`,
  Range: f => `/example/regions/compare/${f.base}..${f.sha}`,
  PullRange: f => `/example/regions/pull/1/compare/${f.base}..${f.sha}`,
};

async function installSignIn(page, state, outcome = 'success') {
  await page.route('**/api/auth/device/start', async route => {
    const id = route.request().postDataJSON().attempt_id;
    if (outcome === 'failure') return route.fulfill({ status: 403, json: {
      $tag: 'Failure', error: { status: 403, code: 'sign_in_denied', message: 'Sign-in denied.' },
    } });
    state.authenticated = outcome === 'success';
    await route.fulfill({ json: successFixture('auth.device.start', {
      attempt_id: id, authenticated: state.authenticated, csrf_token: 'fixture',
      ...(state.authenticated ? { login: 'reviewer', user_id: '1' } : {}),
      device_flow: { id, phase: state.authenticated ? 'completed' : 'pending', user_code: 'ABCD-EFGH',
        verification_uri: 'https://github.com/login/device', expires_at: 2_000_000_000, retry_after: 60, message: '' },
    }) });
  });
  await page.route('**/api/auth/device/cancel', route => route.fulfill({ json: successFixture('auth.device.cancel', {
    authorization_id: route.request().postDataJSON().authorization_id,
    authenticated: false, csrf_token: 'fixture',
  }) }));
}

async function visibilityCycle(page) {
  await page.evaluate(() => {
    for (const hidden of [true, false]) {
      Object.defineProperty(document, 'hidden', { configurable: true, value: hidden });
      document.dispatchEvent(new Event('visibilitychange'));
    }
  });
  await settleRegions(page);
}

for (const [kind, route] of Object.entries(routes)) {
  test(`${kind} authenticated limit drains four requests and blocks every source trigger`, async ({ page }) => {
    const fixture = syntheticFixture({ files: 24, declarations: 2 });
    const initial = gate();
    const state = await installRenderingFixture(page, fixture, { authenticated: true,
      sourceGate: () => initial.promise, sourceFailure: () => limited });
    await page.goto(route(fixture));
    await expect.poll(() => sources(state).length).toBe(4);
    initial.resolve();
    await expect(page.locator('.rate-limit')).toHaveText(authenticatedMessage);
    await expect(page.locator('.loading-inline')).toHaveCount(0);
    await expect(page.locator('.file-message.paused')).toHaveCount(20);
    await expect(page.locator('.rate-limit button')).toHaveCount(0);
    await expect(page.getByRole('button', { name: /Retry file|Try again|Sign in with GitHub/ })).toHaveCount(0);
    await toggle(page, 23);
    await expect(card(page, 23).locator('.paused')).toBeAttached();
    await card(page, 22).evaluate(element => {
      window.dispatchEvent(new WheelEvent('wheel', { deltaY: 1 })); element.scrollIntoView();
    });
    await visibilityCycle(page);
    await page.waitForTimeout(150);
    expect(sources(state)).toHaveLength(4);
    expect(state.maxActiveSources).toBe(4);
    await expect(page.locator('.loading-inline')).toHaveCount(0);
  });

  test(`${kind} anonymous login resumes missing sources and preserves folding`, async ({ page }) => {
    const fixture = syntheticFixture({ files: 24, declarations: 2 });
    const initial = gate();
    const state = await installRenderingFixture(page, fixture, {
      sourceGate: () => initial.promise, sourceFailure: () => state.authenticated ? undefined : limited,
    });
    await installSignIn(page, state);
    await page.goto(route(fixture));
    await expect.poll(() => sources(state).length).toBe(4);
    initial.resolve();
    await expect(page.locator('.rate-limit')).toContainText(anonymousMessage);
    await expect(page.locator('.loading-inline')).toHaveCount(0);
    await expect(page.getByRole('button', { name: /Retry file|Try again/ })).toHaveCount(0);
    await toggle(page, 0);
    const y = await page.evaluate(() => scrollY);
    const validation = gate();
    if (kind === 'PR') state.metadataGate = validation;
    await page.locator('.rate-limit').getByRole('button', { name: 'Sign in with GitHub' }).evaluate(button => button.click());
    await expect(page.getByRole('button', { name: 'Account: reviewer' })).toBeAttached();
    if (kind === 'PR') {
      await expect(page.locator('.rate-limit')).toContainText(anonymousMessage);
      expect(sources(state)).toHaveLength(4);
      validation.resolve();
    }
    await expect(page.locator('.rate-limit')).toHaveCount(0);
    await expect(page.locator('.loading-inline')).toHaveCount(0);
    await expect.poll(() => sources(state).length).toBe(kind === 'PR' ? 52 : 44);
    await expect(card(page, 0)).toHaveClass('file-card');
    await expect(card(page, 23)).toHaveClass('file-card');
    expect(state.maxActiveSources).toBeLessThanOrEqual(4);
    expect(await page.evaluate(() => scrollY)).toBe(y);
    await page.locator('a.workspace-home').evaluate(link => link.click());
    await expect(page.locator('.file-card')).toHaveCount(0);
    await page.goBack();
    await expect(card(page, 0)).toHaveClass('file-card');
    await expect(page.locator('.loading-inline')).toHaveCount(0);
    expect(sources(state)).toHaveLength(kind === 'PR' ? 52 : 44);
  });
}

for (const outcome of ['cancel', 'failure']) {
  test(`anonymous limit remains paused after sign-in ${outcome}`, async ({ page }) => {
    const fixture = syntheticFixture({ files: 24, declarations: 1 });
    const initial = gate();
    const state = await installRenderingFixture(page, fixture, {
      sourceGate: () => initial.promise, sourceFailure: () => limited,
    });
    await installSignIn(page, state, outcome);
    await page.goto('/example/regions/pull/1');
    await expect.poll(() => sources(state).length).toBe(4); initial.resolve();
    const notice = page.locator('.rate-limit');
    await expect(notice).toContainText(anonymousMessage);
    await notice.getByRole('button', { name: 'Sign in with GitHub' }).click();
    if (outcome === 'cancel') {
      await notice.getByRole('button', { name: 'Cancel sign-in' }).click();
      await expect(notice.getByRole('button', { name: 'Sign in with GitHub' })).toBeVisible();
    } else {
      await expect(notice.getByRole('button', { name: 'Try sign-in' })).toBeVisible();
    }
    await toggle(page, 23);
    await visibilityCycle(page);
    await expect(page.locator('.loading-inline')).toHaveCount(0);
    expect(sources(state)).toHaveLength(4);
    await expect(notice).toContainText(anonymousMessage);
  });
}

test('late anonymous limit cannot re-pause login recovery or refetch successful sides', async ({ page }) => {
  const fixture = syntheticFixture({ files: 24, declarations: 2 });
  const pending = new Map();
  const initial = [];
  const state = await installRenderingFixture(page, fixture, {
    sourceGate: args => {
      if (state.authenticated) return;
      const key = `${args.ref}:${args.path}`, blocked = gate();
      pending.set(key, blocked); initial.push(key); return blocked.promise;
    },
    sourceFailure: args => {
      const key = `${args.ref}:${args.path}`;
      if ((key === initial[1] || key === initial[3]) && pending.delete(key)) return limited;
    },
  });
  await installSignIn(page, state);
  await page.goto('/example/regions/pull/1');
  await expect.poll(() => initial.length).toBe(4);
  const late = pending.get(initial[3]);
  pending.get(initial[1]).resolve();
  await expect(page.locator('.rate-limit')).toContainText(anonymousMessage);
  pending.get(initial[0]).resolve(); pending.get(initial[2]).resolve();
  await expect.poll(() => state.activeSources).toBe(1);
  await page.locator('.rate-limit').getByRole('button', { name: 'Sign in with GitHub' }).click();
  await expect(page.locator('.rate-limit')).toHaveCount(0);
  await expect.poll(() => sources(state).length).toBeGreaterThan(4);
  late.resolve();
  await expect(page.locator('.loading-inline')).toHaveCount(0);
  await expect.poll(() => state.activeSources).toBe(0);
  await expect.poll(() => sources(state).length).toBe(50);
  expect(state.maxActiveSources).toBeLessThanOrEqual(4);
  for (const key of [initial[0], initial[2]]) {
    expect(sources(state).filter(call => `${call.args.ref}:${call.args.path}` === key)).toHaveLength(1);
  }
  await expect(page.locator('.rate-limit')).toHaveCount(0);
  await expect(card(page, 23)).toHaveClass('file-card');
});

for (const validationFails of [false, true]) test(`login preserves a loaded reading position when validation ${validationFails ? 'fails' : 'succeeds'}`, async ({ page }) => {
  const fixture = syntheticFixture({ files: 24, declarations: 16 });
  const state = await installRenderingFixture(page, fixture, {
    sourceFailure: args => !state.authenticated && fixture.files.findIndex(file => file.filename === args.path) >= 4 ? limited : undefined,
  });
  await installSignIn(page, state);
  await page.goto('/example/regions/pull/1');
  await expect(page.locator('.rate-limit')).toContainText(anonymousMessage);
  await expect(page.locator('.loading-inline')).toHaveCount(0);
  const anchor = card(page, 1).locator('tr').nth(6);
  await anchor.evaluate(element => {
    window.scrollTo(0, scrollY + element.getBoundingClientRect().top - 180);
    window.rateLimitReadingNode = element;
  });
  await settleRegions(page);
  const before = await anchor.evaluate(element => element.getBoundingClientRect().top);
  const sourceCount = sources(state).length;
  if (validationFails) await page.route('**/api/rpc', async route => {
    if (route.request().postDataJSON().request.$tag === 'PullSnapshotGet') {
      return route.fulfill({ status: 503, json: { $tag: 'Failure', error: {
        status: 503, code: 'unavailable', message: 'Validation is unavailable',
      } } });
    }
    return route.fallback();
  });
  await page.locator('.rate-limit').getByRole('button', { name: 'Sign in with GitHub' }).evaluate(button => button.click());
  await expect(page.getByRole('button', { name: 'Account: reviewer' })).toBeAttached();
  if (validationFails) await expect(page.locator('.rate-limit')).toContainText(anonymousMessage);
  else await expect(page.locator('.rate-limit')).toHaveCount(0);
  await visibilityCycle(page);
  await expect.poll(() => sources(state).length).toBe(validationFails ? sourceCount : sourceCount + 40);
  await expect(page.locator('.loading-inline')).toHaveCount(0);
  expect(await anchor.evaluate(element => element === window.rateLimitReadingNode)).toBe(true);
  expect(Math.abs(await anchor.evaluate(element => element.getBoundingClientRect().top) - before)).toBeLessThan(2);
});
