import { expect, test } from '../../tests/browser-test.mjs';
import { createGate } from '../../tests/browser-control.mjs';
import { successFixture } from '../../tests/protocol-fixtures.mjs';
import { installRenderProbe, settleRegions } from '../../tests/render-probe.mjs';
import { installApi, pullTarget, reviewPath } from './review-fixture.mjs';
import { clickLineCommentButton } from './comment-actions.mjs';

async function openReview(page) {
  await installRenderProbe(page);
  await installApi(page, pullTarget(), { authenticated: true, login: 'alice' });
  await page.goto(reviewPath());
  await expect(page.getByRole('button', { name: 'Account: alice', exact: true })).toBeVisible();
  await expect(page.locator('.loading-inline')).toHaveCount(0);
  await settleRegions(page);
  return page.locator('.overall-comment-editor');
}

for (const width of [1280, 360]) {
  for (const colorScheme of ['light', 'dark']) {
    test(`overall composer is visible with the current avatar at ${width}px in ${colorScheme}`, async ({ page }, testInfo) => {
      await page.setViewportSize({ width, height: 900 });
      await page.emulateMedia({ colorScheme });
      const composer = await openReview(page);
      const editor = composer.getByRole('textbox', { name: 'Add a comment', exact: true });
      await expect(editor).toBeVisible();
      await expect(editor).toHaveValue('');
      await expect(composer.getByRole('button', { name: 'Post comment' })).toBeDisabled();
      await expect(composer.getByRole('button', { name: 'Cancel', exact: true })).toHaveCount(0);
      await expect(page.getByRole('button', { name: 'Add overall comment' })).toHaveCount(0);
      await expect(composer.locator('.comment-avatar-image')).toHaveCSS('background-image', 'url("https://github.com/alice.png?size=64")');
      await expect(composer.locator('.comment-avatar-placeholder')).toBeAttached();
      await expect(composer.locator('.comment-avatar')).toHaveCSS('border-radius', '50%');
      await editor.focus();
      await settleRegions(page);
      await expect(page.locator('textarea[data-draft-id]')).toHaveCount(0);
      const avatar = await composer.locator('.comment-avatar').boundingBox();
      const title = await composer.getByRole('heading', { name: 'Add a comment' }).boundingBox();
      const input = await editor.boundingBox();
      expect(avatar.width).toBe(32);
      expect(avatar.height).toBe(32);
      expect(title.x).toBeGreaterThan(avatar.x + avatar.width);
      expect(Math.abs(title.y - avatar.y)).toBeLessThan(1);
      expect(Math.abs(input.x - title.x)).toBeLessThan(1);
      expect(input.y).toBeGreaterThanOrEqual(title.y + title.height);
      expect(input.x + input.width).toBeLessThan(width);
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
      await composer.screenshot({ path: testInfo.outputPath(`overall-${width}-${colorScheme}.png`) });
    });
  }
}

test('first typing, cancellation, failed posting and successful posting retain the composer node', async ({ page }) => {
  const composer = await openReview(page);
  const editor = composer.locator('textarea');
  const original = await editor.elementHandle();
  await editor.focus();
  await page.keyboard.type('First comment');
  await expect(editor).toHaveValue('First comment');
  await expect(editor).toHaveAttribute('data-draft-id', /draft:/);
  const id = await editor.getAttribute('data-draft-id');
  await page.keyboard.type('!');
  await expect(editor).toHaveAttribute('data-draft-id', id);
  await expect(editor).toHaveValue('First comment!');
  await expect(editor).toBeFocused();
  expect(await original.evaluate(el => el === document.activeElement)).toBe(true);
  await composer.getByRole('button', { name: 'Cancel', exact: true }).click();
  await expect(editor).toHaveValue('');
  await expect(page.locator('textarea[data-draft-id]')).toHaveCount(0);
  await expect(composer.getByRole('button', { name: 'Cancel', exact: true })).toHaveCount(0);
  await editor.fill('Retry this comment');
  await page.evaluate(() => {
    const dispatch = window.__dispatch;
    let fail = true;
    window.__dispatch = message => {
      if (message.op === 'github.issue.comment.create' && fail) {
        fail = false;
        throw Object.assign(new Error('Fixture write failed'), { status: 503 });
      }
      return dispatch(message);
    };
  });
  await composer.getByRole('button', { name: 'Post comment' }).click();
  await expect(composer.locator('.comment-error')).toContainText('Fixture write failed');
  await expect(editor).toHaveValue('Retry this comment');
  await expect(editor).toBeEnabled();
  await composer.getByRole('button', { name: 'Post comment' }).click();
  await expect(page.locator('.github-comment-body').filter({ hasText: 'Retry this comment' })).toBeVisible();
  await expect(editor).toHaveValue('');
  await expect(editor).toBeEnabled();
  await expect(composer.getByRole('button', { name: 'Post comment' })).toBeDisabled();
  await expect(page.locator('textarea[data-draft-id]')).toHaveCount(0);
  expect(await editor.evaluate((el, original) => el === original, original)).toBe(true);
});

