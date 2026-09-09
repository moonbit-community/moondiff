import { test, expect, chromium } from '../../playground/node_modules/@playwright/test/index.mjs';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { buildExtension, outputRoot } from '../scripts/build.mjs';

const origin = 'https://diff.example';
const github = 'https://github.com/acme/widgets';
test('GitHub first load and SPA aliases open safely, preserving drafts across different changes', async () => {
  buildExtension({ env: { MOONDIFF_PLAYGROUND_URL: origin }, log: { write() {} } });
  const profile = await mkdtemp(join(tmpdir(), 'moondiff-extension-'));
  const context = await chromium.launchPersistentContext(profile, {
    channel: 'chromium', headless: true,
    args: [`--disable-extensions-except=${outputRoot}`, `--load-extension=${outputRoot}`],
  });
  try {
    await context.route('https://github.com/**', route => route.fulfill({ contentType: 'text/html', body: '<!doctype html><title>GitHub fixture</title><main>GitHub fixture</main>' }));
    await context.route(`${origin}/**`, route => route.fulfill({ contentType: 'text/html', body: '<!doctype html><title>Playground fixture</title><textarea aria-label="Draft"></textarea>' }));
    const source = await context.newPage();
    const targets = () => context.pages().filter(p => p.url().startsWith(origin));
    async function navigate(path) {
      await source.evaluate(path => { history.pushState(null, '', path); dispatchEvent(new Event('turbo:load')); dispatchEvent(new Event('pjax:end')); document.body.append(document.createElement('div')); }, path);
    }
    await source.goto(`${github}/pull/42/files`);
    await expect.poll(() => targets().length).toBe(1);
    const first = targets()[0]; await expect(first).toHaveURL(`${origin}/acme/widgets/pull/42`);
    await first.getByLabel('Draft').fill('Do not overwrite this draft');
    await navigate('/acme/widgets/pull/42/commits?x=1#discussion_r1');
    await navigate('/acme/widgets/pull/42?x=2');
    await source.waitForTimeout(150); expect(targets()).toHaveLength(1);
    await navigate('/acme/widgets/pull/43'); await expect.poll(() => targets().length).toBe(2);
    await navigate('/acme/widgets/pull/42/files');
    await expect.poll(() => first.evaluate(() => document.visibilityState)).toBe('visible');
    expect(targets()).toHaveLength(2); await expect(first.getByLabel('Draft')).toHaveValue('Do not overwrite this draft');
    // Navigating a destination away must create a new tab, never replace it.
    await first.goto(`${origin}/acme/widgets/pull/99`); await first.getByLabel('Draft').fill('Different change');
    await navigate('/acme/widgets'); await navigate('/acme/widgets/pull/42');
    await expect.poll(() => targets().length).toBe(3);
    await expect(first).toHaveURL(`${origin}/acme/widgets/pull/99`);
    await expect(first.getByLabel('Draft')).toHaveValue('Different change');
    const replacement = targets().find(p => p.url() === `${origin}/acme/widgets/pull/42`);
    await replacement.close(); await navigate('/acme/widgets'); await navigate('/acme/widgets/pull/42');
    await expect.poll(() => targets().length).toBe(3);
    await navigate('/acme/widgets/pull/42/changes/ABCDEF1');
    await expect.poll(() => targets().length).toBe(4);
    await navigate('/acme/widgets/pull/42/commits/abcdef1'); await source.waitForTimeout(100);
    expect(targets()).toHaveLength(4);
    const otherSource = await context.newPage(); await otherSource.goto(`${github}/pull/42`);
    await expect.poll(() => targets().length).toBe(5);
  } finally { await context.close(); await rm(profile, { recursive: true, force: true }); }
});
