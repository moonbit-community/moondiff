import { spawnSync } from "node:child_process";
import {
  copyFileSync,
  cpSync,
  existsSync,
  mkdtempSync,
  renameSync,
  rmSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptsDirectory = dirname(fileURLToPath(import.meta.url));
const playgroundRoot = resolve(scriptsDirectory, "..");
const repositoryRoot = resolve(playgroundRoot, "..");
const targetRoot = mkdtempSync(join(tmpdir(), "moondiff-playground-build-"));
const stagingRoot = mkdtempSync(join(playgroundRoot, ".dist-"));
const outputRoot = join(playgroundRoot, "dist");

try {
  const build = spawnSync(
    "moon",
    [
      "build",
      "--target",
      "js",
      "--release",
      "--target-dir",
      targetRoot,
      "playground/main",
    ],
    { cwd: repositoryRoot, stdio: "inherit" },
  );
  if (build.error) throw build.error;
  if (build.status !== 0) {
    throw new Error(`MoonBit release build failed with exit code ${build.status}.`);
  }
  const builtJavaScript = join(
    targetRoot,
    "js",
    "release",
    "build",
    "playground",
    "main",
    "main.js",
  );
  if (!existsSync(builtJavaScript)) {
    throw new Error(`MoonBit release artifact was not found at ${builtJavaScript}.`);
  }
  cpSync(join(playgroundRoot, "public"), stagingRoot, { recursive: true });
  copyFileSync(builtJavaScript, join(stagingRoot, "index.js"));
  rmSync(outputRoot, { recursive: true, force: true });
  renameSync(stagingRoot, outputRoot);
  process.stdout.write(`Built ${outputRoot}\n`);
} finally {
  rmSync(targetRoot, { recursive: true, force: true });
  rmSync(stagingRoot, { recursive: true, force: true });
}
