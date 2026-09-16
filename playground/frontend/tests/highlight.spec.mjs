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

const cBefore = [
  "#include <stdint.h>",
  "#define STEP(x) \\",
  "  ((x) + 1)",
  "struct Item { int value; };",
  "[[nodiscard, vendor::note(mode)]] static bool ready(const size_t count) {",
  '  const char *label = u8"中文😀<tag>&\\n";',
  "  /* documentation",
  "     if (false) return fake();",
  "  */",
  "  if (true) return log_value(label, 11);",
  "  return false;",
  "}",
].join("\r\n");
const cAfter = cBefore.replace("+ 1)", "+ 2)").replace("label, 11", "label, 22");

const cRegressions = [
  {
    name: "numeric separators",
    filename: "src/numeric-separators.c",
    newline: "\r\n",
    lines: [
      "double values[] = { 0x1'e+2, 0x1'E-2, 1e+2, 0x1.fp-2 };",
      "double spliced = 0x1'\\",
      "e+2;",
      "int numbers(void) { return 1; }",
    ],
    tokens: [
      ["number", "0x1'e"], ["number", "0x1'E"], ["operator", "+"], ["operator", "-"],
      ["number", "1e+2"], ["number", "0x1.fp-2"], ["number", "e"],
    ],
  },
  {
    name: "directive state",
    filename: "src/directive-state.c",
    newline: "\n",
    lines: [
      "#define ATTR [[deprecated(",
      "int after_attribute(void) { return 1; }",
      "#define TAG struct",
      "after_tag();",
      "#define VALUE value",
      "(other);",
    ],
    tokens: [["function", "after_attribute"], ["function", "after_tag"], ["variable", "value"]],
  },
  {
    name: "alternative punctuation",
    filename: "src/digraphs.c",
    newline: "\r\n",
    lines: [
      "%:include <dir/<:%:%:.h>",
      "%:define JOIN(a, b) %:a %:%: b",
      "struct <:[vendor::note(<%a; b%>, <:c:>)]:> Node;",
      "int restored(void) <% return 1; %>",
    ],
    tokens: [
      ["control", "%:"], ["string", "<dir/<:%:%:.h>"], ["operator", "%:%:"],
      ["attribute", "<:["], ["attribute", "]:>"], ["attribute", "note"],
      ["attribute-parameter", "b"], ["attribute-parameter", "c"],
      ["type", "Node"], ["function", "restored"],
    ],
  },
  {
    name: "Unicode identifiers",
    filename: "src/unicode-identifiers.c",
    newline: "\r",
    lines: [
      String.raw`#define \u4e2d(\U0001F600_t) \U0001F600_t`,
      String.raw`struct tag\u4e2d;`,
      String.raw`\u4e2d_t value;`,
      String.raw`int run\U0001F600(void) { return 1; } // 中文😀`,
    ],
    tokens: [
      ["function", String.raw`\u4e2d`], ["variable", String.raw`\U0001F600_t`],
      ["type", String.raw`\U0001F600_t`], ["type", String.raw`tag\u4e2d`],
      ["type", String.raw`\u4e2d_t`], ["function", String.raw`run\U0001F600`],
      ["comment", "// 中文😀"],
    ],
  },
].map(fixture => {
  const old = fixture.lines.join(fixture.newline);
  return { ...fixture, old, new: old.replace("return 1", "return 2").replace("(other)", "(next)") };
});

