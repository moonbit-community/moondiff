import { existsSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";

import { buildExtension, extensionRoot } from "./build.mjs";
import { extensionVersion } from "./version.mjs";
import { lintOutput, packageOutput } from "./web-ext.mjs";

export async function packageExtension({
  destination = join(extensionRoot, "artifacts", `moondiff-firefox-${extensionVersion}.zip`),
  env = process.env,
  log = process.stdout,
} = {}) {
  buildExtension({ env, log, mode: "amo" });
  mkdirSync(dirname(destination), { recursive: true });
  await lintOutput({ log });
  await packageOutput(destination);
  if (!existsSync(destination)) {
    throw new Error(`web-ext did not create ${destination}.`);
  }
  log.write(`Packaged ${destination}\n`);
  return { destination };
}

if (import.meta.url === pathToFileURL(process.argv[1] || "").href) {
  try {
    await packageExtension();
  } catch (error) {
    process.stderr.write(`${error?.message || error}\n`);
    process.exitCode = 1;
  }
}
