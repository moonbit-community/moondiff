import assert from "node:assert/strict";
import { chmodSync, mkdirSync, mkdtempSync, readdirSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { request as httpRequest } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { createMoondiffServer, MAX_REQUEST_BYTES } from "../server.mjs";

const fakeSource = mode => `#!/usr/bin/env node
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
if (process.argv.includes("--version")) process.exit(0);
if (process.env.HOME || process.env.SERVER_ONLY_SECRET) process.exit(9);
if (process.env.DEEPSEEK !== "test-key") process.exit(10);
for (const flag of ["--no-session", "--dir", "--system-prompt-file", "--global-skills-dir", "--thinking"]) {
  if (!process.argv.includes(flag)) process.exit(11);
}
const skills = process.argv[process.argv.indexOf("--global-skills-dir") + 1];
if (readdirSync(skills).length !== 0) process.exit(12);
if (process.argv.includes("--max-steps")) process.exit(13);
if (process.argv[process.argv.indexOf("--thinking") + 1] !== "high") process.exit(14);
const prompt = readFileSync(process.argv[process.argv.indexOf("--system-prompt-file") + 1], "utf8");
if (
  !prompt.includes("senior software developer") ||
  !prompt.includes("review the provided code diff") ||
  !prompt.includes("untrusted data") ||
  !prompt.includes("OUTPUT CONTRACT (MANDATORY)") ||
  !prompt.includes('exactly the keys "summary" and "groups"') ||
  !prompt.includes("No additional keys are allowed") ||
  !prompt.includes('return "groups": []') ||
  !prompt.includes("do not include comments or trailing commas") ||
  !prompt.includes("JSON.parse would accept the response") ||
  !prompt.includes("highest to lowest review importance") ||
  !prompt.includes("exactly once")
) process.exit(15);
const input = JSON.parse(readFileSync(join(process.cwd(), "analysis-input.json"), "utf8"));
const ids = input.hunks.map(hunk => hunk.id);
const hunk = id => ({ id, explanation: "Explains " + id });
let groups = ids.length === 0 ? [] : [{ title: "Only", description: "One purpose.", hunks: ids.map(hunk) }];
if (${JSON.stringify(mode)} === "valid" && ids.length > 1) groups = [
  { title: "Important", description: "Higher review priority.", hunks: [hunk(ids[1])] },
  { title: "Supporting", description: "Lower review priority.", hunks: [hunk(ids[0])] },
];
if (${JSON.stringify(mode)} === "within-group" && ids.length > 1) groups = [
  { title: "One group", description: "One purpose.", hunks: [hunk(ids[1]), hunk(ids[0])] },
];
if (${JSON.stringify(mode)} === "missing") groups = [{ title: "Partial", description: "Partial.", hunks: [hunk(ids[0])] }];
if (${JSON.stringify(mode)} === "duplicate") groups = [{ title: "Duplicate", description: "Duplicate.", hunks: [hunk(ids[0]), hunk(ids[0])] }];
if (${JSON.stringify(mode)} === "unknown") groups = [{ title: "Unknown", description: "Unknown.", hunks: [hunk(ids[0]), hunk("f99-h0")] }];
const answer = JSON.stringify({ summary: "Functional summary.", groups });
if (${JSON.stringify(mode)} === "bad-jsonl") {
  process.stdout.write("not-json\\n");
} else if (${JSON.stringify(mode)} === "bad-answer") {
  console.log(JSON.stringify({ event: "agent_finished", answer: "{" }));
} else if (${JSON.stringify(mode)} === "missing-result") {
  console.log(JSON.stringify({ event: "usage", usage: { input_tokens: 3 } }));
} else if (${JSON.stringify(mode)} === "terminated") {
  console.log(JSON.stringify({ event: "agent_terminated" }));
} else if (${JSON.stringify(mode)} === "slow") {
  setTimeout(() => console.log(JSON.stringify({ event: "agent_finished", answer })), 300);
} else {
  console.log(JSON.stringify({ event: "usage", usage: { input_tokens: 12, total_tokens: 20, ignored: "text" } }));
  console.log(JSON.stringify({ event: "agent_finished", answer }));
}
if (${JSON.stringify(mode)} === "nonzero") process.exitCode = 2;
`;

function analysisInput() {
  return {
    version: 1,
    commit: {
      owner: "example",
      repo: "project",
      sha: "abcdef1",
      parent_sha: "1234567",
      message: "Change behavior",
      html_url: "https://github.com/example/project/commit/abcdef1",
    },
    skipped_files: [],
    hunks: [
      {
        id: "f0-h0",
        path: "src/main.mbt",
        previous_path: null,
        status: "modified",
        patch: "@@ -1 +1 @@\n-SECRET_DIFF_SHOULD_NOT_LOG\n+new\n",
      },
      {
        id: "f0-h1",
        path: "src/main.mbt",
        previous_path: null,
        status: "modified",
        patch: "@@ -8 +8 @@\n-old\n+new\n",
      },
    ],
  };
}

async function startFixture(mode, options = {}) {
  const root = mkdtempSync(join(tmpdir(), "moondiff-server-test-"));
  const staticRoot = join(root, "static");
  const analysisRoot = join(root, "analysis");
  mkdirSync(staticRoot);
  mkdirSync(analysisRoot);
  writeFileSync(join(staticRoot, "index.html"), "<!doctype html><title>fixture</title>");
  const fake = join(root, "fake-openseek.mjs");
  writeFileSync(fake, fakeSource(mode));
  chmodSync(fake, 0o755);
  const logs = [];
  const server = createMoondiffServer({
    staticRoot,
    temporaryRoot: analysisRoot,
    openseekBin: fake,
    timeoutMs: options.timeoutMs ?? 2_000,
    environment: {
      PATH: process.env.PATH,
      LANG: "C.UTF-8",
      DEEPSEEK: "test-key",
      SERVER_ONLY_SECRET: "must-not-leak",
    },
    logger: { info: line => logs.push(line) },
  });
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  const base = `http://127.0.0.1:${port}`;
  return {
    root,
    analysisRoot,
    logs,
    server,
    base,
    async close() {
      await new Promise(resolve => this.server.close(resolve));
      rmSync(root, { recursive: true, force: true });
    },
  };
}

async function analyze(fixture, body = analysisInput(), origin = fixture.base) {
  return fetch(`${fixture.base}/api/analyze`, {
    method: "POST",
    headers: { "content-type": "application/json", origin },
    body: JSON.stringify(body),
  });
}

test("health, static hosting, valid JSONL, normalization, logging, and cleanup", async t => {
  const fixture = await startFixture("valid");
  t.after(() => fixture.close());
  const health = await fetch(`${fixture.base}/api/health`).then(response => response.json());
  assert.deepEqual(health, { version: 1, ok: true, openseek_available: true });
  assert.match(await fetch(fixture.base).then(response => response.text()), /fixture/);
  symlinkSync(join(fixture.root, "fake-openseek.mjs"), join(fixture.root, "static", "escape"));
  assert.equal((await fetch(`${fixture.base}/escape`)).status, 403);

  const response = await analyze(fixture);
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.ok, true);
  assert.deepEqual(body.analysis.groups.map(group => group.title), ["Important", "Supporting"]);
  assert.deepEqual(body.analysis.groups.flatMap(group => group.hunks.map(hunk => hunk.id)), ["f0-h1", "f0-h0"]);
  assert.deepEqual(readdirSync(fixture.analysisRoot), []);
  assert.equal(fixture.logs.length, 1);
  assert.match(fixture.logs[0], /"hunk_count":2/);
  assert.match(fixture.logs[0], /"input_tokens":12/);
  assert.doesNotMatch(fixture.logs[0], /SECRET_DIFF|Functional summary|test-key/);
});

