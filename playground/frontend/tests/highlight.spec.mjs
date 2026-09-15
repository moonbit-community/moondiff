import { expect, test } from "@playwright/test";
import { anonymousApi, routeGithub } from "./api-routes.mjs";

const sha = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee";
const parent = "1111111111111111111111111111111111111111";
const path = `/example/highlights/commit/${sha}`;
const before = [
  "/// Preview docs",
  "/// ```mbt",
  '/// let shown = "中文😀\\{read(1)}"',
  "/// ```",
  '#deprecated("use greet", since="1")',
  "pub async fn greet(value : Int) -> String {",
  '  let label = "中文😀<tag>&\\n"',
  "  let count = 11",
  '  if true { @text.render(label, count).trim() } else { "old" }',
  "}",
  "",
  "let first = 21; let second = 31",
  "",
  "fn another() { 7 }",
].join("\r\n");
const after = [
  "fn another() { 8 }",
  "",
  ...before.split("\r\n").slice(0, 12).map(line => line
    .replace("read(1)", "read(2)").replace('since="1"', 'since="2"')
    .replace("count = 11", "count = 12").replace('"old"', '"new"')
    .replace("first = 21", "first = 22").replace("second = 31", "second = 32")),
].join("\r\n");

const files = [
  { filename: "src/colors.mbt", old: before, new: after },
  { filename: "src/broken.mbt", old: "fn broken( {\n  let x = ` 1", new: "fn broken( [\n  let x = ` 2" },
  { filename: "src/plain.txt", old: 'let x = "before"', new: 'let x = "after"' },
  { filename: "src/renamed.txt", previous_filename: "src/was.mbt", old: "let value = 11", new: "let value = 22" },
  { filename: "src/renamed.mbt", previous_filename: "src/was.txt", old: "let value = 11", new: "let value = 22" },
  { filename: "src/interface.mbti", old: "pub fn before() -> Int", new: "pub fn after() -> Int" },
];

async function installSources(page) {
  const requests = [];
  await anonymousApi(page);
  await routeGithub(page, "api", route => route.fulfill({
    status: 200,
    contentType: "application/json",
    body: JSON.stringify({
      sha, html_url: `https://github.com/example/highlights/commit/${sha}`,
      commit: { message: "MoonBit syntax highlighting" }, parents: [{ sha: parent }],
      stats: { additions: 10, deletions: 10, total: 20 },
      files: files.map(file => ({
        filename: file.filename, previous_filename: file.previous_filename,
        status: file.previous_filename ? "renamed" : "modified",
        additions: 2, deletions: 2, changes: 4,
      })),
    }),
  }));
  await routeGithub(page, "content", route => {
    const parts = new URL(route.request().url()).pathname.split("/");
    const old = parts[3] === parent;
    const filename = decodeURIComponent(parts.slice(4).join("/"));
    requests.push(`${old}:${filename}`);
    const file = files.find(file => (old ? file.previous_filename ?? file.filename : file.filename) === filename);
    if (!file) throw new Error(`Unexpected source request: ${filename}`);
    return route.fulfill({ status: 200, contentType: "text/plain", body: old ? file.old : file.new });
  });
  return requests;
}

async function expectOriginalLines(container, old, current) {
  const rows = await container.locator(".review-diff tr").evaluateAll(rows => rows.flatMap(row => {
    return ["old", "new"].flatMap(side => {
      const gutter = row.querySelector(`.${side}-line-number`);
      const number = Number(gutter?.querySelector(".line-number-value")?.textContent);
      if (!number) return [];
      const cell = row.closest("table").classList.contains("split")
        ? gutter.nextElementSibling : row.querySelector("td:last-child");
      const clone = cell.cloneNode(true);
      clone.querySelector(".diff-prefix")?.remove();
      return [{ side, number, text: clone.textContent }];
    });
  }));
  expect(rows.length).toBeGreaterThan(0);
  const sources = { old: old.split(/\r\n|\r|\n/), new: current.split(/\r\n|\r|\n/) };
  for (const row of rows) expect(row.text, `${row.side} line ${row.number}`).toBe(sources[row.side][row.number - 1]);
}

const colors = {
  light: {
    keyword: "rgb(0, 0, 255)", control: "rgb(175, 0, 219)", function: "rgb(121, 94, 38)",
    type: "rgb(38, 127, 153)", variable: "rgb(0, 16, 128)", number: "rgb(9, 134, 88)",
    string: "rgb(163, 21, 21)", escape: "rgb(238, 0, 0)", comment: "rgb(0, 128, 0)",
    operator: "rgb(0, 0, 0)", interpolation: "rgb(0, 0, 0)", "attribute-parameter": "rgb(128, 0, 0)",
    add: "rgb(233, 248, 241)", del: "rgb(255, 240, 239)", wa: "rgb(185, 235, 213)", wd: "rgb(255, 201, 197)",
  },
  dark: {
    keyword: "rgb(86, 156, 214)", control: "rgb(197, 134, 192)", function: "rgb(220, 220, 170)",
    type: "rgb(78, 201, 176)", variable: "rgb(156, 220, 254)", number: "rgb(181, 206, 168)",
    string: "rgb(206, 145, 120)", escape: "rgb(215, 186, 125)", comment: "rgb(106, 153, 85)",
    operator: "rgb(212, 212, 212)", interpolation: "rgb(86, 156, 214)", "attribute-parameter": "rgb(86, 156, 214)",
    add: "rgb(16, 41, 31)", del: "rgb(50, 26, 27)", wa: "rgb(25, 95, 69)", wd: "rgb(106, 44, 45)",
  },
};

