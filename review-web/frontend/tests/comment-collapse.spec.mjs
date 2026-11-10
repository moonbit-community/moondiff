import { test, expect } from '../../tests/browser-test.mjs';
import { installRenderProbe, renderCounts, settleRegions } from '../../tests/render-probe.mjs';
import { holdRegionFrames } from './dom-timing.mjs';
import { navigate } from './rendering-fixture.mjs';
import { clickLineCommentButton } from './comment-actions.mjs';
import { closeSignInDialog, expectSignInDialog } from './sign-in-dialog.mjs';
import { installApi, reviewPath, pullTarget, commitTarget, commentCard, commentLines } from './review-fixture.mjs';

async function assertOverviewCollapsed(page) {
  const overview = page.locator('#comments');
  await expect(overview.getByRole('heading', { name: 'Comments', exact: true })).toBeVisible();
  const toggle = overview.getByRole('button', { name: 'Expand comments', exact: true });
  await expect(toggle).toHaveAttribute('aria-expanded', 'false');
  await expect(toggle).toHaveAttribute('aria-controls', 'comments-content');
  await expect(overview.locator('#comments-content')).toBeHidden();
  await expect(overview.locator('.comments-controls')).toBeHidden();
  await expect(overview.locator('.section-label')).toBeHidden();
  // The accessibility tree must contain only the heading and toggle.
  expect(await overview.ariaSnapshot()).toBe('- heading "Comments" [level=2]\n- button "Expand comments": ▸');
  const bounds = await overview.evaluate(el => {
    const toolbar = el.querySelector('.comments-toolbar');
    const title = el.querySelector('h2').getBoundingClientRect();
    const button = el.querySelector('.comments-overview-toggle').getBoundingClientRect();
    return { content: el.clientHeight - parseFloat(getComputedStyle(el).paddingTop) - parseFloat(getComputedStyle(el).paddingBottom),
      header: toolbar.getBoundingClientRect().height, sameLine: button.top < title.bottom && title.top < button.bottom,
      overflow: el.scrollWidth - el.clientWidth };
  });
  expect(Math.abs(bounds.content - bounds.header)).toBeLessThan(2);
  expect(bounds.sameLine).toBe(true);
  expect(bounds.overflow).toBeLessThanOrEqual(1);
}

for (const target of [pullTarget(), commitTarget()]) for (const authenticated of [false, true]) {
  test(`overview collapses all ${target.kind} discussion controls for ${authenticated ? 'signed-in' : 'anonymous'} readers`, async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 900 });
    await ready(page, target, { authenticated });
    const inline = commentCard(page, target.kind === 'pull' ? 'review' : 'commit', target.kind === 'pull' ? 20 : 30);
    const before = await renderCounts(page);
    await page.getByRole('button', { name: 'Collapse comments', exact: true }).click();
    await settleRegions(page);
    await assertOverviewCollapsed(page);
    expect((await renderCounts(page)).files).toEqual(before.files);
    await expect(inline.locator('.github-comment-content')).toBeVisible();
    const toggle = page.getByRole('button', { name: 'Expand comments', exact: true });
    await toggle.focus();
    await page.keyboard.press('Tab');
    expect(await page.locator('#comments').evaluate(el => !el.contains(document.activeElement))).toBe(true);
    await toggle.focus();
    await page.keyboard.press('Enter');
    await expect(page.getByRole('button', { name: 'Collapse comments', exact: true })).toBeFocused();
    await expect(page.locator('#comments-content')).not.toHaveAttribute('hidden');
    await expect(page.locator('#comments .refresh-comments')).toBeVisible();
    await page.keyboard.press('Space');
    await assertOverviewCollapsed(page);
  });
}

