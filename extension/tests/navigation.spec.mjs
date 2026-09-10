import { test, expect, chromium } from '../../playground/node_modules/@playwright/test/index.mjs';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { buildExtension, outputRoot } from '../scripts/build.mjs';

const origin = 'https://diff.example';
const github = 'https://github.com/acme/widgets';
const buttonOn = page => page.getByRole('button', { name: 'Open this change in Moondiff', exact: true });
const githubHTML = '<!doctype html><title>GitHub fixture</title><style>button { background: red !important; color: black !important; }</style><main>GitHub fixture</main>';

async function navigate(page, path) {
  await page.evaluate(path => {
    history.pushState(null, '', path);
    dispatchEvent(new Event('turbo:load'));
    dispatchEvent(new Event('pjax:end'));
    document.body.append(document.createElement('div'));
  }, path);
}

test('the black button opens current GitHub changes only on click and safely reuses tabs', async () => {
  buildExtension({ env: { MOONDIFF_PLAYGROUND_URL: origin }, log: { write() {} } });
  const profile = await mkdtemp(join(tmpdir(), 'moondiff-extension-'));
  let context;
  try {
    context = await chromium.launchPersistentContext(profile, {
      channel: 'chromium', headless: true,
      args: [`--disable-extensions-except=${outputRoot}`, `--load-extension=${outputRoot}`],
    });
    await context.route('https://github.com/**', route => route.fulfill({ contentType: 'text/html', body: githubHTML }));
    await context.route(`${origin}/**`, route => route.fulfill({ contentType: 'text/html', body: '<!doctype html><title>Playground fixture</title><textarea aria-label="Draft"></textarea>' }));
    const source = await context.newPage();
    const button = buttonOn(source);
    const targets = () => context.pages().filter(p => p.url().startsWith(origin));
    async function visit(path) {
      await source.bringToFront();
      const count = targets().length;
      await navigate(source, path);
      // Navigating must neither open a tab nor activate an existing destination.
      await source.waitForTimeout(150);
      expect(targets()).toHaveLength(count);
      expect(await source.evaluate(() => document.visibilityState)).toBe('visible');
    }
    async function open(path, count, key) {
      await source.bringToFront();
      if (key) await button.press(key);
      else await button.click();
      await expect(button).toBeEnabled();
      await expect.poll(() => targets().length).toBe(count);
      const destination = targets().find(p => p.url() === origin + path);
      await expect(destination).toHaveURL(origin + path);
      await expect.poll(() => destination.evaluate(() => document.visibilityState)).toBe('visible');
      return destination;
    }
    await source.goto(`${github}/pull/42/files`);
    await expect(button).toHaveText('Open in Moondiff');
    await expect(button).toHaveCSS('background-color', 'rgb(23, 23, 23)');
    await expect(button).toHaveCSS('color', 'rgb(255, 255, 255)');
    await expect(button).toHaveCSS('position', 'fixed');
    await expect(button).toHaveCSS('right', '20px');
    await expect(button).toHaveCSS('bottom', '20px');
    await expect(button).toHaveCSS('border-radius', '999px');
    await source.waitForTimeout(150);
    expect(targets()).toHaveLength(0);

    await source.evaluate(() => document.getElementById('moondiff-extension-root').remove());
    await expect(source.locator('#moondiff-extension-root')).toHaveCount(1);
    await expect(button).toBeVisible();
    expect(targets()).toHaveLength(0);
    await source.keyboard.press('Tab');
    await expect(button).toBeFocused();
    const first = await open('/acme/widgets/pull/42', 1, 'Enter');
    await first.getByLabel('Draft').fill('Do not overwrite this draft');
    for (const path of ['/acme/widgets/pull/42/commits?x=1#discussion_r1', '/Acme/Widgets/pull/42?x=2']) {
      await visit(path);
      expect(await open('/acme/widgets/pull/42', 1)).toBe(first);
    }
    await visit('/acme/widgets/pull/43');
    await open('/acme/widgets/pull/43', 2);
    await visit('/acme/widgets/pull/42/files');
    expect(await open('/acme/widgets/pull/42', 2)).toBe(first);
    await expect(first.getByLabel('Draft')).toHaveValue('Do not overwrite this draft');
    // Navigating a destination away must create a new tab, never replace it.
    await first.goto(`${origin}/acme/widgets/pull/99`); await first.getByLabel('Draft').fill('Different change');
    await visit('/acme/widgets');
    await expect(button).toHaveCount(0);
    await visit('/acme/widgets/pull/42');
    const replacement = await open('/acme/widgets/pull/42', 3);
    await expect(first).toHaveURL(`${origin}/acme/widgets/pull/99`);
    await expect(first.getByLabel('Draft')).toHaveValue('Different change');
    await replacement.close();
    await open('/acme/widgets/pull/42', 3);
    await visit('/acme/widgets/pull/42/changes/ABCDEF1');
    const pullCommit = await open('/acme/widgets/pull/42/commits/abcdef1', 4);
    await visit('/acme/widgets/pull/42/commits/abcdef1');
    expect(await open('/acme/widgets/pull/42/commits/abcdef1', 4, 'Space')).toBe(pullCommit);
    await visit('/acme/widgets/commit/ABCDEF2?diff=split#comment-1');
    await open('/acme/widgets/commit/abcdef2', 5);
    const otherSource = await context.newPage(); await otherSource.goto(`${github}/pull/42`);
    await expect(buttonOn(otherSource)).toBeVisible();
    await otherSource.waitForTimeout(150);
    expect(targets()).toHaveLength(5);
    await buttonOn(otherSource).click();
    await expect.poll(() => targets().length).toBe(6);
  } finally { await context?.close(); await rm(profile, { recursive: true, force: true }); }
});

