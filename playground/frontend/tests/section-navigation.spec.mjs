import { expect, test } from "@playwright/test";
import { anonymousApi, routeGithub } from "./api-routes.mjs";

const sha = "3333333333333333333333333333333333333333";
const parent = "1111111111111111111111111111111111111111";
const longName = `navigate_${"long_declaration_".repeat(12)}`;
const marker = "[data-change-block-start]";
const button = (page, direction) => page.locator(".change-titlebar").getByRole("button", {
  name: direction > 0 ? "Next change" : "Previous change", exact: true,
});

function declaration(name, version, groups = 3) {
  const lines = [`fn ${name}() {`];
  for (let group = 0; group < groups; group++) {
    for (let line = 0; line < 12; line++) lines.push(`  ${version}_call_${group}_${line}()`);
    if (group + 1 < groups) {
      // The first two changes share a hunk; the third is separated by context.
      for (let line = 0; line < (group === 0 ? 2 : 20); line++) lines.push(`  stable_${group}_${line}()`);
    }
  }
  return [...lines, "}"].join("\n");
}

async function loadNavigation(page, { layout = "Split", algorithm = "Tree", width = 1440, single = false, trailingFile = true, leadingAddition = false, message = "Navigate individual changes across declarations", extraFiles = [] } = {}) {
  await page.setViewportSize({ width, height: 720 });
  await anonymousApi(page);
  const source = version => single
    ? declaration("single_change", version, 1)
    : [
      ...(leadingAddition && version === "new" ? [declaration("added_section", "added", 1)] : []),
      declaration(longName, version),
      declaration("second_section", version),
      declaration("single_change", version, 1),
      ...(version === "old" ? [declaration("deleted_section", "removed", 1)] : []),
    ].join("\n\n");
  const files = [{ filename: "navigation.mbt", status: "modified", additions: 84, deletions: 98, changes: 182 }];
  if (trailingFile) files.push({ filename: "other.mbt", status: "modified", additions: 36, deletions: 36, changes: 72 });
  files.push(...extraFiles.map(file => ({ status: "modified", additions: 1, deletions: 1, changes: 2, ...file })));
  await routeGithub(page, "api", route => route.fulfill({
    body: JSON.stringify({
      sha,
      html_url: `https://github.com/example/navigation/commit/${sha}`,
      commit: { message },
      parents: [{ sha: parent }],
      stats: { additions: 120, deletions: 134, total: 254 },
      files,
    }),
  }));
  await routeGithub(page, "content", route => {
    const url = route.request().url();
    const version = url.includes(parent) ? "old" : "new";
    return route.fulfill({
      contentType: "text/plain",
      body: extraFiles.find(file => url.includes(file.filename))?.[version] ?? (url.includes("other.mbt") ? declaration("other_file", version) : source(version)),
    });
  });
  await page.goto(`/example/navigation/commit/${sha}`);
  await expect(page.locator("table.split").first()).toBeVisible();
  await page.getByRole("button", { name: algorithm, exact: true }).click();
  if (layout === "Unified") await page.getByRole("button", { name: layout, exact: true }).click();
  const sections = page.locator("#moondiff-file-0 details.semantic-section");
  const blockCounts = single ? [1] : [...(leadingAddition ? [1] : []), 3, 3, 1, 1];
  await expect(sections).toHaveCount(blockCounts.length);
  for (const [index, count] of blockCounts.entries()) {
    await expect(sections.nth(index).locator(marker)).toHaveCount(count);
  }
  if (trailingFile) await expect(page.locator("#moondiff-file-1").locator(marker)).toHaveCount(3);
  await page.evaluate(() => window.scrollTo(0, 0));
  return sections;
}

// Native scrolling is independent of the navigation handler.
async function readChange(section, index, extra = 0) {
  await section.evaluate((element, { index, extra }) => {
    const summary = element.querySelector("summary");
    const inset = parseFloat(getComputedStyle(summary).top) + summary.getBoundingClientRect().height;
    const row = element.querySelectorAll("[data-change-block-start]")[index];
    window.scrollTo(0, window.scrollY + row.getBoundingClientRect().top - inset - 8 + extra);
  }, { index, extra });
}

