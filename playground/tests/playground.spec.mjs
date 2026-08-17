import { expect, test } from "@playwright/test";

const commitSha = "abcdef1234567890abcdef1234567890abcdef12";
const parentSha = "1111111111111111111111111111111111111111";
const commitUrl = `https://github.com/example/project/commit/${commitSha}`;

const oldSource = [
  "///|",
  "pub fn format_change(input : String) -> String {",
  `  let label = "${"old-value-".repeat(48)}"`,
  "  label + input",
  "}",
].join("\n");

const newSource = [
  "///|",
  "pub fn format_change(input : String) -> String {",
  `  let label = "${"new-value-".repeat(48)}"`,
  "  label + input.trim()",
  "}",
].join("\n");

const oldReadme = [
  "# Project notes",
  "Use the <old> workflow.",
  "Keep this line.",
].join("\r\n");

const newReadme = [
  "# Project notes",
  "Use the &new workflow.",
  "Keep this line.",
].join("\r\n");

const binarySource = Buffer.from([0xff, 0x00, 0x01, 0x02]);

const algorithmSha = "2222222222222222222222222222222222222222";
const algorithmUrl = `https://github.com/example/algorithms/commit/${algorithmSha}`;
const formattingOld = 'fn formatting() { "<same&value>" }';
const formattingNew = [
  "fn formatting() {",
  '  "<same&value>"',
  "}",
].join("\n");
const structuralOld = 'fn structural() { old_call("<script>&safe") }';
const structuralNew = 'fn structural() { new_call("<script>&safe") }';

const commentsSha = "4444444444444444444444444444444444444444";
const commentsUrl = `https://github.com/example/comments/commit/${commentsSha}`;
const mixedCommentsOld = [
  "/// old docs",
  "fn value() -> Int {",
  "  old_value() // old trailing",
  "",
  "\t",
  "}",
].join("\n");
const mixedCommentsNew = [
  "/// new docs",
  "fn value() -> Int {",
  "  new_value()  // new trailing",
  "  ",
  "}",
].join("\n");
const commentsOnlyOld = "fn stable() -> Int {\n  1 // old note\n}";
const commentsOnlyNew = "fn stable() -> Int {\n  1  // new note\n}";
const blankLinesOnlyOld = "fn blank_lines() -> Int {\n  1\n}";
const blankLinesOnlyNew = "\nfn blank_lines() -> Int {\n\u2003\n  1\n\t\n}\n";
const plainCommentsOld = "// old plain-text note";
const plainCommentsNew = "// new plain-text note";
const plainBlankLinesOld = "first plain line\nsecond plain line";
const plainBlankLinesNew = "first plain line\n\nsecond plain line";

const commentsCommit = {
  sha: commentsSha,
  html_url: commentsUrl,
  commit: { message: "Update code and comments" },
  parents: [{ sha: parentSha }],
  stats: { additions: 12, deletions: 5, total: 17 },
  files: [
    {
      filename: "src/mixed.mbt",
      status: "modified",
      additions: 2,
      deletions: 2,
      changes: 4,
    },
    {
      filename: "src/comments_only.mbt",
      status: "modified",
      additions: 1,
      deletions: 1,
      changes: 2,
    },
    {
      filename: "src/blank_lines_only.mbt",
      status: "modified",
      additions: 6,
      deletions: 1,
      changes: 7,
    },
    {
      filename: "notes.txt",
      status: "modified",
      additions: 1,
      deletions: 1,
      changes: 2,
    },
    {
      filename: "blank_lines.txt",
      status: "modified",
      additions: 1,
      deletions: 0,
      changes: 1,
    },
  ],
};

const algorithmCommit = {
  sha: algorithmSha,
  html_url: algorithmUrl,
  commit: { message: "Exercise both diff algorithms" },
  parents: [{ sha: parentSha }],
  stats: { additions: 4, deletions: 2, total: 6 },
  files: [
    {
      filename: "src/formatting_only.mbt",
      status: "modified",
      additions: 3,
      deletions: 1,
      changes: 4,
    },
    {
      filename: "src/structural.mbt",
      status: "modified",
      additions: 1,
      deletions: 1,
      changes: 2,
    },
    {
      filename: "README.md",
      status: "modified",
      additions: 1,
      deletions: 1,
      changes: 2,
    },
  ],
};

const apiCommit = {
  sha: commitSha,
  html_url: commitUrl,
  commit: { message: "Make the playground diff easier to scan" },
  parents: [{ sha: parentSha }],
  stats: { additions: 4, deletions: 4, total: 8 },
  files: [
    {
      filename: "src/format_change.mbt",
      status: "modified",
      additions: 2,
      deletions: 2,
      changes: 4,
    },
    {
      filename: "README.md",
      status: "modified",
      additions: 1,
      deletions: 1,
      changes: 2,
    },
    {
      filename: "assets/logo.bin",
      status: "modified",
      additions: 1,
      deletions: 1,
      changes: 2,
    },
  ],
};

