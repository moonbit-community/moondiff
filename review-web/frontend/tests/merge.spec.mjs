import { installClock } from '../../tests/browser-control.mjs';
import { waitForState, settleRegions, renderCounts, installRenderProbe } from '../../tests/render-probe.mjs';
import { expect, test } from '../../tests/browser-test.mjs';
import { gate, installRenderingFixture, syntheticFixture } from './rendering-fixture.mjs';

const path = '/example/regions/pull/1';

async function scrollMergeCard(page, gap = -1) {
  await settleRegions(page);
  const position = await page.locator('.pull-merge-card').evaluate((card, gap) => {
    const title = document.querySelector('.change-titlebar');
    const bottom = parseFloat(getComputedStyle(title).top) + title.getBoundingClientRect().height;
    window.scrollTo({ top: scrollY + card.getBoundingClientRect().bottom - bottom - gap, behavior: 'instant' });
    return scrollY;
  }, gap);
  await settleRegions(page);
  return position;
}

async function expectMergeSlot(page, inTitlebar) {
  await expect(page.locator('.change-titlebar .rebase-merge-button')).toHaveCSS('visibility', inTitlebar ? 'visible' : 'hidden');
  await expect(page.locator('.pull-merge-card .rebase-merge-button')).toHaveCSS('visibility', inTitlebar ? 'hidden' : 'visible');
  await expect(page.locator('.rebase-merge-button:visible')).toHaveCount(1);
  await expect(page.getByRole('button', { name: /Rebas(e and merge|ing and merging…)/ })).toHaveCount(1);
}