async function expectLanding(section, index) {
  await expect(section).toHaveAttribute("open", "");
  await expect.poll(() => section.evaluate((element, index) => {
    const height = selector => document.querySelector(selector).getBoundingClientRect().height;
    const inset = height(".hero-workspace") + height(".change-titlebar") +
      element.closest(".file-card").querySelector(".file-heading").getBoundingClientRect().height +
      element.querySelector("summary").getBoundingClientRect().height + 8;
    const top = scrollY + element.querySelectorAll("[data-change-block-start]")[index].getBoundingClientRect().top - inset;
    return Math.abs(scrollY - Math.max(0, Math.min(top, document.documentElement.scrollHeight - innerHeight)));
  }, index)).toBeLessThanOrEqual(1);
  expect(await section.evaluate((element, index) => {
    const title = document.querySelector(".change-titlebar").getBoundingClientRect();
    const heading = element.closest(".file-card").querySelector(".file-heading").getBoundingClientRect();
    const summary = element.querySelector("summary").getBoundingClientRect();
    const row = element.querySelectorAll("[data-change-block-start]")[index].getBoundingClientRect();
    return title.top >= document.querySelector(".hero-workspace").getBoundingClientRect().bottom - 1 &&
      heading.top >= title.bottom - 1 && summary.top >= heading.bottom - 1 && row.top >= summary.bottom - 1;
  }, index)).toBe(true);
}

async function expectNoMovement(page, action) {
  const before = await page.evaluate(() => window.scrollY);
  await action();
  expect(await page.evaluate(() => window.scrollY)).toBe(before);
}