for (const target of [pullTarget(), commitTarget()]) for (const status of ['empty', 'loading', 'failed']) {
  test(`overview folds ${status} ${target.kind} discussions`, async ({ page }) => {
    await installRenderProbe(page);
    await installApi(page, target, status === 'failed' ? { commentListError: { status: 503, detail: 'Comments offline' } } : {});
    await page.addInitScript(status => {
      if (status === 'empty') {
        window.__fake.issueComments = [];
        window.__fake.reviewComments = [];
        window.__fake.commitComments = [];
      }
      if (status === 'loading') window.__fake.delayNextList = true;
    }, status);
    try {
      await page.goto(reviewPath(target));
      const content = page.locator('#comments-content');
      if (status === 'loading') await expect(content.locator('.comments-loading')).toBeVisible();
      if (status === 'failed') await expect(content.locator('.comment-error')).toContainText('Comments offline');
      if (status === 'empty') await expect(page.locator('#comments .refresh-comments')).toBeEnabled();
      await page.getByRole('button', { name: 'Collapse comments', exact: true }).click();
      await settleRegions(page);
      await assertOverviewCollapsed(page);
      if (status === 'loading') {
        await expect.poll(() => page.evaluate(() => typeof window.__fake.releaseList)).toBe('function');
        await page.evaluate(() => window.__fake.releaseList());
        await expect(content.locator('.comments-loading')).toHaveCount(0);
        await assertOverviewCollapsed(page);
      }
      await page.getByRole('button', { name: 'Expand comments', exact: true }).click();
      await expect(content).not.toHaveAttribute('hidden');
      await expect(page.locator('#comments .refresh-comments')).toBeVisible();
      if (status === 'failed') await expect(content.locator('.comment-error')).toBeVisible();
      if (status === 'empty') await expect(content.locator('.github-comment')).toHaveCount(0);
    } finally {
      if (status === 'loading') await page.evaluate(() => window.__fake.releaseList?.());
    }
  });
}

