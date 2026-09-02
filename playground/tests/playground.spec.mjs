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
const structuralOld = [
  "fn unchanged_before() {}",
  "",
  "/// structural docs",
  "fn structural() {",
  "  stable_prefix_one()",
  "  stable_prefix_two()",
  "  stable_prefix_three()",
  "  stable_prefix_four()",
  '  old_call("<script>&safe")',
  "  stable_middle_one()",
  "  stable_middle_two()",
  "  stable_middle_three()",
  "  stable_middle_four()",
  "  stable_middle_five()",
  "  old_tail()",
  "  stable_suffix_one()",
  "  stable_suffix_two()",
  "  stable_suffix_three()",
  "  stable_suffix_four()",
  "}",
  "",
  "fn unchanged_after() {}",
].join("\n");
const structuralNew = [
  "fn unchanged_before() {}",
  "",
  "/// structural docs",
  "fn structural() {",
  "  stable_prefix_one()",
  "  stable_prefix_two()",
  "  stable_prefix_three()",
  "  stable_prefix_four()",
  '  new_call("<script>&safe")',
  "  stable_middle_one()",
  "  stable_middle_two()",
  "  stable_middle_three()",
  "  stable_middle_four()",
  "  stable_middle_five()",
  "  new_tail()",
  "  stable_suffix_one()",
  "  stable_suffix_two()",
  "  stable_suffix_three()",
  "  stable_suffix_four()",
  "}",
  "",
  "fn unchanged_after() {}",
].join("\n");
const structuralPatch = [
  "@@ -1,22 +1,22 @@",
  " fn unchanged_before() {}",
  " ",
  " /// structural docs",
  " fn structural() {",
  "   stable_prefix_one()",
  "   stable_prefix_two()",
  "   stable_prefix_three()",
  "   stable_prefix_four()",
  '-  old_call("<script>&safe")',
  '+  new_call("<script>&safe")',
  "   stable_middle_one()",
  "   stable_middle_two()",
  "   stable_middle_three()",
  "   stable_middle_four()",
  "   stable_middle_five()",
  "-  old_tail()",
  "+  new_tail()",
  "   stable_suffix_one()",
  "   stable_suffix_two()",
  "   stable_suffix_three()",
  "   stable_suffix_four()",
  " }",
  " ",
  " fn unchanged_after() {}",
].join("\n");

const collapsibleSectionsOld = [
  "fn first_change() -> Int {",
  "  old_first()",
  "}",
  "",
  "fn second_change() -> Int {",
  "  old_second()",
  "}",
].join("\n");
const collapsibleSectionsNew = [
  "fn first_change() -> Int {",
  "  new_first()",
  "}",
  "",
  "fn second_change() -> Int {",
  "  new_second()",
  "}",
].join("\n");
const collapsibleSectionsPatch = [
  "@@ -1,7 +1,7 @@",
  " fn first_change() -> Int {",
  "-  old_first()",
  "+  new_first()",
  " }",
  " ",
  " fn second_change() -> Int {",
  "-  old_second()",
  "+  new_second()",
  " }",
].join("\n");

const longFunctionName = `render${"semanticsectioncontext".repeat(12)}`;
const longDeclarationOld = [
  "///|",
  `fn ${longFunctionName}() -> Int {`,
  "  1",
  "}",
].join("\n");
const longDeclarationNew = [
  "///|",
  `fn ${longFunctionName}() -> Int {`,
  "  2",
  "}",
].join("\n");
const longDeclarationFile = {
  filename: "src/long_declaration.mbt",
  status: "modified",
  additions: 1,
  deletions: 1,
  changes: 2,
};

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

const testsSha = "5555555555555555555555555555555555555555";
const testsUrl = `https://github.com/example/tests/commit/${testsSha}`;
const mixedTestsOld = [
  'test "sample" { old_test() }',
  "fn production() { old_value() }",
].join("\n");
const mixedTestsNew = [
  'test "sample" { new_test() }',
  "fn production() { new_value() }",
].join("\n");
const testsOnlyOld = [
  "/// old test docs",
  "///|UUID(old-test)",
  'async test "sample" { old_test() }',
].join("\n");
const testsOnlyNew = [
  "/// new test docs",
  "///|UUID(new-test)",
  'async test "renamed" { new_test() }',
].join("\n");
const combinedOnlyOld = [
  "/// old production docs",
  "fn stable() {}",
  'test "sample" { old_test() }',
].join("\n");
const combinedOnlyNew = [
  "/// new production docs",
  "fn stable() {}",
  'test "sample" { new_test() }',
].join("\n");
const plainTestsOld = 'test "plain" { old_value() }';
const plainTestsNew = 'test "plain" { new_value() }';

