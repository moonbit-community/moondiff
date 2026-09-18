import { fixtureRequest, successFixture } from '../../tests/protocol-fixtures.mjs';
import { e2eOrigin } from '../../tests/e2e-config.mjs';
import { expect, test } from '@playwright/test';
import { setTimeout as delay } from 'node:timers/promises';
const sha = 'abcdef1234567890abcdef1234567890abcdef12';
const route = `/fixture/repo/commit/${sha}`;

test.beforeEach(async ({ page }) => {
  await page.route('https://api.github.com/repos/fixture/repo/**', route => {
    const url = new URL(route.request().url());
    const headers = { 'Access-Control-Allow-Origin': '*' };
    if (url.pathname.endsWith('/comments')) return route.fulfill({ json: [], headers });
    if (url.pathname.includes('/contents/')) {
      return route.fulfill({ body: 'pub fn hello() { 42 }\n', contentType: 'text/plain', headers });
    }
    const revision = url.pathname.split('/').at(-1);
    return route.fulfill({ json: {
      sha: revision, html_url: `https://github.com/fixture/repo/commit/${revision}`,
      commit: { message: 'Fixture root commit' }, parents: [],
      stats: { additions: 1, deletions: 0, total: 1 },
      files: [{ filename: 'hello.mbt', status: 'added', additions: 1, deletions: 0,
        changes: 1, patch: '@@ -0,0 +1 @@\n+pub fn hello() { 42 }' }],
    }, headers });
  });
});

async function fixtureCommentRefresh(page) {
  let refreshed;
  const refresh = new Promise(resolve => { refreshed = resolve; });
  await page.route('**/api/rpc', async handler => {
    const { op } = fixtureRequest(handler.request().postDataJSON());
    if (op !== 'github.comments.list') return handler.fallback();
    await handler.fulfill({ json: successFixture(op, {
      issue_comments: [], review_comments: [], commit_comments: [],
    }) });
    refreshed();
  });
  return { refresh };
}

async function authorize(page, code) {
  const opened = page.waitForEvent('popup');
  await page.getByRole('button', { name: 'Open GitHub' }).click();
  const verification = await opened;
  await verification.getByRole('textbox', { name: 'Verification code' }).fill(code);
  await verification.getByRole('button', { name: 'Authorize device' }).click();
  await expect(verification.getByText('Device authorized. Return to Moondiff.')).toBeVisible();
  await verification.close();
}

test('real Wasm device login displays and copies the code, opens GitHub and completes automatically', async ({ page, context }) => {
  const external = [], publicRequests = [], backendReads = [], responses = [];
  const sessions = [];
  page.on('request', request => {
    if (new URL(request.url()).origin !== e2eOrigin) {
      external.push(request.url());
      publicRequests.push(request);
    }
  });
  page.on('response', async response => { if (response.url().includes('/api/auth/')) responses.push(await response.text().catch(() => '')); });
  page.on('request', request => { if (request.url().endsWith('/api/auth/session')) sessions.push(request); });
  page.on('request', request => {
    if (request.url().endsWith('/api/rpc') && request.postDataJSON()?.request?.$tag === 'CommitGet') backendReads.push(request);
  });
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.goto(route);
  await expect(page.getByText('Fixture root commit', { exact: true }).first()).toBeVisible();
  await expect(page.locator('table').first()).toContainText('hello');
  expect(sessions).toHaveLength(0);
  expect((await context.cookies()).some(c => c.name === 'moondiff')).toBe(false);
  await page.getByRole('button', { name: 'Sign in with GitHub' }).click();
  await expect(page.locator('.device-code')).toHaveText(/^[A-Z0-9]{4}-[A-Z0-9]{4}$/);
  expect(context.pages()).toHaveLength(1);
  const code = await page.locator('.device-code').textContent();
  await page.getByRole('button', { name: 'Copy code' }).click();
  await expect(page.getByRole('status')).toContainText('Code copied.');
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(code);
  await authorize(page, code);
  await expect(page.getByRole('button', { name: 'Account: alice', exact: true })).toBeVisible();
  expect((await context.cookies()).find(c => c.name === 'moondiff')).toMatchObject({ httpOnly: true, sameSite: 'Lax', path: '/' });
  expect(sessions).toHaveLength(1);
  expect(await page.evaluate(() => document.cookie)).not.toContain('moondiff=');
  expect(await page.evaluate(() => ({ ...localStorage }))).toEqual({});
  await page.reload(); await expect(page.getByRole('button', { name: 'Account: alice', exact: true })).toBeVisible();
  await expect.poll(() => backendReads.length).toBeGreaterThan(0);
  await page.getByRole('button', { name: 'Account: alice' }).click();
  await page.getByRole('menuitem', { name: 'Sign out' }).click();
  await expect(page.getByRole('button', { name: 'Sign in with GitHub' })).toBeVisible();
  const directBeforeLogoutReload = publicRequests.length;
  await page.reload();
  await expect(page.getByText('Fixture root commit', { exact: true }).first()).toBeVisible();
  await expect.poll(() => publicRequests.length).toBeGreaterThan(directBeforeLogoutReload);
  expect(external.length).toBeGreaterThan(0);
  expect(external.every(url => url.startsWith('https://api.github.com/repos/fixture/repo/'))).toBe(true);
  for (const request of publicRequests) {
    const headers = await request.allHeaders();
    expect(headers).not.toHaveProperty('cookie');
    expect(headers).not.toHaveProperty('authorization');
    expect(headers).not.toHaveProperty('x-github-api-version');
  }
  expect(responses.join('')).not.toMatch(/device_code|access_token|refresh_token|client_secret/);
});

