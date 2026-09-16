import { test, expect } from '@playwright/test';
import { installRenderProbe, renderCounts, settleRegions } from '../../tests/render-probe.mjs';
import { holdRegionFrames } from './dom-timing.mjs';
import { gate, installRenderingFixture, navigate, syntheticFixture } from './rendering-fixture.mjs';

const card = (page, index) => page.locator(`#moondiff-file-${index}`);
const region = index => `file:${index ? `src/unrelated-${index}.mbt` : 'local_test.mbt'}`;
const fileRoute = fixture => `/example/regions/commit/${fixture.sha}`;

async function setup(page, algorithm, layout, options = {}) {
  await installRenderProbe(page);
  const fixture = syntheticFixture({ files: 5, declarations: 12 });
  await installRenderingFixture(page, fixture, options);
  await page.goto(fileRoute(fixture));
  await expect(page.locator('.file-card')).toHaveCount(fixture.files.length);
  if (!options.contentGate) await expect(page.locator('.loading-inline')).toHaveCount(0);
  await page.getByRole('button', { name: algorithm, exact: true }).click();
  await page.getByRole('button', { name: layout, exact: true }).click();
  await settleRegions(page);
  return fixture;
}

async function probeNavigation(page) {
  await page.evaluate(() => {
    window.scrollTo(0, 0);
    window.navigationEffects = [];
    const scrollIntoView = Element.prototype.scrollIntoView;
    Element.prototype.scrollIntoView = function (...args) {
      if (this.matches('.file-card')) navigationEffects.push(['file', this.id]);
      return scrollIntoView.apply(this, args);
    };
    const scrollTo = window.scrollTo;
    window.scrollTo = function (...args) {
      if (args[0]?.behavior === 'instant') navigationEffects.push(['change']);
      return scrollTo.apply(this, args);
    };
    const focus = HTMLElement.prototype.focus;
    HTMLElement.prototype.focus = function (...args) {
      if (this.matches('.file-toggle, .section-change-button')) {
        navigationEffects.push(['focus', this.closest('.file-card')?.id ?? this.dataset.changeDirection]);
      }
      return focus.apply(this, args);
    };
  });
}

async function effects(page) {
  await settleRegions(page);
  return page.evaluate(() => navigationEffects);
}

async function openFiles(page, indices) {
  await page.evaluate(indices => {
    for (const index of indices) {
      const path = index ? `src/unrelated-${index}.mbt` : 'local_test.mbt';
      document.querySelector(`[data-region="tree"] [aria-label="Open ${path}"]`).click();
    }
  }, indices);
}

async function expectFileLanding(page, index) {
  await expect.poll(() => card(page, index).evaluate(file => {
    const height = selector => document.querySelector(selector).getBoundingClientRect().height;
    const inset = height('.hero-workspace') + height('.change-titlebar') +
      parseFloat(getComputedStyle(document.documentElement).fontSize) / 2;
    const top = scrollY + file.getBoundingClientRect().top - inset;
    return Math.abs(scrollY - Math.max(0, Math.min(top, document.documentElement.scrollHeight - innerHeight)));
  })).toBeLessThanOrEqual(1);
}

async function expectChangeLanding(page, index) {
  const section = card(page, index).locator('.semantic-section').first();
  await expect(section).toHaveAttribute('open', '');
  await expect.poll(() => section.evaluate(section => {
    const height = selector => document.querySelector(selector).getBoundingClientRect().height;
    const inset = height('.hero-workspace') + height('.change-titlebar') +
      section.closest('.file-card').querySelector('.file-heading').getBoundingClientRect().height +
      section.querySelector('summary').getBoundingClientRect().height + 8;
    const top = scrollY + section.querySelector('[data-change-block-start]').getBoundingClientRect().top - inset;
    return Math.abs(scrollY - Math.max(0, Math.min(top, document.documentElement.scrollHeight - innerHeight)));
  })).toBeLessThanOrEqual(1);
}

async function expectUnrelated(page, before, fixture, changed) {
  const after = await renderCounts(page);
  for (const [index, file] of fixture.files.entries()) {
    if (!changed.includes(index)) expect(after.files[file.filename], file.filename).toEqual(before.files[file.filename]);
  }
  expect(after.errors).toEqual([]);
}