async function installMockRoutes(page) {
  await page.route("https://**", route => route.abort("blockedbyclient"));
  await page.route("https://api.github.com/**", async route => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      headers: { "access-control-allow-origin": "*" },
      body: JSON.stringify(apiCommit),
    });
  });
  await page.route("https://raw.githubusercontent.com/**", async route => {
    const parts = new URL(route.request().url()).pathname.split("/");
    const revision = parts[3];
    const filename = decodeURIComponent(parts.slice(4).join("/"));
    if (filename === "assets/logo.bin") {
      await route.fulfill({
        status: 200,
        contentType: "application/octet-stream",
        headers: { "access-control-allow-origin": "*" },
        body: binarySource,
      });
      return;
    }
    const body = filename === "README.md"
      ? (revision === parentSha ? oldReadme : newReadme)
      : (revision === parentSha ? oldSource : newSource);
    await route.fulfill({
      status: 200,
      contentType: "text/plain",
      headers: { "access-control-allow-origin": "*" },
      body,
    });
  });
}

async function installAlgorithmRoutes(
  page,
  { formatOnly = false, health = false, parseFailure = false } = {},
) {
  const commit = formatOnly
    ? { ...algorithmCommit, files: [algorithmCommit.files[0]] }
    : algorithmCommit;
  if (health) await installAnalysisHealth(page);
  await page.route("https://**", route => route.abort("blockedbyclient"));
  await page.route("https://api.github.com/**", async route => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      headers: { "access-control-allow-origin": "*" },
      body: JSON.stringify(commit),
    });
  });
  await page.route("https://raw.githubusercontent.com/**", async route => {
    const parts = new URL(route.request().url()).pathname.split("/");
    const revision = parts[3];
    const filename = decodeURIComponent(parts.slice(4).join("/"));
    let body;
    if (filename === "src/formatting_only.mbt") {
      body = parseFailure
        ? (revision === parentSha ? "fn broken( {" : "fn broken() {}")
        : (revision === parentSha ? formattingOld : formattingNew);
    } else if (filename === "src/structural.mbt") {
      body = revision === parentSha ? structuralOld : structuralNew;
    } else {
      body = revision === parentSha ? oldReadme : newReadme;
    }
    await route.fulfill({
      status: 200,
      contentType: "text/plain",
      headers: { "access-control-allow-origin": "*" },
      body,
    });
  });
}

async function loadAlgorithmCommit(page, options) {
  await installAlgorithmRoutes(page, options);
  await page.goto("/");
  await page.getByLabel("Public GitHub commit URL").fill(algorithmUrl);
  await page.getByRole("button", { name: "View diff" }).click();
  await expect(page.locator("table.split").first()).toBeVisible();
}

async function installCommentsRoutes(
  page,
  { blankOnly = false, health = false } = {},
) {
  if (health) await installAnalysisHealth(page);
  const commit = blankOnly
    ? { ...commentsCommit, files: [commentsCommit.files[2]] }
    : commentsCommit;
  await page.route("https://**", route => route.abort("blockedbyclient"));
  await page.route("https://api.github.com/**", route => route.fulfill({
    status: 200,
    contentType: "application/json",
    headers: { "access-control-allow-origin": "*" },
    body: JSON.stringify(commit),
  }));
  await page.route("https://raw.githubusercontent.com/**", async route => {
    const parts = new URL(route.request().url()).pathname.split("/");
    const revision = parts[3];
    const filename = decodeURIComponent(parts.slice(4).join("/"));
    let body;
    if (filename === "src/mixed.mbt") {
      body = revision === parentSha ? mixedCommentsOld : mixedCommentsNew;
    } else if (filename === "src/comments_only.mbt") {
      body = revision === parentSha ? commentsOnlyOld : commentsOnlyNew;
    } else if (filename === "src/blank_lines_only.mbt") {
      body = revision === parentSha ? blankLinesOnlyOld : blankLinesOnlyNew;
    } else if (filename === "blank_lines.txt") {
      body = revision === parentSha ? plainBlankLinesOld : plainBlankLinesNew;
    } else {
      body = revision === parentSha ? plainCommentsOld : plainCommentsNew;
    }
    await route.fulfill({
      status: 200,
      contentType: "text/plain",
      headers: { "access-control-allow-origin": "*" },
      body,
    });
  });
}

async function loadCommentsCommit(page, options) {
  await installCommentsRoutes(page, options);
  await page.goto("/");
  await page.getByLabel("Public GitHub commit URL").fill(commentsUrl);
  await page.getByRole("button", { name: "View diff" }).click();
  await expect(page.locator("table.split").first()).toBeVisible();
}

async function loadMockedCommit(page) {
  await installMockRoutes(page);
  await page.goto("/");
  await page.getByLabel("Public GitHub commit URL").fill(commitUrl);
  await page.getByRole("button", { name: "View diff" }).click();
  await expect(page.locator("table.split")).toBeVisible();
  await expect(page.getByRole("button", { name: "Lexical" })).toHaveAttribute("aria-pressed", "true");
}

async function openMockedShareLink(page) {
  await installMockRoutes(page);
  await page.goto(`/#/example/project/commit/${commitSha}`);
  await expect(page.locator("table.split")).toBeVisible();
}