const testsCommit = {
  sha: testsSha,
  html_url: testsUrl,
  commit: { message: "Exercise test filtering" },
  parents: [{ sha: parentSha }],
  stats: { additions: 5, deletions: 5, total: 10 },
  files: [
    {
      filename: "src/mixed_tests.mbt",
      status: "modified",
      additions: 2,
      deletions: 2,
      changes: 4,
    },
    {
      filename: "src/tests_only.mbt",
      status: "modified",
      additions: 3,
      deletions: 3,
      changes: 6,
    },
    {
      filename: "src/combined_only.mbt",
      status: "modified",
      additions: 2,
      deletions: 2,
      changes: 4,
    },
    {
      filename: "tests.txt",
      status: "modified",
      additions: 1,
      deletions: 1,
      changes: 2,
    },
  ],
};

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
  stats: { additions: 8, deletions: 6, total: 14 },
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
      additions: 2,
      deletions: 2,
      changes: 4,
      patch: structuralPatch,
    },
    {
      filename: "src/collapsible_sections.mbt",
      status: "modified",
      additions: 2,
      deletions: 2,
      changes: 4,
      patch: collapsibleSectionsPatch,
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

const treeSha = "3333333333333333333333333333333333333333";
const treeUrl = `https://github.com/example/tree/commit/${treeSha}`;
const treeCommit = {
  sha: treeSha,
  html_url: treeUrl,
  commit: { message: "Exercise the changed-file tree" },
  parents: [{ sha: parentSha }],
  stats: { additions: 7, deletions: 6, total: 13 },
  files: [
    {
      filename: "src/core/main.mbt",
      status: "modified",
      additions: 1,
      deletions: 1,
      changes: 2,
    },
    {
      filename: "src/utils/helper.mbt",
      status: "added",
      additions: 2,
      deletions: 0,
      changes: 2,
    },
    {
      filename: "docs/guide.md",
      status: "removed",
      additions: 0,
      deletions: 2,
      changes: 2,
    },
    {
      filename: "src/renamed/new_name.mbt",
      previous_filename: "legacy/Old_Name.mbt",
      status: "renamed",
      additions: 2,
      deletions: 2,
      changes: 4,
    },
    {
      filename: "COPYING",
      status: "copied",
      additions: 2,
      deletions: 1,
      changes: 3,
    },
  ],
};

const pullNumber = 4082;
const pullUrl = `https://github.com/example/project/pull/${pullNumber}`;
const pullFilesUrl = `${pullUrl}/files`;
const pullMergeBaseOne = "7777777777777777777777777777777777777777";
const pullMergeBaseTwo = "6666666666666666666666666666666666666666";
const pullBaseSha = "8888888888888888888888888888888888888888";
const pullHeadOne = "9999999999999999999999999999999999999999";
const pullHeadTwo = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const pullFirstPage = Array.from({ length: 100 }, (_, index) => ({
  filename: `notes/change_${String(index).padStart(3, "0")}.txt`,
  status: "modified",
  additions: 1,
  deletions: 1,
  changes: 2,
}));
const pullSecondPage = [{
  filename: "src/from_second_commit.mbt",
  status: "modified",
  additions: 2,
  deletions: 1,
  changes: 3,
}];
function pullMetadata(head) {
  return {
    title: head === pullHeadTwo
      ? "Aggregate the latest PR snapshot"
      : "Aggregate changes from both PR commits",
    html_url: pullUrl,
    base: { sha: pullBaseSha },
    head: { sha: head },
    additions: head === pullHeadTwo ? 103 : 102,
    deletions: 101,
    changed_files: 101,
  };
}

function mergeBaseForHead(head) {
  return head === pullHeadTwo ? pullMergeBaseTwo : pullMergeBaseOne;
}

async function installFetchCacheRecorder(page) {
  await page.addInitScript(() => {
    const originalFetch = window.fetch;
    window.__moondiffFetchCalls = [];
    window.fetch = function(input, init) {
      const request = input instanceof Request ? input : null;
      const url = request?.url ?? new URL(String(input), window.location.href).href;
      window.__moondiffFetchCalls.push({
        url,
        cache: init?.cache ?? request?.cache ?? "default",
      });
      return originalFetch.call(this, input, init);
    };
  });
}

async function installPullRoutes(page, { heads = [pullHeadOne] } = {}) {
  let metadataCalls = 0;
  const apiRequests = [];
  const mutableApiRequests = [];
  const rawRequests = [];
  await installFetchCacheRecorder(page);
  await page.route("https://**", route => route.abort("blockedbyclient"));
  await page.route("https://api.github.com/**", async route => {
    const request = route.request();
    const url = new URL(request.url());
    apiRequests.push(url.toString());
    let body;
    if (url.pathname.includes("/compare/")) {
      const comparison = url.pathname.split("/compare/")[1];
      const [base, head] = comparison.split("...");
      expect(base).toBe(pullBaseSha);
      body = { merge_base_commit: { sha: mergeBaseForHead(head) } };
    } else if (url.pathname.endsWith(`/pulls/${pullNumber}/files`)) {
      mutableApiRequests.push({
        url: url.toString(),
        headers: await request.allHeaders(),
      });
      body = url.searchParams.get("page") === "2"
        ? pullSecondPage
        : pullFirstPage;
    } else {
      mutableApiRequests.push({
        url: url.toString(),
        headers: await request.allHeaders(),
      });
      const head = heads[Math.min(metadataCalls, heads.length - 1)];
      metadataCalls += 1;
      body = pullMetadata(head);
    }
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      headers: {
        "access-control-allow-origin": "*",
        "cache-control": "public, max-age=60",
      },
      body: JSON.stringify(body),
    });
  });
  await page.route("https://raw.githubusercontent.com/**", async route => {
    const rawUrl = route.request().url();
    rawRequests.push(rawUrl);
    const parts = new URL(rawUrl).pathname.split("/");
    const revision = parts[3];
    const body = revision === pullMergeBaseOne
      ? "fn aggregate() -> String { \"merge base one\" }"
      : revision === pullMergeBaseTwo
        ? "fn aggregate() -> String { \"merge base two\" }"
      : revision === pullHeadTwo
        ? "fn aggregate() -> String { \"head two\" }"
        : "fn aggregate() -> String { \"head one\" }";
    await route.fulfill({
      status: 200,
      contentType: "text/plain",
      headers: { "access-control-allow-origin": "*" },
      body,
    });
  });
  return {
    apiRequests,
    mutableApiRequests,
    rawRequests,
    fetchCalls: () => page.evaluate(() => window.__moondiffFetchCalls),
    metadataCalls: () => metadataCalls,
  };
}

function expectRevalidatingRequests(requests, fetchCalls) {
  expect(requests.length).toBeGreaterThan(0);
  expect(fetchCalls).toHaveLength(requests.length);
  for (const [index, request] of requests.entries()) {
    expect(fetchCalls[index].url).toBe(request.url);
    expect(fetchCalls[index].cache).toBe("no-cache");
    // Playwright routing disables its HTTP cache, so a cold mocked request can
    // omit Chromium's derived Cache-Control header. Validate it when present.
    const cacheControl = request.headers["cache-control"] ?? "";
    if (cacheControl !== "") {
      expect(cacheControl).toMatch(/max-age=0|no-cache/i);
    }
  }
}

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

async function installTreeRoutes(page) {
  const rawRequests = [];
  await page.route("https://**", route => route.abort("blockedbyclient"));
  await page.route("https://api.github.com/**", route => route.fulfill({
    status: 200,
    contentType: "application/json",
    headers: { "access-control-allow-origin": "*" },
    body: JSON.stringify(treeCommit),
  }));
  await page.route("https://raw.githubusercontent.com/**", async route => {
    const url = new URL(route.request().url());
    const parts = url.pathname.split("/");
    const revision = parts[3];
    const filename = decodeURIComponent(parts.slice(4).join("/"));
    rawRequests.push(filename);
    const old = revision === parentSha;
    let body;
    if (filename === "src/core/main.mbt") {
      body = [
        "fn main() {",
        ...Array.from({ length: 32 }, (_, index) => `  ${old ? "old" : "new"}_value_${index}()`),
        "}",
      ].join("\n");
    } else if (filename === "src/utils/helper.mbt") {
      body = [
        "fn helper() {",
        ...Array.from({ length: 24 }, (_, index) => `  added_value_${index}()`),
        "}",
      ].join("\n");
    } else if (filename === "docs/guide.md") {
      body = "# Removed guide\nOld instructions";
    } else if (filename === "legacy/Old_Name.mbt") {
      body = "fn old_name() { old_value() }";
    } else if (filename === "src/renamed/new_name.mbt") {
      body = "fn new_name() { new_value() }";
    } else {
      body = old ? "Copyright old" : "Copyright copied\nAll rights reserved";
    }
    await route.fulfill({
      status: 200,
      contentType: "text/plain",
      headers: { "access-control-allow-origin": "*" },
      body,
    });
  });
  return rawRequests;
}

