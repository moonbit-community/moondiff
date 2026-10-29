import { test, expect } from '../../tests/browser-test.mjs';
import { createGate, trackRoute } from '../../tests/browser-control.mjs';
import { installRenderProbe, settleRegions } from '../../tests/render-probe.mjs';
import { holdRegionFrames } from './dom-timing.mjs';
import { navigate } from './rendering-fixture.mjs';
import { installApi, reviewPath, pullTarget, commitTarget, commentCard, commentLines } from './review-fixture.mjs';

const longFootnote = 'First[^note], again[^note], Unicode[^说明🙂].\n\n'
  + commentLines('Body line', 35) + '\n\n[^note]: First footnote.\n\n    '
  + Array.from({ length: 30 }, (_, i) => `Footnote line ${i + 1}`).join('\n    ')
  + '\n\n[^说明🙂]: Unicode footnote.\n\n    Last paragraph.';

function geometry(el) {
  const toolbar = document.querySelector('.hero-workspace');
  const title = el.closest('.change-main')?.querySelector('.change-titlebar');
  const heading = el.closest('.file-card')?.querySelector('.file-heading');
  const section = el.closest('.semantic-section')?.querySelector('.semantic-section-title');
  const inset = [toolbar, title, heading, section].reduce((n, node) => n + (node?.getBoundingClientRect().height ?? 0), 8);
  const rect = el.getBoundingClientRect();
  return { top: rect.top, bottom: rect.bottom, inset, height: innerHeight, scroll: scrollY,
    maximum: document.documentElement.scrollHeight - innerHeight };
}

async function assertLanding(page, link, card) {
  const href = await link.getAttribute('href');
  await settleRegions(page);
  expect(await page.evaluate(() => location.hash)).toBe(href);
  const target = page.locator(`[id="${decodeURIComponent(href.slice(1))}"]`);
  await expect(target).toBeFocused();
  const position = await target.evaluate(geometry);
  expect(position.top).toBeGreaterThanOrEqual(position.inset - 1);
  expect(position.top).toBeLessThan(position.height);
  await expect(card.locator('.comment-body-clip')).toHaveAttribute('data-expanded', 'true');
  expect(await card.locator('.comment-body-clip').evaluate(el => el.scrollTop === 0 && el.clientHeight >= el.scrollHeight - 1)).toBe(true);
  return target;
}

test('Markdown web links open real new tabs and preserve the current draft and editor', async ({ page, context }) => {
  await installRenderProbe(page);
  await context.route('https://example.com/**', route => route.fulfill({ contentType: 'text/html', body: '<title>External page</title>' }));
  const body = '[Ordinary](https://example.com/ordinary)\n[Reference][ref]\n<https://example.com/automatic>\n[![Wrapped image](https://example.com/image.png)](https://example.com/wrapped)\n[Mail](mailto:reader@example.com)\n\nNote[^note].\n\n[ref]: https://example.com/reference\n\n[^note]: Local footnote.';
  await installApi(page, pullTarget(), { authenticated: true, issueBody: body });
  await page.goto(reviewPath());
  await page.getByRole('button', { name: 'Add overall comment' }).click();
  const editor = page.locator('.comment-editor textarea');
  await editor.fill('Keep this unsent draft\nwith another line');
  await editor.evaluate(el => { window.savedEditor = el; });
  const card = commentCard(page, 'issue', 10);
  await card.locator('.comment-body-toggle').click();
  const url = page.url();
  for (const path of ['ordinary', 'reference', 'automatic', 'wrapped']) {
    const link = card.locator(`a[href="https://example.com/${path}"]`);
    await expect(link).toHaveAttribute('target', '_blank');
    await expect(link).toHaveAttribute('rel', 'noopener noreferrer');
    const opened = context.waitForEvent('page');
    await link.click();
    const popup = await opened;
    await popup.waitForURL(`https://example.com/${path}`);
    expect(await popup.evaluate(() => opener)).toBeNull();
    await popup.close();
    expect(page.url()).toBe(url);
    await expect(editor).toHaveValue('Keep this unsent draft\nwith another line');
    expect(await editor.evaluate(el => el === window.savedEditor)).toBe(true);
  }
  await expect(card.getByRole('link', { name: 'Mail', exact: true })).not.toHaveAttribute('target');
  await card.locator('[role="doc-noteref"]').click();
  await settleRegions(page);
  expect(context.pages()).toHaveLength(1);
  await expect(editor).toHaveValue('Keep this unsent draft\nwith another line');
});

