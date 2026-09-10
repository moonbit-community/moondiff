import {
  copyFileSync,
  mkdirSync,
  mkdtempSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { deflateSync } from "node:zlib";

import { extensionVersion } from "./version.mjs";

const scriptsDirectory = dirname(fileURLToPath(import.meta.url));
export const extensionRoot = resolve(scriptsDirectory, "..");
export const repositoryRoot = resolve(extensionRoot, "..");
export const outputRoot = join(extensionRoot, "dist");

export function readBuildConfig(env = process.env, mode = "development") {
  if (!["development", "webstore"].includes(mode)) throw new Error(`Unknown build mode: ${mode}`);
  const value = env.MOONDIFF_PLAYGROUND_URL;
  if (!value) throw new Error("Missing MOONDIFF_PLAYGROUND_URL.");
  const url = new URL(value);
  const loopback = ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
  if (url.username || url.password || url.pathname !== "/" || url.search || url.hash ||
      !(url.protocol === "https:" || mode === "development" && loopback && url.protocol === "http:")) {
    throw new Error("MOONDIFF_PLAYGROUND_URL must be an HTTPS root URL; development also allows loopback HTTP.");
  }
  return { playgroundUrl: url.origin + "/" };
}

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const name = Buffer.from(type, "ascii");
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const checksum = Buffer.alloc(4);
  checksum.writeUInt32BE(crc32(Buffer.concat([name, data])));
  return Buffer.concat([length, name, data, checksum]);
}

function segmentDistance(px, py, x1, y1, x2, y2) {
  const dx = x2 - x1;
  const dy = y2 - y1;
  const length = dx * dx + dy * dy;
  const t = length === 0 ? 0 : Math.max(0, Math.min(1, ((px - x1) * dx + (py - y1) * dy) / length));
  return Math.hypot(px - (x1 + t * dx), py - (y1 + t * dy));
}

function rasterIcon(size) {
  const scale = size / 32;
  const pixels = Buffer.alloc(size * size * 4);
  const samples = 4;
  for (let y = 0; y < size; y += 1) {
    for (let x = 0; x < size; x += 1) {
      let background = 0;
      let white = 0;
      for (let sy = 0; sy < samples; sy += 1) {
        for (let sx = 0; sx < samples; sx += 1) {
          const px = (x + (sx + 0.5) / samples) / scale;
          const py = (y + (sy + 0.5) / samples) / scale;
          const qx = Math.max(8 - px, 0, px - 24);
          const qy = Math.max(8 - py, 0, py - 24);
          const inside = qx * qx + qy * qy <= 64;
          if (inside) background += 1;
          const stroke = Math.min(
            segmentDistance(px, py, 10, 8, 10, 16),
            segmentDistance(px, py, 6, 12, 14, 12),
            segmentDistance(px, py, 18, 22, 26, 22),
          ) <= 1.3;
          if (inside && stroke) white += 1;
        }
      }
      const total = samples * samples;
      const alpha = Math.round(255 * background / total);
      const blend = background ? white / background : 0;
      const channel = Math.round(23 * (1 - blend) + 255 * blend);
      const offset = (y * size + x) * 4;
      pixels[offset] = channel;
      pixels[offset + 1] = channel;
      pixels[offset + 2] = channel;
      pixels[offset + 3] = alpha;
    }
  }
  const raw = Buffer.alloc((size * 4 + 1) * size);
  for (let y = 0; y < size; y += 1) {
    const row = y * (size * 4 + 1);
    raw[row] = 0;
    pixels.copy(raw, row + 1, y * size * 4, (y + 1) * size * 4);
  }
  const header = Buffer.alloc(13);
  header.writeUInt32BE(size, 0);
  header.writeUInt32BE(size, 4);
  header[8] = 8;
  header[9] = 6;
  return Buffer.concat([
    Buffer.from("89504e470d0a1a0a", "hex"),
    pngChunk("IHDR", header),
    pngChunk("IDAT", deflateSync(raw, { level: 9 })),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
}

function manifest(config) {
  const icons = {
    "16": "icons/icon-16.png",
    "32": "icons/icon-32.png",
    "48": "icons/icon-48.png",
    "128": "icons/icon-128.png",
  };
  return {
    manifest_version: 3,
    name: "Moondiff",
    description: "Open GitHub changes in your Moondiff playground with the Open in Moondiff button.",
    version: extensionVersion,
    minimum_chrome_version: "116",
    permissions: ["storage"],
    host_permissions: [new URL(config.playgroundUrl).origin + "/*"],
    background: { service_worker: "service-worker.js" },
    content_scripts: [{
      // GitHub can SPA-navigate into a PR or commit without creating a new document,
      // so the route watcher must already be present before that transition.
      matches: ["https://github.com/*"],
      js: ["target.js", "content-script.js"],
      run_at: "document_idle",
    }],
    icons,
    content_security_policy: {
      extension_pages: "script-src 'self'; object-src 'none'; connect-src 'self'",
    },
  };
}

export function buildExtension({ env = process.env, log = process.stdout, mode = "development" } = {}) {
  const buildConfig = readBuildConfig(env, mode);
  const stagingRoot = mkdtempSync(join(extensionRoot, ".dist-"));
  try {
    mkdirSync(join(stagingRoot, "icons"), { recursive: true });
    for (const file of ["target.js", "content-script.js", "service-worker.js"]) {
      copyFileSync(join(extensionRoot, "src", file), join(stagingRoot, file));
    }
    copyFileSync(join(extensionRoot, "icons", "favicon.svg"), join(stagingRoot, "icons", "favicon.svg"));
    for (const size of [16, 32, 48, 128]) {
      writeFileSync(join(stagingRoot, "icons", `icon-${size}.png`), rasterIcon(size));
    }
    writeFileSync(join(stagingRoot, "manifest.json"), `${JSON.stringify(manifest(buildConfig), null, 2)}\n`);
    writeFileSync(join(stagingRoot, "config.js"), `globalThis.MoondiffConfig = Object.freeze(${JSON.stringify({
      playgroundUrl: buildConfig.playgroundUrl,
    })});\n`);
    rmSync(outputRoot, { recursive: true, force: true });
    renameSync(stagingRoot, outputRoot);
    log.write(`Built ${outputRoot}\n`);
    return { outputRoot };
  } finally {
    rmSync(stagingRoot, { recursive: true, force: true });
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] || "").href) {
  try {
    buildExtension();
  } catch (error) {
    process.stderr.write(`${error?.message || error}\n`);
    process.exitCode = 1;
  }
}