async function installAlgorithmRoutes(
  page,
  {
    formatOnly = false,
    longDeclarationOnly = false,
    parseFailure = false,
    extensionHost = false,
  } = {},
) {
  const commit = formatOnly
    ? { ...algorithmCommit, files: [algorithmCommit.files[0]] }
    : longDeclarationOnly
      ? {
        ...algorithmCommit,
        stats: { additions: 1, deletions: 1, total: 2 },
        files: [longDeclarationFile],
      }
      : algorithmCommit;
  if (extensionHost) {
    await page.addInitScript(
      ({
        commit,
        parentSha,
        formattingOld,
        formattingNew,
        structuralOld,
        structuralNew,
        collapsibleSectionsOld,
        collapsibleSectionsNew,
        oldReadme,
        newReadme,
      }) => {
        globalThis.__MOONDIFF_EXTENSION_HOST__ = {
          async request(operation, args) {
            if (operation === "auth.status") {
              return { authenticated: true, login: "reviewer" };
            }
            if (operation === "github.comments.list") {
              return { issue_comments: [], review_comments: [], commit_comments: [] };
            }
            if (operation === "github.commit.get") return commit;
            if (operation === "github.content.get") {
              const old = args.ref === parentSha;
              const body = args.path === "src/formatting_only.mbt"
                ? (old ? formattingOld : formattingNew)
                : args.path === "src/structural.mbt"
                  ? (old ? structuralOld : structuralNew)
                  : args.path === "src/collapsible_sections.mbt"
                    ? (old ? collapsibleSectionsOld : collapsibleSectionsNew)
                  : (old ? oldReadme : newReadme);
              return {
                base64: btoa(body),
                size: body.length,
                contentType: "text/plain",
              };
            }
            throw Object.assign(new Error(`Unhandled test operation: ${operation}`), {
              status: 400,
              code: "unhandled_test_operation",
            });
          },
        };
      },
      {
        commit,
        parentSha,
        formattingOld,
        formattingNew,
        structuralOld,
        structuralNew,
        collapsibleSectionsOld,
        collapsibleSectionsNew,
        oldReadme,
        newReadme,
      },
    );
  }
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
    } else if (filename === "src/collapsible_sections.mbt") {
      body = revision === parentSha ? collapsibleSectionsOld : collapsibleSectionsNew;
    } else if (filename === longDeclarationFile.filename) {
      body = revision === parentSha ? longDeclarationOld : longDeclarationNew;
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
  await page.getByLabel("Public GitHub commit or pull request URL").fill(algorithmUrl);
  await page.getByRole("button", { name: "View diff" }).click();
  await expect(page.locator("table.split").first()).toBeVisible();
}

async function installTestsRoutes(
  page,
  { testsOnly = false } = {},
) {
  const commit = testsOnly
    ? { ...testsCommit, files: [testsCommit.files[1]] }
    : testsCommit;
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
    if (filename === "src/mixed_tests.mbt") {
      body = revision === parentSha ? mixedTestsOld : mixedTestsNew;
    } else if (filename === "src/tests_only.mbt") {
      body = revision === parentSha ? testsOnlyOld : testsOnlyNew;
    } else if (filename === "src/combined_only.mbt") {
      body = revision === parentSha ? combinedOnlyOld : combinedOnlyNew;
    } else {
      body = revision === parentSha ? plainTestsOld : plainTestsNew;
    }
    await route.fulfill({
      status: 200,
      contentType: "text/plain",
      headers: { "access-control-allow-origin": "*" },
      body,
    });
  });
}

async function loadTestsCommit(page, options) {
  await installTestsRoutes(page, options);
  await page.goto("/");
  await page.getByLabel("Public GitHub commit or pull request URL").fill(testsUrl);
  await page.getByRole("button", { name: "View diff" }).click();
  await expect(page.locator("table.split").first()).toBeVisible();
}

async function installCommentsRoutes(
  page,
  { blankOnly = false } = {},
) {
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
  await page.getByLabel("Public GitHub commit or pull request URL").fill(commentsUrl);
  await page.getByRole("button", { name: "View diff" }).click();
  await expect(page.locator("table.split").first()).toBeVisible();
}

async function loadMockedCommit(page) {
  await installMockRoutes(page);
  await page.goto("/");
  await page.getByLabel("Public GitHub commit or pull request URL").fill(commitUrl);
  await page.getByRole("button", { name: "View diff" }).click();
  await expect(page.locator("table.split")).toBeVisible();
  await expect(page.getByRole("button", { name: "Lexical" })).toHaveAttribute("aria-pressed", "true");
}

async function loadTreeCommit(page) {
  const rawRequests = await installTreeRoutes(page);
  await page.goto("/");
  await page.getByLabel("Public GitHub commit or pull request URL").fill(treeUrl);
  await page.getByRole("button", { name: "View diff" }).click();
  await expect(page.locator("table.split").first()).toBeVisible();
  return rawRequests;
}

async function fileTreeWidth(page) {
  return page.locator("#file-tree-sidebar").evaluate(
    element => element.getBoundingClientRect().width,
  );
}

async function moveFileTreeDivider(page, targetWidth) {
  const divider = page.getByRole("separator", { name: "Resize file tree" });
  const box = await divider.boundingBox();
  if (!box) throw new Error("File tree resize divider is not visible.");
  const startWidth = await fileTreeWidth(page);
  const startX = box.x + box.width / 2;
  const y = box.y + Math.min(24, box.height / 2);
  await page.mouse.move(startX, y);
  await page.mouse.down();
  await page.mouse.move(startX + targetWidth - startWidth, y, { steps: 4 });
  return divider;
}

async function dragFileTree(page, targetWidth) {
  const divider = await moveFileTreeDivider(page, targetWidth);
  await page.mouse.up();
  return divider;
}