for (const outcome of ['failure', 'cancel', 'success']) {
  test(`an in-flight public source finishes after sign-in ${outcome}`, async ({ page }) => {
    let release;
    const gate = new Promise(resolve => { release = resolve; });
    let started;
    const requested = new Promise(resolve => { started = resolve; });
    let sourceReads = 0;
    await page.route('https://api.github.com/repos/fixture/repo/contents/**', async handler => {
      sourceReads++;
      started();
      await gate;
      await handler.fulfill({ body: 'pub fn hello() { 42 }\n', contentType: 'text/plain',
        headers: { 'Access-Control-Allow-Origin': '*' } }).catch(() => {});
    });
    if (outcome === 'failure') {
      await page.route('**/api/auth/device/start', handler => handler.fulfill({ status: 403,
        json: { $tag: 'Failure', error: { status: 403, code: 'sign_in_denied', message: 'Sign-in denied.' } } }), { times: 1 });
    }
    try {
      await page.goto(route);
      await requested;
      await expect(page.locator('.file-card').first()).toContainText('Loading file contents');
      await page.getByRole('button', { name: 'Sign in with GitHub' }).click();
      if (outcome === 'failure') {
        await expect(page.getByRole('button', { name: 'Try sign-in' })).toBeVisible();
      } else {
        await expect(page.locator('.device-code')).toBeVisible();
        if (outcome === 'cancel') {
          await page.getByRole('button', { name: 'Cancel sign-in' }).click();
          await expect(page.getByRole('button', { name: 'Sign in with GitHub' })).toBeVisible();
        } else {
          await authorize(page, await page.locator('.device-code').textContent());
          await expect(page.getByRole('button', { name: 'Account: alice', exact: true })).toBeVisible();
        }
      }
    } finally {
      release();
    }
    await expect(page.locator('.file-card table').first()).toContainText('pub fn hello');
    await expect(page.locator('.file-card').first()).not.toContainText('Loading file contents');
    expect(sourceReads).toBe(1);
  });
}

test('reload and navigation retain a pending code; cancellation allows a fresh attempt', async ({ page }) => {
  await page.goto(route);
  await page.getByRole('button', { name: 'Sign in with GitHub' }).click();
  await expect(page.locator('.device-code')).toBeVisible();
  const code = await page.locator('.device-code').textContent();
  await page.reload(); await expect(page.locator('.device-code')).toHaveText(code);
  const next = '/fixture/repo/commit/1111111111111111111111111111111111111111';
  await page.evaluate(path => { history.pushState(null, '', path); dispatchEvent(new PopStateEvent('popstate')); }, next);
  await expect(page.locator('.device-code')).toHaveText(code);
  await page.getByRole('button', { name: 'Cancel sign-in' }).click();
  await expect(page.getByRole('button', { name: 'Sign in with GitHub' })).toBeVisible();
  await page.getByRole('button', { name: 'Sign in with GitHub' }).click();
  await expect(page.locator('.device-code')).toBeVisible();
  await expect(page.locator('.device-code')).not.toHaveText(code);
  await authorize(page, await page.locator('.device-code').textContent());
  await expect(page.getByRole('button', { name: 'Account: alice', exact: true })).toBeVisible();
  expect(new URL(page.url()).pathname).toBe(next);
});