for (const kind of ['inline', 'reply']) {
  test(`empty overall composer allows a ${kind} draft and stays disabled until it finishes`, async ({ page }) => {
    const composer = await openReview(page);
    const overall = composer.locator('textarea');
    const original = await overall.elementHandle();
    await overall.focus();
    if (kind === 'inline') {
      await clickLineCommentButton(page.locator('.line-comment-button').first());
    } else {
      await page.getByRole('button', { name: 'Reply', exact: true }).first().click();
    }
    const draft = page.locator('.comment-editor[data-draft-id]');
    await expect(draft).toHaveCount(1);
    await expect(overall).toBeVisible();
    await expect(overall).toBeDisabled();
    await expect(composer.getByText('Post or cancel your current draft before adding an overall comment.')).toBeVisible();
    await expect(composer.getByRole('button', { name: 'Cancel', exact: true })).toHaveCount(0);
    await draft.locator('textarea').fill('Other draft');
    await draft.getByRole('button', { name: 'Cancel', exact: true }).click();
    await expect(overall).toBeEnabled();
    await expect(overall).toHaveValue('');
    await expect(composer.locator('.comment-notice')).toHaveCount(0);
    expect(await overall.evaluate((el, original) => el === original, original)).toBe(true);
    await overall.fill('Overall draft');
    await expect(page.locator('textarea[data-draft-id]')).toHaveCount(1);
    await expect(page.getByRole('button', { name: 'Reply', exact: true }).first()).toBeDisabled();
    await expect(page.locator('.line-comment-button').first()).toBeDisabled();
  });
}

for (const startDuringCheck of [false, true]) {
  test(`Chinese composition ${startDuringCheck ? 'starting during' : 'preceding'} identity checking and refresh keeps its node and caret`, async ({ page }) => {
    const composer = await openReview(page);
    const editor = composer.locator('textarea');
    await editor.focus();
    const original = await editor.elementHandle();
    const cdp = await page.context().newCDPSession(page);
    if (!startDuringCheck) {
      await cdp.send('Input.imeSetComposition', { text: '中', selectionStart: 1, selectionEnd: 1 });
      await expect(editor).toHaveValue('中');
    }
    const held = createGate('identity check');
    const entered = createGate('identity check entered');
    await page.route('**/api/auth/status', async route => {
      const value = await page.evaluate(() => window.__dispatch({ op: 'auth.status' }));
      entered.release();
      await held.promise;
      await route.fulfill({ json: successFixture('auth.status', value) });
    }, { times: 1 });
    await page.evaluate(() => {
      dispatchEvent(new Event('pagehide'));
      dispatchEvent(new Event('pageshow'));
    });
    await entered.promise;
    await expect(composer.locator('.comment-notice')).toContainText('Checking your GitHub account');
    await expect(editor).toBeFocused();
    await expect(editor).toBeEnabled();
    await cdp.send('Input.imeSetComposition', { text: '中文', selectionStart: 2, selectionEnd: 2 });
    await expect(editor).toHaveValue('中文');
    await expect(editor).toHaveAttribute('data-draft-id', /draft:/);
    const id = await editor.getAttribute('data-draft-id');
    await expect(composer.getByRole('button', { name: 'Post comment' })).toBeDisabled();
    held.release();
    await expect(composer.getByRole('button', { name: 'Post comment' })).toBeEnabled();
    await page.getByRole('button', { name: 'Refresh', exact: true }).evaluate(el => el.click());
    await expect(page.getByRole('button', { name: 'Refresh', exact: true })).toBeEnabled();
    await settleRegions(page);
    await expect(editor).toBeFocused();
    expect(await original.evaluate(el => el === document.activeElement)).toBe(true);
    expect(await editor.evaluate(el => [el.selectionStart, el.selectionEnd])).toEqual([2, 2]);
    await cdp.send('Input.insertText', { text: '中文评论' });
    await expect(editor).toHaveValue('中文评论');
    await expect(editor).toHaveAttribute('data-draft-id', id);
  });
}