async function openMockedShareLink(page) {
  await installMockRoutes(page);
  await page.goto(`/#/example/project/commit/${commitSha}`);
  await expect(page.locator("table.split")).toBeVisible();
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

test("desktop file tree supports collapse search status filters and file navigation", async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  const rawRequests = await loadTreeCommit(page);
  const sidebar = page.getByRole("complementary", { name: "Changed files" });
  await expect(sidebar).toBeVisible();
  const sidebarLayout = await sidebar.evaluate(element => ({
    width: element.getBoundingClientRect().width,
    position: getComputedStyle(element).position,
    overflow: getComputedStyle(element.querySelector(".file-tree-scroll")).overflowY,
    rowFontSize: getComputedStyle(element.querySelector(".file-tree-row")).fontSize,
  }));
  expect(sidebarLayout.width).toBe(320);
  expect(sidebarLayout.position).toBe("sticky");
  expect(sidebarLayout.overflow).toBe("auto");
  expect(sidebarLayout.rowFontSize).toBe("13px");
  await expect(page.getByRole("button", { name: "Open file tree" })).toBeHidden();
  await expect(sidebar.locator(".file-tree-row.file-row")).toHaveCount(5);

  await page.getByRole("treeitem", { name: "Collapse directory src", exact: true }).click();
  await expect(page.getByRole("treeitem", { name: "Expand directory src", exact: true })).toHaveAttribute(
    "aria-expanded",
    "false",
  );
  await expect(sidebar.getByRole("treeitem", { name: /new_name\.mbt/u })).toHaveCount(0);

  await page.getByRole("button", { name: "Search files" }).click();
  await page.getByRole("searchbox", { name: "Search changed files" }).fill("OLD_NAME.MBT");
  await expect(sidebar.locator(".file-tree-row.file-row")).toHaveCount(1);
  const renamed = sidebar.getByRole("treeitem", {
    name: "Open src/renamed/new_name.mbt, renamed from legacy/Old_Name.mbt",
  });
  await expect(renamed).toBeVisible();
  await expect(renamed).toHaveAttribute("title", /renamed from legacy\/Old_Name\.mbt/u);
  const filteredSrc = page.getByRole("treeitem", {
    name: "Directory src, expanded while filtering",
    exact: true,
  });
  await expect(filteredSrc).toHaveAttribute(
    "aria-expanded",
    "true",
  );
  await expect(filteredSrc).toHaveAttribute("aria-disabled", "true");
  await expect(filteredSrc).toBeDisabled();
  await filteredSrc.dispatchEvent("click");

  await page.getByRole("button", { name: "Close file search" }).click();
  await expect(page.getByRole("treeitem", { name: "Expand directory src", exact: true })).toHaveAttribute(
    "aria-expanded",
    "false",
  );
  await page.getByRole("button", { name: "Search files" }).click();
  await expect(page.getByRole("searchbox", { name: "Search changed files" })).toHaveValue("");
  await page.getByRole("button", { name: "Close file search" }).click();

  const expandSrc = page.getByRole("treeitem", { name: "Expand directory src", exact: true });
  await expandSrc.focus();
  await expandSrc.press("Enter");
  const collapseSrc = page.getByRole("treeitem", { name: "Collapse directory src", exact: true });
  await expect(collapseSrc).toHaveAttribute("aria-expanded", "true");
  await collapseSrc.focus();
  await collapseSrc.press("Space");
  const keyboardCollapsed = page.getByRole("treeitem", { name: "Expand directory src", exact: true });
  await expect(keyboardCollapsed).toHaveAttribute("aria-expanded", "false");
  await keyboardCollapsed.press("Enter");

  await page.getByRole("button", { name: "Filter added files" }).click();
  await page.getByRole("button", { name: "Filter deleted files" }).click();
  await expect(sidebar.locator(".file-tree-row.file-row")).toHaveCount(2);
  await expect(sidebar.getByRole("treeitem", { name: "Open src/utils/helper.mbt" })).toBeVisible();
  await expect(sidebar.getByRole("treeitem", { name: "Open docs/guide.md" })).toBeVisible();
  await page.getByRole("button", { name: "Filter added files" }).click();
  await page.getByRole("button", { name: "Filter deleted files" }).click();
  await expect(sidebar.locator(".file-tree-row.file-row")).toHaveCount(5);

  const guideCard = page.locator("#moondiff-file-2");
  await expect(guideCard.getByRole("button", { name: "Expand docs/guide.md" })).toBeVisible();
  expect(await guideCard.evaluate(element => element.getBoundingClientRect().top)).toBeGreaterThan(900);
  expect(rawRequests).not.toContain("docs/guide.md");
  const guideTreeItem = sidebar.getByRole("treeitem", { name: "Open docs/guide.md" });
  await guideTreeItem.click();
  await expect(guideTreeItem).toHaveAttribute("aria-selected", "true");
  await expect(guideCard.getByRole("button", { name: "Collapse docs/guide.md" })).toBeVisible();
  await expect(guideCard).toContainText("Removed guide");
  await expect.poll(() => rawRequests.includes("docs/guide.md")).toBe(true);
  await expect.poll(() => guideCard.evaluate(element => {
    const bounds = element.getBoundingClientRect();
    return bounds.top >= 0 && bounds.top < innerHeight;
  })).toBe(true);
  expect(await page.evaluate(() => scrollY)).toBeGreaterThan(0);
});

test("desktop file tree resizes live, persists across changes, and resets on refresh", async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await loadTreeCommit(page);
  const divider = page.getByRole("separator", { name: "Resize file tree" });

  await expect(divider).toBeVisible();
  await expect(divider).toHaveCSS("cursor", "col-resize");
  await expect(divider).toHaveCSS("touch-action", "none");
  expect(await fileTreeWidth(page)).toBe(320);

  await moveFileTreeDivider(page, 440);
  expect(await fileTreeWidth(page)).toBe(440);
  await divider.evaluate(element => {
    const pointerId = element.__moondiffFileTreeResize.pointerId;
    element.dispatchEvent(new PointerEvent("pointercancel", {
      bubbles: true,
      isPrimary: true,
      pointerId,
      pointerType: "mouse",
    }));
  });
  await page.mouse.up();
  await expect(divider).not.toHaveClass(/\bis-resizing\b/u);
  expect(await fileTreeWidth(page)).toBe(320);

  await moveFileTreeDivider(page, 480);
  await expect(divider).toHaveClass(/\bis-resizing\b/u);
  expect(await fileTreeWidth(page)).toBe(480);
  await page.mouse.up();
  await expect(divider).not.toHaveClass(/\bis-resizing\b/u);
  expect(await fileTreeWidth(page)).toBe(480);

  const nextSha = "5555555555555555555555555555555555555555";
  const nextUrl = "https://github.com/example/tree/commit/" + nextSha;
  await page.getByLabel("Public GitHub commit or pull request URL").fill(nextUrl);
  await page.getByRole("button", { name: "View diff" }).click();
  await expect(page).toHaveURL("/#/example/tree/commit/" + nextSha);
  await expect(page.locator("table.split").first()).toBeVisible();
  expect(await fileTreeWidth(page)).toBe(480);

  await page.reload();
  await expect(page.locator("table.split").first()).toBeVisible();
  expect(await fileTreeWidth(page)).toBe(320);
});

test("file tree width obeys minimum, absolute maximum, and viewport maximum", async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await loadTreeCommit(page);
  const divider = page.getByRole("separator", { name: "Resize file tree" });

  await dragFileTree(page, 0);
  expect(await fileTreeWidth(page)).toBe(240);
  await expect(divider).toHaveAttribute("aria-valuenow", "240");

  await dragFileTree(page, 900);
  expect(await fileTreeWidth(page)).toBe(640);
  await expect(divider).toHaveAttribute("aria-valuenow", "640");

  for (const [width, expectedSidebarWidth] of [[800, 400], [768, 384]]) {
    await page.setViewportSize({ width, height: 900 });
    await expect(divider).toBeVisible();
    expect(await fileTreeWidth(page)).toBe(expectedSidebarWidth);
    const documentWidth = await page.evaluate(() => ({
      client: document.documentElement.clientWidth,
      scroll: document.documentElement.scrollWidth,
    }));
    expect(documentWidth.scroll).toBeLessThanOrEqual(documentWidth.client);
  }

  await page.setViewportSize({ width: 1440, height: 900 });
  expect(await fileTreeWidth(page)).toBe(640);

  await page.setViewportSize({ width: 767, height: 900 });
  await expect(divider).toBeHidden();
  const mobileWidth = await page.evaluate(() => ({
    client: document.documentElement.clientWidth,
    scroll: document.documentElement.scrollWidth,
  }));
  expect(mobileWidth.scroll).toBeLessThanOrEqual(mobileWidth.client);
});