test('overview keeps reading choices across refresh and layout changes and resets on reload and navigation', async ({ page }) => {
  await ready(page);
  await page.getByRole('button', { name: 'Refresh', exact: true }).click();
  await page.getByRole('button', { name: 'Collapse comments', exact: true }).click();
  await expect(page.locator('.refresh-comments')).toBeEnabled();
  for (const name of ['Unified', 'Tree', 'Token', 'Split']) {
    await page.getByRole('button', { name, exact: true }).click();
    await settleRegions(page);
    await assertOverviewCollapsed(page);
  }
  // Refresh remains operable through page reactivation while its button is hidden.
  const lists = await page.evaluate(() => window.__fake.commentListCalls);
  await page.evaluate(() => {
    dispatchEvent(new Event('pagehide'));
    dispatchEvent(new Event('pageshow'));
  });
  await expect.poll(() => page.evaluate(() => window.__fake.commentListCalls)).toBeGreaterThan(lists);
  await assertOverviewCollapsed(page);
  await page.reload();
  await expect(page.getByRole('button', { name: 'Collapse comments', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Collapse comments', exact: true }).click();
  await page.evaluate(target => { window.__fake.target = target; }, commitTarget());
  await navigate(page, reviewPath(commitTarget()));
  await expect(page.getByRole('button', { name: 'Collapse comments', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Collapse comments', exact: true }).click();
  await page.evaluate(target => { window.__fake.target = target; }, pullTarget());
  await navigate(page, reviewPath());
  await expect(page.getByRole('button', { name: 'Collapse comments', exact: true })).toBeVisible();
});

test('collapsed overview preserves comment previews and menus and leaves inline sign-in available', async ({ page }) => {
  await ready(page, pullTarget(), { issueBody: commentLines('Overview', 30) });
  const card = commentCard(page, 'issue', 10);
  const preview = card.locator('.comment-body-toggle');
  await preview.click();
  await card.getByRole('button', { name: 'More options' }).click();
  await expect(card.locator('.comment-menu')).toBeVisible();
  await page.getByRole('button', { name: 'Collapse comments', exact: true }).evaluate(el => el.click());
  await settleRegions(page);
  await expect(card.locator('.comment-menu')).toBeHidden();
  await expect(card.locator('.comment-more')).toHaveAttribute('aria-expanded', 'false');
  // Hidden previews must not be remeasured as zero-height bodies.
  await expect(preview).not.toHaveAttribute('hidden');
  await clickLineCommentButton(page.locator('.line-comment-button').first());
  await expectSignInDialog(page, 'Sign in to comment');
  await expect(page.locator('#comments-content')).toBeHidden();
  await closeSignInDialog(page);
  await page.getByRole('button', { name: 'Expand comments', exact: true }).click();
  await settleRegions(page);
  await expect(preview).toHaveText('Show less');
  await preview.click();
  await expect(preview).toHaveText('Show more');
});

test('overview retains missing-file reply drafts and each comment collapse choice', async ({ page }) => {
  await installRenderProbe(page);
  await installApi(page, pullTarget(), { authenticated: true, replyBody: commentLines('Reply', 30) });
  await page.addInitScript(() => { window.__fake.reviewComments.forEach(c => { c.path = 'missing.mbt'; }); });
  await page.goto(reviewPath());
  const root = commentCard(page, 'review', 20);
  const reply = commentCard(page, 'review', 21);
  await reply.locator('.comment-body-toggle').click();
  await root.locator('.comment-collapse-toggle').click();
  await root.locator('xpath=..').getByRole('button', { name: 'Reply', exact: true }).click();
  const editor = page.getByRole('textbox', { name: 'Write a reply', exact: true });
  await editor.fill('Missing-file reply');
  await expect(editor).toHaveAttribute('data-draft-id', /draft:/);
  const original = await editor.elementHandle();
  const id = await editor.getAttribute('data-draft-id');
  await editor.evaluate(el => el.setSelectionRange(2, 9, 'backward'));
  await page.getByRole('button', { name: 'Collapse comments', exact: true }).click();
  await settleRegions(page);
  await expect(editor).toBeHidden();
  await page.getByRole('button', { name: 'Expand comments', exact: true }).click();
  await settleRegions(page);
  await assertSingleLine(root);
  await expect(reply.locator('.comment-body-toggle')).toHaveText('Show less');
  await expect(editor).toHaveValue('Missing-file reply');
  await expect(editor).toHaveAttribute('data-draft-id', id);
  expect(await editor.evaluate((el, original) => el === original, original)).toBe(true);
  expect(await editor.evaluate(el => [el.selectionStart, el.selectionEnd, el.selectionDirection])).toEqual([2, 9, 'backward']);
});

async function ready(page, target = pullTarget(), options = {}) {
  await installRenderProbe(page);
  await installApi(page, target, options);
  await page.goto(reviewPath(target));
  await expect(page.locator('.loading-inline')).toHaveCount(0);
  await expect(commentCard(page, target.kind === 'pull' ? 'review' : 'commit', target.kind === 'pull' ? 20 : 30)).toBeVisible();
  await settleRegions(page);
}

async function assertSingleLine(card, author = 'reviewer') {
  await expect(card).toHaveAttribute('data-collapsed', 'true');
  await expect(card.locator('.comment-collapse-toggle')).toHaveAccessibleName(`Expand comment by ${author}`);
  await expect(card.locator('.comment-collapse-toggle')).toHaveAttribute('aria-expanded', 'false');
  await expect(card.locator('.github-comment-content')).toBeHidden();
  await expect(card.locator('.comment-byline strong')).toBeVisible();
  await expect(card.locator('.comment-byline strong')).toHaveText(author);
  await expect(card.locator('.comment-actions')).toBeHidden();
  await expect(card.locator('time')).toBeVisible();
  const size = await card.evaluate(el => {
    const header = el.querySelector('.github-comment-meta');
    return { height: el.getBoundingClientRect().height, header: header.getBoundingClientRect().height,
      overflow: el.scrollWidth - el.clientWidth, wrap: getComputedStyle(header).flexWrap,
      byline: getComputedStyle(el.querySelector('.comment-byline')).whiteSpace };
  });
  expect(Math.abs(size.height - size.header)).toBeLessThan(3);
  expect(size.height).toBeLessThanOrEqual(60);
  expect(size.overflow).toBeLessThanOrEqual(1);
  expect(size.wrap).toBe('nowrap');
  expect(size.byline).toBe('nowrap');
}

for (const width of [320, 420]) for (const target of [pullTarget(), commitTarget()]) {
  test(`collapsed ${target.kind} comment retains a long username and timestamp at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 });
    await installRenderProbe(page);
    await installApi(page, target);
    const author = 'reviewer-with-a-very-long-github-username';
    await page.addInitScript(author => {
      window.__fake.reviewComments[0].user.login = author;
      window.__fake.commitComments[0].user.login = author;
    }, author);
    await page.goto(reviewPath(target));
    const card = commentCard(page, target.kind === 'pull' ? 'review' : 'commit', target.kind === 'pull' ? 20 : 30);
    await expect(card).toBeVisible();
    await card.locator('.comment-collapse-toggle').click();
    for (const layout of ['Split', 'Unified']) {
      await page.getByRole('button', { name: layout, exact: true }).click();
      await settleRegions(page);
      await assertSingleLine(card, author);
      const bounds = await card.evaluate(el => {
        const byline = el.querySelector('.comment-byline').getBoundingClientRect();
        const author = el.querySelector('.comment-byline strong').getBoundingClientRect();
        const time = el.querySelector('time').getBoundingClientRect();
        return { authorWidth: author.width, timeWidth: time.width,
          inside: author.left >= byline.left && time.right <= byline.right + 1,
          overlap: author.right > time.left,
          overflow: document.documentElement.scrollWidth - innerWidth };
      });
      expect(bounds.authorWidth).toBeGreaterThan(0);
      expect(bounds.timeWidth).toBeGreaterThan(0);
      expect(bounds.inside).toBe(true);
      expect(bounds.overlap).toBe(false);
      expect(bounds.overflow).toBeLessThanOrEqual(1);
    }
  });
}

for (const width of [1280, 420]) for (const layout of ['Split', 'Unified']) {
  test(`manual collapse preserves each preview and reply at ${width}px ${layout}`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 });
    const body = '[Body link](https://example.com/)\n' + commentLines('Long comment', 40);
    await ready(page, pullTarget(), { inlineBody: body, replyBody: body });
    await page.getByRole('button', { name: layout, exact: true }).click();
    await settleRegions(page);
    const root = commentCard(page, 'review', 20);
    const reply = commentCard(page, 'review', 21);
    await root.locator('.github-comment-body').evaluate(el => { window.savedCommentBody = el; });
    await root.locator('.comment-body-toggle').click();
    await expect(root.locator('.comment-body-toggle')).toHaveText('Show less');
    const rootToggle = root.locator('.comment-collapse-toggle');
    await rootToggle.click();
    await settleRegions(page);
    await assertSingleLine(root);
    await expect(rootToggle).toBeFocused();
    await expect(rootToggle).toBeInViewport();
    await expect(reply.locator('.github-comment-content')).toBeVisible();
    await expect(reply.locator('.comment-body-toggle')).toHaveText('Show more');
    await reply.locator('.comment-collapse-toggle').focus();
    await page.keyboard.press('Space');
    await settleRegions(page);
    await assertSingleLine(reply, 'author');
    await expect(page.getByRole('button', { name: 'Expand comment by reviewer', exact: true })).toHaveCount(1);
    await expect(page.getByRole('button', { name: 'Expand comment by author', exact: true })).toHaveCount(1);
    expect(await root.ariaSnapshot()).toContain('button "Expand comment by reviewer"');
    expect(await reply.ariaSnapshot()).toContain('button "Expand comment by author"');
    await rootToggle.focus();
    await page.keyboard.press('Enter');
    await settleRegions(page);
    await expect(rootToggle).toBeFocused();
    await expect(rootToggle).toBeInViewport();
    await expect(rootToggle).toHaveAttribute('aria-expanded', 'true');
    await expect(rootToggle).toHaveAccessibleName('Collapse comment by reviewer');
    await expect(root.locator('.comment-body-toggle')).toHaveText('Show less');
    expect(await root.locator('.github-comment-body').evaluate(el => el === window.savedCommentBody)).toBe(true);
    expect(await root.locator('.comment-body-clip').evaluate(el => el.clientHeight >= el.scrollHeight - 1)).toBe(true);
    await assertSingleLine(reply, 'author');
    await page.getByRole('button', { name: 'Expand comment by author', exact: true }).click();
    await settleRegions(page);
    await expect(reply.locator('.comment-collapse-toggle')).toHaveAccessibleName('Collapse comment by author');
    await expect(reply.locator('.comment-body-toggle')).toHaveText('Show more');
    expect(await reply.locator('.comment-body-clip').evaluate(el => el.clientHeight < el.scrollHeight)).toBe(true);
    await expect(commentCard(page, 'issue', 10).locator('.comment-collapse-toggle')).toHaveCount(0);
    const short = commentCard(page, 'review', 24);
    await short.locator('.comment-collapse-toggle').click();
    await settleRegions(page);
    await assertSingleLine(short);
    await rootToggle.click();
    await settleRegions(page);
    await rootToggle.focus();
    await page.keyboard.press('Tab');
    expect(await root.evaluate(el => !el.contains(document.activeElement))).toBe(true);
  });
}

for (const width of [1280, 420]) {
  test(`commit comments collapse and restore five-line preview at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 });
    await ready(page, commitTarget(), { commitBody: commentLines('Commit body', 30) });
    const card = commentCard(page, 'commit', 30);
    for (const layout of ['Split', 'Unified']) {
      await page.getByRole('button', { name: layout, exact: true }).click();
      await card.locator('.comment-collapse-toggle').click();
      await settleRegions(page);
      await assertSingleLine(card);
      await expect(card.locator('.comment-collapse-toggle')).toBeFocused();
      await card.locator('.comment-collapse-toggle').press('Space');
      await settleRegions(page);
      await expect(card.locator('.comment-collapse-toggle')).toHaveAccessibleName('Collapse comment by reviewer');
      await expect(card.locator('.comment-body-toggle')).toHaveText('Show more');
    }
  });
}

for (const target of [pullTarget(), commitTarget()]) {
  test(`collapse names retain the ghost fallback for ${target.kind} comments`, async ({ page }) => {
    await installRenderProbe(page);
    await installApi(page, target);
    await page.addInitScript(() => {
      window.__fake.reviewComments[0].user = null;
      window.__fake.commitComments[0].user = null;
    });
    await page.goto(reviewPath(target));
    const card = commentCard(page, target.kind === 'pull' ? 'review' : 'commit', target.kind === 'pull' ? 20 : 30);
    await page.getByRole('button', { name: 'Collapse comment by ghost', exact: true }).click();
    await settleRegions(page);
    await assertSingleLine(card, 'ghost');
    await page.getByRole('button', { name: 'Expand comment by ghost', exact: true }).click();
    await settleRegions(page);
    await expect(card.locator('.comment-collapse-toggle')).toHaveAccessibleName('Collapse comment by ghost');
    await expect(card.locator('.comment-byline strong')).toHaveText('ghost');
  });
}

test('collapse retains replies, editor identity, selection, refresh and layout choices', async ({ page }) => {
  await ready(page, pullTarget(), { authenticated: true });
  const root = commentCard(page, 'review', 20);
  const reply = commentCard(page, 'review', 21);
  await root.locator('xpath=..').getByRole('button', { name: 'Reply', exact: true }).click();
  const editor = page.getByRole('textbox', { name: 'Write a reply', exact: true });
  await editor.fill('Keep this reply draft\nand its cursor');
  await editor.evaluate(el => { window.savedReplyEditor = el; el.setSelectionRange(5, 15, 'backward'); });
  await root.locator('.comment-collapse-toggle').click();
  await reply.locator('.comment-collapse-toggle').click();
  await settleRegions(page);
  await expect(editor).toBeVisible();
  expect(await editor.evaluate(el => el === window.savedReplyEditor)).toBe(true);
  expect(await editor.evaluate(el => [el.selectionStart, el.selectionEnd, el.selectionDirection])).toEqual([5, 15, 'backward']);
  await editor.focus();
  await editor.press('!');
  await expect(editor).toHaveValue('Keep ! draft\nand its cursor');
  for (const name of ['Refresh', 'Unified', 'Tree', 'Token', 'Split']) {
    await page.getByRole('button', { name, exact: true }).click();
    await settleRegions(page);
    await assertSingleLine(root);
    await assertSingleLine(reply, 'author');
    expect(await editor.evaluate(el => el === window.savedReplyEditor)).toBe(true);
    await expect(editor).toHaveValue('Keep ! draft\nand its cursor');
  }
  await page.locator('#moondiff-file-0 .file-toggle').click();
  await page.locator('#moondiff-file-0 .file-toggle').click();
  await settleRegions(page);
  await assertSingleLine(root);
  await assertSingleLine(reply, 'author');
  await expect(editor).toHaveValue('Keep ! draft\nand its cursor');
  await page.reload();
  await expect(root.locator('.comment-collapse-toggle')).toHaveAttribute('aria-expanded', 'true');
});

test('collapse hides and restores deletion confirmation and closes an open menu', async ({ page }) => {
  await ready(page, pullTarget(), { authenticated: true, login: 'reviewer' });
  const card = commentCard(page, 'review', 20);
  await card.getByRole('button', { name: 'More options' }).click();
  await card.getByRole('menuitem', { name: 'Delete', exact: true }).click();
  await expect(card.getByRole('button', { name: 'Confirm delete' })).toBeVisible();
  await card.getByRole('button', { name: 'More options' }).click();
  await expect(card.locator('.comment-menu')).toBeVisible();
  await card.locator('.comment-collapse-toggle').evaluate(el => el.click());
  await settleRegions(page);
  await assertSingleLine(card);
  await expect(card.locator('.comment-menu')).toBeHidden();
  await expect(card.locator('.comment-more')).toHaveAttribute('aria-expanded', 'false');
  await expect(card.locator('.comment-delete-confirm')).toBeHidden();
  await card.locator('.comment-collapse-toggle').press('Tab');
  expect(await card.evaluate(el => !el.contains(document.activeElement))).toBe(true);
  await card.locator('.comment-collapse-toggle').click();
  await settleRegions(page);
  await expect(card.getByRole('button', { name: 'Confirm delete' })).toBeVisible();
});

test('missing-file discussions retain independent collapse and replies', async ({ page }) => {
  await installRenderProbe(page);
  await installApi(page, pullTarget(), { authenticated: true });
  await page.addInitScript(() => { window.__fake.reviewComments.forEach(c => { c.path = 'missing.mbt'; }); });
  await page.goto(reviewPath());
  const root = commentCard(page, 'review', 20);
  const reply = commentCard(page, 'review', 21);
  await expect(root).toBeVisible();
  await root.locator('.comment-collapse-toggle').click();
  await settleRegions(page);
  await assertSingleLine(root);
  await expect(reply.locator('.github-comment-content')).toBeVisible();
  await expect(page.locator('#comments .comment-reply-button').first()).toBeVisible();
  await page.getByRole('button', { name: 'Refresh', exact: true }).click();
  await settleRegions(page);
  await assertSingleLine(root);
});

test('manual collapse cancels queued footnote scrolling and yields focus to newer input', async ({ page }) => {
  const body = 'Note[^note].\n' + commentLines('Body', 30) + '\n\n[^note]: Footnote.';
  await ready(page, pullTarget(), { authenticated: true, inlineBody: body });
  const card = commentCard(page, 'review', 20);
  const editor = page.locator('.overall-comment-editor textarea');
  const barrier = await holdRegionFrames(page, ['file:src/main.mbt']);
  await card.locator('[role="doc-noteref"]').evaluate(el => el.click());
  await barrier.blocked();
  await card.locator('.comment-collapse-toggle').evaluate(el => el.click());
  await editor.focus();
  await editor.fill('Newer input');
  const position = await page.evaluate(() => scrollY);
  await barrier.release();
  await settleRegions(page);
  await assertSingleLine(card);
  await expect(editor).toBeFocused();
  expect(await page.evaluate(() => location.hash)).toBe('');
  expect(await page.evaluate(() => scrollY)).toBe(position);
});

test('collapse survives code-section placement changes and keeps reply entry usable', async ({ page }) => {
  await installRenderProbe(page);
  await installApi(page, pullTarget(), {
    authenticated: true,
    oldSource: 'let first = 11; let second = 22',
    newSource: 'let first = 33; let second = 44',
    patch: '@@ -1 +1 @@\n-let first = 11; let second = 22\n+let first = 33; let second = 44',
  });
  await page.addInitScript(() => {
    window.__fake.reviewComments = window.__fake.reviewComments.slice(0, 2).map(c => ({ ...c, line: 1, position: 2 }));
  });
  await page.goto(reviewPath());
  const sections = page.locator('details.semantic-section');
  await expect(sections).toHaveCount(2);
  const root = commentCard(page, 'review', 20);
  await root.locator('.comment-collapse-toggle').click();
  await sections.nth(0).locator('summary').click();
  await settleRegions(page);
  await assertSingleLine(root);
  await expect(sections.nth(1).locator('.review-thread')).toBeVisible();
  await sections.nth(1).locator('summary').click();
  await settleRegions(page);
  await assertSingleLine(root);
  await expect(page.locator('.file-discussions .review-thread')).toBeVisible();
  await root.locator('xpath=..').getByRole('button', { name: 'Reply', exact: true }).click();
  const editor = page.getByRole('textbox', { name: 'Write a reply', exact: true });
  await editor.fill('Reply to a collapsed comment');
  await sections.nth(0).locator('summary').click();
  await settleRegions(page);
  await assertSingleLine(root);
  await expect(editor).toHaveValue('Reply to a collapsed comment');
  await expect(editor).toBeVisible();
});

test('missing-file commit comments collapse while general commit comments stay expanded', async ({ page }) => {
  await installRenderProbe(page);
  await installApi(page, commitTarget());
  await page.addInitScript(() => {
    const original = window.__fake.commitComments[0];
    window.__fake.commitComments = [
      { ...original, path: 'missing.mbt' },
      { ...original, id: '31', path: null, body: 'General commit discussion' },
    ];
  });
  await page.goto(reviewPath(commitTarget()));
  const card = commentCard(page, 'commit', 30);
  await card.locator('.comment-collapse-toggle').click();
  await settleRegions(page);
  await assertSingleLine(card);
  await expect(commentCard(page, 'commit', 31).locator('.comment-collapse-toggle')).toHaveCount(0);
  await page.getByRole('button', { name: 'Refresh', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Refresh', exact: true })).toBeEnabled();
  await settleRegions(page);
  await assertSingleLine(card);
});
