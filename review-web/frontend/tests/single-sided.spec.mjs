import { expect, test } from "../../tests/browser-test.mjs";
import { anonymousApi, routeGithub } from "./api-routes.mjs";
import { ensureFileExpanded } from "./file-actions.mjs";

const sha = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee";
const parent = "1111111111111111111111111111111111111111";
const path = `/example/single-sided/commit/${sha}`;
const sources = [
  {
    filename: "src/sections.mbt", status: "modified",
    old: "fn keep() { 1 }\n\nfn removed() { 2 }",
    new: "fn keep() { 3 }\n\nfn inserted() { 4 }",
  },
  { filename: "src/added.mbt", status: "added", old: "", new: "fn added() { 1 }" },
  { filename: "src/removed.mbt", status: "removed", old: "fn removed() { 2 }", new: "" },
  { filename: "added.txt", status: "added", old: "", new: "added line" },
  { filename: "removed.txt", status: "removed", old: "removed line", new: "" },
];

async function installSources(page) {
  await page.route("https://**", route => route.abort("blockedbyclient"));
  await routeGithub(page, "api", route => route.fulfill({
    contentType: "application/json",
    body: JSON.stringify({
      sha, html_url: `https://github.com${path}`,
      commit: { message: "Single-sided diff widths" }, parents: [{ sha: parent }],
      stats: { additions: 4, deletions: 4, total: 8 },
      files: sources.map(({ filename, status, old, new: after }) => ({
        filename, status, additions: after ? 1 : 0, deletions: old ? 1 : 0, changes: 2,
      })),
    }),
  }));
  await routeGithub(page, "content", route => {
    const parts = new URL(route.request().url()).pathname.split("/");
    const source = sources.find(source => source.filename === decodeURIComponent(parts.slice(4).join("/")));
    return route.fulfill({ contentType: "text/plain", body: parts[3] === parent ? source.old : source.new });
  });
  await anonymousApi(page);
}

async function expectFullWidth(table, side, layout, line) {
  await expect(table).toHaveClass(layout === "Split" ? "split single-sided review-diff" : "unified numbered review-diff");
  await expect(table.locator("td.empty")).toHaveCount(0);
  const row = table.locator("tr[data-reading-row]").first();
  await expect(row.locator("td")).toHaveCount(layout === "Split" ? 2 : 3);
  await expect(row.locator(`.${side === "del" ? "old" : "new"}-line-number .line-number-value`)).toHaveText(String(line));
  const cell = row.locator(`td.${side}`);
  await expect(cell).toBeVisible();
  const widths = await cell.evaluate(cell => ({
    code: cell.getBoundingClientRect().width,
    table: cell.closest("table").getBoundingClientRect().width,
    gutters: [...cell.parentElement.querySelectorAll(".line-number")]
      .reduce((sum, gutter) => sum + gutter.getBoundingClientRect().width, 0),
  }));
  expect(Math.abs(widths.code + widths.gutters - widths.table)).toBeLessThanOrEqual(1);
  expect(widths.code).toBeGreaterThan(widths.table * 0.6);
}

for (const width of [1440, 420]) {
  test(`pure insertions and deletions use full width at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 });
    await installSources(page);
    await page.goto(path);
    for (const index of sources.keys()) await ensureFileExpanded(page.locator(`#moondiff-file-${index}`));

    const sections = page.locator("#moondiff-file-0 .semantic-section");
    await expect(sections).toHaveCount(3);
    for (const algorithm of ["Token", "Tree"]) {
      await page.getByRole("button", { name: algorithm, exact: true }).click();
      for (const layout of ["Split", "Unified", "Split"]) {
        await page.getByRole("button", { name: layout, exact: true }).click();
        for (const [kind, side] of [["Inserted", "add"], ["Deleted", "del"]]) {
          const table = sections.filter({ has: page.locator(".semantic-section-title", { hasText: `· ${kind} ·` }) }).locator("table");
          await expectFullWidth(table, side, layout, 3);
        }
        const matched = sections.filter({ has: page.locator(".semantic-section-title", { hasText: "· Matched ·" }) }).locator("table");
        await expect(matched).not.toHaveClass(/single-sided/);
        await expect(matched.locator("tr[data-reading-row]").first().locator("td")).toHaveCount(layout === "Split" ? 4 : 3);
        for (const [index, side] of [[1, "add"], [2, "del"], [3, "add"], [4, "del"]]) {
          await expectFullWidth(page.locator(`#moondiff-file-${index} table`), side, layout, 1);
        }
      }
    }
  });
}