for (const algorithm of ["Token", "Tree"]) {
  for (const layout of ["Split", "Unified"]) {
    for (const width of [1440, 420]) {
      test(`${algorithm} ${layout} ${width}px: first Next lands on a leading added declaration`, async ({ page }) => {
        const sections = await loadNavigation(page, { algorithm, layout, width, leadingAddition: true });
        const first = sections.nth(0);
        const second = sections.nth(1);
        await expect(first.locator(".semantic-section-label")).toContainText("added_section");
        await expect(second.locator(".semantic-section-label")).toContainText(longName);
        expect(await page.evaluate(() => window.scrollY)).toBe(0);

        await button(page, 1).click();
        await expectLanding(first, 0);
        const firstScroll = await page.evaluate(() => window.scrollY);
        expect(firstScroll).toBeGreaterThan(0);

        await button(page, 1).click();
        await expectLanding(second, 0);
        expect(await page.evaluate(() => window.scrollY)).toBeGreaterThan(firstScroll);

        await button(page, -1).click();
        await expectLanding(first, 0);
        expect(Math.abs(await page.evaluate(() => window.scrollY) - firstScroll)).toBeLessThanOrEqual(1);
      });
    }

    test(`${algorithm} ${layout}: first change, manual scroll, both directions across sections and file boundaries`, async ({ page }) => {
      const sections = await loadNavigation(page, { algorithm, layout });
      const first = sections.nth(0);
      await expect(page.locator(".change-titlebar .section-change-button")).toHaveCount(2);
      await expect(page.locator(".file-heading .section-change-button")).toHaveCount(0);
      await expect(sections.locator(".section-change-controls")).toHaveCount(0);
      await expect(button(page, 1)).toHaveText("↓ next");
      await expect(button(page, -1)).toHaveText("↑ prev");
      await expect(button(page, 1)).toHaveAttribute("title", "Next change");
      await expect(button(page, -1)).toHaveAttribute("title", "Previous change");
      expect(await first.locator(marker).evaluateAll(rows => rows.every(row => row.querySelector(".line-number") && !row.querySelector(".hunk-header")))).toBe(true);
      expect(await first.locator(".hunk-header").count()).toBeLessThan(3);
      const other = page.locator("#moondiff-file-1 .semantic-section");
      // First Previous wraps to the final block, then Next wraps back to the first.
      await button(page, -1).click();
      await expectLanding(other, 2);
      await button(page, 1).click();
      await expectLanding(first, 0);
      await button(page, 1).click();
      await expectLanding(first, 1);
      await button(page, 1).click();
      await expectLanding(first, 2);
      await button(page, 1).click();
      await expectLanding(sections.nth(1), 0);
      await expect(button(page, 1)).toBeFocused();
      await button(page, -1).click();
      await expectLanding(first, 2);
      await expect(button(page, -1)).toBeFocused();

      await readChange(first, 1, 60);
      await button(page, 1).click();
      await expectLanding(first, 2);
      await readChange(first, 1, 90);
      await button(page, -1).click();
      await expectLanding(first, 0);
      await button(page, -1).click();
      await expectLanding(other, 2);

      // The final deleted declaration is part of this file's navigation order.
      await readChange(sections.nth(2), 0);
      await button(page, 1).click();
      await expectLanding(sections.nth(3), 0);
      await button(page, 1).click();
      await expectLanding(other, 0);
      await expect(button(page, 1)).toBeFocused();
      await button(page, -1).click();
      await expectLanding(sections.nth(3), 0);
    });

    test(`${algorithm} ${layout}: collapsed targets expand and continuous keyboard navigation follows focus`, async ({ page }) => {
      const sections = await loadNavigation(page, { algorithm, layout });
      const first = sections.nth(0);
      const second = sections.nth(1);
      const secondKey = await second.getAttribute("data-section-key");
      await second.locator(".semantic-section-label").click();
      await expect(second).not.toHaveAttribute("open", "");
      await expect(button(page, 1)).toBeEnabled();
      await expect(button(page, -1)).toBeEnabled();
      await readChange(first, 2);
      await button(page, 1).focus();
      await page.keyboard.press("Enter");
      await expectLanding(second, 0);
      await expect(button(page, 1)).toBeFocused();
      await page.keyboard.press("Space");
      await expectLanding(second, 1);
      await page.keyboard.press("Enter");
      await expectLanding(second, 2);
      await page.keyboard.press("Space");
      await expectLanding(sections.nth(2), 0);
      await expect(button(page, 1)).toBeFocused();
      await page.keyboard.press("Shift+Tab");
      await expect(button(page, -1)).toBeFocused();
      await page.keyboard.press("Enter");
      await expectLanding(second, 2);
      await page.keyboard.press("Space");
      await expectLanding(second, 1);

      await first.locator(".semantic-section-label").click();
      await expect(first).not.toHaveAttribute("open", "");
      await readChange(second, 0);
      await button(page, -1).click();
      await expectLanding(first, 2);
      for (const nextLayout of [layout === "Split" ? "Unified" : "Split", layout]) {
        await page.getByRole("button", { name: nextLayout, exact: true }).click();
        await expect(first).toHaveAttribute("open", "");
        await expect(second).toHaveAttribute("open", "");
        await expect(second).toHaveAttribute("data-section-key", secondKey);
        await readChange(first, 1);
        await button(page, 1).click();
        await expectLanding(first, 2);
      }
    });

    test(`${algorithm} ${layout}: a single global target stays navigable`, async ({ page }) => {
      const sections = await loadNavigation(page, { algorithm, layout, single: true, trailingFile: false });
      const section = sections.first();
      await expect(button(page, -1)).toBeEnabled();
      await expect(button(page, 1)).toBeEnabled();
      await section.locator("summary").click();
      await expect(section).not.toHaveAttribute("open", "");
      await expect(button(page, 1)).toBeEnabled();
      await button(page, 1).click();
      await expectLanding(section, 0);
      await expectNoMovement(page, () => button(page, 1).click());
      await expectNoMovement(page, () => button(page, -1).click());
    });

    test(`${algorithm} ${layout}: narrow long titles and arrow hover keep stable dimensions`, async ({ page }) => {
      const sections = await loadNavigation(page, { algorithm, layout, width: 420, trailingFile: false });
      const first = sections.nth(0);
      await readChange(first, 0);
      const previous = button(page, -1);
      const next = button(page, 1);
      const metrics = await first.locator(".semantic-section-label").evaluate(element => ({
        height: element.getBoundingClientRect().height,
        lineHeight: parseFloat(getComputedStyle(element).lineHeight),
        right: element.getBoundingClientRect().right,
      }));
      expect(metrics.height).toBeGreaterThan(metrics.lineHeight * 2);
      const filename = await page.locator(".commit-message-title").boundingBox();
      const previousRect = await previous.boundingBox();
      expect(filename.x + filename.width).toBeLessThan(previousRect.x);
      expect(previousRect.x - filename.x - filename.width).toBeCloseTo(32, 1);
      expect(Math.abs(filename.y + filename.height / 2 - previousRect.y - previousRect.height / 2)).toBeLessThan(1);
      expect((await next.boundingBox()).x + (await next.boundingBox()).width).toBeLessThanOrEqual(420);
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(420);
      await page.mouse.move(0, 0);
      await expect(next).toHaveCSS("color", "rgb(0, 0, 0)");
      await expect(next).toHaveCSS("font-weight", "400");
      const size = await next.boundingBox();
      await next.hover();
      await expect(next).toHaveCSS("color", "rgb(9, 105, 218)");
      await expect(next).toHaveCSS("font-weight", "700");
      expect((await next.boundingBox()).width).toBe(size.width);
      expect((await next.boundingBox()).height).toBe(size.height);
      await next.focus();
      await page.keyboard.press("Shift+Tab");
      await expect(previous).toBeFocused();
      await expect(previous).toHaveCSS("outline-style", "solid");
      await page.keyboard.press("Tab");
      await expect(next).toBeFocused();
      await page.keyboard.press("Enter");
      await expectLanding(first, 1);
      await page.keyboard.press("Space");
      await expectLanding(first, 2);
      await page.keyboard.press("Enter");
      await expectLanding(sections.nth(1), 0);
      await expect(button(page, 1)).toBeFocused();
      await page.locator("#moondiff-file-0 .file-toggle").click();
      await expect(next).toBeDisabled();
      await next.hover();
      await expect(next).toHaveCSS("color", "rgb(0, 0, 0)");
      await expect(next).toHaveCSS("font-weight", "400");
      await expect(next).toHaveCSS("opacity", "0.35");
      const rect = await next.boundingBox();
      await page.mouse.click(rect.x + rect.width / 2, rect.y + rect.height / 2);
      await expect(page.locator("#moondiff-file-0")).not.toHaveClass(/expanded/);
    });
  }
}

