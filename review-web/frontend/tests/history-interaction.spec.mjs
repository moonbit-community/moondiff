import { scrollAndWait } from '../../tests/scroll-control.mjs';
import { expect, test } from '../../tests/browser-test.mjs';
import { gate, installRenderingFixture, syntheticFixture } from './rendering-fixture.mjs';
import { holdRegionFrames } from './dom-timing.mjs';
import { installRenderProbe, settleRegions } from '../../tests/render-probe.mjs';

async function returnToDraft(page, { small = false } = {}) {
  const fixture = syntheticFixture(small ? { files: 8, declarations: 1 } : { files: 24, declarations: 3 });
  if (small) {
    // Restoration only needs real scrollable files and a focus target. Added
    // files avoid loading/rendering a second source side for this timing probe.
    fixture.files = fixture.files.map(file => {
      const lines = fixture.sources[`${fixture.sha}:${file.filename}`].trimEnd().split('\n');
      return { ...file, status: 'added', additions: lines.length, deletions: 0, changes: lines.length,
        patch: `@@ -0,0 +1,${lines.length} @@\n${lines.map(line => `+${line}`).join('\n')}` };
    });
  }
  await installRenderProbe(page);
  const state = await installRenderingFixture(page, fixture, { authenticated: true });
  await page.goto('/example/regions/pull/1');
  // Isolate application scroll restoration from the browser's native anchoring
  // when the temporary validation banner disappears.
  await page.addStyleTag({ content: 'html { overflow-anchor: none !important; }' });
  await expect(page.locator('.loading-inline')).toHaveCount(0);
  await page.getByRole('button', { name: 'Add overall comment' }).click();
  await page.locator('.comment-editor textarea').fill('History draft');
  await settleRegions(page);
  await page.evaluate(() => {
    document.querySelector('#moondiff-file-7 .file-toggle').focus({ preventScroll: true });
    scrollTo(0, 1800);
  });
  await page.locator('a.workspace-home').evaluate(link => link.click());
  await expect(page.locator('.file-card')).toHaveCount(0);
  const validation = gate();
  state.metadataGate = validation;
  const reads = state.calls.filter(call => call.op === 'github.pull.get').length;
  await page.goBack();
  await expect(page.locator('.comment-editor textarea')).toHaveValue('History draft');
  await expect(page.getByText('Checking the current PR version…', { exact: true })).toBeVisible();
  await expect.poll(() => state.calls.filter(call => call.op === 'github.pull.get').length).toBeGreaterThan(reads);
  return { state, validation };
}

for (const timing of ['validation', 'queued']) {
  for (const interaction of ['typing', 'wheel', 'keyboard']) {
    test(`${interaction} cancels history restoration during ${timing}`, async ({ page }) => {
      // Exercise restoration scheduling under CPU throttling with enough files
      // to scroll/focus file 7, without benchmarking bulk source rendering.
      const { state, validation } = await returnToDraft(page, { small: true });
      let barrier;
      if (timing === 'queued') {
        // Validation has finished and restoration is waiting on a regional paint.
        barrier = await holdRegionFrames(page, ['status']);
        state.metadataGate = null;
        validation.resolve();
        await barrier.blocked();
      }
      const editor = page.locator('.comment-editor textarea');
      if (interaction === 'typing') {
        await editor.fill('User typing takes precedence');
        await editor.evaluate(element => element.setSelectionRange(4, 9, 'backward'));
      } else {
        await page.locator('#moondiff-file-0 .file-toggle').evaluate(button => button.focus({ preventScroll: true }));
        await scrollAndWait(page, async () => {
          if (interaction === 'wheel') {
            await page.mouse.move(1000, 500);
            await page.mouse.wheel(0, 380);
          } else {
            await page.keyboard.press('PageDown');
          }
        });
      }
      const position = await page.evaluate(() => {
        window.historyInteractionFocus = document.activeElement;
        return { x: scrollX, y: scrollY };
      });
      state.metadataGate = null;
      validation.resolve();
      if (barrier) await barrier.release();
      await expect(page.getByText('Checking the current PR version…', { exact: true })).toHaveCount(0);
      await settleRegions(page);
      expect(await page.evaluate(() => document.activeElement === window.historyInteractionFocus)).toBe(true);
      expect(await page.evaluate(() => ({ x: scrollX, y: scrollY }))).toEqual(position);
      if (interaction === 'typing') {
        await expect(editor).toHaveValue('User typing takes precedence');
        expect(await editor.evaluate(el => [el.selectionStart, el.selectionEnd, el.selectionDirection])).toEqual([4, 9, 'backward']);
      }
    });
  }
}

test('delayed history restores normally without user input', async ({ page }) => {
  const { state, validation } = await returnToDraft(page);
  state.metadataGate = null;
  validation.resolve();
  await expect(page.locator('#moondiff-file-7 .file-toggle')).toBeFocused();
  await expect.poll(() => page.evaluate(() => scrollY)).toBe(1800);
});

test('an explicit file jump supersedes delayed history restoration', async ({ page }) => {
  const { state, validation } = await returnToDraft(page);
  await page.locator('[data-region="tree"] [aria-label="Open src/unrelated-12.mbt"]').evaluate(button => button.click());
  await settleRegions(page);
  const position = await page.evaluate(() => scrollY);
  expect(position).toBeGreaterThan(1800);
  state.metadataGate = null;
  validation.resolve();
  await expect(page.getByText('Checking the current PR version…', { exact: true })).toHaveCount(0);
  await settleRegions(page);
  expect(await page.evaluate(() => scrollY)).toBe(position);
});

test('typing during restored source loading cancels the pending focus and scroll', async ({ page }) => {
  const fixture = syntheticFixture({ files: 24, declarations: 3 });
  const first = gate(), resumed = gate();
  await installRenderProbe(page);
  const state = await installRenderingFixture(page, fixture, {
    authenticated: true,
    contentGate: { path: fixture.files[0].filename, promise: first.promise },
  });
  await page.goto(`/example/regions/commit/${fixture.sha}`);
  await page.addStyleTag({ content: 'html { overflow-anchor: none !important; }' });
  await expect(page.locator('.file-card')).toHaveCount(24);
  await expect(page.locator('.loading-inline')).toHaveCount(1);
  await page.evaluate(() => {
    document.querySelector('#moondiff-file-7 .file-toggle').focus({ preventScroll: true });
    scrollTo(0, 1800);
  });
  await page.locator('a.workspace-home').evaluate(link => link.click());
  await expect(page.locator('.file-card')).toHaveCount(0);
  state.contentGate = { path: fixture.files[0].filename, promise: resumed.promise };
  await page.goBack();
  await expect(page.locator('.loading-inline')).toHaveCount(1);
  await expect.poll(() => state.calls.filter(call => call.op === 'github.content.get'
    && call.args.path === fixture.files[0].filename && call.args.ref === fixture.sha).length).toBe(2);
  await page.getByRole('button', { name: 'Search files', exact: true }).click();
  const search = page.getByRole('searchbox', { name: 'Search changed files' });
  await search.fill('unrelated');
  const y = await page.evaluate(() => scrollY);
  resumed.resolve();
  first.resolve();
  await expect(page.locator('.loading-inline')).toHaveCount(0);
  await settleRegions(page);
  await expect(search).toBeFocused();
  await expect(search).toHaveValue('unrelated');
  expect(await page.evaluate(() => scrollY)).toBe(y);
});
