import { createServer } from "node:http";
import { readFileSync } from "node:fs";
import { extname, join, normalize } from "node:path";

import { buildExtension, outputRoot } from "../scripts/build.mjs";

buildExtension({
  env: { MOONDIFF_EXTENSION_ALLOW_TEST_CONFIG: "1" },
  log: { write() {} },
});

const types = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".json": "application/json; charset=utf-8",
};

createServer(async (request, response) => {
  try {
    const pathname = new URL(request.url, "http://localhost").pathname;
    const relative = pathname === "/" ? "panel.html" : pathname.slice(1);
    const safe = normalize(relative);
    if (safe.startsWith("..") || safe.includes("\0")) {
      response.writeHead(403).end("Forbidden");
      return;
    }
    const file = readFileSync(join(outputRoot, safe));
    response.writeHead(200, {
      "content-type": types[extname(safe)] || "application/octet-stream",
      "cache-control": "no-store",
    });
    response.end(file);
  } catch {
    response.writeHead(404).end("Not found");
  }
}).listen(4184, "127.0.0.1");