test("navigation clamps the final change to the page bottom", async ({ page }) => {
  const sections = await loadNavigation(page, { trailingFile: false });
  const previous = sections.nth(2);
  await readChange(previous, 0);
  await button(page, 1).click();
  await expect(button(page, 1)).toBeFocused();
  await expect.poll(() => page.evaluate(() => document.documentElement.scrollHeight - innerHeight - scrollY)).toBeLessThanOrEqual(1);
  expect(await sections.nth(3).locator(marker).evaluate(element => element.getBoundingClientRect().bottom <= innerHeight)).toBe(true);
  await button(page, -1).click();
  await expectLanding(previous, 0);
  await button(page, 1).click();
  await expectLanding(sections.nth(3), 0);
  await page.keyboard.press("Enter");
  await expectLanding(sections.nth(0), 0);
  await button(page, -1).click();
  await expect.poll(() => page.evaluate(() => document.documentElement.scrollHeight - innerHeight - scrollY)).toBeLessThanOrEqual(1);
});

for (const algorithm of ["Token", "Tree"]) {
  for (const layout of ["Split", "Unified"]) {
    test(`${algorithm} ${layout}: every block participates in the global cycle in DOM order`, async ({ page }) => {
      await loadNavigation(page, { algorithm, layout });
      const sections = page.locator('.file-card .semantic-section');
      const targets = [];
      for (let i = 0; i < await sections.count(); i++) {
        for (let block = 0; block < await sections.nth(i).locator(marker).count(); block++) {
          targets.push([sections.nth(i), block]);
        }
      }
      await expect(sections.nth(3)).toContainText('deleted_section');
      await button(page, 1).focus();
      let activation = 0;
      for (const [section, block] of [...targets, targets[0]]) {
        await page.keyboard.press(activation++ % 2 ? 'Space' : 'Enter');
        await expectLanding(section, block);
        await expect(button(page, 1)).toBeFocused();
      }
      await button(page, -1).focus();
      for (const [section, block] of [...targets].reverse()) {
        await page.keyboard.press(activation++ % 2 ? 'Space' : 'Enter');
        await expectLanding(section, block);
      }
      await expect(button(page, -1)).toBeFocused();
    });
  }
}