test('cancel during startup ignores its delayed response after a new attempt begins', async ({ page }) => {
  let release; const gate = new Promise(r => { release = r; });
  let entered; const started = new Promise(r => { entered = r; });
  await page.route('**/api/auth/device/start', async handler => {
    const response = await handler.fetch(); entered(); await gate;
    await handler.fulfill({ response }).catch(() => {});
  }, { times: 1 });
  await page.goto(route);
  await page.getByRole('button', { name: 'Sign in with GitHub' }).click();
  await started;
  await expect(page.getByText('Starting GitHub sign-in…')).toBeVisible();
  await page.getByRole('button', { name: 'Cancel sign-in' }).click();
  await expect(page.getByRole('button', { name: 'Sign in with GitHub' })).toBeVisible();
  await page.getByRole('button', { name: 'Sign in with GitHub' }).click();
  await expect(page.locator('.device-code')).toBeVisible();
  const code = await page.locator('.device-code').textContent(); release();
  await expect(page.locator('.device-code')).toHaveText(code);
  await authorize(page, code); await expect(page.getByRole('button', { name: 'Account: alice', exact: true })).toBeVisible();
});

test('a delayed successful poll cannot replace a newer sign-in after cancellation', async ({ page }) => {
  let release; const gate = new Promise(r => { release = r; });
  let entered; const polling = new Promise(r => { entered = r; });
  await page.route('**/api/auth/device/poll', async handler => {
    const { authorization_id } = handler.request().postDataJSON(); entered(); await gate;
    await handler.fulfill({ json: successFixture('auth.device.poll', { csrf_token: 'fixture', authenticated: true, user_id: 'stale-user', login: 'stale-user', authorization_id, device_flow: { id: authorization_id, phase: 'completed', user_code: '', verification_uri: '', expires_at: 0, retry_after: 0, message: '' } }) }).catch(() => {});
  }, { times: 1 });
  await page.goto(route);
  await page.getByRole('button', { name: 'Sign in with GitHub' }).click(); await polling;
  await page.getByRole('button', { name: 'Cancel sign-in' }).click();
  await page.getByRole('button', { name: 'Sign in with GitHub' }).click();
  await expect(page.locator('.device-code')).toBeVisible(); const code = await page.locator('.device-code').textContent();
  release(); await expect(page.locator('.device-code')).toHaveText(code);
  await expect(page.getByRole('button', { name: 'Account: stale-user', exact: true })).toHaveCount(0);
  await authorize(page, code); await expect(page.getByRole('button', { name: 'Account: alice', exact: true })).toBeVisible();
});

test('initial session resolution precedes change loading even when navigating during startup', async ({ page }) => {
  let release; const gate = new Promise(r => { release = r; });
  const calls = [];
  await page.route('**/api/auth/status', async handler => { await gate; await handler.continue(); });
  page.on('request', request => {
    const url = request.url();
    if (url.startsWith('https://api.github.com/repos/fixture/repo/commits/') && !url.includes('/comments')) calls.push(new URL(url).pathname.split('/').at(-1));
  });
  await page.goto(route);
  await page.waitForFunction(() => document.querySelector('input'));
  const nextSha = '1111111111111111111111111111111111111111';
  await page.evaluate(path => { history.pushState(null, '', path); dispatchEvent(new PopStateEvent('popstate')); dispatchEvent(new Event('focus')); }, `/fixture/repo/commit/${nextSha}`);
  await page.waitForTimeout(100); expect(calls).toEqual([]); release();
  await expect(page.getByText('Fixture root commit', { exact: true }).first()).toBeVisible();
  expect(calls.length).toBeGreaterThan(0);
  expect(calls.every(sha => sha === nextSha)).toBe(true);
});

test('legacy hash links display an invalid-link error without loading a change', async ({ page }) => {
  const calls = [];
  page.on('request', request => { if (request.url().startsWith('https://api.github.com/')) calls.push(request.url()); });
  await page.goto('/#' + route);
  await expect(page.locator('.error')).toBeVisible();
  expect(calls).toEqual([]); expect(new URL(page.url()).hash).toBe('#' + route);
});