for (const width of [1280, 480]) {
  test(`collapsing long comments keeps the button visible and focused at ${width}px`, async ({ page }) => {
    await installRenderProbe(page);
    await page.setViewportSize({ width, height: 900 });
    const body = commentLines('Long comment', 100);
    await installApi(page, pullTarget(), { issueBody: body, inlineBody: body, replyBody: body, commitBody: body });
    await page.goto(reviewPath());
    for (const [kind, id] of [['issue', 10], ['review', 20], ['review', 21], ['commit', 30]]) {
      if (kind === 'commit') {
        await page.evaluate(target => { window.__fake.target = target; }, commitTarget());
        await navigate(page, reviewPath(commitTarget()));
      }
      const toggle = commentCard(page, kind, id).locator('.comment-body-toggle');
      await expect(toggle).toHaveText('Show more');
      await expect(page.locator('.loading-inline')).toHaveCount(0);
      await settleRegions(page);
      await toggle.click();
      await expect(toggle).toHaveText('Show less');
      await settleRegions(page);
      await toggle.evaluate(el => { el.scrollIntoView({ block: 'center' }); el.focus({ preventScroll: true }); });
      const before = await toggle.evaluate(geometry);
      await page.keyboard.press('Enter');
      await settleRegions(page);
      await expect(toggle).toHaveText('Show more');
      await expect(toggle).toBeFocused();
      const after = await toggle.evaluate(geometry);
      expect(after.top).toBeGreaterThanOrEqual(after.inset - 1);
      expect(after.bottom).toBeLessThanOrEqual(after.height - 7);
      if (after.scroll > 1 && after.scroll < after.maximum - 1) {
        expect(Math.abs(after.top - Math.max(before.top, after.inset))).toBeLessThan(2);
      }
    }
  });

  test(`footnotes expand before landing and return to the correct reference at ${width}px`, async ({ page, context }) => {
    await installRenderProbe(page);
    await page.setViewportSize({ width, height: 900 });
    await installApi(page, pullTarget(), { issueBody: longFootnote, inlineBody: longFootnote, replyBody: longFootnote, commitBody: longFootnote });
    await page.goto(reviewPath());
    for (const [kind, id] of [['issue', 10], ['review', 20], ['review', 21], ['commit', 30]]) {
      if (kind === 'commit') {
        await page.evaluate(target => { window.__fake.target = target; }, commitTarget());
        await navigate(page, reviewPath(commitTarget()));
      }
      const card = commentCard(page, kind, id);
      await expect(card.locator('.comment-body-toggle')).toHaveText('Show more');
      // Source arrival can migrate a fallback comment into the diff and replace its anchor.
      await expect(page.locator('.loading-inline')).toHaveCount(0);
      await settleRegions(page);
      const reference = card.locator('[role="doc-noteref"]').nth(1);
      await reference.focus();
      const history = await page.evaluate(() => window.history.length);
      await page.keyboard.press('Enter');
      const target = await assertLanding(page, reference, card);
      expect(await page.evaluate(() => window.history.length)).toBe(history + 1);
      await expect(target).toHaveAttribute('tabindex', '-1');
      // Repeated activation is an expansion request, never a toggle.
      await reference.evaluate(el => el.click());
      await assertLanding(page, reference, card);
      expect(await page.evaluate(() => window.history.length)).toBe(history + 1);
      const backlink = target.locator('[role="doc-backlink"]').nth(1);
      await backlink.click();
      await assertLanding(page, backlink, card);
      await expect(reference).toBeFocused();
      await expect(target).not.toHaveAttribute('tabindex');
      await card.locator('[role="doc-noteref"]').nth(2).click();
      await assertLanding(page, card.locator('[role="doc-noteref"]').nth(2), card);
      expect(context.pages()).toHaveLength(1);
    }
  });
}

