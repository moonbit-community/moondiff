import { expect, test } from '@playwright/test';
import { gate, installRenderingFixture, syntheticFixture } from './rendering-fixture.mjs';

const path = '/example/regions/pull/1';

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
  await expect(card.getByRole('button', { name: 'Rebase and merge', exact: true })).toHaveCount(0);
  expect(state.calls.filter(call => call.op === 'github.pull.rebase.merge')).toHaveLength(0);
});

test('pending CI polls into a successful status', async ({ page }) => {
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
  const card = page.locator('.pull-merge-card');
  await expect(card.getByText('Some checks haven’t completed yet', { exact: true })).toBeVisible();
  await expect(card.getByText('1 in progress check', { exact: true })).toBeVisible();
  await expect(card.getByText('All checks have passed', { exact: true })).toBeVisible({ timeout: 4_500 });
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
  const fixture = syntheticFixture({ files: 1, declarations: 1 });
  const state = await installRenderingFixture(page, fixture, {
    authenticated: true,
    mergeFailure: { status: 409, code: 'pull_snapshot_changed', message: 'This pull request changed.' },
  });
  await page.goto(path);
  const card = page.locator('.pull-merge-card');
  await card.getByRole('button', { name: 'Rebase and merge', exact: true }).click();
  await expect(card.getByText('This PR snapshot is out of date. Load the latest changes before merging.', { exact: true })).toBeVisible();
  await expect(card.getByText('Load latest', { exact: true })).toBeVisible();
  await expect(card.getByRole('button', { name: 'Rebase and merge', exact: true })).toHaveCount(0);
  await expect(card.getByText('× This branch has conflicts that must be resolved before rebasing.', { exact: true })).toHaveCount(0);
  expect(state.calls.filter(call => call.op === 'github.pull.rebase.merge')).toHaveLength(1);
});

test('a failed merge stays retryable and a retry succeeds', async ({ page }) => {
  const fixture = syntheticFixture({ files: 1, declarations: 1 });
  const state = await installRenderingFixture(page, fixture, {
    authenticated: true,
    mergeFailure: { status: 503, code: 'merge_upstream_failure', message: 'GitHub could not complete the rebase merge.' },
  });
  await page.goto(path);
  const card = page.locator('.pull-merge-card');
  await card.getByRole('button', { name: 'Rebase and merge', exact: true }).click();
  await expect(card.getByText('GitHub could not complete the rebase merge. Try again.', { exact: true })).toBeVisible();
  await expect(card.getByRole('button', { name: 'Rebase and merge', exact: true })).toBeEnabled();
  await card.getByRole('button', { name: 'Rebase and merge', exact: true }).click();
  await expect(card.getByText('✓ This pull request is merged.', { exact: true })).toBeVisible();
  expect(state.calls.filter(call => call.op === 'github.pull.rebase.merge')).toHaveLength(2);
});