const files = [
  { filename: "src/colors.mbt", old: before, new: after },
  { filename: "src/broken.mbt", old: "fn broken( {\n  let x = ` 1", new: "fn broken( [\n  let x = ` 2" },
  { filename: "src/plain.txt", old: 'let x = "before"', new: 'let x = "after"' },
  { filename: "src/renamed.txt", previous_filename: "src/was.mbt", old: "let value = 11", new: "let value = 22" },
  { filename: "src/renamed.mbt", previous_filename: "src/was.txt", old: "let value = 11", new: "let value = 22" },
  { filename: "src/interface.mbti", old: "pub fn before() -> Int", new: "pub fn after() -> Int" },
  { filename: "src/colors.c", old: cBefore, new: cAfter },
  { filename: "src/added.h", status: "added", old: "", new: '#ifndef API_H\n#define API_H\nint call(const char *text); // 中文😀<&>\n#endif' },
  { filename: "src/deleted.c", status: "removed", old: '/* 中文😀\n   old code */\nint removed(void) { return 0; }', new: "" },
  { filename: "src/renamed.h", previous_filename: "src/was.c", old: "int value = 11;", new: "int value = 22;" },
  { filename: "src/from_c.txt", previous_filename: "src/from_c.c", old: "int value = 11;", new: "int value = 22;" },
  { filename: "src/from_text.h", previous_filename: "src/was.h.txt", old: "int value = 11;", new: "int value = 22;" },
  { filename: "src/from_moonbit.c", previous_filename: "src/from_moonbit.mbt", old: "let value = 11", new: "int value = 22;" },
  { filename: "src/from_c.mbt", previous_filename: "src/was_to_mbt.c", old: "int value = 11;", new: "let value = 22" },
  { filename: "src/upper.C", old: "int value = 11;", new: "int value = 22;" },
  ...cRegressions,
];