test('global controls skip closed files, unchanged files, line diffs, fallback and filtered changes', async ({ page }) => {
  await loadNavigation(page, {
    extraFiles: [
      { filename: 'unchanged.mbt', old: 'fn unchanged() { 1 }', new: 'fn unchanged() { 1 }' },
      { filename: 'plain.txt', old: 'old', new: 'new' },
      { filename: 'broken.mbt', old: 'fn broken( {', new: 'fn broken( }' },
      { filename: 'comments.mbt', old: '// old\nfn same() { 1 }', new: '// new\nfn same() { 1 }' },
      { filename: 'ignored_test.mbt', old: 'fn ignored() { 1 }', new: 'fn ignored() { 2 }' },
    ],
  });
  const first = page.locator('#moondiff-file-0');
  const other = page.locator('#moondiff-file-1 .semantic-section');
  await page.getByRole('checkbox', { name: 'Ignore comments', exact: true }).check();
  await page.getByRole('checkbox', { name: 'Ignore tests', exact: true }).check();
  await page.locator('#moondiff-file-3 .file-toggle').click();
  await expect(page.locator('#moondiff-file-3 table')).toBeVisible();
  await expect(page.locator('.file-card[data-navigation-enabled="true"]')).toHaveCount(2);
  await first.locator('.file-toggle').click();
  await expect(first).not.toHaveClass(/expanded/);
  await page.evaluate(() => window.scrollTo(0, 0));
  await button(page, 1).click();
  await expectLanding(other, 0);
  await button(page, -1).click();
  await expectLanding(other, 2);
  await button(page, 1).click();
  await expectLanding(other, 0);
  await page.locator('#moondiff-file-1 .file-toggle').click();
  await expect(button(page, 1)).toBeDisabled();
  await expect(button(page, -1)).toBeDisabled();
  await page.getByRole('checkbox', { name: 'Ignore tests', exact: true }).uncheck();
  await expect(button(page, 1)).toBeEnabled();
  await button(page, 1).click();
  await expectLanding(page.locator('#moondiff-file-6 .semantic-section'), 0);
});

test('clamped global landing is invalidated by manual scroll, layout and eligibility changes', async ({ page }) => {
  await loadNavigation(page);
  const first = page.locator('#moondiff-file-0 .semantic-section').first();
  const other = page.locator('#moondiff-file-1 .semantic-section');
  await button(page, -1).click();
  await expectLanding(other, 2);
  await readChange(first, 1, 40);
  await button(page, 1).click();
  await expectLanding(first, 2);
  await page.evaluate(() => window.scrollTo(0, 0));
  await button(page, -1).click();
  await expectLanding(other, 2);
  await page.getByRole('button', { name: 'Unified', exact: true }).click();
  await readChange(other, 0);
  await button(page, 1).click();
  await expectLanding(other, 1);
  await page.evaluate(() => window.scrollTo(0, 0));
  await button(page, -1).click();
  await page.locator('#moondiff-file-1 .file-toggle').click();
  await page.evaluate(() => window.scrollTo(0, 0));
  await button(page, -1).click();
  await expectLanding(page.locator('#moondiff-file-0 .semantic-section').last(), 0);
  await button(page, 1).click();
  await expectLanding(first, 0);
});

for (const width of [1440, 420]) {
  test(`wrapped commit title stays sticky beyond its body at ${width}px and remeasures on resize`, async ({ page }) => {
    const title = 'Keep the complete commit title visible while reviewing changes across several files and declarations';
    const body = '  Indented explanation\n\n' + 'The body should scroll normally.\n'.repeat(12);
    const sections = await loadNavigation(page, { width, message: `${title}\n\n${body}` });
    const titlebar = page.locator('.change-titlebar');
    await expect(page.locator('.commit-message-body')).toHaveJSProperty('textContent', body);
    await button(page, 1).click();
    await expectLanding(sections.first(), 0);
    await expect.poll(() => page.locator('.commit-card').evaluate(el => el.getBoundingClientRect().bottom)).toBeLessThan(0);
    await button(page, -1).click();
    await expectLanding(page.locator('#moondiff-file-1 .semantic-section'), 2);
    const initialHeight = (await titlebar.boundingBox()).height;
    const opposite = width === 1440 ? 420 : 1440;
    await page.setViewportSize({ width: opposite, height: 720 });
    await expect.poll(() => titlebar.evaluate(el => el.getBoundingClientRect().height)).not.toBe(initialHeight);
    await page.evaluate(() => window.scrollTo(0, 0));
    await button(page, 1).click();
    await expectLanding(sections.first(), 0);
    await page.getByRole('button', { name: 'Unified', exact: true }).click();
    await readChange(sections.nth(1), 0);
    await button(page, 1).click();
    await expectLanding(sections.nth(1), 1);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(opposite);
  });
}