for (const algorithm of ['Token', 'Tree']) for (const layout of ['Split', 'Unified']) {
  test(`page commit: collapse above and open below in one frame, ${algorithm}/${layout}`, async ({ page }) => {
    const fixture = await setup(page, algorithm, layout);
    await probeNavigation(page);
    const before = await renderCounts(page);
    const barrier = await holdRegionFrames(page, [region(1)]);
    try {
      await page.evaluate(() => {
        document.querySelector('#moondiff-file-1 .file-toggle').click();
        document.querySelector('[aria-label="Open src/unrelated-2.mbt"]').click();
      });
      await barrier.blocked();
      expect(await effects(page)).toEqual([]);
    } finally { await barrier.release(); }
    await expectFileLanding(page, 2);
    expect(await effects(page)).toEqual([['file', 'moondiff-file-2']]);
    await expectUnrelated(page, before, fixture, [1]);
  });

  test(`page commit: expanded B supersedes pending collapsed A and its drawer focus, ${algorithm}/${layout}`, async ({ page }) => {
    await page.setViewportSize({ width: 420, height: 720 });
    const fixture = await setup(page, algorithm, layout);
    await card(page, 1).locator('.file-toggle').evaluate(el => el.click());
    await settleRegions(page);
    await page.locator('.file-tree-trigger').click();
    await expect(page.locator('.drawer-close')).toBeFocused();
    await probeNavigation(page);
    const before = await renderCounts(page);
    const barrier = await holdRegionFrames(page, [region(1)]);
    try {
      await openFiles(page, [1]);
      await barrier.blocked();
      // A is already waiting on its region when the unchanged B receives intent.
      await openFiles(page, [2]);
      expect(await effects(page)).toEqual([]);
    } finally { await barrier.release(); }
    await expectFileLanding(page, 2);
    expect(await effects(page)).toEqual([['file', 'moondiff-file-2']]);
    await expectUnrelated(page, before, fixture, [1]);
  });

  for (const order of [[1, 2], [2, 1]]) {
    test(`page commit: both targets update, release ${order.join(' then ')}, ${algorithm}/${layout}`, async ({ page }) => {
      const fixture = await setup(page, algorithm, layout);
      await page.evaluate(() => {
        for (const index of [1, 2]) document.querySelector(`#moondiff-file-${index} .file-toggle`).click();
      });
      await settleRegions(page);
      await probeNavigation(page);
      const before = await renderCounts(page);
      const barrier = await holdRegionFrames(page, [region(1), region(2)]);
      try {
        await openFiles(page, [1, 2]);
        await barrier.blocked();
        await barrier.release([region(order[0])]);
        await expect(card(page, order[0])).toHaveClass('file-card expanded');
        expect(await effects(page)).toEqual([]);
      } finally { await barrier.release(); }
      await expectFileLanding(page, 2);
      expect(await effects(page)).toEqual([['file', 'moondiff-file-2']]);
      await expectUnrelated(page, before, fixture, [1, 2]);
    });
  }

  for (const last of ['file', 'change']) {
    test(`page commit: interleaved navigation keeps latest ${last}, ${algorithm}/${layout}`, async ({ page }) => {
      const fixture = await setup(page, algorithm, layout);
      await page.evaluate(() => {
        document.querySelector('#moondiff-file-1 summary').click();
        document.querySelector('#moondiff-file-2 .file-toggle').click();
      });
      await settleRegions(page);
      await probeNavigation(page);
      const before = await renderCounts(page);
      const barrier = await holdRegionFrames(page, [region(1), region(2)]);
      try {
        await page.evaluate(last => {
          const file = () => document.querySelector('[aria-label="Open src/unrelated-2.mbt"]').click();
          const change = () => document.querySelector('[data-change-direction="1"]').click();
          if (last === 'file') { change(); file(); } else { file(); change(); }
        }, last);
        await barrier.blocked();
        await barrier.release([region(last === 'file' ? 2 : 1)]);
        expect(await effects(page)).toEqual([]);
      } finally { await barrier.release(); }
      if (last === 'file') {
        await expectFileLanding(page, 2);
        expect(await effects(page)).toEqual([['file', 'moondiff-file-2']]);
      } else {
        await expectChangeLanding(page, 1);
        expect(await effects(page)).toEqual([['change'], ['focus', '1']]);
        await expect(page.locator('[data-change-direction="1"]')).toBeFocused();
      }
      await expectUnrelated(page, before, fixture, [1, 2]);
    });
  }
}

test('page commit: later revisions and newly scheduled regions join the wait', async ({ page }) => {
  const fixture = await setup(page, 'Tree', 'Split');
  await probeNavigation(page);
  const before = await renderCounts(page);
  const barrier = await holdRegionFrames(page, [region(0), region(1)]);
  try {
    await card(page, 0).locator('.file-toggle').evaluate(el => el.click());
    await openFiles(page, [2]);
    await barrier.blocked([region(0)]);
    await page.evaluate(() => {
      document.querySelector('#moondiff-file-0 .file-toggle').click();
      document.querySelector('#moondiff-file-1 .file-toggle').click();
    });
    await barrier.blocked();
    await barrier.release([region(0)]);
    expect(await effects(page)).toEqual([]);
  } finally { await barrier.release(); }
  await expectFileLanding(page, 2);
  expect(await effects(page)).toEqual([['file', 'moondiff-file-2']]);
  await expectUnrelated(page, before, fixture, [0, 1]);
});

test('page commit: route switch cancels pending navigation and stale region callbacks', async ({ page }) => {
  await setup(page, 'Tree', 'Split');
  await card(page, 1).locator('.file-toggle').evaluate(el => el.click());
  await settleRegions(page);
  await probeNavigation(page);
  const barrier = await holdRegionFrames(page, [region(1)]);
  try {
    await openFiles(page, [1]);
    await barrier.blocked();
    await navigate(page, '/');
    await expect(page.locator('.hero-landing')).toBeVisible();
  } finally { await barrier.release(); }
  expect(await effects(page)).toEqual([]);
  const counts = await renderCounts(page);
  expect(counts.errors).toEqual([]);
  expect(counts.active).toMatchObject({ mounts: 2, stores: 2, subscriptions: 2, runtimeStores: 3, observers: 0 });
});

test('page commit: outstanding source requests do not delay navigation', async ({ page }) => {
  const pending = gate();
  try {
    await setup(page, 'Tree', 'Unified', { contentGate: { path: 'src/unrelated-1.mbt', ...pending } });
    await expect(card(page, 2).locator('table').first()).toBeVisible();
    await expect(card(page, 1)).toContainText('Loading file contents');
    await probeNavigation(page);
    await openFiles(page, [2]);
    await expectFileLanding(page, 2);
    expect(await effects(page)).toEqual([['file', 'moondiff-file-2']]);
    await expect(card(page, 1)).toContainText('Loading file contents');
  } finally { pending.resolve(); }
  await expect(page.locator('.loading-inline')).toHaveCount(0);
  expect(await effects(page)).toEqual([['file', 'moondiff-file-2']]);
});
