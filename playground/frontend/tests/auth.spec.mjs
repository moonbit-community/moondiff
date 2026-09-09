import { successFixture } from '../../tests/protocol-fixtures.mjs';
import { expect, test } from '@playwright/test';
const sha = 'abcdef1234567890abcdef1234567890abcdef12';
const route = `/fixture/repo/commit/${sha}`;

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
  const external = [], responses = [];
  page.on('request', request => { if (!request.url().startsWith('http://127.0.0.1:4173/')) external.push(request.url()); });
  page.on('response', async response => { if (response.url().includes('/api/auth/')) responses.push(await response.text().catch(() => '')); });
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.goto(route);
  await expect(page.getByText('Fixture root commit', { exact: true }).first()).toBeVisible();
  await expect(page.locator('table').first()).toContainText('hello');
  await page.getByRole('button', { name: 'Sign in with GitHub' }).click();
  await expect(page.locator('.device-code')).toHaveText(/^[A-Z0-9]{4}-[A-Z0-9]{4}$/);
  expect(context.pages()).toHaveLength(1);
  const code = await page.locator('.device-code').textContent();
  await page.getByRole('button', { name: 'Copy code' }).click();
  await expect(page.getByRole('status')).toContainText('Code copied.');
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(code);
  await authorize(page, code);
  await expect(page.getByText('Signed in as alice')).toBeVisible();
  expect((await context.cookies()).find(c => c.name === 'moondiff')).toMatchObject({ httpOnly: true, sameSite: 'Lax', path: '/' });
  expect(await page.evaluate(() => document.cookie)).not.toContain('moondiff=');
  expect(await page.evaluate(() => ({ ...localStorage }))).toEqual({});
  await page.reload(); await expect(page.getByText('Signed in as alice')).toBeVisible();
  await page.getByRole('button', { name: 'Sign out' }).click();
  await expect(page.getByRole('button', { name: 'Sign in with GitHub' })).toBeVisible();
  expect(external).toEqual([]);
  expect(responses.join('')).not.toMatch(/device_code|access_token|refresh_token|client_secret/);
});

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
  await expect(page.getByText('Signed in as alice')).toBeVisible();
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
  await authorize(page, code); await expect(page.getByText('Signed in as alice')).toBeVisible();
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
  await expect(page.getByText('Signed in as stale-user')).toHaveCount(0);
  await authorize(page, code); await expect(page.getByText('Signed in as alice')).toBeVisible();
});

test('initial session resolution precedes change loading even when navigating during startup', async ({ page }) => {
  let release; const gate = new Promise(r => { release = r; });
  const calls = [];
  await page.route('**/api/auth/status', async handler => { await gate; await handler.continue(); });
  page.on('request', request => { if (request.url().endsWith('/api/rpc')) calls.push(request.postDataJSON()); });
  await page.goto(route);
  await page.waitForFunction(() => document.querySelector('input'));
  const nextSha = '1111111111111111111111111111111111111111';
  await page.evaluate(path => { history.pushState(null, '', path); dispatchEvent(new PopStateEvent('popstate')); dispatchEvent(new Event('focus')); }, `/fixture/repo/commit/${nextSha}`);
  await page.waitForTimeout(100); expect(calls).toEqual([]); release();
  await expect(page.getByText('Fixture root commit', { exact: true }).first()).toBeVisible();
  expect(calls.length).toBeGreaterThan(0);
  expect(calls.every(c => !c.request['0'].sha || c.request['0'].sha === nextSha)).toBe(true);
});

test('legacy hash links display an invalid-link error without loading a change', async ({ page }) => {
  const calls = [];
  page.on('request', request => { if (request.url().endsWith('/api/rpc')) calls.push(request.postDataJSON()); });
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
  await authorize(page, code); await expect(page.getByText('Signed in as alice')).toBeVisible();
});

