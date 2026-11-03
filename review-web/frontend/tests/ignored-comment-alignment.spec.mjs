import { readFileSync } from "node:fs";
import { expect, test } from "../../tests/browser-test.mjs";
import { anonymousApi, routeGithub } from "./api-routes.mjs";

// Pin the complete declaration so toolchain updates cannot change this case.
const original = readFileSync(new URL("./fixtures/array_get_view.mbt", import.meta.url), "utf8").trimEnd();
const attribute = '#intrinsic("%array.get_view")';
const withAttribute = original.replace("pub fn[T] Array::get_view(", `${attribute}\npub fn[T] Array::get_view(`);
const documentation = original.split("\n").filter(line => line.startsWith("///"));
const parent = "1111111111111111111111111111111111111111";
const head = "2222222222222222222222222222222222222222";
const commitURL = `https://github.com/example/comment-alignment/commit/${head}`;

async function loadAttributeCommit(page, reverse) {
  const oldSource = reverse ? withAttribute : original;
  const newSource = reverse ? original : withAttribute;
  await anonymousApi(page);
  await page.route("https://**", route => route.abort("blockedbyclient"));
  await routeGithub(page, "api", route => route.fulfill({
    contentType: "application/json",
    body: JSON.stringify(new URL(route.request().url()).pathname.endsWith("/comments") ? [] : {
      sha: head,
      html_url: commitURL,
      commit: { message: "Update Array::get_view intrinsic" },
      parents: [{ sha: parent }],
      stats: { additions: reverse ? 0 : 1, deletions: reverse ? 1 : 0, total: 1 },
      files: [{
        filename: "src/arrayview.mbt",
        status: "modified",
        additions: reverse ? 0 : 1,
        deletions: reverse ? 1 : 0,
        changes: 1,
        patch: [
          `@@ -1,${oldSource.split("\n").length} +1,${newSource.split("\n").length} @@`,
          ...withAttribute.split("\n").map(line => `${line === attribute ? (reverse ? "-" : "+") : " "}${line}`),
        ].join("\n"),
      }],
    }),
  }));
  await routeGithub(page, "content", route => route.fulfill({
    contentType: "text/plain",
    body: new URL(route.request().url()).pathname.split("/")[3] === parent ? oldSource : newSource,
  }));
  await page.goto("/");
  await page.getByLabel("Public GitHub commit or pull request URL").fill(commitURL);
  await page.getByRole("button", { name: "View diff" }).click();
  await expect(page.locator(".file-card table.split")).toBeVisible();
}

for (const reverse of [false, true]) {
  for (const algorithm of ["Token", "Tree"]) {
    for (const layout of ["Split", "Unified"]) {
      test(`${algorithm} ${layout} pairs ignored Array::get_view docs on attribute ${reverse ? "deletion" : "insertion"}`, async ({ page }) => {
        await page.setViewportSize({ width: 1440, height: 900 });
        await loadAttributeCommit(page, reverse);
        const section = page.locator(".file-card .semantic-section");
        await expect(section).toHaveCount(1);
        await expect(section.locator(".semantic-section-title")).toContainText("Matched");
        const comments = page.getByRole("checkbox", { name: "Ignore comments", exact: true });
        await expect(comments).toBeChecked();
        await page.getByRole("button", { name: algorithm, exact: true }).click();
        // Tree adds hunk headers; Token renders the complete declaration. Wait
        // for that DOM change before checking rows from the selected algorithm.
        if (algorithm === "Tree") {
          await expect(section.locator(".hunk-header")).not.toHaveCount(0);
        } else {
          await expect(section.locator(".hunk-header")).toHaveCount(0);
        }
        await page.getByRole("button", { name: layout, exact: true }).click();
        const table = section.locator(`table.${layout.toLowerCase()}`);
        await expect(table).toBeVisible();
        const ignoredCells = table.locator("td.ctx.ignored");
        await expect(ignoredCells).toHaveCount(documentation.length * (layout === "Split" ? 2 : 1));
        const rows = await table.locator("tr").evaluateAll((rows, layout) => rows.filter(row => row.querySelector("td.old-line-number")).map(row => ({
          old: row.querySelector("td.old-line-number").textContent.trim(),
          new: row.querySelector("td.new-line-number").textContent.trim(),
          docs: [...row.querySelectorAll("td.ctx.ignored")].map(cell => layout === "Unified" ? cell.textContent.slice(1) : cell.textContent),
        })), layout);
        expect(rows.filter(row => row.docs.length).map(row => row.docs)).toEqual(
          documentation.map(line => layout === "Split" ? [line, line] : [line]),
        );
        for (const [index, row] of rows.filter(row => row.docs.length).entries()) {
          expect([row.old, row.new]).toEqual([String(index + 1), String(index + 1)]);
        }
        for (const side of ["old", "new"]) {
          const indexes = rows.map(row => row[side]).filter(Boolean).map(Number);
          expect(indexes.every((line, index) => index === 0 || line > indexes[index - 1])).toBe(true);
          if (algorithm === "Token") {
            const length = (side === "old") === reverse ? 45 : 44;
            expect(indexes).toEqual(Array.from({ length }, (_, i) => i + 1));
          }
        }
        if (algorithm === "Token") expect(rows).toHaveLength(45);
        await expect(table.locator(reverse ? "td.del" : "td.add")).toHaveText([
          `${layout === "Unified" ? (reverse ? "-" : "+") : ""}${attribute}`,
        ]);
        await expect(table.locator(reverse ? "td.add" : "td.del")).toHaveCount(0);
        // A filter redraw must preserve the pairing, too.
        await comments.uncheck();
        await expect(ignoredCells).toHaveCount(0);
        await comments.check();
        await expect(ignoredCells).toHaveCount(documentation.length * (layout === "Split" ? 2 : 1));
      });
    }
  }
}