test("tablet-width layout keeps the sidebar without widening the document", async ({ page }) => {
  await page.setViewportSize({ width: 800, height: 900 });
  await loadTreeCommit(page);
  const sidebar = page.locator("#file-tree-sidebar");
  const treeTrigger = page.locator("button.file-tree-trigger");

  for (const width of [800, 768]) {
    await page.setViewportSize({ width, height: 900 });
    await expect(sidebar).toBeVisible();
    await expect(sidebar).toHaveAttribute("role", "complementary");
    await expect(treeTrigger).toBeHidden();
    const layout = await page.evaluate(() => ({
      documentClientWidth: document.documentElement.clientWidth,
      documentScrollWidth: document.documentElement.scrollWidth,
      sidebarWidth: document.querySelector("#file-tree-sidebar").getBoundingClientRect().width,
    }));
    expect(layout.sidebarWidth).toBe(320);
    expect(layout.documentScrollWidth).toBeLessThanOrEqual(layout.documentClientWidth);
  }

  await page.setViewportSize({ width: 767, height: 900 });
  await expect(sidebar).toBeHidden();
  await expect(treeTrigger).toBeVisible();
  const narrowLayout = await page.evaluate(() => ({
    documentClientWidth: document.documentElement.clientWidth,
    documentScrollWidth: document.documentElement.scrollWidth,
  }));
  expect(narrowLayout.documentScrollWidth).toBeLessThanOrEqual(
    narrowLayout.documentClientWidth,
  );

  await page.setViewportSize({ width: 766, height: 900 });
  const openTree = page.getByRole("button", { name: "Open file tree" });
  await openTree.click();
  await expect(sidebar).toHaveAttribute("role", "dialog");
  await expect(sidebar.locator("button.drawer-close")).toBeFocused();

  await page.setViewportSize({ width: 767, height: 900 });
  await expect(sidebar).toHaveClass(/\bopen\b/u);
  await expect(sidebar).toHaveAttribute("role", "dialog");
  await expect(treeTrigger).toHaveAttribute("aria-expanded", "true");

  await page.setViewportSize({ width: 768, height: 900 });
  await expect(sidebar).toBeVisible();
  await expect(sidebar).not.toHaveClass(/\bopen\b/u);
  await expect(sidebar).toHaveAttribute("role", "complementary");
  await expect(sidebar).not.toHaveAttribute("aria-modal", "true");
  await expect(treeTrigger).toHaveAttribute("aria-expanded", "false");
  await expect(sidebar.locator("button.search-toggle")).toBeFocused();
  await expect(page.locator(".hero-workspace")).not.toHaveAttribute("inert", "");
  await expect(page.locator(".change-main")).not.toHaveAttribute("inert", "");
});

test("mobile file tree is a modal focus trap and restores focus after dismissal", async ({ page }) => {
  await page.setViewportSize({ width: 420, height: 900 });
  await loadTreeCommit(page);
  const sidebar = page.locator("#file-tree-sidebar");
  const openTree = page.getByRole("button", { name: "Open file tree" });
  const treeTrigger = page.locator("button.file-tree-trigger");
  await expect(openTree).toBeVisible();
  await expect(treeTrigger).toHaveAttribute("aria-expanded", "false");
  await expect(sidebar).toHaveAttribute("role", "complementary");
  await expect(sidebar).toBeHidden();

  await openTree.click();
  await expect(sidebar).toBeVisible();
  await expect(sidebar).toHaveAttribute("role", "dialog");
  await expect(sidebar).toHaveAttribute("aria-modal", "true");
  await expect(page.locator(".hero-workspace")).toHaveAttribute("inert", "");
  await expect(page.locator(".change-main")).toHaveAttribute("inert", "");
  const drawerClose = sidebar.locator("button.drawer-close");
  await expect(drawerClose).toBeFocused();

  const backdrop = page.locator("button.file-tree-backdrop");
  await expect(backdrop).toHaveAttribute("tabindex", "-1");
  await expect(backdrop).toHaveCSS("background-color", "rgba(0, 0, 0, 0.42)");
  await backdrop.hover({ position: { x: 10, y: 10 } });
  await expect(backdrop).toHaveCSS("background-color", "rgba(0, 0, 0, 0.42)");
  await expect(backdrop).toHaveCSS("transform", "none");

  const focusable = sidebar.locator("button:not([disabled]), input:not([disabled])");
  const firstFocusable = focusable.first();
  const lastFocusable = focusable.last();
  await firstFocusable.focus();
  await firstFocusable.press("Shift+Tab");
  await expect(lastFocusable).toBeFocused();
  await lastFocusable.press("Tab");
  await expect(firstFocusable).toBeFocused();

  await firstFocusable.press("Escape");
  await expect(sidebar).toBeHidden();
  await expect(sidebar).toHaveAttribute("role", "complementary");
  await expect(openTree).toBeFocused();
  await expect(page.locator(".hero-workspace")).not.toHaveAttribute("inert", "");
  await expect(page.locator(".change-main")).not.toHaveAttribute("inert", "");

  await openTree.click();
  await expect(drawerClose).toBeFocused();
  await backdrop.click({ position: { x: 10, y: 10 } });
  await expect(sidebar).toBeHidden();
  await expect(openTree).toBeFocused();

  await openTree.click();
  await expect(drawerClose).toBeFocused();
  await drawerClose.click();
  await expect(sidebar).toBeHidden();
  await expect(openTree).toBeFocused();
});

test("mobile file tree closes after selection and focuses the file card", async ({ page }) => {
  await page.setViewportSize({ width: 420, height: 900 });
  await loadTreeCommit(page);
  const sidebar = page.locator("#file-tree-sidebar");
  const openTree = page.getByRole("button", { name: "Open file tree" });
  const treeTrigger = page.locator("button.file-tree-trigger");
  const copyingCard = page.locator("#moondiff-file-4");
  expect(await copyingCard.evaluate(element => element.getBoundingClientRect().top)).toBeGreaterThan(900);

  await openTree.click();
  await expect(sidebar).toBeVisible();
  await expect(sidebar).toHaveAttribute("role", "dialog");
  await expect(sidebar.locator("button.drawer-close")).toBeFocused();
  await expect(treeTrigger).toHaveAttribute("aria-expanded", "true");
  await sidebar.getByRole("treeitem", { name: "Open COPYING" }).click();

  await expect(sidebar).toBeHidden();
  await expect(treeTrigger).toHaveAttribute("aria-expanded", "false");
  await expect(copyingCard.getByRole("button", { name: "Collapse COPYING" })).toBeVisible();
  await expect(copyingCard).toContainText("Copyright copied");
  await expect.poll(() => copyingCard.evaluate(element => {
    const bounds = element.getBoundingClientRect();
    return bounds.top >= 0 && bounds.top < innerHeight;
  })).toBe(true);
  await expect(copyingCard.locator("button.file-toggle")).toBeFocused();
  expect(await page.evaluate(() => scrollY)).toBeGreaterThan(0);
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
  await expect(readmeCard.locator("b.wd")).toHaveText("<old>");
  await expect(readmeCard.locator("b.wa")).toHaveText("&new");

  await binaryCard.getByRole("button", { name: "Expand" }).click();
  await expect(binaryCard).toContainText("Cannot render: the file is binary or is not valid UTF-8.");
  await expect(binaryCard.locator(".diff-scroll")).toHaveCount(0);

  await page.getByRole("button", { name: "Use unified view" }).click();
  await expect(moonbitCard.locator("table.unified")).toBeVisible();
  await expect(readmeCard.locator("table.unified")).toBeVisible();
  await expect(page.locator("table.unified")).toHaveCount(2);
  await expect(readmeCard.locator("b.wd")).toHaveText("<old>");
  await expect(readmeCard.locator("b.wa")).toHaveText("&new");
});

