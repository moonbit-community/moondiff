import { expect, test } from "@playwright/test";
import { anonymousApi, routeGithub } from "./api-routes.mjs";

const sha = "3333333333333333333333333333333333333333";
const parent = "1111111111111111111111111111111111111111";
const longName = `navigate_${"long_declaration_".repeat(12)}`;
const marker = "[data-change-block-start]";
const button = (page, direction) => page.locator("#moondiff-file-0 .file-heading").getByRole("button", {
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

async function loadNavigation(page, { layout = "Split", algorithm = "Tree", width = 1440, single = false, trailingFile = true, leadingAddition = false } = {}) {
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
  await routeGithub(page, "api", route => route.fulfill({
    body: JSON.stringify({
      sha,
      html_url: `https://github.com/example/navigation/commit/${sha}`,
      commit: { message: "Navigate individual changes across declarations" },
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
      body: url.includes("other.mbt") ? declaration("other_file", version) : source(version),
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
    const summary = element.querySelector("summary").getBoundingClientRect();
    return Math.abs(element.querySelectorAll("[data-change-block-start]")[index].getBoundingClientRect().top - summary.bottom - 8);
  }, index)).toBeLessThanOrEqual(1);
  expect(await section.evaluate(element => {
    const summary = element.querySelector("summary").getBoundingClientRect();
    return summary.top >= element.closest(".file-card").querySelector(".file-heading").getBoundingClientRect().bottom - 1;
  })).toBe(true);
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
      await expect(page.locator("#moondiff-file-0 .file-heading .section-change-button")).toHaveCount(2);
      await expect(sections.locator(".section-change-controls")).toHaveCount(0);
      await expect(button(page, 1)).toHaveText("↓ next");
      await expect(button(page, -1)).toHaveText("↑ prev");
      await expect(button(page, 1)).toHaveAttribute("title", "Next change");
      await expect(button(page, -1)).toHaveAttribute("title", "Previous change");
      expect(await first.locator(marker).evaluateAll(rows => rows.every(row => row.querySelector(".line-number") && !row.querySelector(".hunk-header")))).toBe(true);
      expect(await first.locator(".hunk-header").count()).toBeLessThan(3);
      // No first-block default: the first Next must actually land on block zero.
      await button(page, -1).click();
      await expectNoMovement(page, () => button(page, -1).click());
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
      await expectNoMovement(page, () => button(page, -1).click());

      // The final deleted declaration is part of this file's navigation order.
      await readChange(sections.nth(2), 0);
      await button(page, 1).click();
      await expectLanding(sections.nth(3), 0);
      await expectNoMovement(page, () => button(page, 1).click());
      await expect(button(page, 1)).toBeFocused();
      await button(page, -1).click();
      await expectLanding(sections.nth(2), 0);
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

    test(`${algorithm} ${layout}: a file with one change can locate it`, async ({ page }) => {
      const sections = await loadNavigation(page, { algorithm, layout, single: true });
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
      const sections = await loadNavigation(page, { algorithm, layout, width: 420 });
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
      const filename = await page.locator("#moondiff-file-0 .file-path").boundingBox();
      const previousRect = await previous.boundingBox();
      expect(filename.x + filename.width).toBeLessThan(previousRect.x);
      expect(previousRect.x - filename.x - filename.width).toBeLessThan(24);
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
      await page.locator("#moondiff-file-0 .file-toggle").focus();
      await page.keyboard.press("Tab");
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
  await expectNoMovement(page, () => page.keyboard.press("Enter"));
  expect(await sections.nth(3).locator(marker).evaluate(element => element.getBoundingClientRect().bottom <= innerHeight)).toBe(true);
  await button(page, -1).click();
  await expectLanding(previous, 0);
});
