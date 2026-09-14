import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import test from "node:test";

const dockerignore = readFileSync(
  resolve(import.meta.dirname, "../../../.dockerignore"),
  "utf8",
);
const rules = new Set(
  dockerignore
    .split(/\r?\n/)
    .map(line => line.trim())
    .filter(line => line && !line.startsWith("#")),
);

test("Docker context excludes browser extension artifacts", () => {
  assert(rules.has("extension/*/artifacts"));
  assert(!rules.has("extension/chrome/artifacts"));
});