test('Tab skips clipped code, scrolling tables and explicit tabindex elements and restores attributes', async ({ page }) => {
  await installRenderProbe(page);
  const body = '[Visible](https://example.com/)\nTwo\nThree\nFour\nFive\n\n```text\n' + 'long code '.repeat(100) + '\n```\n\n|' + Array(80).fill('Header').join('|') + '|\n|' + Array(80).fill('---').join('|') + '|\n|' + Array(80).fill('Cell').join('|') + '|' ;
  await installApi(page, pullTarget(), { issueBody: body });
  await page.goto(reviewPath());
  const card = commentCard(page, 'issue', 10);
  const toggle = card.locator('.comment-body-toggle');
  const pre = card.locator('pre');
  const table = card.locator('div[role="region"]');
  await expect(pre).toHaveAttribute('tabindex', '-1');
  await expect(table).toHaveAttribute('tabindex', '-1');
  await card.getByRole('link', { name: 'Visible', exact: true }).focus();
  await page.keyboard.press('Tab');
  await expect(toggle).toBeFocused();
  await page.keyboard.press('Enter');
  await settleRegions(page);
  await expect(pre).not.toHaveAttribute('tabindex');
  const tableIndex = await table.getAttribute('tabindex');
  expect(await table.evaluate(el => el.scrollWidth > el.clientWidth)).toBe(true);
  await card.getByRole('link', { name: 'Visible', exact: true }).focus();
  await page.keyboard.press('Tab');
  await expect(pre).toBeFocused();
  await page.keyboard.press('Tab');
  await expect(table).toBeFocused();
  await pre.evaluate(el => el.setAttribute('tabindex', '0'));
  await card.locator('code').evaluate(el => el.setAttribute('tabindex', '-1'));
  await toggle.evaluate(el => el.click());
  await settleRegions(page);
  await expect(toggle).toBeFocused();
  await expect(pre).toHaveAttribute('tabindex', '-1');
  expect(await card.locator('.comment-body-clip').evaluate(el => el.scrollTop)).toBe(0);
  await toggle.click();
  await settleRegions(page);
  await expect(pre).toHaveAttribute('tabindex', '0');
  expect(await table.getAttribute('tabindex')).toBe(tableIndex);
  await expect(card.locator('code')).toHaveAttribute('tabindex', '-1');
});

test('queued footnote and collapse actions yield to newer input and route changes', async ({ page }) => {
  await installRenderProbe(page);
  await installApi(page, pullTarget(), { authenticated: true, issueBody: longFootnote });
  await page.goto(reviewPath());
  await page.getByRole('button', { name: 'Add overall comment' }).click();
  const editor = page.locator('.comment-editor textarea');
  await editor.fill('Keep editing');
  const card = commentCard(page, 'issue', 10);
  const reference = card.locator('[role="doc-noteref"]').first();
  const toggle = card.locator('.comment-body-toggle');
  await settleRegions(page);
  let barrier = await holdRegionFrames(page, ['discussion']);
  await reference.evaluate(el => { el.click(); el.click(); });
  await barrier.blocked();
  await editor.focus();
  await editor.press('End');
  await editor.press('!');
  const position = await page.evaluate(() => scrollY);
  await barrier.release();
  await settleRegions(page);
  await expect(toggle).toHaveText('Show less');
  await expect(editor).toBeFocused();
  expect(await page.evaluate(() => location.hash)).toBe('');
  expect(await page.evaluate(() => scrollY)).toBe(position);
  barrier = await holdRegionFrames(page, ['discussion']);
  await toggle.evaluate(el => el.click());
  await barrier.blocked();
  await toggle.evaluate(el => el.click());
  await barrier.release();
  await settleRegions(page);
  await expect(toggle).toHaveText('Show less');
  await expect(editor).toBeFocused();
  await toggle.evaluate(el => el.click());
  await settleRegions(page);
  barrier = await holdRegionFrames(page, ['discussion']);
  await reference.evaluate(el => el.click());
  await barrier.blocked();
  await navigate(page, '/');
  await barrier.release();
  await settleRegions(page);
  expect(await page.evaluate(() => location.hash)).toBe('');
  expect(await page.evaluate(() => __moondiffMetrics.active.observers)).toBe(0);
});