function analysisForRequest(request) {
  const groups = request.hunks.map((hunk, index) => ({
    title: index === 0 ? "Formatting behavior" : "Documentation flow",
    description: index === 0
      ? "Updates the formatting path across the commit."
      : "Keeps the documented workflow aligned with the implementation.",
    hunks: [{
      id: hunk.id,
      explanation: index === 0
        ? "Updates <formatting> & output behavior."
        : "Refreshes the user-facing workflow description.",
    }],
  }));
  return {
    version: 1,
    ok: true,
    analysis: {
      summary: "The commit updates formatting behavior and its documentation.",
      groups: groups.reverse(),
    },
  };
}

async function installAnalysisHealth(page) {
  await page.route("**/api/health", route => route.fulfill({
    status: 200,
    contentType: "application/json",
    body: JSON.stringify({ version: 1, ok: true, openseek_available: true }),
  }));
}

test("landing follows the compact DiffsHub-style URL handoff", async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto("/");

  await expect(page.getByRole("heading", { name: "Moondiff playground" })).toBeVisible();
  await expect(page.getByText("− github", { exact: true })).toBeVisible();
  await expect(page.getByText("+ playground", { exact: true })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Supported links" })).toBeVisible();

  const landingMetrics = await page.locator(".shell.landing").evaluate(shell => ({
    width: shell.getBoundingClientRect().width,
    background: getComputedStyle(document.body).backgroundColor,
  }));
  expect(landingMetrics.width).toBeLessThanOrEqual(688);
  expect(landingMetrics.background).toBe("rgb(247, 247, 247)");
});

test("desktop keeps split columns balanced and switches views", async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await loadMockedCommit(page);

  await expect(page.getByText("example/project@", { exact: false })).toBeVisible();
  await expect(page).toHaveURL(`/#/example/project/commit/${commitSha}`);
  await expect(page.getByLabel("Shareable playground URL")).toHaveValue(page.url());
  await expect(page.getByRole("link", { name: "Open commit on GitHub" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Copy link" })).toBeVisible();
  await expect(page.locator(".summary-grid, .share-panel")).toHaveCount(0);

  const heroLayout = await page.locator(".hero").evaluate(hero => {
    const copy = hero.querySelector(".hero-copy").getBoundingClientRect();
    const controls = hero.querySelector(".hero-controls").getBoundingClientRect();
    return {
      height: hero.getBoundingClientRect().height,
      position: getComputedStyle(hero).position,
      top: getComputedStyle(hero).top,
      copyX: copy.x,
      copyCenterY: copy.y + copy.height / 2,
      controlsX: controls.x,
      controlsCenterY: controls.y + controls.height / 2,
    };
  });
  expect(heroLayout.height).toBeLessThanOrEqual(56);
  expect(heroLayout.position).toBe("sticky");
  expect(heroLayout.top).toBe("0px");
  expect(heroLayout.controlsX).toBeGreaterThan(heroLayout.copyX);
  expect(Math.abs(heroLayout.controlsCenterY - heroLayout.copyCenterY)).toBeLessThan(1);

  const fileHeading = await page.locator(".file-heading").first().evaluate(heading => ({
    height: heading.getBoundingClientRect().height,
    position: getComputedStyle(heading).position,
  }));
  expect(fileHeading.height).toBeLessThanOrEqual(48);
  expect(fileHeading.position).toBe("sticky");

  const maximumGutterWidth = await page
    .locator("table.split td.line-number")
    .evaluateAll(cells => Math.max(...cells.map(cell => cell.getBoundingClientRect().width)));
  expect(maximumGutterWidth).toBeLessThanOrEqual(64);

  const splitMetrics = await page.locator("table.split").evaluate(table => {
    const row = [...table.rows].find(candidate => candidate.querySelectorAll("td.ctx").length === 2);
    const codeCells = [...row.querySelectorAll("td.ctx")];
    return {
      tableWidth: table.getBoundingClientRect().width,
      leftWidth: codeCells[0].getBoundingClientRect().width,
      rightWidth: codeCells[1].getBoundingClientRect().width,
    };
  });
  expect(Math.abs(splitMetrics.leftWidth - splitMetrics.rightWidth)).toBeLessThanOrEqual(1);
  expect(splitMetrics.leftWidth).toBeGreaterThanOrEqual(splitMetrics.tableWidth * 0.4);
  expect(splitMetrics.rightWidth).toBeGreaterThanOrEqual(splitMetrics.tableWidth * 0.4);

  const changedRowColors = await page.locator("table.split tr").filter({
    has: page.locator("td.del"),
  }).first().evaluate(row => ({
    oldNumber: getComputedStyle(row.querySelector(".old-line-number")).backgroundColor,
    newNumber: getComputedStyle(row.querySelector(".new-line-number")).backgroundColor,
    oldCode: getComputedStyle(row.querySelector("td.del")).backgroundColor,
    newCode: getComputedStyle(row.querySelector("td.add")).backgroundColor,
  }));
  expect(changedRowColors.oldNumber).toBe(changedRowColors.oldCode);
  expect(changedRowColors.newNumber).toBe(changedRowColors.newCode);
  expect(changedRowColors.oldCode).not.toBe(changedRowColors.newCode);

  await page.getByRole("button", { name: "Use unified view" }).click();
  await expect(page.locator("table.unified")).toBeVisible();
  await expect(page.locator("table.split")).toHaveCount(0);
  await page.getByRole("button", { name: "Use split view" }).click();
  await expect(page.locator("table.split")).toBeVisible();
});

test("mixed commits use lazy line diffs and preserve binary file cards", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await loadMockedCommit(page);

  const cards = page.locator(".file-card");
  const moonbitCard = cards.filter({ hasText: "src/format_change.mbt" });
  const readmeCard = cards.filter({ hasText: "README.md" });
  const binaryCard = cards.filter({ hasText: "assets/logo.bin" });

  await expect(cards).toHaveCount(3);
  await expect(page.locator(".file-path")).toHaveText([
    "src/format_change.mbt",
    "README.md",
    "assets/logo.bin",
  ]);
  await expect(moonbitCard.locator("table.split")).toBeVisible();
  expect(await moonbitCard.locator("b.wd, b.wa").count()).toBeGreaterThan(0);
  await expect(readmeCard.getByRole("button", { name: "Expand" })).toBeVisible();
  await expect(binaryCard.getByRole("button", { name: "Expand" })).toBeVisible();
  await expect(page.locator(".diff-scroll")).toHaveCount(1);

  await readmeCard.getByRole("button", { name: "Expand" }).click();
  await expect(readmeCard.locator("table.split")).toBeVisible();
  await expect(readmeCard.locator("td.del")).toContainText("Use the <old> workflow.");
  await expect(readmeCard.locator("td.add")).toContainText("Use the &new workflow.");
  await expect(readmeCard.locator("b.wd, b.wa")).toHaveCount(0);

  await binaryCard.getByRole("button", { name: "Expand" }).click();
  await expect(binaryCard).toContainText("Cannot render: the file is binary or is not valid UTF-8.");
  await expect(binaryCard.locator(".diff-scroll")).toHaveCount(0);

  await page.getByRole("button", { name: "Use unified view" }).click();
  await expect(moonbitCard.locator("table.unified")).toBeVisible();
  await expect(readmeCard.locator("table.unified")).toBeVisible();
  await expect(page.locator("table.unified")).toHaveCount(2);
  await expect(readmeCard.locator("b.wd, b.wa")).toHaveCount(0);
});

test("a shared playground URL restores the commit and can be copied", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.context().grantPermissions(["clipboard-read", "clipboard-write"]);
  await openMockedShareLink(page);

  await expect(page.getByLabel("Public GitHub commit URL")).toHaveValue(commitUrl);
  await expect(page.getByLabel("Shareable playground URL")).toHaveValue(page.url());
  await page.getByRole("button", { name: "Copy link" }).click();
  await expect(page.getByRole("button", { name: "Copied" })).toBeVisible();
  await expect.poll(() => page.evaluate(() => navigator.clipboard.readText())).toBe(page.url());

  await page.reload();
  await expect(page.locator("table.split")).toBeVisible();
});

