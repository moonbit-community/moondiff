import { test, expect } from '../../tests/browser-test.mjs';
import { successFixture } from '../../tests/protocol-fixtures.mjs';
import { gate, installRenderingFixture, syntheticFixture } from './rendering-fixture.mjs';

const sources = state => state.calls.filter(call => call.op === 'github.content.get');
const limited = { status: 429, code: 'rate_limit', detail: 'Rate limited' };

async function signIn(page, state) {
  await page.route('**/api/auth/device/start', route => {
    const id = route.request().postDataJSON().attempt_id;
    state.authenticated = true;
    return route.fulfill({ json: successFixture('auth.device.start', {
      attempt_id: id, authenticated: true, login: 'reviewer', user_id: '1', csrf_token: 'fixture',
      device_flow: { id, phase: 'completed', user_code: '', verification_uri: '',
        expires_at: 2_000_000_000, retry_after: 5, message: '' },
    }) });
  });
  await page.locator('.rate-limit').getByRole('button', { name: 'Sign in with GitHub' }).click();
}

for (const kind of ['PR', 'Commit']) {
  test(`${kind} initial metadata limit can sign in and restart source loading`, async ({ page }) => {
    const fixture = syntheticFixture({ files: 2, declarations: 2 });
    const state = await installRenderingFixture(page, fixture);
    await page.route(`https://api.github.com/repos/example/regions/${kind === 'PR' ? 'pulls/1' : `commits/${fixture.sha}`}*`, route => {
      return route.fulfill({ status: 429, json: { message: 'Rate limited' }, headers: { 'Access-Control-Allow-Origin': '*' } });
    });
    await page.goto(kind === 'PR' ? '/example/regions/pull/1' : `/example/regions/commit/${fixture.sha}`);
    await expect(page.locator('.rate-limit')).toContainText('Sign in to continue.');
    await expect(page.getByRole('button', { name: 'Try again' })).toHaveCount(0);
    await signIn(page, state);
    await expect(page.locator('.rate-limit')).toHaveCount(0);
    await expect(page.locator('.file-card')).toHaveCount(2);
    await expect(page.locator('.loading-inline')).toHaveCount(0);
    await expect.poll(() => sources(state).length).toBe(4);
  });
}

test('a paused PR restored from history resumes after login without expanding collapsed files', async ({ page }) => {
  const fixture = syntheticFixture({ files: 24, declarations: 2 });
  const initial = gate();
  const state = await installRenderingFixture(page, fixture, {
    sourceGate: () => initial.promise,
    sourceFailure: () => state.authenticated ? undefined : limited,
  });
  await page.goto('/example/regions/pull/1');
  await expect.poll(() => sources(state).length).toBe(4); initial.resolve();
  await expect(page.locator('.rate-limit')).toContainText('Sign in to continue.');
  await expect(page.locator('.loading-inline')).toHaveCount(0);
  await page.locator('#moondiff-file-0 .file-toggle').evaluate(button => button.click());
  await page.locator('a.workspace-home').evaluate(link => link.click());
  await expect(page.locator('.file-card')).toHaveCount(0);
  await page.goBack();
  await expect(page.locator('.file-message.paused')).toHaveCount(19);
  expect(sources(state)).toHaveLength(4);
  await signIn(page, state);
  await expect(page.locator('.rate-limit')).toHaveCount(0);
  await expect(page.locator('.loading-inline')).toHaveCount(0);
  await expect.poll(() => sources(state).length).toBe(52);
  await expect(page.locator('#moondiff-file-0')).toHaveClass('file-card');
  expect(state.maxActiveSources).toBeLessThanOrEqual(4);
});