test('a page restored during startup resumes the server code after unloading its request', async ({ page }) => {
  let release; const gate = new Promise(r => { release = r; });
  let entered; const started = new Promise(r => { entered = r; });
  await page.route('**/api/auth/device/start', async handler => {
    const response = await handler.fetch(); entered(); await gate;
    await handler.fulfill({ response }).catch(() => {});
  }, { times: 1 });
  await page.goto(route);
  await page.getByRole('button', { name: 'Sign in with GitHub' }).click(); await started;
  await page.evaluate(() => {
    dispatchEvent(new PageTransitionEvent('pagehide', { persisted: true }));
    dispatchEvent(new PageTransitionEvent('pageshow', { persisted: true }));
    dispatchEvent(new Event('focus'));
  });
  await expect(page.locator('.device-code')).toBeVisible(); release();
  const code = await page.locator('.device-code').textContent();
  await authorize(page, code); await expect(page.getByRole('button', { name: 'Account: alice', exact: true })).toBeVisible();
});

// Install and pause before navigation: real response/actionability waits must
// never consume the application's retry budget. The install time precedes the
// fixed pause time so pauseAt cannot race a moving wall clock.
async function installAuthClock(page) {
  await page.clock.install({ time: new Date('2026-08-18T00:00:00Z') });
  await page.clock.pauseAt(new Date('2026-08-18T01:00:00Z'));
  await page.addInitScript(() => {
    const randomUUID = crypto.randomUUID.bind(crypto);
    window.__attempts = [];
    crypto.randomUUID = () => { const id = randomUUID(); window.__attempts.push(id); return id; };
    const timeout = window.setTimeout.bind(window);
    window.__authTimers = [];
    window.setTimeout = (callback, ms, ...args) => {
      if ([5_000, 10_000, 20_000].includes(ms)) window.__authTimers.push({ ms, at: Date.now() });
      return timeout(callback, ms, ...args);
    };
  });
}

async function fulfillAuth(page, handler, response, responseDelay) {
  if (responseDelay) {
    const before = await page.evaluate(() => Date.now());
    await delay(responseDelay);
    expect(await page.evaluate(() => Date.now()), 'real response latency must not advance virtual time').toBe(before);
  }
  await handler.fulfill(response);
}

function authResponse(page, endpoint) {
  return page.waitForResponse(response => new URL(response.url()).pathname === `/api/auth/${endpoint}`);
}

async function renderAuthResponse(page, pending, locator, timerCount) {
  const response = await pending;
  expect(await response.finished(), `response body for ${response.url()}`).toBeNull();
  // Body completion precedes the central and regional paints. Advance only a
  // small bounded budget, well below the shortest (5 second) auth timer.
  for (let frames = 0; frames < 60; frames++) {
    await page.clock.runFor(16);
    if (await locator.isVisible() && await page.evaluate(count => window.__authTimers.length === count, timerCount)) return;
  }
  const diagnostic = await page.evaluate(() => ({ now: Date.now(), timers: window.__authTimers, text: document.body.innerText.slice(0, 2_000) }));
  throw new Error(`Auth did not render ${locator} after ${response.url()} within 60 frames (960ms): ${JSON.stringify(diagnostic)}`);
}

async function beforeAuthDeadline(page, index, ms) {
  const { timer, now } = await page.evaluate(index => ({ timer: window.__authTimers[index], now: Date.now() }), index);
  expect(timer, `auth timer ${index}`).toMatchObject({ ms });
  // Account for every frame already consumed while waiting for the UI.
  const remaining = timer.at + ms - now;
  expect(remaining, `time left before ${ms}ms auth deadline`).toBeGreaterThan(1);
  await page.clock.runFor(remaining - 1);
  expect(await page.evaluate(() => Date.now())).toBe(timer.at + ms - 1);
}