test("narrow viewport scrolls only the diff and keeps controls usable", async ({ page }) => {
  await page.setViewportSize({ width: 640, height: 900 });
  await loadMockedCommit(page);

  const heroLayout = await page.locator(".hero").evaluate(hero => {
    const copy = hero.querySelector(".hero-copy").getBoundingClientRect();
    const controls = hero.querySelector(".hero-controls").getBoundingClientRect();
    return { copyBottom: copy.bottom, controlsTop: controls.top };
  });
  expect(heroLayout.controlsTop).toBeGreaterThanOrEqual(heroLayout.copyBottom);

  const formFitsViewport = await page.locator(".commit-form").evaluate(form => {
    const input = form.querySelector("input").getBoundingClientRect();
    const button = form.querySelector("button").getBoundingClientRect();
    return input.left >= 0 && input.right <= innerWidth && button.left >= 0 && button.right <= innerWidth;
  });
  expect(formFitsViewport).toBe(true);

  const splitOverflow = await page.locator(".diff-scroll").evaluate(scroller => {
    const codeCells = [...scroller.querySelectorAll("table.split td.ctx, table.split td.del, table.split td.add")];
    return {
      clientWidth: scroller.clientWidth,
      scrollWidth: scroller.scrollWidth,
      codeDoesNotWrap: codeCells.every(cell => getComputedStyle(cell).whiteSpace === "pre"),
      documentClientWidth: document.documentElement.clientWidth,
      documentScrollWidth: document.documentElement.scrollWidth,
    };
  });
  expect(splitOverflow.scrollWidth).toBeGreaterThan(splitOverflow.clientWidth);
  expect(splitOverflow.codeDoesNotWrap).toBe(true);
  expect(splitOverflow.documentScrollWidth).toBeLessThanOrEqual(splitOverflow.documentClientWidth);

  const scroller = page.locator(".diff-scroll");
  await scroller.evaluate(element => {
    element.scrollLeft = 120;
  });
  expect(await scroller.evaluate(element => element.scrollLeft)).toBeGreaterThan(0);

  const fileButton = page
    .locator(".file-card")
    .filter({ hasText: "src/format_change.mbt" })
    .locator("button.file-toggle");
  await fileButton.click();
  await expect(page.locator(".file-card .diff-scroll")).toHaveCount(0);
  await expect(fileButton).toHaveAttribute("aria-expanded", "false");
  await fileButton.click();
  await expect(fileButton).toHaveAttribute("aria-expanded", "true");
  await expect(page.locator(".file-card .diff-scroll")).toBeVisible();

  await page.getByRole("button", { name: "Use unified view" }).click();
  await expect(page.locator("table.unified")).toBeVisible();
  const unifiedOverflow = await page.locator(".diff-scroll").evaluate(element => ({
    clientWidth: element.clientWidth,
    scrollWidth: element.scrollWidth,
  }));
  expect(unifiedOverflow.scrollWidth).toBeGreaterThan(unifiedOverflow.clientWidth);
});