for (const algorithm of ["Token", "Tree"]) {
  for (const layout of ["Split", "Unified"]) {
    for (const theme of ["light", "dark"]) {
      test(`${algorithm} ${layout} ${theme}: MoonBit syntax composes with diff backgrounds`, async ({ page }, info) => {
        await page.setViewportSize({ width: 1440, height: 1100 });
        await page.emulateMedia({ colorScheme: theme });
        await installSources(page);
        await page.goto(path);
        await page.getByRole("button", { name: algorithm, exact: true }).click();
        await page.getByRole("button", { name: layout, exact: true }).click();
        const file = page.locator("#moondiff-file-0");
        await expect(file.locator(".syntax-async").first()).toBeVisible();
        await expect(file.locator("table").first()).toHaveClass(new RegExp(`\\b${layout.toLowerCase()}\\b`));
        const palette = colors[theme];
        for (const kind of ["keyword", "control", "function", "type", "variable", "number", "string", "escape", "comment", "operator", "interpolation", "attribute-parameter"]) {
          await expect(file.locator(`.syntax-${kind}`).first()).toHaveCSS("color", palette[kind]);
        }
        for (const [kind, color] of [["async", "control"], ["attribute", "control"], ["modifier", "keyword"], ["boolean", "keyword"], ["package", "type"]]) {
          await expect(file.locator(`.syntax-${kind}`).first()).toHaveCSS("color", palette[color]);
        }
        await expect(file.locator(".syntax-async").first()).toHaveCSS("font-style", "italic");
        await expect(file.locator(".syntax-function").first()).toHaveCSS("font-style", "normal");
        await expect(file.locator(".syntax-function").first()).toHaveCSS("text-decoration-line", "none");
        for (const kind of ["wa", "wd"]) {
          const change = file.locator(`b.${kind}`).filter({ has: page.locator(".syntax-number") }).first();
          await expect(change).toHaveCSS("background-color", palette[kind]);
          await expect(change.locator(".syntax-number").first()).toHaveCSS("color", palette.number);
        }
        await expect(file.locator("td.add").first()).toHaveCSS("background-color", palette.add);
        await expect(file.locator("td.del").first()).toHaveCSS("background-color", palette.del);
        await expect(file.locator("td.ctx .syntax-keyword").first()).toHaveCSS("color", palette.keyword);
        await expect(file.locator("tag, script, [class^=syntax-] .diff-prefix")).toHaveCount(0);
        await expectOriginalLines(file, before, after);
        const broken = page.locator("#moondiff-file-1");
        await expect(broken.locator(".diff-notice").first()).toBeVisible();
        await expect(broken.locator(".syntax-keyword").first()).toHaveCSS("color", palette.keyword);
        await expectOriginalLines(broken, files[1].old, files[1].new);
        // Keep one representative screenshot for every algorithm/layout/theme.
        await file.screenshot({ path: info.outputPath("moonbit-highlighting.png") });
      });
    }
  }
}

test("renames highlight each source side independently; filters and layouts reuse loaded sources", async ({ page }) => {
  const requests = await installSources(page);
  await page.goto(path);
  for (const index of [2, 5]) {
    await page.getByRole("button", { name: `Expand ${files[index].filename}`, exact: true }).click();
    await expect(page.locator(`#moondiff-file-${index} .review-diff`)).toBeVisible();
    await expect(page.locator(`#moondiff-file-${index} [class^=syntax-]`)).toHaveCount(0);
  }
  for (const algorithm of ["Token", "Tree"]) {
    await page.getByRole("button", { name: algorithm, exact: true }).click();
    for (const layout of ["Split", "Unified"]) {
      await page.getByRole("button", { name: layout, exact: true }).click();
      for (const [index, highlightedSide] of [[3, "del"], [4, "add"]]) {
        const file = page.locator(`#moondiff-file-${index}`);
        await expect(file.locator(`td.${highlightedSide} .syntax-keyword`)).toHaveCount(1);
        await expect(file.locator(`td.${highlightedSide === "del" ? "add" : "del"} [class^=syntax-]`)).toHaveCount(0);
        await expectOriginalLines(file, files[index].old, files[index].new);
      }
    }
  }
  const count = requests.length;
  for (const filter of ["Ignore comments", "Ignore tests", "Ignore comments", "Ignore tests"]) {
    await page.getByRole("checkbox", { name: filter, exact: true }).click();
    await expect(page.locator("#moondiff-file-0 .syntax-async").first()).toBeVisible();
  }
  expect(requests.length).toBe(count);
});
