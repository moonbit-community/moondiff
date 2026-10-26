import { expect, test } from '../../tests/browser-test.mjs';
import { setup, gate, failure, row } from './home-fixture.mjs';
import { successFixture } from '../../tests/protocol-fixtures.mjs';
import { installRenderingFixture, syntheticFixture } from './rendering-fixture.mjs';
import { installRenderProbe, settleRegions } from '../../tests/render-probe.mjs';

test('drafts survive SPA history with new editor identities and disappear after reload', async ({ page }) => {
  await setup(page);
  await page.goto('/');
  const documentId = await page.evaluate(() => window.dashboardDocumentId);
  await row(page, 'Pull request 3').getByRole('link').click();
  await page.getByRole('button', { name: 'Add overall comment' }).click();
  await page.locator('.comment-editor textarea').fill('Remember this route');
  await page.getByRole('link', { name: /Moondiff/ }).click();
  await expect(page.getByRole('tab').first()).toBeVisible();
  await page.goBack();
  await expect(page.locator('.comment-editor textarea')).toHaveValue('Remember this route');
  expect(await page.evaluate(() => window.dashboardDocumentId)).toBe(documentId);
  await page.reload();
  await expect(page.getByRole('button', { name: 'Add overall comment' })).toBeVisible();
  await expect(page.locator('.comment-editor textarea')).toHaveCount(0);
});

for (const failed of [false, true]) test(`history navigation during a comment write ${failed ? 'stays on failure' : 'replays after success'}`, async ({ page }) => {
  const writing = gate();
  await setup(page, async ({ route, kind }) => {
    if (kind !== 'IssueCommentCreate') return false;
    await writing.promise;
    await route.fulfill(failed ? failure('network_error', 'Fixture write failed') : { json: successFixture('github.issue.comment.create', {
      id: 91, created_at: '2026-09-01T00:00:00Z', body: 'Frozen body', html_url: 'https://github.com/upstream/repo/pull/3#issuecomment-91', user: { login: 'alice' },
    }) });
    return true;
  });
  await page.goto('/');
  await row(page, 'Pull request 3').getByRole('link').click();
  await page.getByRole('button', { name: 'Add overall comment' }).click();
  await page.locator('.comment-editor textarea').fill('Frozen body');
  await page.getByRole('button', { name: 'Post comment' }).click();
  await page.goBack();
  await expect(page).toHaveURL(/\/pull\/3$/);
  await expect(page.locator('.comment-editor textarea')).toHaveValue('Frozen body');
  writing.release();
  if (failed) {
    await expect(page.locator('.comment-editor')).toContainText('Fixture write failed');
    await expect(page).toHaveURL(/\/pull\/3$/);
  } else {
    await expect(page).toHaveURL(/\/$/);
    await page.goForward();
    await expect(page.getByText('Frozen body', { exact: true })).toBeVisible();
    await expect(page.locator('.comment-editor textarea')).toHaveCount(0);
  }
});

test('history restores page and sidebar scroll, focus, file folding and filters after layout', async ({ page }) => {
  await installRenderProbe(page);
  const data = syntheticFixture({ files: 28, declarations: 4 });
  await installRenderingFixture(page, data);
  await page.goto(`/example/regions/commit/${data.sha}`);
  await expect(page.locator('.file-card')).toHaveCount(28);
  await expect(page.locator('.loading-inline')).toHaveCount(0);
  await page.locator('#moondiff-file-1 .file-toggle').click();
  await page.getByRole('checkbox', { name: 'Ignore comments', exact: true }).uncheck();
  await settleRegions(page);
  const before = await page.evaluate(() => {
    document.querySelector('#moondiff-file-7 .file-toggle').focus({ preventScroll: true });
    document.querySelector('.file-tree-scroll').scrollTop = 110;
    scrollTo(0, 1800);
    return { y: scrollY, sidebar: document.querySelector('.file-tree-scroll').scrollTop };
  });
  await page.locator('a.workspace-home').evaluate(link => link.click());
  await expect(page.locator('.hero-landing')).toBeVisible();
  await page.goBack();
  await expect(page.locator('.loading-inline')).toHaveCount(0);
  await expect(page.locator('#moondiff-file-1')).toHaveClass('file-card');
  await expect(page.getByRole('checkbox', { name: 'Ignore comments', exact: true })).not.toBeChecked();
  await settleRegions(page);
  await expect(page.locator('#moondiff-file-7 .file-toggle')).toBeFocused();
  await expect.poll(() => page.evaluate(() => scrollY)).toBe(before.y);
  await expect.poll(() => page.locator('.file-tree-scroll').evaluate(el => el.scrollTop)).toBe(before.sidebar);
});