test("Ignore comments works across algorithms and layouts without changing plain text", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await loadCommentsCommit(page);

  const toggle = page.getByRole("button", { name: "Ignore comments" });
  const mixedCard = page.locator(".file-card").filter({ hasText: "src/mixed.mbt" });
  const commentsOnlyCard = page.locator(".file-card").filter({ hasText: "src/comments_only.mbt" });
  const blankLinesOnlyCard = page.locator(".file-card").filter({ hasText: "src/blank_lines_only.mbt" });
  const plainCard = page.locator(".file-card").filter({ hasText: "notes.txt" });
  const plainBlankLinesCard = page.locator(".file-card").filter({ hasText: "blank_lines.txt" });
  await expect(toggle).toHaveAttribute("aria-pressed", "false");
  await expect(toggle).toHaveAttribute(
    "title",
    "Ignore MoonBit comment and blank-line changes",
  );
  await expect(commentsOnlyCard.locator("table.split")).toBeVisible();
  await expect(blankLinesOnlyCard.locator("table.split")).toBeVisible();

  await plainCard.getByRole("button", { name: "Expand" }).click();
  await plainBlankLinesCard.getByRole("button", { name: "Expand" }).click();
  await expect(plainCard.locator("td.del")).toContainText("// old plain-text note");
  const plainBlankLineNumber = plainBlankLinesCard
    .locator("td.new-line-number")
    .filter({ hasText: /^2$/ });
  const plainBlankSplitRow = plainBlankLineNumber.locator("xpath=..");
  await expect(plainBlankLineNumber).toHaveCount(1);
  await expect(plainBlankSplitRow.locator("td.old-line-number")).toHaveText("");
  await expect(plainBlankSplitRow.locator("td").nth(3)).toHaveText("");
  const plainBlankSplitHtml = await plainBlankLinesCard.locator(".diff-scroll").innerHTML();
  await toggle.click();
  await expect(toggle).toHaveAttribute("aria-pressed", "true");
  await expect(toggle).toHaveAttribute(
    "title",
    "Show comment and blank-line changes",
  );
  await expect(commentsOnlyCard).toContainText(
    "No changes besides comments or blank lines found. Turn off Ignore comments",
  );
  await expect(commentsOnlyCard.locator("table")).toHaveCount(0);
  await expect(blankLinesOnlyCard).toContainText(
    "No changes besides comments or blank lines found. Turn off Ignore comments",
  );
  await expect(blankLinesOnlyCard.locator("table")).toHaveCount(0);
  expect(await mixedCard.locator("td.ctx.ignored").count()).toBeGreaterThan(2);
  await expect(mixedCard.locator("td.ctx.ignored").first()).toContainText("/// old docs");
  await expect(mixedCard.locator(".ignored-context")).toContainText([
    "/// old docs",
    "/// new docs",
    " // old trailing",
    "  // new trailing",
  ]);
  await expect(mixedCard.locator("b.wd")).toContainText("old_value");
  await expect(mixedCard.locator("b.wa")).toContainText("new_value");
  await expect(plainCard.locator("td.del")).toContainText("// old plain-text note");
  await expect(plainCard.locator("td.add")).toContainText("// new plain-text note");
  await expect(plainBlankLinesCard.locator(".diff-scroll")).toHaveJSProperty(
    "innerHTML",
    plainBlankSplitHtml,
  );

  await page.getByRole("button", { name: "AST" }).click();
  await expect(commentsOnlyCard).toContainText(
    "No structural changes besides comments or blank lines found",
  );
  await expect(blankLinesOnlyCard).toContainText(
    "No structural changes besides comments or blank lines found",
  );
  await expect(mixedCard.locator("b.wd")).toContainText("old_value");
  await expect(
    mixedCard.locator(".ignored-context").filter({ hasText: "old trailing" }),
  ).toHaveCount(1);
  await page.getByRole("button", { name: "Use unified view" }).click();
  await expect(mixedCard.locator("table.unified")).toBeVisible();
  expect(await mixedCard.locator("td.ctx.ignored").count()).toBeGreaterThan(2);
  await expect(blankLinesOnlyCard.locator("table")).toHaveCount(0);
  const unifiedPlainBlankLineNumber = plainBlankLinesCard
    .locator("td.new-line-number")
    .filter({ hasText: /^2$/ });
  await expect(unifiedPlainBlankLineNumber).toHaveCount(1);
  await expect(
    unifiedPlainBlankLineNumber.locator("xpath=..").locator("td.old-line-number"),
  ).toHaveText("");

  await page.getByRole("button", { name: "Lexical" }).click();
  await toggle.click();
  await expect(toggle).toHaveAttribute("aria-pressed", "false");
  await expect(commentsOnlyCard.locator("table.unified")).toBeVisible();
  await expect(blankLinesOnlyCard.locator("table.unified")).toBeVisible();

  await page.setViewportSize({ width: 420, height: 900 });
  const compactToggle = await toggle.evaluate(button => ({
    left: button.getBoundingClientRect().left,
    right: button.getBoundingClientRect().right,
    width: button.getBoundingClientRect().width,
    labelDisplay: getComputedStyle(button.querySelector(".ignore-comments-label")).display,
    pageWidth: document.documentElement.scrollWidth,
    viewportWidth: document.documentElement.clientWidth,
  }));
  expect(compactToggle.left).toBeGreaterThanOrEqual(0);
  expect(compactToggle.right).toBeLessThanOrEqual(420);
  expect(compactToggle.width).toBeLessThanOrEqual(36);
  expect(compactToggle.labelDisplay).toBe("none");
  expect(compactToggle.pageWidth).toBeLessThanOrEqual(compactToggle.viewportWidth);
});