test("keeps source order for hunks inside an importance-ordered group", async t => {
  const fixture = await startFixture("within-group");
  t.after(() => fixture.close());
  const response = await analyze(fixture);
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.deepEqual(body.analysis.groups.map(group => group.title), ["One group"]);
  assert.deepEqual(body.analysis.groups[0].hunks.map(hunk => hunk.id), ["f0-h0", "f0-h1"]);
});

for (const [mode, code, message] of [
  ["missing", "invalid_coverage", "OpenSeek left 1 hunk out of the analysis. Please retry."],
  ["duplicate", "invalid_coverage", "OpenSeek included the same hunk more than once. Please retry the analysis."],
  ["unknown", "invalid_coverage", "OpenSeek referenced a hunk that is not part of this diff. Please retry the analysis."],
  ["bad-answer", "invalid_answer", "OpenSeek returned malformed JSON, so the analysis could not be displayed. Please retry."],
  ["bad-jsonl", "invalid_jsonl", "OpenSeek returned an unreadable response. Please retry the analysis."],
  ["missing-result", "missing_result", "OpenSeek finished without returning an analysis. Please retry."],
  ["terminated", "terminated", "OpenSeek stopped before the analysis was complete. Please retry."],
  ["nonzero", "nonzero_exit", "OpenSeek could not complete the analysis. Please check the model provider and try again."],
]) {
  test(`maps ${mode} OpenSeek output to a stable error`, async t => {
    const fixture = await startFixture(mode);
    t.after(() => fixture.close());
    const response = await analyze(fixture);
    assert.equal(response.status, 502);
    const error = (await response.json()).error;
    assert.equal(error.code, code);
    assert.equal(error.message, message);
    assert.deepEqual(readdirSync(fixture.analysisRoot), []);
  });
}