test('proxy failures during session start and polling back off and recover on one login attempt', async ({ page }) => {
  let sessions = 0;
  const starts = [], polls = [];
  const canonical = 'canonical-proxy-recovery-0001';
  const device = { id: canonical, phase: 'pending', user_code: 'ABCD-EFGH', verification_uri: 'https://github.com/login/device', expires_at: 2000000000, retry_after: 5, message: '' };
  await page.addInitScript(() => {
    const randomUUID = crypto.randomUUID.bind(crypto);
    window.__attempts = [];
    crypto.randomUUID = () => { const id = randomUUID(); window.__attempts.push(id); return id; };
  });
  await page.route('**/api/auth/status', handler => {
    sessions += 1;
    if (sessions === 2) return handler.fulfill({ status: 503, contentType: 'text/html', body: '<html><body>Proxy unavailable</body></html>' });
    return handler.fulfill({ json: successFixture('auth.status', {
      authenticated: false,
      csrf_token: `session-csrf-${sessions}`,
      ...(sessions >= 4 ? { device_flow: device } : {}),
    }) });
  });
  await page.route('**/api/auth/device/start', handler => {
    const { attempt_id } = handler.request().postDataJSON();
    starts.push({ attempt_id, csrf: handler.request().headers()['x-csrf-token'] });
    if (starts.length === 1) return handler.fulfill({ status: 502, body: '' });
    return handler.fulfill({ json: successFixture('auth.device.start', { authenticated: false, csrf_token: 'poll-csrf', attempt_id, device_flow: device }) });
  });
  await page.route('**/api/auth/device/poll', handler => {
    const { authorization_id } = handler.request().postDataJSON();
    polls.push({ authorization_id, csrf: handler.request().headers()['x-csrf-token'] });
    if (polls.length === 1) return handler.fulfill({ status: 504, contentType: 'application/json', body: '{invalid json' });
    return handler.fulfill({ json: successFixture('auth.device.poll', { authenticated: true, csrf_token: 'signed-in-csrf', user_id: 'alice', login: 'alice', authorization_id, device_flow: { ...device, phase: 'completed' } }) });
  });
  await page.clock.install();
  await page.goto(route);
  await page.getByRole('button', { name: 'Sign in with GitHub' }).click();
  const retryMessage = page.getByText('Connection interrupted. Sign-in will retry automatically.');
  await expect(retryMessage).toBeVisible();
  expect(sessions).toBe(2);
  expect(starts).toEqual([]);
  await expect(page.getByText('Proxy unavailable')).toHaveCount(0);

  await page.clock.pauseAt(new Date());
  await page.clock.fastForward(9_000);
  expect(sessions).toBe(2);
  await page.clock.fastForward(1_000);
  await expect.poll(() => starts.length).toBe(1);
  await page.clock.runFor(50);
  await expect(retryMessage).toBeVisible();
  expect(sessions).toBe(3);
  await page.clock.fastForward(19_000);
  expect(sessions).toBe(3);
  expect(starts).toHaveLength(1);
  await page.clock.fastForward(1_000);
  await expect.poll(() => starts.length).toBe(2);
  await page.clock.runFor(50);
  await expect(page.locator('.device-code')).toHaveText('ABCD-EFGH');
  expect(sessions).toBe(4);
  const attempts = await page.evaluate(() => window.__attempts);
  expect(attempts).toHaveLength(1);
  expect(starts).toEqual([
    { attempt_id: attempts[0], csrf: 'session-csrf-3' },
    { attempt_id: attempts[0], csrf: 'session-csrf-4' },
  ]);
  expect(attempts[0]).not.toBe(canonical);

  await page.clock.fastForward(4_000);
  expect(polls).toEqual([]);
  await page.clock.fastForward(1_000);
  await expect.poll(() => polls.length).toBe(1);
  await page.clock.runFor(50);
  await expect(retryMessage).toBeVisible();
  await page.clock.fastForward(9_000);
  expect(polls).toHaveLength(1);
  await page.clock.fastForward(1_000);
  await expect.poll(() => polls.length).toBe(2);
  await page.clock.runFor(50);
  await expect(page.getByText('Signed in as alice')).toBeVisible();
  expect(polls).toEqual([
    { authorization_id: canonical, csrf: 'poll-csrf' },
    { authorization_id: canonical, csrf: 'poll-csrf' },
  ]);
  expect(sessions).toBe(4);
  expect(starts).toHaveLength(2);
  expect(await page.evaluate(() => window.__attempts)).toEqual(attempts);
});

test('session failures back off on one login attempt and recover with fresh CSRF and canonical polling', async ({ page }) => {
  let sessions = 0;
  const starts = [], polls = [];
  const canonical = 'canonical-authorization-0001';
  const device = { id: canonical, phase: 'pending', user_code: 'ABCD-EFGH', verification_uri: 'https://github.com/login/device', expires_at: 2000000000, retry_after: 5, message: '' };
  await page.addInitScript(() => {
    const randomUUID = crypto.randomUUID.bind(crypto);
    window.__attempts = [];
    crypto.randomUUID = () => { const id = randomUUID(); window.__attempts.push(id); return id; };
  });
  await page.route('**/api/auth/status', handler => {
    sessions += 1;
    return handler.fulfill({ status: sessions <= 3 ? 503 : 200, json: sessions <= 3
      ? { $tag: 'Failure', error: { status: 503, code: 'unavailable', message: 'Session temporarily unavailable' } }
      : successFixture('auth.status', { authenticated: false, csrf_token: 'fresh-retry-csrf' }) });
  });
  await page.route('**/api/auth/device/start', handler => {
    const { attempt_id } = handler.request().postDataJSON();
    starts.push({ attempt_id, csrf: handler.request().headers()['x-csrf-token'] });
    return handler.fulfill({ json: successFixture('auth.device.start', { authenticated: false, csrf_token: 'fresh-retry-csrf', attempt_id, device_flow: device }) });
  });
  await page.route('**/api/auth/device/poll', handler => {
    const { authorization_id } = handler.request().postDataJSON(); polls.push(authorization_id);
    return handler.fulfill({ json: successFixture('auth.device.poll', { authenticated: true, csrf_token: 'fresh-retry-csrf', user_id: 'alice', login: 'alice', authorization_id, device_flow: { ...device, phase: 'completed' } }) });
  });
  await page.clock.install();
  await page.goto(route);
  await page.getByRole('button', { name: 'Try sign-in' }).click();
  await expect(page.getByText('Connection interrupted. Sign-in will retry automatically.')).toBeVisible();
  expect(sessions).toBe(2);
  await page.clock.pauseAt(new Date());
  await page.clock.fastForward(9_000);
  expect(sessions).toBe(2);
  await page.clock.fastForward(1_000);
  await expect.poll(() => sessions).toBe(3);
  await page.clock.runFor(50);
  await page.clock.fastForward(19_000);
  expect(sessions).toBe(3);
  await page.clock.fastForward(1_000);
  await expect.poll(() => starts.length).toBe(1);
  await page.clock.runFor(50);
  await expect(page.locator('.device-code')).toHaveText('ABCD-EFGH');
  expect(sessions).toBe(4);
  const attempts = await page.evaluate(() => window.__attempts);
  expect(attempts).toHaveLength(1);
  expect(starts).toEqual([{ attempt_id: attempts[0], csrf: 'fresh-retry-csrf' }]);
  await page.clock.fastForward(5_000);
  await expect.poll(() => polls.length).toBe(1);
  await page.clock.runFor(50);
  await expect(page.getByText('Signed in as alice')).toBeVisible();
  expect(polls).toEqual([canonical]);
});