test("Ignore comments skips blank-line-only MoonBit changes during analysis", async ({ page }) => {
  let analyzeCalls = 0;
  await page.route("**/api/analyze", async route => {
    analyzeCalls += 1;
    await route.fulfill({ status: 500, body: "unexpected" });
  });
  await loadCommentsCommit(page, { blankOnly: true, health: true });
  const blankCard = page.locator(".file-card").filter({ hasText: "src/blank_lines_only.mbt" });
  await page.getByRole("button", { name: "Ignore comments" }).click();
  await expect(blankCard).toContainText(
    "No changes besides comments or blank lines found",
  );
  await page.getByRole("button", { name: "Analyze changes" }).click();
  await expect(page.getByRole("heading", { name: "Nothing to analyze" })).toBeVisible();
  await expect(page.locator(".analysis-skipped")).toContainText("src/blank_lines_only.mbt");
  await expect(page.locator(".analysis-skipped")).toContainText(
    "No changes besides comments or blank lines were found",
  );
  expect(analyzeCalls).toBe(0);

  await page.getByRole("button", { name: "AST" }).click();
  await expect(blankCard).toContainText(
    "No structural changes besides comments or blank lines found",
  );
  await page.getByRole("button", { name: "Analyze changes" }).click();
  await expect(page.locator(".analysis-skipped")).toContainText(
    "No structural changes besides comments or blank lines were found",
  );
  expect(analyzeCalls).toBe(0);
});

test("AST mode keeps structural spans, empty states, line diffs, and layouts usable", async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await loadAlgorithmCommit(page);

  const formattingCard = page.locator(".file-card").filter({ hasText: "src/formatting_only.mbt" });
  const structuralCard = page.locator(".file-card").filter({ hasText: "src/structural.mbt" });
  const readmeCard = page.locator(".file-card").filter({ hasText: "README.md" });
  const urlBeforeSwitch = page.url();

  await expect(page.getByRole("button", { name: "Lexical" })).toHaveAttribute("aria-pressed", "true");
  await expect(formattingCard.locator("table.split")).toBeVisible();
  await page.getByRole("button", { name: "AST" }).click();
  await expect(page.getByRole("button", { name: "AST" })).toHaveAttribute("aria-pressed", "true");
  await expect(formattingCard).toContainText(
    "No structural changes found. Switch to Lexical to view text changes.",
  );
  await expect(formattingCard.locator("table")).toHaveCount(0);

  await expect(structuralCard.locator("table.split")).toBeVisible();
  await expect(structuralCard.locator("b.wd")).toContainText("old_call");
  await expect(structuralCard.locator("b.wa")).toContainText("new_call");
  await expect(structuralCard.locator("td.old-line-number").first()).not.toHaveText("");
  await expect(structuralCard).toContainText('"<script>&safe"');
  await expect(structuralCard.locator("script")).toHaveCount(0);

  await readmeCard.getByRole("button", { name: "Expand" }).click();
  await expect(readmeCard.locator("table.split")).toBeVisible();
  const lineHtmlInAstMode = await readmeCard.locator(".diff-scroll").innerHTML();
  await expect(readmeCard.locator("b.wd, b.wa")).toHaveCount(0);

  await page.getByRole("button", { name: "Use unified view" }).click();
  await expect(structuralCard.locator("table.unified")).toBeVisible();
  await expect(readmeCard.locator("table.unified")).toBeVisible();
  await expect(structuralCard.locator("b.wd")).toContainText("old_call");
  await expect(structuralCard.locator("b.wa")).toContainText("new_call");

  await page.setViewportSize({ width: 640, height: 900 });
  const astOverflow = await structuralCard.locator(".diff-scroll").evaluate(element => ({
    clientWidth: element.clientWidth,
    scrollWidth: element.scrollWidth,
    pageWidth: document.documentElement.scrollWidth,
    viewportWidth: document.documentElement.clientWidth,
  }));
  expect(astOverflow.scrollWidth).toBeGreaterThan(astOverflow.clientWidth);
  expect(astOverflow.pageWidth).toBeLessThanOrEqual(astOverflow.viewportWidth);

  await page.getByRole("button", { name: "Lexical" }).click();
  await expect(formattingCard.locator("table.unified")).toBeVisible();
  await page.getByRole("button", { name: "Use split view" }).click();
  await expect(readmeCard.locator(".diff-scroll")).toHaveJSProperty("innerHTML", lineHtmlInAstMode);
  expect(page.url()).toBe(urlBeforeSwitch);
  expect(new URL(page.url()).search).toBe("");
  expect(new URL(page.url()).hash).toBe(`#/example/algorithms/commit/${algorithmSha}`);
});