test('code focus follows resizing, image load and body replacement and releases retired nodes', async ({ page }) => {
  await installRenderProbe(page);
  await page.setViewportSize({ width: 1600, height: 900 });
  const image = createGate('code focus image');
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aXWQAAAAASUVORK5CYII=', 'base64');
  await page.route('https://camo.githubusercontent.com/code-focus', async route => {
    await image.promise;
    await trackRoute(route).fulfill({ contentType: 'image/png', body: png });
  });
  const code = '\n\n```text\n' + 'long code '.repeat(100) + '\n```';
  await installApi(page, pullTarget(), { issueBody: 'Wrapping words '.repeat(12) + code });
  await page.goto(reviewPath());
  const card = commentCard(page, 'issue', 10);
  const pre = card.locator('pre');
  const toggle = card.locator('.comment-body-toggle');
  await expect(pre).toHaveCount(1);
  await settleRegions(page);
  await expect(pre).not.toHaveAttribute('tabindex');
  await pre.focus();
  await expect(pre).toBeFocused();
  await page.setViewportSize({ width: 480, height: 900 });
  await expect(pre).toHaveAttribute('tabindex', '-1');
  await expect(toggle).toBeFocused();
  expect(await card.locator('.comment-body-clip').evaluate(el => el.scrollTop)).toBe(0);
  await page.setViewportSize({ width: 1600, height: 900 });
  await expect(pre).not.toHaveAttribute('tabindex');
  await page.evaluate(code => { window.__fake.issueComments[0].body = '<img src="https://camo.githubusercontent.com/code-focus" alt="Delayed" width="240" height="240">' + code; }, code);
  await page.getByRole('button', { name: 'Refresh', exact: true }).click();
  await expect(card.locator('.markdown-image')).toHaveAttribute('data-image-state', 'pending');
  await settleRegions(page);
  await expect(pre).not.toHaveAttribute('tabindex');
  await pre.focus();
  image.release();
  await expect(card.locator('.markdown-image')).toHaveAttribute('data-image-state', 'loaded');
  await expect(pre).toHaveAttribute('tabindex', '-1');
  await expect(toggle).toBeFocused();
  await card.locator('.markdown-body :is(pre, a, img)').evaluateAll(nodes => { window.retiredBodyNodes = nodes.map(node => new WeakRef(node)); });
  await page.evaluate(() => { window.__fake.issueComments[0].body = '[Replacement](https://example.com/replacement)'; });
  await page.getByRole('button', { name: 'Refresh', exact: true }).click();
  await expect(card.locator('.markdown-body')).toHaveText('Replacement');
  await settleRegions(page);
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('HeapProfiler.collectGarbage');
  expect(await page.evaluate(() => retiredBodyNodes.filter(ref => ref.deref()).length)).toBe(0);
  await card.locator('a').evaluateAll(nodes => { window.retiredBodyNodes = nodes.map(node => new WeakRef(node)); });
  await navigate(page, '/');
  await settleRegions(page);
  await cdp.send('HeapProfiler.collectGarbage');
  expect(await page.evaluate(() => retiredBodyNodes.filter(ref => ref.deref()).length)).toBe(0);
  expect(await page.evaluate(() => __moondiffMetrics.active.observers)).toBe(0);
});

test('footnote delegation preserves modifiers, rejects foreign targets and records fragment history', async ({ page }) => {
  await installRenderProbe(page);
  await installApi(page, pullTarget(), { issueBody: longFootnote, inlineBody: longFootnote });
  await page.goto(reviewPath());
  const card = commentCard(page, 'issue', 10);
  const reference = card.locator('[role="doc-noteref"]').first();
  await expect(reference).toHaveCount(1);
  await settleRegions(page);
  for (const options of [{ ctrlKey: true }, { metaKey: true }, { shiftKey: true }, { altKey: true }, { button: 1 }]) {
    expect(await reference.evaluate((link, options) => {
      let intercepted;
      window.addEventListener('click', event => {
        intercepted = event.defaultPrevented;
        event.preventDefault(); // Observe delegation without launching native modifier navigation.
      }, { once: true });
      link.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, ...options }));
      return intercepted;
    }, options)).toBe(false);
  }
  const foreign = await commentCard(page, 'review', 20).locator('[role="doc-noteref"]').first().getAttribute('href');
  expect(await reference.evaluate((link, foreign) => {
    const href = link.getAttribute('href');
    link.setAttribute('href', foreign);
    let intercepted;
    window.addEventListener('click', event => { intercepted = event.defaultPrevented; event.preventDefault(); }, { once: true });
    link.click();
    link.setAttribute('href', href);
    return intercepted;
  }, foreign)).toBe(false);
  await expect(card.locator('.comment-body-toggle')).toHaveText('Show more');
  const barrier = await holdRegionFrames(page, ['discussion']);
  await reference.evaluate(el => { el.click(); el.click(); });
  await barrier.blocked();
  expect(await page.evaluate(() => location.hash)).toBe('');
  await barrier.release();
  const target = await assertLanding(page, reference, card);
  await expect(commentCard(page, 'review', 20).locator('.comment-body-toggle')).toHaveText('Show more');
  const hash = await reference.getAttribute('href');
  await target.locator('[role="doc-backlink"]').first().click();
  await settleRegions(page);
  await page.goBack();
  await settleRegions(page);
  expect(await page.evaluate(() => location.hash)).toBe(hash);
  await expect(card.locator('.comment-body-toggle')).toHaveText('Show less');
  await reference.click();
  await assertLanding(page, reference, card);
  await card.locator('[id]').evaluateAll(nodes => { window.retiredFootnotes = nodes.map(node => new WeakRef(node)); });
  await navigate(page, '/');
  await settleRegions(page);
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('HeapProfiler.collectGarbage');
  expect(await page.evaluate(() => retiredFootnotes.filter(ref => ref.deref()).length)).toBe(0);
});