for (const responseDelay of [0, 250]) {
  const latency = responseDelay ? ` (${responseDelay}ms responses)` : '';

  test(`proxy failures during session start and polling back off and recover on one login attempt${latency}`, async ({ page }) => {
    let sessions = 0;
    const starts = [], polls = [];
    const canonical = 'canonical-proxy-recovery-0001';
    const device = { id: canonical, phase: 'pending', user_code: 'ABCD-EFGH', verification_uri: 'https://github.com/login/device', expires_at: 2000000000, retry_after: 5, message: '' };
    await installAuthClock(page);
    const { refresh: commentsRefreshed } = await fixtureCommentRefresh(page);
    await page.route('**/api/auth/status', handler => {
      sessions += 1;
      const response = sessions === 2
        ? { status: 503, contentType: 'text/html', body: '<html><body>Proxy unavailable</body></html>' }
        : { json: successFixture('auth.status', {
          authenticated: false,
          csrf_token: `session-csrf-${sessions}`,
          ...(sessions >= 4 ? { device_flow: device } : {}),
        }) };
      return fulfillAuth(page, handler, response, responseDelay);
    });
    await page.route('**/api/auth/device/start', handler => {
      const { attempt_id } = handler.request().postDataJSON();
      starts.push({ attempt_id, csrf: handler.request().headers()['x-csrf-token'] });
      return fulfillAuth(page, handler, starts.length === 1
        ? { status: 502, body: '' }
        : { json: successFixture('auth.device.start', { authenticated: false, csrf_token: 'poll-csrf', attempt_id, device_flow: device }) }, responseDelay);
    });
    await page.route('**/api/auth/device/poll', handler => {
      const { authorization_id } = handler.request().postDataJSON();
      polls.push({ authorization_id, csrf: handler.request().headers()['x-csrf-token'] });
      return fulfillAuth(page, handler, polls.length === 1
        ? { status: 504, contentType: 'application/json', body: '{invalid json' }
        : { json: successFixture('auth.device.poll', { authenticated: true, csrf_token: 'signed-in-csrf', user_id: 'alice', login: 'alice', authorization_id, device_flow: { ...device, phase: 'completed' } }) }, responseDelay);
    });
    let response = authResponse(page, 'status');
    await page.goto(route);
    const signIn = page.getByRole('button', { name: 'Sign in with GitHub' });
    await renderAuthResponse(page, response, signIn, 0);
    response = authResponse(page, 'status');
    await signIn.click();
    const retryMessage = page.getByText('Connection interrupted. Sign-in will retry automatically.');
    await renderAuthResponse(page, response, retryMessage, 1);
    expect(sessions).toBe(2);
    expect(starts).toEqual([]);
    await expect(page.getByText('Proxy unavailable')).toHaveCount(0);

    await beforeAuthDeadline(page, 0, 10_000);
    expect(sessions).toBe(2);
    expect(starts).toEqual([]);
    response = authResponse(page, 'device/start');
    await page.clock.runFor(1);
    await renderAuthResponse(page, response, retryMessage, 2);
    expect(sessions).toBe(3);
    expect(starts).toHaveLength(1);
    await beforeAuthDeadline(page, 1, 20_000);
    expect(sessions).toBe(3);
    expect(starts).toHaveLength(1);
    response = authResponse(page, 'device/start');
    await page.clock.runFor(1);
    await renderAuthResponse(page, response, page.locator('.device-code'), 3);
    await expect(page.locator('.device-code')).toHaveText('ABCD-EFGH');
    expect(sessions).toBe(4);
    const attempts = await page.evaluate(() => window.__attempts);
    expect(attempts).toHaveLength(1);
    expect(starts).toEqual([
      { attempt_id: attempts[0], csrf: 'session-csrf-3' },
      { attempt_id: attempts[0], csrf: 'session-csrf-4' },
    ]);
    expect(attempts[0]).not.toBe(canonical);

    await beforeAuthDeadline(page, 2, 5_000);
    expect(polls).toEqual([]);
    response = authResponse(page, 'device/poll');
    await page.clock.runFor(1);
    await renderAuthResponse(page, response, retryMessage, 4);
    expect(polls).toHaveLength(1);
    await beforeAuthDeadline(page, 3, 10_000);
    expect(polls).toHaveLength(1);
    response = authResponse(page, 'device/poll');
    await page.clock.runFor(1);
    const account = page.getByRole('button', { name: 'Account: alice', exact: true });
    await renderAuthResponse(page, response, account, 4);
    await commentsRefreshed;
    await expect(account).toBeVisible();
    expect(polls).toEqual([
      { authorization_id: canonical, csrf: 'poll-csrf' },
      { authorization_id: canonical, csrf: 'poll-csrf' },
    ]);
    expect(sessions).toBe(4);
    expect(starts).toHaveLength(2);
    expect(await page.evaluate(() => window.__attempts)).toEqual(attempts);
  });

  test(`session failures back off on one login attempt and recover with fresh CSRF and canonical polling${latency}`, async ({ page }) => {
    let sessions = 0;
    const starts = [], polls = [];
    const canonical = 'canonical-authorization-0001';
    const device = { id: canonical, phase: 'pending', user_code: 'ABCD-EFGH', verification_uri: 'https://github.com/login/device', expires_at: 2000000000, retry_after: 5, message: '' };
    await installAuthClock(page);
    const { refresh: commentsRefreshed } = await fixtureCommentRefresh(page);
    await page.route('**/api/auth/status', handler => {
      sessions += 1;
      return fulfillAuth(page, handler, { status: sessions <= 3 ? 503 : 200, json: sessions <= 3
        ? { $tag: 'Failure', error: { status: 503, code: 'unavailable', message: 'Session temporarily unavailable' } }
        : successFixture('auth.status', { authenticated: false, csrf_token: 'fresh-retry-csrf' }) }, responseDelay);
    });
    await page.route('**/api/auth/device/start', handler => {
      const { attempt_id } = handler.request().postDataJSON();
      starts.push({ attempt_id, csrf: handler.request().headers()['x-csrf-token'] });
      return fulfillAuth(page, handler, { json: successFixture('auth.device.start', { authenticated: false, csrf_token: 'fresh-retry-csrf', attempt_id, device_flow: device }) }, responseDelay);
    });
    await page.route('**/api/auth/device/poll', handler => {
      const { authorization_id } = handler.request().postDataJSON();
      polls.push({ authorization_id, csrf: handler.request().headers()['x-csrf-token'] });
      return fulfillAuth(page, handler, { json: successFixture('auth.device.poll', { authenticated: true, csrf_token: 'fresh-retry-csrf', user_id: 'alice', login: 'alice', authorization_id, device_flow: { ...device, phase: 'completed' } }) }, responseDelay);
    });
    let response = authResponse(page, 'status');
    await page.goto(route);
    const signIn = page.getByRole('button', { name: 'Try sign-in' });
    await renderAuthResponse(page, response, signIn, 0);
    response = authResponse(page, 'status');
    await signIn.click();
    const retryMessage = page.getByText('Connection interrupted. Sign-in will retry automatically.');
    await renderAuthResponse(page, response, retryMessage, 1);
    expect(sessions).toBe(2);
    expect(starts).toEqual([]);
    await beforeAuthDeadline(page, 0, 10_000);
    expect(sessions).toBe(2);
    response = authResponse(page, 'status');
    await page.clock.runFor(1);
    await renderAuthResponse(page, response, retryMessage, 2);
    expect(sessions).toBe(3);
    expect(starts).toEqual([]);
    await beforeAuthDeadline(page, 1, 20_000);
    expect(sessions).toBe(3);
    expect(starts).toEqual([]);
    response = authResponse(page, 'device/start');
    await page.clock.runFor(1);
    await renderAuthResponse(page, response, page.locator('.device-code'), 3);
    await expect(page.locator('.device-code')).toHaveText('ABCD-EFGH');
    expect(sessions).toBe(4);
    const attempts = await page.evaluate(() => window.__attempts);
    expect(attempts).toHaveLength(1);
    expect(attempts[0]).not.toBe(canonical);
    expect(starts).toEqual([{ attempt_id: attempts[0], csrf: 'fresh-retry-csrf' }]);
    await beforeAuthDeadline(page, 2, 5_000);
    expect(polls).toEqual([]);
    response = authResponse(page, 'device/poll');
    await page.clock.runFor(1);
    const account = page.getByRole('button', { name: 'Account: alice', exact: true });
    await renderAuthResponse(page, response, account, 3);
    await commentsRefreshed;
    await expect(account).toBeVisible();
    expect(polls).toEqual([{ authorization_id: canonical, csrf: 'fresh-retry-csrf' }]);
    expect(sessions).toBe(4);
    expect(starts).toHaveLength(1);
    expect(await page.evaluate(() => window.__attempts)).toEqual(attempts);
  });
}