test("AST structural empty analysis is handled locally without a backend request", async ({ page }) => {
  let analyzeCalls = 0;
  await page.route("**/api/analyze", async route => {
    analyzeCalls += 1;
    await route.fulfill({ status: 500, body: "unexpected" });
  });
  await loadAlgorithmCommit(page, { formatOnly: true, health: true });
  await page.getByRole("button", { name: "AST" }).click();
  await expect(page.locator(".structural-empty")).toBeVisible();
  await page.getByRole("button", { name: "Analyze changes" }).click();
  await expect(page.getByRole("heading", { name: "Nothing to analyze" })).toBeVisible();
  await expect(page.locator(".analysis-skipped")).toContainText("src/formatting_only.mbt");
  await expect(page.locator(".analysis-skipped")).toContainText("No structural changes");
  expect(analyzeCalls).toBe(0);
});

test("the selected algorithm survives later commit navigation without entering the URL", async ({ page }) => {
  await loadAlgorithmCommit(page);
  await page.getByRole("button", { name: "AST" }).click();
  await page.getByRole("button", { name: "Ignore comments" }).click();
  const nextSha = "3333333333333333333333333333333333333333";
  const nextUrl = `https://github.com/example/algorithms/commit/${nextSha}`;
  await page.getByLabel("Public GitHub commit URL").fill(nextUrl);
  await page.getByRole("button", { name: "View diff" }).click();
  await expect(page.getByRole("button", { name: "AST" })).toHaveAttribute("aria-pressed", "true");
  await expect(page.getByRole("button", { name: "Ignore comments" })).toHaveAttribute("aria-pressed", "true");
  await expect(page.locator(".structural-empty")).toBeVisible();
  await expect(page).toHaveURL(`/#/example/algorithms/commit/${nextSha}`);
  expect(new URL(page.url()).search).toBe("");
  expect(page.url()).not.toContain("ignore");
});

test("parse failures show their lexical fallback reason above both layouts", async ({ page }) => {
  await loadAlgorithmCommit(page, { formatOnly: true, parseFailure: true });
  const card = page.locator(".file-card").filter({ hasText: "src/formatting_only.mbt" });
  await expect(card.locator(".diff-notice")).toContainText("Lexical fallback");
  await expect(card.locator(".diff-notice")).toContainText("this entire file");
  await expect(card.locator(".diff-notice")).toContainText("old:");
  await expect(card.locator("table.split")).toBeVisible();
  await page.getByRole("button", { name: "AST" }).click();
  await expect(card.locator(".diff-notice")).toContainText("Lexical fallback");
  await expect(card.locator(".diff-notice")).toContainText("this entire file");
  await page.getByRole("button", { name: "Use unified view" }).click();
  await expect(card.locator("table.unified")).toBeVisible();
  await expect(card.locator(".diff-notice")).toContainText("old:");
});

test("switching algorithms cancels the visible analysis and ignores its late response", async ({ page }) => {
  await installAnalysisHealth(page);
  let releaseAnalysis;
  const analysisGate = new Promise(resolve => {
    releaseAnalysis = resolve;
  });
  await page.route("**/api/analyze", async route => {
    const request = route.request().postDataJSON();
    await analysisGate;
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify(analysisForRequest(request)),
    });
  });
  await loadMockedCommit(page);
  await page.getByRole("button", { name: "Analyze changes" }).click();
  await expect(page.getByRole("button", { name: "Analyzing…" })).toBeVisible();
  await page.getByRole("button", { name: "AST" }).click();
  await expect(page.locator(".analysis-card")).toHaveCount(0);
  await expect(page.locator(".file-card")).toHaveCount(3);
  const lateResponse = page.waitForResponse(response => response.url().endsWith("/api/analyze"));
  releaseAnalysis();
  await lateResponse;
  await expect(page.getByRole("heading", { name: "Change groups" })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Analyze changes" })).toBeVisible();
});