test("times out OpenSeek, rejects concurrent work, and cleans both runs", async t => {
  const fixture = await startFixture("slow", { timeoutMs: 80 });
  t.after(() => fixture.close());
  const first = analyze(fixture);
  while (readdirSync(fixture.analysisRoot).length === 0) {
    await new Promise(resolve => setTimeout(resolve, 5));
  }
  const busy = await analyze(fixture);
  assert.equal(busy.status, 429);
  assert.deepEqual((await busy.json()).error, {
    code: "busy",
    message: "Another analysis is already running. Please try again in a moment.",
  });
  const timedOut = await first;
  assert.equal(timedOut.status, 504);
  assert.deepEqual((await timedOut.json()).error, {
    code: "openseek_timeout",
    message: "OpenSeek took too long to analyze this commit. Please retry, or try a smaller commit.",
  });
  assert.deepEqual(readdirSync(fixture.analysisRoot), []);
});

test("terminates OpenSeek and cleans its workspace when the client disconnects", async t => {
  const fixture = await startFixture("slow", { timeoutMs: 2_000 });
  t.after(() => fixture.close());
  const url = new URL(`${fixture.base}/api/analyze`);
  const body = JSON.stringify(analysisInput());
  const request = httpRequest({
    hostname: url.hostname,
    port: url.port,
    path: url.pathname,
    method: "POST",
    headers: {
      origin: fixture.base,
      "content-type": "application/json",
      "content-length": Buffer.byteLength(body),
    },
  });
  request.on("error", () => {});
  request.end(body);
  while (readdirSync(fixture.analysisRoot).length === 0) {
    await new Promise(resolve => setTimeout(resolve, 5));
  }
  request.destroy();
  await assert.doesNotReject(async () => {
    const deadline = Date.now() + 1_500;
    while (readdirSync(fixture.analysisRoot).length !== 0) {
      if (Date.now() > deadline) throw new Error("temporary analysis directory was not cleaned");
      await new Promise(resolve => setTimeout(resolve, 10));
    }
  });
});

test("rejects cross-origin, malformed, and oversized requests before spawning", async t => {
  const fixture = await startFixture("valid");
  t.after(() => fixture.close());
  const forbidden = await analyze(fixture, analysisInput(), "https://attacker.example");
  assert.equal(forbidden.status, 403);
  assert.equal((await forbidden.json()).error.code, "origin_forbidden");

  const malformed = await fetch(`${fixture.base}/api/analyze`, {
    method: "POST",
    headers: { "content-type": "application/json", origin: fixture.base },
    body: "{",
  });
  assert.equal(malformed.status, 400);
  assert.equal((await malformed.json()).error.code, "invalid_json");

  const oversized = await new Promise((resolveRequest, rejectRequest) => {
    const url = new URL(`${fixture.base}/api/analyze`);
    const request = httpRequest({
      hostname: url.hostname,
      port: url.port,
      path: url.pathname,
      method: "POST",
      headers: {
        origin: fixture.base,
        "content-type": "application/json",
        connection: "close",
      },
    }, resolveRequest);
    request.on("error", rejectRequest);
    request.end(Buffer.alloc(MAX_REQUEST_BYTES + 1, "x"));
  });
  assert.equal(oversized.statusCode, 413);
  oversized.resume();
  await new Promise(resolve => oversized.once("end", resolve));
  assert.deepEqual(readdirSync(fixture.analysisRoot), []);
});

test("health reports a missing OpenSeek backend", async t => {
  const fixture = await startFixture("valid");
  t.after(() => fixture.close());
  await new Promise(resolve => fixture.server.close(resolve));
  const staticRoot = join(fixture.root, "static");
  fixture.server = createMoondiffServer({
    staticRoot,
    temporaryRoot: fixture.analysisRoot,
    openseekAvailable: false,
    logger: { info() {} },
  });
  await new Promise(resolve => fixture.server.listen(0, "127.0.0.1", resolve));
  const { port } = fixture.server.address();
  fixture.base = `http://127.0.0.1:${port}`;
  const response = await fetch(`${fixture.base}/api/health`);
  assert.deepEqual(await response.json(), { version: 1, ok: false, openseek_available: false });
  const unavailable = await analyze(fixture);
  assert.equal(unavailable.status, 503);
  assert.deepEqual((await unavailable.json()).error, {
    code: "openseek_unavailable",
    message: "OpenSeek analysis is not configured or available on this server.",
  });
});