async function installSources(page, sources = files) {
  const requests = [];
  await anonymousApi(page);
  await routeGithub(page, "api", route => route.fulfill({
    status: 200,
    contentType: "application/json",
    body: JSON.stringify({
      sha, html_url: `https://github.com/example/highlights/commit/${sha}`,
      commit: { message: "Source syntax highlighting" }, parents: [{ sha: parent }],
      stats: { additions: 10, deletions: 10, total: 20 },
      files: sources.map(file => ({
        filename: file.filename, previous_filename: file.previous_filename,
        status: file.status ?? (file.previous_filename ? "renamed" : "modified"),
        additions: 2, deletions: 2, changes: 4,
      })),
    }),
  }));
  await routeGithub(page, "content", route => {
    const parts = new URL(route.request().url()).pathname.split("/");
    const old = parts[3] === parent;
    const filename = decodeURIComponent(parts.slice(4).join("/"));
    requests.push(`${old}:${filename}`);
    const file = sources.find(file => (old ? file.previous_filename ?? file.filename : file.filename) === filename);
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
  return rows;
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

for (const layout of ["Split", "Unified"]) {
  test(`${layout}: C long generated lines fall back without losing text or diff backgrounds`, async ({ page }, info) => {
    const declaration = `const unsigned char data[] = {${Array(100_000).fill("0").join(",")}};`;
    const old = ["#include <stdint.h>", declaration, "int main(void) { return 0; } // 中文😀"].join("\r\n");
    const current = old.replace("0};", "1};");
    const fixture = { filename: "src/long-line.c", old, new: current };
    const errors = [];
    page.on("pageerror", error => errors.push(error.message));
    await page.emulateMedia({ colorScheme: "light" });
    const requests = await installSources(page, [fixture]);
    await page.goto(path);
    await page.getByRole("button", { name: layout, exact: true }).click();
    const started = Date.now();
    await page.getByRole("button", { name: `Expand ${fixture.filename}`, exact: true }).click();
    const file = page.locator("#moondiff-file-0");
    await expect(file.locator(".review-diff")).toBeVisible();
    await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    const renderMs = Date.now() - started;
    const syntaxNodes = await file.locator("[class^=syntax-]").count();
    await info.attach("long-line-render.json", {
      body: JSON.stringify({ layout, elements: 100_000, sourceBytes: Buffer.byteLength(old), renderMs, syntaxNodes }, null, 2),
      contentType: "application/json",
    });
    for (const side of ["del", "add"]) {
      const cell = file.locator(`td.${side}`).filter({ hasText: "const unsigned char data[] =" });
      await expect(cell).toHaveCount(1);
      await expect(cell.locator("[class^=syntax-]")).toHaveCount(0);
      await expect(cell).toHaveCSS("background-color", colors.light[side]);
    }
    await expect(file.locator("td.ctx .syntax-control").first()).toHaveCSS("color", colors.light.control);
    await expect(file.locator("td.ctx .syntax-type").first()).toHaveCSS("color", colors.light.type);
    expect(syntaxNodes).toBeGreaterThan(0);
    expect(syntaxNodes).toBeLessThan(32);
    const rows = await expectOriginalLines(file, old, current);
    for (const side of ["old", "new"]) {
      expect(rows.filter(row => row.side === side).map(row => row.number)).toEqual([1, 2, 3]);
    }
    expect(requests).toHaveLength(2);
    expect(errors).toEqual([]);
  });
}

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

test("MoonBit manifests auto-expand with highlighted line diffs, including renames", async ({ page }) => {
  const moduleBefore = 'name = "example/demo"\nversion = "0.1.0"\nimport {\n  "moonbitlang/lexer@0.3.16",\n}';
  const packageBefore = 'import {\n  "moonbitlang/core/json",\n}\noptions("is-main": false)';
  const sources = [
    ...["moon.mod", "nested/moon.mod"].map(filename => ({
      filename, old: moduleBefore, new: moduleBefore.replace("0.1.0", "0.2.0"),
      highlightedSides: ["del", "add"],
    })),
    ...["moon.pkg", "nested/moon.pkg"].map(filename => ({
      filename, old: packageBefore, new: packageBefore.replace("false", "true"),
      highlightedSides: ["del", "add"],
    })),
    {
      filename: "legacy/moon.mod.txt", previous_filename: "legacy/moon.mod",
      old: moduleBefore, new: moduleBefore.replace("0.1.0", "0.2.0"),
      highlightedSides: ["del"],
    },
    {
      filename: "migrated/moon.pkg", previous_filename: "migrated/moon.pkg.txt",
      old: packageBefore, new: packageBefore.replace("false", "true"),
      highlightedSides: ["add"],
    },
  ];
  const requests = await installSources(page, sources);
  await page.emulateMedia({ colorScheme: "light" });
  await page.goto(path);
  for (const algorithm of ["Token", "Tree"]) {
    await page.getByRole("button", { name: algorithm, exact: true }).click();
    for (const layout of ["Split", "Unified"]) {
      await page.getByRole("button", { name: layout, exact: true }).click();
      for (const [index, source] of sources.entries()) {
        const file = page.locator(`#moondiff-file-${index}`);
        await expect(file.locator(".file-toggle")).toHaveAttribute("aria-expanded", "true");
        await expect(file.locator(".review-diff")).toBeVisible();
        await expect(file.locator("table")).toHaveClass(new RegExp(`\\b${layout.toLowerCase()}\\b`));
        await expect(file.locator(".diff-notice")).toHaveCount(0);
        for (const side of ["del", "add"]) {
          if (source.highlightedSides.includes(side)) {
            await expect(file.locator(`td.${side} .syntax-string`).first()).toHaveCSS("color", colors.light.string);
          } else {
            await expect(file.locator(`td.${side} [class^=syntax-]`)).toHaveCount(0);
          }
          await expect(file.locator(`td.${side}`).first()).toHaveCSS("background-color", colors.light[side]);
        }
        if (source.highlightedSides.length === 2) {
          await expect(file.locator(".syntax-keyword").first()).toHaveCSS("color", colors.light.keyword);
        }
        await expectOriginalLines(file, source.old, source.new);
      }
    }
  }
  expect(requests).toHaveLength(sources.length * 2);
});

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

for (const layout of ["Split", "Unified"]) {
  for (const theme of ["light", "dark"]) {
    test(`${layout} ${theme}: expanded C sources preserve text and diff backgrounds`, async ({ page }, info) => {
      await page.setViewportSize({ width: 1440, height: 1100 });
      await page.emulateMedia({ colorScheme: theme });
      const requests = await installSources(page);
      await page.goto(path);
      const file = page.locator("#moondiff-file-6");
      await expect(file.locator(".review-diff")).toHaveCount(0);
      expect(requests.some(request => request.endsWith(":src/colors.c"))).toBe(false);
      await page.getByRole("button", { name: "Expand src/colors.c", exact: true }).click();
      await page.getByRole("button", { name: layout, exact: true }).click();
      await expect(file.locator(".syntax-type").first()).toBeVisible();
      await expect(file.locator("table").first()).toHaveClass(new RegExp(`\\b${layout.toLowerCase()}\\b`));
      const palette = colors[theme];
      for (const kind of ["keyword", "control", "function", "type", "variable", "number", "string", "escape", "comment", "operator", "attribute-parameter"]) {
        await expect(file.locator(`.syntax-${kind}`).first()).toHaveCSS("color", palette[kind]);
      }
      for (const [kind, color] of [["attribute", "control"], ["modifier", "keyword"], ["boolean", "keyword"]]) {
        await expect(file.locator(`.syntax-${kind}`).first()).toHaveCSS("color", palette[color]);
      }
      for (const kind of ["wa", "wd"]) {
        const change = file.locator(`b.${kind}`).filter({ has: page.locator(".syntax-number") }).first();
        await expect(change).toHaveCSS("background-color", palette[kind]);
        await expect(change.locator(".syntax-number").first()).toHaveCSS("color", palette.number);
      }
      await expect(file.locator("td.add").first()).toHaveCSS("background-color", palette.add);
      await expect(file.locator("td.del").first()).toHaveCSS("background-color", palette.del);
      await expect(file.locator("td.ctx .syntax-type").first()).toHaveCSS("color", palette.type);
      await expect(file.locator("tag, script, [class^=syntax-] .diff-prefix, .syntax-comment [class^=syntax-]")).toHaveCount(0);
      await expectOriginalLines(file, cBefore, cAfter);
      await file.screenshot({ path: info.outputPath("c-highlighting.png") });
    });
  }
}

test("C headers additions deletions and language renames reuse highlights across controls", async ({ page }) => {
  const requests = await installSources(page);
  await page.goto(path);
  for (let index = 6; index < files.length; index++) {
    const file = page.locator(`#moondiff-file-${index}`);
    await expect(file).toBeVisible();
    const expand = file.getByRole("button", { name: /^Expand / });
    if (await expand.count()) await expand.click();
    await expect(file.locator(".review-diff")).toBeVisible();
  }
  const count = requests.length;
  const expected = [
    [7, null, "type"], [8, "type", null], [9, "type", "type"],
    [10, "type", null], [11, null, "type"], [12, "keyword", "type"],
    [13, "type", "keyword"], [14, null, null],
  ];
  for (const algorithm of ["Token", "Tree"]) {
    await page.getByRole("button", { name: algorithm, exact: true }).click();
    for (const layout of ["Split", "Unified"]) {
      await page.getByRole("button", { name: layout, exact: true }).click();
      for (const [index, oldKind, newKind] of expected) {
        const file = page.locator(`#moondiff-file-${index}`);
        for (const [side, kind] of [["del", oldKind], ["add", newKind]]) {
          if (kind) await expect(file.locator(`td.${side} .syntax-${kind}`).first()).toBeVisible();
          else await expect(file.locator(`td.${side} [class^=syntax-]`)).toHaveCount(0);
        }
        await expectOriginalLines(file, files[index].old, files[index].new);
      }
    }
  }
  for (const filter of ["Ignore comments", "Ignore tests", "Ignore comments", "Ignore tests"]) {
    await page.getByRole("checkbox", { name: filter, exact: true }).click();
    await expectOriginalLines(page.locator("#moondiff-file-6"), cBefore, cAfter);
  }
  expect(requests.length).toBe(count);
  expect(requests).not.toContain("true:src/added.h");
  expect(requests).not.toContain("false:src/deleted.c");
});

for (const layout of ["Split", "Unified"]) {
  for (const fixture of cRegressions) {
    test(`${layout}: C ${fixture.name} preserves token scopes and source`, async ({ page }) => {
      await installSources(page);
      await page.goto(path);
      await page.getByRole("button", { name: `Expand ${fixture.filename}`, exact: true }).click();
      await page.getByRole("button", { name: layout, exact: true }).click();
      const file = page.locator(`#moondiff-file-${files.indexOf(fixture)}`);
      await expect(file.locator(".syntax-function").first()).toBeVisible();
      const tokens = await file.locator("[class^=syntax-]").evaluateAll(spans => spans.map(span => [
        span.className.slice("syntax-".length), span.textContent,
      ]));
      for (const token of fixture.tokens) expect(tokens).toContainEqual(token);
      await expectOriginalLines(file, fixture.old, fixture.new);
    });
  }
}