test("a shared playground URL restores the commit and can be copied", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.context().grantPermissions(["clipboard-read", "clipboard-write"]);
  await openMockedShareLink(page);

  await expect(page.getByLabel("Public GitHub commit or pull request URL")).toHaveValue(commitUrl);
  await expect(page.getByLabel("Shareable playground URL")).toHaveValue(page.url());
  await page.getByRole("button", { name: "Copy link" }).click();
  await expect(page.getByRole("button", { name: "Copied" })).toBeVisible();
  await expect.poll(() => page.evaluate(() => navigator.clipboard.readText())).toBe(page.url());

  await page.reload();
  await expect(page.locator("table.split")).toBeVisible();
});

test("a PR URL loads every paginated file and preserves the PR share route", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.context().grantPermissions(["clipboard-read", "clipboard-write"]);
  const requests = await installPullRoutes(page);
  await page.goto("/");
  await page
    .getByLabel("Public GitHub commit or pull request URL")
    .fill(pullFilesUrl);
  await page.getByRole("button", { name: "View diff" }).click();

  const aggregateCard = page.locator(".file-card").filter({
    hasText: "src/from_second_commit.mbt",
  });
  await expect(aggregateCard.locator("table.split")).toBeVisible();
  await expect(page).toHaveURL(`/#/example/project/pull/${pullNumber}`);
  await expect(
    page.getByLabel("Public GitHub commit or pull request URL"),
  ).toHaveValue(pullUrl);
  await expect(page.locator(".file-card")).toHaveCount(101);
  await expect(page.getByText("Public pull request", { exact: true })).toBeVisible();
  await expect(
    page.getByRole("link", { name: `example/project#${pullNumber}` }),
  ).toHaveAttribute("href", pullUrl);
  await expect(page.locator(".commit-message")).toHaveText(
    "Aggregate changes from both PR commits",
  );
  await expect(page.locator(".parent")).toContainText(pullMergeBaseOne);
  await expect(page.locator(".parent")).toContainText(pullHeadOne);
  await expect(
    page.getByRole("link", { name: "Open pull request on GitHub" }),
  ).toHaveAttribute("href", pullUrl);
  await expect(page.getByLabel("Shareable playground URL")).toHaveValue(page.url());
  expect(requests.apiRequests).toContain(
    `https://api.github.com/repos/example/project/compare/${pullBaseSha}...${pullHeadOne}`,
  );
  expect(requests.apiRequests.some(url => url.includes("/commits?"))).toBe(false);
  expect(requests.apiRequests.some(url => url.includes("/files?per_page=100&page=1"))).toBe(true);
  expect(requests.apiRequests.some(url => url.includes("/files?per_page=100&page=2"))).toBe(true);
  expect(requests.metadataCalls()).toBe(2);
  const metadataRequests = requests.mutableApiRequests.filter(({ url }) =>
    new URL(url).pathname.endsWith(`/pulls/${pullNumber}`)
  );
  const fileRequests = requests.mutableApiRequests.filter(({ url }) =>
    new URL(url).pathname.endsWith(`/pulls/${pullNumber}/files`)
  );
  expect(metadataRequests).toHaveLength(2);
  expect(fileRequests).toHaveLength(2);
  const fetchCalls = await requests.fetchCalls();
  expectRevalidatingRequests(
    metadataRequests,
    fetchCalls.filter(({ url }) =>
      new URL(url).pathname.endsWith(`/pulls/${pullNumber}`)
    ),
  );
  expectRevalidatingRequests(
    fileRequests,
    fetchCalls.filter(({ url }) =>
      new URL(url).pathname.endsWith(`/pulls/${pullNumber}/files`)
    ),
  );

  await page.getByRole("button", { name: "Copy link" }).click();
  await expect.poll(() => page.evaluate(() => navigator.clipboard.readText())).toBe(page.url());
});

test("opening the same PR share route refreshes its head", async ({ page }) => {
  const requests = await installPullRoutes(page, {
    heads: [pullHeadOne, pullHeadOne, pullHeadTwo, pullHeadTwo],
  });
  const sharePath = `/#/example/project/pull/${pullNumber}`;
  await page.goto(sharePath);
  const aggregateCard = page.locator(".file-card").filter({
    hasText: "src/from_second_commit.mbt",
  });
  await expect(aggregateCard.locator("table.split")).toBeVisible();
  await expect(page.locator(".parent")).toContainText(pullHeadOne);
  await expect(aggregateCard).toContainText("head one");
  const firstUrl = page.url();

  await page.reload();
  await expect(aggregateCard.locator("table.split")).toBeVisible();
  await expect(page.locator(".parent")).toContainText(pullHeadTwo);
  await expect(page.locator(".parent")).toContainText(pullMergeBaseTwo);
  await expect(aggregateCard).toContainText("head two");
  expect(page.url()).toBe(firstUrl);
  expect(requests.metadataCalls()).toBe(4);
  expect(requests.apiRequests).toContain(
    `https://api.github.com/repos/example/project/compare/${pullBaseSha}...${pullHeadOne}`,
  );
  expect(requests.apiRequests).toContain(
    `https://api.github.com/repos/example/project/compare/${pullBaseSha}...${pullHeadTwo}`,
  );
});

test("a PR updated while loading retries and only shows the latest snapshot", async ({ page }) => {
  const requests = await installPullRoutes(page, {
    heads: [pullHeadOne, pullHeadTwo, pullHeadTwo],
  });
  await page.goto(`/#/example/project/pull/${pullNumber}`);

  const aggregateCard = page.locator(".file-card").filter({
    hasText: "src/from_second_commit.mbt",
  });
  await expect(aggregateCard.locator("table.split")).toBeVisible();
  await expect(page.locator(".parent")).toContainText(pullMergeBaseTwo);
  await expect(page.locator(".parent")).toContainText(pullHeadTwo);
  await expect(page.locator(".commit-message")).toHaveText(
    "Aggregate the latest PR snapshot",
  );
  await expect(aggregateCard).toContainText("head two");
  await expect(aggregateCard).toContainText("merge base two");

  expect(requests.metadataCalls()).toBe(3);
  expect(requests.apiRequests).toContain(
    `https://api.github.com/repos/example/project/compare/${pullBaseSha}...${pullHeadOne}`,
  );
  expect(requests.apiRequests).toContain(
    `https://api.github.com/repos/example/project/compare/${pullBaseSha}...${pullHeadTwo}`,
  );
  expect(requests.rawRequests.some(url => url.includes(`/${pullHeadOne}/`))).toBe(false);
});