for (const width of [1440, 420, 320]) {
  test(`rebase follows the card boundary without moving layout or focus at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 });
    const fixture = syntheticFixture({ files: 2, declarations: 16 });
    fixture.message = 'A long pull request title with an_unbroken_identifier_that_wraps_inside_the_available_width';
    await installRenderingFixture(page, fixture, { authenticated: true });
    await page.goto(path);
    const card = page.locator('.pull-merge-card');
    const original = card.locator('.rebase-merge-button');
    const title = page.locator('.change-titlebar');
    const sticky = title.locator('.rebase-merge-button');
    await expect(original).toBeEnabled();
    await expect(page.locator('.loading-inline')).toHaveCount(0);
    await expectMergeSlot(page, false);
    await scrollMergeCard(page, await card.evaluate(el => el.getBoundingClientRect().height + 8));
    await expect(original).toBeInViewport();
    await original.evaluate(el => el.focus({ preventScroll: true }));
    await scrollMergeCard(page, 1);
    await expectMergeSlot(page, false);
    await expect(original).toBeFocused();
    const sizes = () => page.evaluate(() => ({
      card: document.querySelector('.pull-merge-card').getBoundingClientRect().height,
      title: document.querySelector('.change-titlebar').getBoundingClientRect().height,
      document: document.documentElement.scrollHeight,
    }));
    const before = await sizes();
    const down = await scrollMergeCard(page);
    await expectMergeSlot(page, true);
    await expect(sticky).toBeFocused();
    expect(await sizes()).toEqual(before);
    expect(await page.evaluate(() => scrollY)).toBe(down);
    // The hidden copy cannot steal focus, even through a direct DOM focus call.
    await original.evaluate(el => el.focus({ preventScroll: true }));
    await expect(sticky).toBeFocused();
    await title.getByRole('button', { name: 'Previous change', exact: true }).focus();
    await page.keyboard.press('Tab');
    await expect(title.getByRole('button', { name: 'Next change', exact: true })).toBeFocused();
    await page.keyboard.press('Tab');
    await expect(sticky).toBeFocused();
    const up = await scrollMergeCard(page, 1);
    await expectMergeSlot(page, false);
    await expect(original).toBeFocused();
    expect(await sizes()).toEqual(before);
    expect(await page.evaluate(() => scrollY)).toBe(up);
    await sticky.evaluate(el => el.focus({ preventScroll: true }));
    await expect(original).toBeFocused();

    await scrollMergeCard(page);
    expect(await title.evaluate(el => {
      const buttons = [...el.querySelectorAll('button')].map(button => button.getBoundingClientRect());
      return buttons.every((button, index) => button.left >= 0 && button.right <= innerWidth &&
        Math.abs(button.top + button.height / 2 - buttons[0].top - buttons[0].height / 2) < 1 &&
        (index === 0 || button.left >= buttons[index - 1].right));
    })).toBe(true);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    if (width <= 420) {
      expect(await title.evaluate(el => el.querySelector('.section-change-controls').getBoundingClientRect().top >=
        el.querySelector('.commit-message-title').getBoundingClientRect().bottom)).toBe(true);
    }
    const rows = page.locator('.file-card [data-change-block-start]');
    for (const [direction, index] of [['Next change', 0], ['Next change', 1], ['Previous change', 0]]) {
      await title.getByRole('button', { name: direction, exact: true }).click();
      await expect.poll(() => rows.nth(index).evaluate(row => {
        const file = row.closest('.file-card');
        const section = row.closest('.semantic-section');
        const bottom = document.querySelector('.change-titlebar').getBoundingClientRect().bottom +
          file.querySelector('.file-heading').getBoundingClientRect().height +
          section.querySelector('summary').getBoundingClientRect().height + 8;
        return Math.abs(row.getBoundingClientRect().top - bottom);
      })).toBeLessThanOrEqual(1);
      await expectMergeSlot(page, true);
    }
  });
}

test('rebase placement responds to CI height and window resize and releases its layout lifecycle', async ({ page }) => {
  await installRenderProbe(page);
  const fixture = syntheticFixture({ files: 2, declarations: 16 });
  await installRenderingFixture(page, fixture, {
    authenticated: true,
    mergeStatus: {
      base_sha: fixture.base, head_sha: fixture.sha, open: true, draft: false, merged: false,
      mergeable: true, rebaseable: true, mergeable_state: 'clean', ci_summary: { $tag: 'Success' },
      ci_checks: Array.from({ length: 4 }, (_, i) => ({ name: `Check ${i}`, state: { $tag: 'Success' }, description: 'Passed', source: { $tag: 'CheckRun' } })),
      ci_warnings: [],
    },
  });
  await page.goto(path);
  await expect(page.locator('.pull-merge-card .rebase-merge-button')).toBeEnabled();
  await expect(page.locator('.loading-inline')).toHaveCount(0);
  // Keep native anchoring from moving the viewport when the hidden disclosure grows.
  await page.evaluate(() => { document.documentElement.style.overflowAnchor = 'none'; });
  await scrollMergeCard(page, -8);
  const disclosure = page.locator('.pull-ci-disclosure');
  const position = await page.evaluate(() => scrollY);
  await disclosure.evaluate(el => { el.open = true; });
  await expectMergeSlot(page, false);
  expect(await page.evaluate(() => scrollY)).toBe(position);
  await disclosure.evaluate(el => { el.open = false; });
  await expectMergeSlot(page, true);
  expect(await page.evaluate(() => scrollY)).toBe(position);
  for (const width of [420, 960, 320, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    await settleRegions(page);
    const above = await page.evaluate(() => document.querySelector('.pull-merge-card').getBoundingClientRect().bottom <=
      document.querySelector('.change-titlebar').getBoundingClientRect().bottom);
    await expectMergeSlot(page, above);
    await scrollMergeCard(page);
    await expectMergeSlot(page, true);
    await scrollMergeCard(page, 1);
    await expectMergeSlot(page, false);
  }
  await page.locator('a.workspace-home').click();
  await expect(page.getByRole('tab').first()).toBeVisible();
  await settleRegions(page);
  const retired = await renderCounts(page);
  expect(retired.active.observers).toBe(0);
  await expect(page.locator('.rebase-merge-button')).toHaveCount(0);
  await page.evaluate(() => { dispatchEvent(new Event('scroll')); dispatchEvent(new Event('resize')); });
  await settleRegions(page);
  expect((await renderCounts(page)).layout).toEqual(retired.layout);
  expect((await renderCounts(page)).errors).toEqual([]);
});

test('the titlebar rebase submits once and both copies stay disabled until success', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 900 });
  const fixture = syntheticFixture({ files: 2, declarations: 16 });
  const mergeGate = gate();
  const state = await installRenderingFixture(page, fixture, { authenticated: true, mergeGate });
  await page.goto(path);
  await expect(page.locator('.pull-merge-card .rebase-merge-button')).toBeEnabled();
  await expect(page.locator('.loading-inline')).toHaveCount(0);
  await scrollMergeCard(page);
  const sticky = page.locator('.change-titlebar .rebase-merge-button');
  await expectMergeSlot(page, true);
  await sticky.evaluate(el => { el.click(); el.click(); });
  await expect.poll(() => state.calls.filter(call => call.op === 'github.pull.rebase.merge').length).toBe(1);
  for (const button of [sticky, page.locator('.pull-merge-card .rebase-merge-button')]) {
    await expect(button).toBeDisabled();
    await expect(button).toHaveText('Rebasing and merging…');
  }
  expect(state.calls.find(call => call.op === 'github.pull.rebase.merge').args).toMatchObject({
    expected_base_sha: fixture.base, expected_head_sha: fixture.sha,
  });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await scrollMergeCard(page, 1);
  await expectMergeSlot(page, false);
  await scrollMergeCard(page);
  await expectMergeSlot(page, true);
  mergeGate.resolve();
  await expect(page.locator('.pull-merge-card')).toContainText('✓ This pull request is merged.');
  await expect(page.locator('.rebase-merge-button')).toHaveCount(0);
  expect(state.calls.filter(call => call.op === 'github.pull.rebase.merge')).toHaveLength(1);
});

test('merge card shows aggregate CI and submits one pinned rebase merge', async ({ page }) => {
  const fixture = syntheticFixture({ files: 1, declarations: 2 });
  const mergeGate = gate();
  const state = await installRenderingFixture(page, fixture, {
    authenticated: true,
    mergeGate,
    mergeStatus: {
      base_sha: fixture.base,
      head_sha: fixture.sha,
      open: true,
      draft: false,
      merged: false,
      mergeable: true,
      rebaseable: true,
      mergeable_state: 'clean',
      ci_summary: { $tag: 'Failure' },
      ci_checks: [
        { name: 'MoonBit tests', state: { $tag: 'Failure' }, description: 'Native target failed', details_url: 'https://example.com/check/1', source: { $tag: 'CheckRun' } },
        { name: 'deploy', state: { $tag: 'Success' }, description: 'Preview is ready', source: { $tag: 'CommitStatus' } },
      ],
      ci_warnings: ['Commit statuses could not be read; CI results are incomplete.'],
    },
  });
  await page.goto(path);
  const card = page.locator('.pull-merge-card');
  await expect(card.getByRole('heading', { name: 'Merge status' })).toBeVisible();
  await expect(card.getByText('Some checks were not successful', { exact: true })).toBeVisible();
  await expect(card.getByText('1 failing and 1 successful checks', { exact: true })).toBeVisible();
  const checks = card.locator('.pull-ci-disclosure');
  const summary = checks.locator('summary');
  const toggle = card.locator('.pull-ci-toggle');
  const chevron = card.locator('.pull-ci-chevron');
  const chevronAngle = () => chevron.evaluate(element => {
    const matrix = new DOMMatrixReadOnly(getComputedStyle(element).transform);
    return Math.round(Math.atan2(matrix.b, matrix.a) * 180 / Math.PI);
  });
  await expect(checks).toHaveJSProperty('open', false);
  await expect(summary).toHaveCSS('user-select', 'none');
  expect(await toggle.evaluate(element => parseFloat(getComputedStyle(element).fontSize))).toBeGreaterThanOrEqual(13);
  expect(await chevronAngle()).toBe(-45);
  await expect(card.getByText('MoonBit tests', { exact: true })).toBeHidden();
  await expect(card.getByText('Commit statuses could not be read; CI results are incomplete.', { exact: true })).toBeVisible();
  await card.getByText('Show all checks', { exact: true }).click();
  await expect(checks).toHaveJSProperty('open', true);
  await expect.poll(chevronAngle).toBe(45);
  await expect(card.getByText('Hide all checks', { exact: true })).toBeVisible();
  await expect(card.getByText('MoonBit tests', { exact: true })).toBeVisible();
  await expect(card.getByRole('link', { name: 'View MoonBit tests CI job' })).toHaveAttribute('href', 'https://example.com/check/1');
  await summary.focus();
  await summary.press('Enter');
  await expect(checks).toHaveJSProperty('open', false);
  await expect.poll(chevronAngle).toBe(-45);
  await summary.press('Space');
  await expect(checks).toHaveJSProperty('open', true);
  await expect.poll(chevronAngle).toBe(45);
  expect(await page.locator('.comments-overview, .pull-merge-card, .file-card').evaluateAll(nodes => nodes.map(node => node.className))).toEqual([
    'comments-overview', 'pull-merge-card', expect.stringContaining('file-card'),
  ]);

  const merge = card.getByRole('button', { name: 'Rebase and merge', exact: true });
  await merge.evaluate(button => { button.click(); button.click(); });
  await expect(card.getByRole('button', { name: 'Rebasing and merging…', exact: true })).toBeDisabled();
  await expect.poll(() => state.calls.filter(call => call.op === 'github.pull.rebase.merge').length).toBe(1);
  expect(state.calls.find(call => call.op === 'github.pull.rebase.merge').args).toEqual({
    owner: 'example', repo: 'regions', number: '1',
    expected_base_sha: fixture.base, expected_head_sha: fixture.sha,
  });
  mergeGate.resolve();
  await expect(card.getByText('✓ This pull request is merged.', { exact: true })).toBeVisible();
  await expect(card.getByRole('button', { name: 'Rebase and merge', exact: true })).toHaveCount(0);
});

test('anonymous merge card requires sign-in and never calls the protected status RPC', async ({ page }) => {
  const fixture = syntheticFixture({ files: 1, declarations: 1 });
  await page.addInitScript(() => {
    let active = true;
    document.hasFocus = () => active;
    window.reactivate = () => {
      active = false; dispatchEvent(new Event('blur'));
      active = true; dispatchEvent(new Event('focus'));
    };
  });
  const state = await installRenderingFixture(page, fixture);
  await page.goto(path);
  const card = page.locator('.pull-merge-card');
  await expect(card.getByText('Sign in to load CI and merge status', { exact: true })).toBeVisible();
  await expect(card.getByRole('button', { name: 'Sign in to merge', exact: true })).toBeVisible();
  expect(state.calls.filter(call => call.op === 'github.pull.merge.status')).toHaveLength(0);
  await expect.poll(() => state.authStatusCalls).toBe(1);
  const authStatusCalls = state.authStatusCalls;
  await page.evaluate(() => window.reactivate());
  await expect.poll(() => state.authStatusCalls).toBe(authStatusCalls + 1);
  expect(state.calls.filter(call => call.op === 'github.pull.merge.status')).toHaveLength(0);
});

test('conflicts and repository rules never expose an enabled merge action', async ({ page }) => {
  const fixture = syntheticFixture({ files: 1, declarations: 1 });
  const state = await installRenderingFixture(page, fixture, {
    authenticated: true,
    mergeStatus: {
      base_sha: fixture.base,
      head_sha: fixture.sha,
      open: true,
      draft: false,
      merged: false,
      mergeable: false,
      rebaseable: false,
      mergeable_state: 'dirty',
      ci_summary: { $tag: 'Success' },
      ci_checks: [],
      ci_warnings: [],
    },
  });
  await page.goto(path);
  const card = page.locator('.pull-merge-card');
  await expect(card.getByText('× This branch has conflicts that must be resolved before rebasing.', { exact: true })).toBeVisible();
  await expect(page.locator('.rebase-merge-button')).toHaveCount(0);
  expect(state.calls.filter(call => call.op === 'github.pull.rebase.merge')).toHaveLength(0);
});

test('repository rules keep the rebase action disabled in either position', async ({ page }) => {
  const fixture = syntheticFixture({ files: 2, declarations: 16 });
  const state = await installRenderingFixture(page, fixture, {
    authenticated: true,
    mergeStatus: {
      base_sha: fixture.base, head_sha: fixture.sha, open: true, draft: false, merged: false,
      mergeable: true, rebaseable: true, mergeable_state: 'blocked', ci_checks: [], ci_warnings: [],
    },
  });
  await page.goto(path);
  await expect(page.locator('.pull-merge-card')).toContainText('Repository rules currently block this merge.');
  await expect(page.locator('.pull-merge-card .rebase-merge-button')).toBeDisabled();
  await expect(page.locator('.loading-inline')).toHaveCount(0);
  await scrollMergeCard(page);
  await expectMergeSlot(page, true);
  await expect(page.locator('.change-titlebar .rebase-merge-button')).toBeDisabled();
  await expect(page.locator('.change-titlebar')).not.toContainText('Repository rules');
  expect(state.calls.filter(call => call.op === 'github.pull.rebase.merge')).toHaveLength(0);
});

test('pending CI polls into a successful status', async ({ page }) => {
  const clock = await installClock(page);
  const fixture = syntheticFixture({ files: 1, declarations: 1 });
  let statusCalls = 0;
  const state = await installRenderingFixture(page, fixture, {
    authenticated: true,
    mergeStatus: () => {
      const pending = statusCalls++ === 0;
      return {
        base_sha: fixture.base,
        head_sha: fixture.sha,
        open: true,
        draft: false,
        merged: false,
        mergeable: true,
        rebaseable: true,
        mergeable_state: 'clean',
        ci_summary: { $tag: pending ? 'Pending' : 'Success' },
        ci_checks: [{
          name: 'MoonBit tests',
          state: { $tag: pending ? 'Pending' : 'Success' },
          description: pending ? 'Running' : 'Passed',
          source: { $tag: 'CheckRun' },
        }],
        ci_warnings: [],
      };
    },
  });
  await page.goto(path);
  await waitForState(page, state => state.application?.merge.pollScheduled, 'pending CI poll scheduled');
  const card = page.locator('.pull-merge-card');
  await expect(card.getByText('Some checks haven’t completed yet', { exact: true })).toBeVisible();
  await expect(card.getByText('1 in progress check', { exact: true })).toBeVisible();
  const timer = await clock.timer(2000);
  await clock.before(timer);
  expect(statusCalls).toBe(1);
  await clock.fire(timer);
  await clock.until(() => card.getByText('All checks have passed', { exact: true }).isVisible(), 'successful CI poll rendered');
  await expect(card.getByText('1 successful check', { exact: true })).toBeVisible();
  expect(state.calls.filter(call => call.op === 'github.pull.merge.status')).toHaveLength(2);
});

test('a changed snapshot offers Load latest and hides merge', async ({ page }) => {
  const fixture = syntheticFixture({ files: 1, declarations: 1 });
  await installRenderingFixture(page, fixture, {
    authenticated: true,
    mergeStatus: {
      base_sha: fixture.base,
      head_sha: 'd'.repeat(40),
      open: true,
      draft: false,
      merged: false,
      mergeable: true,
      rebaseable: true,
      mergeable_state: 'clean',
      ci_summary: { $tag: 'Success' },
      ci_checks: [],
      ci_warnings: [],
    },
  });
  await page.goto(path);
  const card = page.locator('.pull-merge-card');
  await expect(card.getByText('This PR snapshot is out of date. Load the latest changes before merging.', { exact: true })).toBeVisible();
  await expect(card.getByRole('button', { name: 'Reload PR for merge', exact: true })).toBeVisible();
  await expect(card.getByRole('button', { name: 'Rebase and merge', exact: true })).toHaveCount(0);
});

test('a snapshot change during merge offers Load latest without showing a conflict', async ({ page }) => {
  const fixture = syntheticFixture({ files: 2, declarations: 16 });
  const state = await installRenderingFixture(page, fixture, {
    authenticated: true,
    mergeFailure: { status: 409, code: 'pull_snapshot_changed', message: 'This pull request changed.' },
  });
  await page.goto(path);
  const card = page.locator('.pull-merge-card');
  await expect(card.locator('.rebase-merge-button')).toBeEnabled();
  await expect(page.locator('.loading-inline')).toHaveCount(0);
  await scrollMergeCard(page);
  await page.locator('.change-titlebar').getByRole('button', { name: 'Rebase and merge', exact: true }).click();
  await expect(card.getByText('This PR snapshot is out of date. Load the latest changes before merging.', { exact: true })).toBeVisible();
  await expect(card.getByText('Load latest', { exact: true })).toBeVisible();
  await expect(page.locator('.rebase-merge-button')).toHaveCount(0);
  await expect(page.locator('.change-titlebar')).not.toContainText('Load latest');
  await expect(card.getByText('× This branch has conflicts that must be resolved before rebasing.', { exact: true })).toHaveCount(0);
  expect(state.calls.filter(call => call.op === 'github.pull.rebase.merge')).toHaveLength(1);
});

test('a failed merge stays retryable and a retry succeeds', async ({ page }) => {
  const fixture = syntheticFixture({ files: 2, declarations: 16 });
  const state = await installRenderingFixture(page, fixture, {
    authenticated: true,
    mergeFailure: { status: 503, code: 'merge_upstream_failure', message: 'GitHub could not complete the rebase merge.' },
  });
  await page.goto(path);
  const card = page.locator('.pull-merge-card');
  await expect(card.locator('.rebase-merge-button')).toBeEnabled();
  await expect(page.locator('.loading-inline')).toHaveCount(0);
  await scrollMergeCard(page);
  const sticky = page.locator('.change-titlebar').getByRole('button', { name: 'Rebase and merge', exact: true });
  await sticky.click();
  await expect(card.getByText('GitHub could not complete the rebase merge. Try again.', { exact: true })).toBeVisible();
  await expect(page.locator('.change-titlebar')).not.toContainText('GitHub could not complete');
  await scrollMergeCard(page);
  await expect(sticky).toBeEnabled();
  await sticky.click();
  await expect(card.getByText('✓ This pull request is merged.', { exact: true })).toBeVisible();
  await expect(page.locator('.rebase-merge-button')).toHaveCount(0);
  expect(state.calls.filter(call => call.op === 'github.pull.rebase.merge')).toHaveLength(2);
});


test('navigating away cancels the effect of a pending CI poll', async ({ page }) => {
  const clock = await installClock(page);
  const fixture = syntheticFixture({ files: 1, declarations: 1 });
  const state = await installRenderingFixture(page, fixture, { authenticated: true,
    mergeStatus: { base_sha: fixture.base, head_sha: fixture.sha, open: true, draft: false,
      merged: false, mergeable: true, rebaseable: true, mergeable_state: 'clean',
      ci_summary: { $tag: 'Pending' }, ci_checks: [], ci_warnings: [] },
  });
  await page.goto(path);
  await waitForState(page, state => state.application?.merge.pollScheduled, 'CI poll scheduled');
  await page.locator('a.workspace-home').click();
  await clock.until(() => page.getByRole('tab').first().isVisible(), 'navigation committed');
  await clock.jump(120_000);
  await settleRegions(page);
  expect(state.calls.filter(call => call.op === 'github.pull.merge.status')).toHaveLength(1);
});