// Use a real DOM and trusted browser input, replacing only the runtime boundary
// so worker failures and in-flight requests can be exercised deterministically.
async function loadContentScript(page, path) {
  await page.route('https://github.com/**', route => route.fulfill({ contentType: 'text/html', body: githubHTML }));
  await page.goto(github + path);
  await page.evaluate(() => {
    globalThis.openRequests = [];
    globalThis.chrome ??= {};
    globalThis.chrome.runtime = {
      sendMessage(message) {
        openRequests.push(message);
        return new Promise((resolve, reject) => {
          globalThis.completeOpen = resolve;
          globalThis.failOpen = reject;
        });
      },
    };
  });
  for (const script of ['target.js', 'content-script.js']) {
    await page.addScriptTag({ path: resolve(import.meta.dirname, '../src', script) });
  }
}

test('content script keeps one button through SPA transitions and redraws without sending open requests', async ({ page }) => {
  await loadContentScript(page, '');
  const button = buttonOn(page);
  await expect(button).toHaveCount(0);
  for (const path of ['/acme/widgets/pull/42', '/acme/widgets/pull/42/files', '/acme/widgets/pull/42/commits?x=1#comment', '/acme/widgets/commit/abcdef1']) {
    await navigate(page, path);
    await expect(button).toHaveCount(1);
    await expect(button).toBeVisible();
  }
  await page.evaluate(() => document.getElementById('moondiff-extension-root').remove());
  await expect(button).toHaveCount(1);
  await expect(button).toBeVisible();
  await page.evaluate(() => {
    history.replaceState(null, '', '/acme/widgets/issues/1');
    dispatchEvent(new PopStateEvent('popstate'));
  });
  await expect(button).toHaveCount(0);
  // A History API transition alone must also restore the button.
  await page.evaluate(() => history.pushState(null, '', '/acme/widgets/pull/43'));
  await expect(button).toBeVisible();
  await page.evaluate(() => { location.hash = '#discussion_r1'; });
  await expect(button).toHaveCount(1);
  expect(await page.evaluate(() => openRequests)).toEqual([]);
});

test('content script requires trusted clicks, blocks repeated pending opens and retries failures on the current route', async ({ page }) => {
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await loadContentScript(page, '/pull/42');
  const button = buttonOn(page);
  await button.evaluate(element => element.click());
  expect(await page.evaluate(() => openRequests)).toEqual([]);

  await button.click();
  await expect(button).toBeDisabled();
  await expect(button).toHaveAttribute('aria-busy', 'true');
  const bounds = await button.boundingBox();
  await page.mouse.click(bounds.x + bounds.width / 2, bounds.y + bounds.height / 2);
  expect(await page.evaluate(() => openRequests.length)).toBe(1);
  await page.evaluate(() => document.getElementById('moondiff-extension-root').remove());
  await expect(button).toHaveCount(1);
  await expect(button).toBeDisabled();

  await page.evaluate(() => failOpen(new Error('Worker unavailable')));
  await expect(button).toBeEnabled();
  await expect(button).not.toHaveAttribute('aria-busy');
  await button.press('Enter');
  await expect(button).toBeDisabled();
  await page.evaluate(() => completeOpen({ ok: false, error: { message: 'Cannot open tab' } }));
  await expect(button).toBeEnabled();

  await navigate(page, '/Acme/Widgets/pull/43/files?diff=split#comment');
  expect(await page.evaluate(() => openRequests.length)).toBe(2);
  await button.press('Space');
  expect(await page.evaluate(() => openRequests)).toEqual([
    { v: 1, op: 'playground.open', args: { route: '/acme/widgets/pull/42' } },
    { v: 1, op: 'playground.open', args: { route: '/acme/widgets/pull/42' } },
    { v: 1, op: 'playground.open', args: { route: '/acme/widgets/pull/43' } },
  ]);
  await page.evaluate(() => completeOpen({ ok: true, value: { tabId: 1, reused: false } }));
  await expect(button).toBeEnabled();
  await expect(button).not.toHaveAttribute('aria-busy');
  expect(errors).toEqual([]);
});
