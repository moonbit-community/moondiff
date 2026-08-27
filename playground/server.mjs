import {
  createReadStream,
  existsSync,
  realpathSync,
  statSync,
} from "node:fs";
import { createServer } from "node:http";
import { dirname, extname, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const moduleDirectory = dirname(fileURLToPath(import.meta.url));
const defaultStaticRoot = resolve(moduleDirectory, "dist");

const contentTypes = new Map([
  [".css", "text/css; charset=utf-8"],
  [".html", "text/html; charset=utf-8"],
  [".js", "text/javascript; charset=utf-8"],
  [".json", "application/json; charset=utf-8"],
  [".map", "application/json; charset=utf-8"],
  [".svg", "image/svg+xml"],
  [".wasm", "application/wasm"],
]);

function serveStatic(request, response, staticRoot) {
  if (request.method !== "GET" && request.method !== "HEAD") {
    response.writeHead(405, { allow: "GET, HEAD" }).end("Method not allowed");
    return;
  }

  let pathname;
  try {
    pathname = decodeURIComponent(
      new URL(request.url ?? "/", "http://localhost").pathname,
    );
  } catch {
    response.writeHead(400).end("Bad request");
    return;
  }

  const relative = pathname === "/" ? "index.html" : pathname.slice(1);
  const candidate = resolve(staticRoot, relative);
  if (candidate !== staticRoot && !candidate.startsWith(`${staticRoot}${sep}`)) {
    response.writeHead(403).end("Forbidden");
    return;
  }

  try {
    const real = realpathSync(candidate);
    if (real !== staticRoot && !real.startsWith(`${staticRoot}${sep}`)) {
      response.writeHead(403).end("Forbidden");
      return;
    }
    const stat = statSync(real);
    if (!stat.isFile()) {
      response.writeHead(404).end("Not found");
      return;
    }
    response.writeHead(200, {
      "cache-control": "no-store",
      "content-type": contentTypes.get(extname(real)) ?? "application/octet-stream",
      "content-length": stat.size,
    });
    if (request.method === "HEAD") {
      response.end();
    } else {
      createReadStream(real).pipe(response);
    }
  } catch {
    response.writeHead(404).end("Not found");
  }
}

export function createMoondiffServer(options = {}) {
  const staticRoot = realpathSync(options.staticRoot ?? defaultStaticRoot);
  return createServer((request, response) => {
    serveStatic(request, response, staticRoot);
  });
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  if (!existsSync(defaultStaticRoot)) {
    throw new Error(
      `Static build not found at ${defaultStaticRoot}; run npm run build first.`,
    );
  }
  const host = process.env.HOST ?? "127.0.0.1";
  const port = Number.parseInt(process.env.PORT ?? "4173", 10);
  const server = createMoondiffServer();
  server.listen(port, host, () => {
    process.stdout.write(
      `Moondiff playground listening on http://${host}:${port}\n`,
    );
  });
}
