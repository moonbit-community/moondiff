import assert from "node:assert/strict";
import {
  mkdirSync,
  mkdtempSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { request as httpRequest } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { createMoondiffServer } from "../server.mjs";

async function startFixture() {
  const root = mkdtempSync(join(tmpdir(), "moondiff-server-test-"));
  const staticRoot = join(root, "static");
  mkdirSync(staticRoot);
  writeFileSync(
    join(staticRoot, "index.html"),
    "<!doctype html><title>fixture</title>",
  );
  writeFileSync(join(staticRoot, "styles.css"), "body { color: navy; }");
  writeFileSync(join(root, "outside.txt"), "secret");
  symlinkSync(join(root, "outside.txt"), join(staticRoot, "escape"));

  const server = createMoondiffServer({ staticRoot });
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  return {
    root,
    server,
    port,
    base: `http://127.0.0.1:${port}`,
    async close() {
      await new Promise(resolve => server.close(resolve));
      rmSync(root, { recursive: true, force: true });
    },
  };
}

function rawRequest(fixture, path, method = "GET") {
  return new Promise((resolve, reject) => {
    const request = httpRequest(
      {
        hostname: "127.0.0.1",
        port: fixture.port,
        path,
        method,
      },
      response => {
        const chunks = [];
        response.on("data", chunk => chunks.push(chunk));
        response.on("end", () => resolve({
          status: response.statusCode,
          headers: response.headers,
          body: Buffer.concat(chunks).toString("utf8"),
        }));
      },
    );
    request.on("error", reject);
    request.end();
  });
}

test("serves static files, HEAD requests, and missing-file responses", async t => {
  const fixture = await startFixture();
  t.after(() => fixture.close());

  const index = await fetch(`${fixture.base}/`);
  assert.equal(index.status, 200);
  assert.equal(index.headers.get("cache-control"), "no-store");
  assert.equal(index.headers.get("content-type"), "text/html; charset=utf-8");
  assert.match(await index.text(), /<title>fixture<\/title>/);

  const head = await fetch(`${fixture.base}/styles.css`, { method: "HEAD" });
  assert.equal(head.status, 200);
  assert.equal(head.headers.get("content-type"), "text/css; charset=utf-8");
  assert.equal(await head.text(), "");

  const missing = await fetch(`${fixture.base}/missing.txt`);
  assert.equal(missing.status, 404);
  assert.equal(await missing.text(), "Not found");
});

test("rejects unsupported methods and unsafe paths", async t => {
  const fixture = await startFixture();
  t.after(() => fixture.close());

  const method = await fetch(`${fixture.base}/`, { method: "POST" });
  assert.equal(method.status, 405);
  assert.equal(method.headers.get("allow"), "GET, HEAD");

  const traversal = await rawRequest(fixture, "/..%2Foutside.txt");
  assert.equal(traversal.status, 403);
  assert.equal(traversal.body, "Forbidden");

  const symlink = await fetch(`${fixture.base}/escape`);
  assert.equal(symlink.status, 403);
  assert.equal(await symlink.text(), "Forbidden");

  const malformed = await rawRequest(fixture, "/%E0%A4%A");
  assert.equal(malformed.status, 400);
  assert.equal(malformed.body, "Bad request");
});