test('sidebar resizing remeasures wrapped titles and file-tree landing clears the title', async ({ page }) => {
  const title = 'Review the entire commit and keep its full subject visible. '.repeat(4);
  const sections = await loadNavigation(page, { message: title });
  const titlebar = page.locator('.change-titlebar');
  const initial = (await titlebar.boundingBox()).height;
  const divider = page.getByRole('separator', { name: 'Resize file tree' });
  const box = await divider.boundingBox();
  await page.mouse.move(box.x + box.width / 2, box.y + 80);
  await page.mouse.down();
  await page.mouse.move(640, box.y + 80, { steps: 8 });
  await page.mouse.up();
  await expect.poll(() => titlebar.evaluate(el => el.getBoundingClientRect().height)).toBeGreaterThan(initial);
  await button(page, 1).click();
  await expectLanding(sections.first(), 0);
  await page.getByRole('treeitem', { name: 'Open other.mbt', exact: true }).click();
  await expect.poll(() => page.locator('#moondiff-file-1').evaluate(el => el.getBoundingClientRect().top - document.querySelector('.change-titlebar').getBoundingClientRect().bottom)).toBeGreaterThanOrEqual(7);
  await button(page, -1).click();
  await expectLanding(sections.last(), 0);
  await page.getByRole('treeitem', { name: 'Open other.mbt', exact: true }).click();
  await button(page, 1).click();
  await expectLanding(page.locator('#moondiff-file-1 .semantic-section'), 0);
});

test('route changes disconnect the old height observer and reset navigation', async ({ page }) => {
  await page.addInitScript(() => {
    const Native = window.ResizeObserver;
    window.resizeObservers = [];
    window.ResizeObserver = class extends Native {
      constructor(callback) { super(callback); window.resizeObservers.push(this); }
      disconnect() { this.disconnected = true; super.disconnect(); }
    };
  });
  await loadNavigation(page);
  await button(page, -1).click();
  await page.evaluate(() => { history.pushState(null, '', '/'); dispatchEvent(new PopStateEvent('popstate')); });
  await expect(page.locator('.hero-landing')).toBeVisible();
  await expect.poll(() => page.evaluate(() => window.resizeObservers.every(observer => observer.disconnected))).toBe(true);
  await page.evaluate(sha => { history.pushState(null, '', `/example/navigation/commit/${sha}`); dispatchEvent(new PopStateEvent('popstate')); }, sha);
  await expect(page.locator('#moondiff-file-1 .semantic-section')).toBeVisible();
  await page.evaluate(() => window.scrollTo(0, 0));
  await button(page, 1).click();
  await expectLanding(page.locator('#moondiff-file-0 .semantic-section').first(), 0);
  expect(await page.evaluate(() => window.resizeObservers.filter(observer => !observer.disconnected).length)).toBe(await page.locator('.file-card').count() + 2);
});

test('a height-only viewport resize discards the clamped landing', async ({ page }) => {
  await loadNavigation(page);
  const other = page.locator('#moondiff-file-1 .semantic-section');
  await button(page, -1).click();
  await expectLanding(other, 2);
  // The final target was below the reading edge. A shorter viewport makes a
  // new physical landing possible and Next must re-read that position.
  await page.setViewportSize({ width: 1440, height: 480 });
  await button(page, 1).click();
  await expectLanding(other, 2);
  await button(page, 1).click();
  await expectLanding(page.locator('#moondiff-file-0 .semantic-section').first(), 0);
});
