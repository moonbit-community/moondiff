import { spawnSync } from "node:child_process";
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  statSync,
} from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { dirname, extname, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const testsDir = dirname(fileURLToPath(import.meta.url));
const playgroundRoot = resolve(testsDir, "..");
const repositoryRoot = resolve(playgroundRoot, "..");
const temporaryRoot = mkdtempSync(join(tmpdir(), "moondiff-playground-e2e-"));
const targetDir = join(temporaryRoot, "moon-target");
const publicRoot = join(playgroundRoot, "public");

const build = spawnSync(
  "moon",
  [
    "build",
    "--target",
    "js",
    "--release",
    "--target-dir",
    targetDir,
    "playground/main",
  ],
  { cwd: repositoryRoot, stdio: "inherit" },
);

if (build.error) {
  rmSync(temporaryRoot, { recursive: true, force: true });
  throw build.error;
}
if (build.status !== 0) {
  rmSync(temporaryRoot, { recursive: true, force: true });
  throw new Error(`MoonBit release build failed with exit code ${build.status}.`);
}

const builtJavaScript = join(
  targetDir,
  "js",
  "release",
  "build",
  "moonbit-community",
  "moondiff-playground",
  "main",
  "main.js",
);
if (!existsSync(builtJavaScript)) {
  rmSync(temporaryRoot, { recursive: true, force: true });
  throw new Error(`MoonBit release artifact was not found at ${builtJavaScript}.`);
}

const builtJavaScriptBody = readFileSync(builtJavaScript);
rmSync(temporaryRoot, { recursive: true, force: true });

const contentTypes = new Map([
  [".css", "text/css; charset=utf-8"],
  [".html", "text/html; charset=utf-8"],
  [".js", "text/javascript; charset=utf-8"],
  [".json", "application/json; charset=utf-8"],
  [".svg", "image/svg+xml"],
]);

const server = createServer((request, response) => {
  const requestUrl = new URL(request.url ?? "/", "http://127.0.0.1");
  const relativePath = decodeURIComponent(
    requestUrl.pathname === "/" ? "index.html" : requestUrl.pathname.slice(1),
  );
  if (relativePath === "index.js") {
    response.writeHead(200, {
      "cache-control": "no-store",
      "content-type": contentTypes.get(".js"),
    });
    response.end(builtJavaScriptBody);
    return;
  }

  const filePath = resolve(publicRoot, relativePath);
  if (!filePath.startsWith(`${publicRoot}${sep}`)) {
    response.writeHead(403).end("Forbidden");
    return;
  }

  try {
    if (!statSync(filePath).isFile()) {
      response.writeHead(404).end("Not found");
      return;
    }
    response.writeHead(200, {
      "cache-control": "no-store",
      "content-type": contentTypes.get(extname(filePath)) ?? "application/octet-stream",
    });
    response.end(readFileSync(filePath));
  } catch {
    response.writeHead(404).end("Not found");
  }
});

const port = Number.parseInt(process.env.PORT ?? "4173", 10);

function shutdown() {
  server.close();
  process.exit(0);
}

process.on("SIGHUP", shutdown);
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);

server.listen(port, "127.0.0.1", () => {
  process.stdout.write(`Moondiff playground E2E server listening on http://127.0.0.1:${port}\n`);
});