test("manual functional analysis prepares the whole commit and annotates stable hunks", async ({ page }) => {
  await installAnalysisHealth(page);
  let submitted;
  await page.route("**/api/analyze", async route => {
    submitted = route.request().postDataJSON();
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify(analysisForRequest(submitted)),
    });
  });
  await loadMockedCommit(page);

  await expect(page.getByRole("button", { name: "Analyze changes" })).toBeVisible();
  await page.getByRole("button", { name: "Analyze changes" }).click();
  await expect(page.getByRole("heading", { name: "Change groups" })).toBeVisible();

  expect(submitted.version).toBe(1);
  expect(submitted.commit).toMatchObject({
    owner: "example",
    repo: "project",
    sha: commitSha,
    parent_sha: parentSha,
  });
  expect(submitted.hunks.map(hunk => hunk.id)).toEqual(["f0-h0", "f1-h0"]);
  expect(submitted.hunks.map(hunk => hunk.path)).toEqual([
    "src/format_change.mbt",
    "README.md",
  ]);
  expect(submitted.hunks.every(hunk => hunk.patch.startsWith("@@ "))).toBe(true);
  expect(submitted.skipped_files.map(file => file.path)).toEqual(["assets/logo.bin"]);

  await expect(page.locator(".analysis-summary")).toContainText("formatting behavior");
  await expect(page.locator(".analysis-skipped")).toContainText("assets/logo.bin");
  await expect(page.locator(".analysis-group-title")).toHaveText([
    "Documentation flow",
    "Formatting behavior",
  ]);
  const groups = page.locator(".analysis-group");
  await expect(groups).toHaveCount(2);
  await expect(groups.nth(0).getByRole("button", { name: "Collapse Documentation flow" })).toHaveAttribute("aria-expanded", "true");
  await expect(groups.nth(1).getByRole("button", { name: "Expand Formatting behavior" })).toHaveAttribute("aria-expanded", "false");
  await expect(page.locator(".file-list, .file-card")).toHaveCount(0);
  await expect(page.locator(".analysis-hunk")).toHaveCount(1);
  await expect(page.locator(".analysis-hunk .file-path")).toHaveText("README.md");
  await expect(page.locator(".diff-scroll")).toHaveCount(1);
  await expect(page.locator("td.hunk-note")).toHaveCount(1);
  await expect(page.locator("td.hunk-note")).toContainText("Documentation flow");
  await expect(page.locator("td.hunk-note")).toContainText("Refreshes the user-facing workflow description.");

  await groups.nth(1).getByRole("button", { name: "Expand Formatting behavior" }).click();
  await expect(page.locator(".analysis-hunk")).toHaveCount(2);
  await expect(page.locator("td.hunk-note")).toHaveCount(2);
  await expect(groups.nth(1).locator("td.hunk-note")).toContainText("Updates <formatting> & output behavior.");
  await expect(groups.nth(1).locator("td.hunk-note script, td.hunk-note formatting")).toHaveCount(0);
  await page.getByRole("button", { name: "Use unified view" }).click();
  await expect(page.locator("table.unified td.hunk-note")).toHaveCount(2);
  await groups.nth(0).getByRole("button", { name: "Collapse Documentation flow" }).click();
  await expect(page.locator("table.unified td.hunk-note")).toHaveCount(1);
  await expect(groups.nth(1).locator("table.unified td.hunk-note")).toContainText("Formatting behavior");
});

test("analysis errors can be retried without reloading or expanding files", async ({ page }) => {
  await installAnalysisHealth(page);
  let attempts = 0;
  await page.route("**/api/analyze", async route => {
    attempts += 1;
    const request = route.request().postDataJSON();
    if (attempts === 1) {
      await route.fulfill({
        status: 502,
        contentType: "application/json",
        body: JSON.stringify({
          version: 1,
          ok: false,
          error: {
            code: "invalid_answer",
            message: "OpenSeek returned malformed JSON, so the analysis could not be displayed. Please retry.",
          },
        }),
      });
    } else {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify(analysisForRequest(request)),
      });
    }
  });
  await loadMockedCommit(page);
  await page.getByRole("button", { name: "Analyze changes" }).click();
  await expect(page.getByRole("heading", { name: "Analysis failed" })).toBeVisible();
  await expect(page.locator(".analysis-card")).toContainText(
    "OpenSeek returned malformed JSON, so the analysis could not be displayed. Please retry.",
  );
  await page.locator(".analysis-card").getByRole("button", { name: "Retry analysis" }).click();
  await expect(page.getByRole("heading", { name: "Change groups" })).toBeVisible();
  expect(attempts).toBe(2);
  await expect(page.locator(".analysis-group").first().getByRole("button", { name: "Collapse Documentation flow" })).toBeVisible();
  await expect(page.locator(".file-card")).toHaveCount(0);
});

test("a static deployment hides analysis when no backend is detected", async ({ page }) => {
  await loadMockedCommit(page);
  await expect(page.getByRole("button", { name: /Analyze changes|Retry analysis|Analyze again/ })).toHaveCount(0);
});