test("a PR metadata 403 keeps the anonymous rate-limit guidance", async ({ page }) => {
  const metadataRequests = [];
  await installFetchCacheRecorder(page);
  await page.route("https://**", route => route.abort("blockedbyclient"));
  await page.route("https://api.github.com/**", async route => {
    const request = route.request();
    metadataRequests.push({
      url: request.url(),
      headers: await request.allHeaders(),
    });
    await route.fulfill({
      status: 403,
      contentType: "application/json",
      headers: {
        "access-control-allow-origin": "*",
        "cache-control": "public, max-age=60",
      },
      body: JSON.stringify({ message: "API rate limit exceeded" }),
    });
  });

  await page.goto(`/#/example/project/pull/${pullNumber}`);

  await expect(page.locator(".empty-state.error")).toContainText(
    "GitHub rejected the request (HTTP 403). The anonymous API limit may be exhausted; try again later.",
  );
  expect(metadataRequests).toHaveLength(1);
  const fetchCalls = await page.evaluate(() => window.__moondiffFetchCalls);
  expectRevalidatingRequests(
    metadataRequests,
    fetchCalls.filter(({ url }) =>
      new URL(url).pathname.endsWith(`/pulls/${pullNumber}`)
    ),
  );
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

test("long semantic section titles wrap without widening narrow pages", async ({ page }) => {
  await page.setViewportSize({ width: 420, height: 900 });
  await loadAlgorithmCommit(page, { longDeclarationOnly: true });

  const card = page.locator(".file-card").filter({ hasText: longDeclarationFile.filename });
  const title = card.locator(".semantic-section-title");
  await expect(title).toHaveCount(1);
  await expect(title).toContainText(longFunctionName);

  const layout = await title.evaluate(element => {
    const range = document.createRange();
    range.selectNodeContents(element);
    const lineTops = new Set(
      [...range.getClientRects()]
        .filter(rect => rect.width > 0 && rect.height > 0)
        .map(rect => Math.round(rect.top)),
    );
    return {
      lineCount: lineTops.size,
      overflowWrap: getComputedStyle(element).overflowWrap,
      titleClientWidth: element.clientWidth,
      titleScrollWidth: element.scrollWidth,
      documentClientWidth: document.documentElement.clientWidth,
      documentScrollWidth: document.documentElement.scrollWidth,
    };
  });
  expect(layout.overflowWrap).toBe("anywhere");
  expect(layout.lineCount).toBeGreaterThan(1);
  expect(layout.titleScrollWidth).toBeLessThanOrEqual(layout.titleClientWidth);
  expect(layout.documentScrollWidth).toBeLessThanOrEqual(layout.documentClientWidth);
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

test("Ignore tests works across algorithms, layouts, combined filters, and narrow screens", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await loadTestsCommit(page);

  const testsToggle = page.getByRole("button", { name: "Ignore tests" });
  const commentsToggle = page.getByRole("button", { name: "Ignore comments" });
  const mixedCard = page.locator(".file-card").filter({ hasText: "src/mixed_tests.mbt" });
  const testsOnlyCard = page.locator(".file-card").filter({ hasText: "src/tests_only.mbt" });
  const combinedCard = page.locator(".file-card").filter({ hasText: "src/combined_only.mbt" });
  const plainCard = page.locator(".file-card").filter({ hasText: "tests.txt" });
  const urlBeforeFilters = page.url();

  await expect(testsToggle).toHaveAttribute("aria-pressed", "false");
  await expect(testsToggle).toHaveAttribute(
    "title",
    "Ignore top-level MoonBit test and async test blocks",
  );
  await plainCard.getByRole("button", { name: "Expand" }).click();
  const plainHtml = await plainCard.locator(".diff-scroll").innerHTML();

  await testsToggle.click();
  await expect(testsToggle).toHaveAttribute("aria-pressed", "true");
  await expect(testsToggle).toHaveAttribute("title", "Show MoonBit test changes");
  await expect(testsOnlyCard).toContainText(
    "No changes besides MoonBit test blocks found. Turn off Ignore tests",
  );
  await expect(testsOnlyCard.locator("table")).toHaveCount(0);
  await expect(mixedCard.locator("b.wd")).toContainText("old_value");
  await expect(mixedCard.locator("b.wa")).toContainText("new_value");
  await expect(mixedCard.locator("td.del")).not.toContainText("old_test");
  await expect(mixedCard.locator("td.add")).not.toContainText("new_test");
  await expect(combinedCard.locator("table.split")).toBeVisible();
  await expect(plainCard.locator(".diff-scroll")).toHaveJSProperty("innerHTML", plainHtml);

  await commentsToggle.click();
  await expect(combinedCard).toContainText(
    "No changes besides MoonBit test blocks, comments, or blank lines found",
  );
  await expect(combinedCard.locator("table")).toHaveCount(0);

  await page.getByRole("button", { name: "AST" }).click();
  await expect(testsOnlyCard).toContainText(
    "No structural changes besides MoonBit test blocks, comments, or blank lines found",
  );
  await expect(mixedCard.locator("b.wd")).toContainText("old_value");
  await page.getByRole("button", { name: "Use unified view" }).click();
  await expect(mixedCard.locator("table.unified")).toBeVisible();
  await expect(plainCard.locator("table.unified")).toBeVisible();
  expect(page.url()).toBe(urlBeforeFilters);
  expect(new URL(page.url()).search).toBe("");
  expect(page.url()).not.toContain("ignore");

  await page.setViewportSize({ width: 420, height: 900 });
  const compact = await testsToggle.evaluate(button => ({
    left: button.getBoundingClientRect().left,
    right: button.getBoundingClientRect().right,
    width: button.getBoundingClientRect().width,
    labelDisplay: getComputedStyle(button.querySelector(".ignore-tests-label")).display,
    pageWidth: document.documentElement.scrollWidth,
    viewportWidth: document.documentElement.clientWidth,
  }));
  expect(compact.left).toBeGreaterThanOrEqual(0);
  expect(compact.right).toBeLessThanOrEqual(420);
  expect(compact.width).toBeLessThanOrEqual(36);
  expect(compact.labelDisplay).toBe("none");
  expect(compact.pageWidth).toBeLessThanOrEqual(compact.viewportWidth);
});

test("complete Lexical sections hide only hunk headings in both review layouts", async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await loadAlgorithmCommit(page, { extensionHost: true });
  await expect(page.getByText("Signed in as reviewer")).toBeVisible();

  const structuralCard = page.locator(".file-card").filter({ hasText: "src/structural.mbt" });
  const section = structuralCard.locator(".semantic-section");
  await expect(section).toHaveCount(1);
  await expect(section.locator(".semantic-section-title")).toContainText(
    "Section #2 · Matched · old lines 3-20 · new lines 3-20 · fn structural() {",
  );
  await expect(section.locator("table.split")).toBeVisible();
  await expect(section.locator(".hunk-header")).toHaveCount(0);
  await expect(section).toContainText("/// structural docs");
  await expect(section).toContainText("stable_prefix_one()");
  await expect(section).toContainText("stable_suffix_four()");
  await expect(section).toContainText("new_tail()");
  await expect(section).not.toContainText("unchanged_before");
  await expect(section).not.toContainText("unchanged_after");
  await expect(
    section.locator('.new-line-number button[aria-label="Comment on line 15"]'),
  ).toHaveCount(1);

  await page.getByRole("button", { name: "Use unified view" }).click();
  await expect(section.locator("table.unified")).toBeVisible();
  await expect(section.locator(".hunk-header")).toHaveCount(0);
  await expect(section).toContainText("/// structural docs");
  await expect(section).toContainText("stable_suffix_four()");
  await expect(
    section.locator('.new-line-number button[aria-label="Comment on line 15"]'),
  ).toHaveCount(1);

  await page.getByRole("button", { name: "AST" }).click();
  const astUnifiedHeaders = structuralCard.locator(".hunk-header");
  expect(await astUnifiedHeaders.count()).toBeGreaterThan(0);
  expect(
    (await astUnifiedHeaders.allTextContents()).every(text => text.endsWith("fn structural() {")),
  ).toBe(true);
  await expect(
    structuralCard.locator('.new-line-number button[aria-label="Comment on line 15"]'),
  ).toHaveCount(1);

  const readmeCard = page.locator(".file-card").filter({ hasText: "README.md" });
  await readmeCard.getByRole("button", { name: "Expand" }).click();
  await expect(readmeCard.locator("table.unified")).toBeVisible();
  expect(await readmeCard.locator(".hunk-header").count()).toBeGreaterThan(0);

  await page.getByRole("button", { name: "Use split view" }).click();
  await expect(structuralCard.locator("table.split")).toBeVisible();
  const astSplitHeaders = structuralCard.locator(".hunk-header");
  expect(await astSplitHeaders.count()).toBeGreaterThan(0);
  expect(
    (await astSplitHeaders.allTextContents()).every(text => text.endsWith("fn structural() {")),
  ).toBe(true);
  expect(await readmeCard.locator(".hunk-header").count()).toBeGreaterThan(0);
});

test("MoonBit toplevel sections fold independently with mouse and keyboard", async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await loadAlgorithmCommit(page, { extensionHost: true });

  const card = page.locator(".file-card").filter({
    hasText: "src/collapsible_sections.mbt",
  });
  const sections = card.locator("details.semantic-section");
  const first = sections.nth(0);
  const second = sections.nth(1);
  const firstSummary = first.locator("summary");

  await expect(sections).toHaveCount(2);
  await expect(firstSummary).toContainText("Section #1 · Matched · old lines 1-3 · new lines 1-3 · fn first_change() -> Int {");
  await expect(second.locator("summary")).toContainText("Section #2 · Matched · old lines 5-7 · new lines 5-7 · fn second_change() -> Int {");
  expect(await sections.evaluateAll(items => items.every(item => item.open))).toBe(true);
  await expect(first.locator("table.split")).toBeVisible();
  await expect(second.locator("table.split")).toBeVisible();

  await firstSummary.click();
  await expect(first).not.toHaveAttribute("open", "");
  await expect(first.locator("table.split")).toBeHidden();
  await expect(second).toHaveAttribute("open", "");
  await expect(second.locator("table.split")).toBeVisible();

  await firstSummary.click();
  await expect(first.locator("table.split")).toBeVisible();
  await firstSummary.focus();
  await firstSummary.press("Space");
  await expect(first.locator("table.split")).toBeHidden();
  await expect(second.locator("table.split")).toBeVisible();
  await firstSummary.press("Enter");
  await expect(first.locator("table.split")).toBeVisible();

  const commentAnchor = first.locator(
    '.new-line-number button[aria-label="Comment on line 2"]',
  );
  await expect(commentAnchor).toHaveCount(1);
  await commentAnchor.locator("xpath=..").hover();
  await expect(commentAnchor).toBeVisible();

  await page.getByRole("button", { name: "Use unified view" }).click();
  await expect(first.locator("table.unified")).toBeVisible();
  await expect(second.locator("table.unified")).toBeVisible();
  await expect(first.locator("table.split")).toHaveCount(0);
  await expect(commentAnchor).toHaveCount(1);
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
  const structuralSplitHeaders = structuralCard.locator(".hunk-header");
  expect(await structuralSplitHeaders.count()).toBeGreaterThan(0);
  expect(
    (await structuralSplitHeaders.allTextContents()).every(text => text.endsWith("fn structural() {")),
  ).toBe(true);
  await expect(structuralCard.locator("b.wd").filter({ hasText: "old_call" })).toHaveText("old_call");
  await expect(structuralCard.locator("b.wa").filter({ hasText: "new_call" })).toHaveText("new_call");
  await expect(structuralCard.locator("td.old-line-number").first()).not.toHaveText("");
  await expect(structuralCard).toContainText('"<script>&safe"');
  await expect(structuralCard.locator("script")).toHaveCount(0);

  await readmeCard.getByRole("button", { name: "Expand" }).click();
  await expect(readmeCard.locator("table.split")).toBeVisible();
  expect(await readmeCard.locator(".hunk-header").count()).toBeGreaterThan(0);
  const lineHtmlInAstMode = await readmeCard.locator(".diff-scroll").innerHTML();
  await expect(readmeCard.locator("b.wd")).toHaveText("<old>");
  await expect(readmeCard.locator("b.wa")).toHaveText("&new");

  await page.getByRole("button", { name: "Use unified view" }).click();
  await expect(structuralCard.locator("table.unified")).toBeVisible();
  await expect(readmeCard.locator("table.unified")).toBeVisible();
  const structuralUnifiedHeaders = structuralCard.locator(".hunk-header");
  expect(await structuralUnifiedHeaders.count()).toBeGreaterThan(0);
  expect(
    (await structuralUnifiedHeaders.allTextContents()).every(text => text.endsWith("fn structural() {")),
  ).toBe(true);
  expect(await readmeCard.locator(".hunk-header").count()).toBeGreaterThan(0);
  await expect(structuralCard.locator("b.wd").filter({ hasText: "old_call" })).toHaveText("old_call");
  await expect(structuralCard.locator("b.wa").filter({ hasText: "new_call" })).toHaveText("new_call");
  await expect(readmeCard.locator("b.wd")).toHaveText("<old>");
  await expect(readmeCard.locator("b.wa")).toHaveText("&new");

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

test("the selected algorithm survives later commit navigation without entering the URL", async ({ page }) => {
  await loadAlgorithmCommit(page);
  await page.getByRole("button", { name: "AST" }).click();
  await page.getByRole("button", { name: "Ignore comments" }).click();
  await page.getByRole("button", { name: "Ignore tests" }).click();
  const nextSha = "3333333333333333333333333333333333333333";
  const nextUrl = `https://github.com/example/algorithms/commit/${nextSha}`;
  await page.getByLabel("Public GitHub commit or pull request URL").fill(nextUrl);
  await page.getByRole("button", { name: "View diff" }).click();
  await expect(page.getByRole("button", { name: "AST" })).toHaveAttribute("aria-pressed", "true");
  await expect(page.getByRole("button", { name: "Ignore comments" })).toHaveAttribute("aria-pressed", "true");
  await expect(page.getByRole("button", { name: "Ignore tests" })).toHaveAttribute("aria-pressed", "true");
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
  expect(await card.locator(".hunk-header").count()).toBeGreaterThan(0);
  await page.getByRole("button", { name: "AST" }).click();
  await expect(card.locator(".diff-notice")).toContainText("Lexical fallback");
  await expect(card.locator(".diff-notice")).toContainText("this entire file");
  await page.getByRole("button", { name: "Use unified view" }).click();
  await expect(card.locator("table.unified")).toBeVisible();
  expect(await card.locator(".hunk-header").count()).toBeGreaterThan(0);
  await expect(card.locator(".diff-notice")).toContainText("old:");
});
