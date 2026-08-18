import {
  mkdirSync,
  readdirSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { join, relative } from "node:path";
import { pathToFileURL } from "node:url";

import { buildExtension, extensionRoot, outputRoot } from "./build.mjs";

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function filesUnder(root, directory = root) {
  const files = [];
  for (const name of readdirSync(directory).sort()) {
    const path = join(directory, name);
    if (statSync(path).isDirectory()) files.push(...filesUnder(root, path));
    else files.push({ path, name: relative(root, path).split("\\").join("/") });
  }
  return files;
}

function localHeader(name, data, checksum) {
  const encoded = Buffer.from(name);
  const header = Buffer.alloc(30);
  header.writeUInt32LE(0x04034b50, 0);
  header.writeUInt16LE(20, 4);
  header.writeUInt16LE(0, 6);
  header.writeUInt16LE(0, 8);
  header.writeUInt16LE(0, 10);
  header.writeUInt16LE(33, 12);
  header.writeUInt32LE(checksum, 14);
  header.writeUInt32LE(data.length, 18);
  header.writeUInt32LE(data.length, 22);
  header.writeUInt16LE(encoded.length, 26);
  header.writeUInt16LE(0, 28);
  return Buffer.concat([header, encoded, data]);
}

function centralHeader(name, data, checksum, offset) {
  const encoded = Buffer.from(name);
  const header = Buffer.alloc(46);
  header.writeUInt32LE(0x02014b50, 0);
  header.writeUInt16LE(20, 4);
  header.writeUInt16LE(20, 6);
  header.writeUInt16LE(0, 8);
  header.writeUInt16LE(0, 10);
  header.writeUInt16LE(0, 12);
  header.writeUInt16LE(33, 14);
  header.writeUInt32LE(checksum, 16);
  header.writeUInt32LE(data.length, 20);
  header.writeUInt32LE(data.length, 24);
  header.writeUInt16LE(encoded.length, 28);
  header.writeUInt16LE(0, 30);
  header.writeUInt16LE(0, 32);
  header.writeUInt16LE(0, 34);
  header.writeUInt16LE(0, 36);
  header.writeUInt32LE(0, 38);
  header.writeUInt32LE(offset, 42);
  return Buffer.concat([header, encoded]);
}

export function createZip(source, destination) {
  const entries = filesUnder(source).filter(entry => {
    if (entry.name.endsWith(".map")) return false;
    if (entry.name.includes("/.dist-") || entry.name.includes("/.tmp")) return false;
    return true;
  });
  const locals = [];
  const centrals = [];
  let offset = 0;
  for (const entry of entries) {
    const data = readFileSync(entry.path);
    const checksum = crc32(data);
    const local = localHeader(entry.name, data, checksum);
    locals.push(local);
    centrals.push(centralHeader(entry.name, data, checksum, offset));
    offset += local.length;
  }
  const central = Buffer.concat(centrals);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(0, 4);
  end.writeUInt16LE(0, 6);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(central.length, 12);
  end.writeUInt32LE(offset, 16);
  end.writeUInt16LE(0, 20);
  writeFileSync(destination, Buffer.concat([...locals, central, end]));
  return entries.map(entry => entry.name);
}

export function packageExtension(options = {}) {
  buildExtension(options);
  const artifacts = join(extensionRoot, "artifacts");
  mkdirSync(artifacts, { recursive: true });
  const destination = join(artifacts, "moondiff-chrome-0.0.1.zip");
  rmSync(destination, { force: true });
  const entries = createZip(outputRoot, destination);
  process.stdout.write(`Packaged ${destination} (${entries.length} files)\n`);
  return { destination, entries };
}

if (import.meta.url === pathToFileURL(process.argv[1] || "").href) {
  try {
    packageExtension();
  } catch (error) {
    process.stderr.write(`${error?.message || error}\n`);
    process.exitCode = 1;
  }
}
