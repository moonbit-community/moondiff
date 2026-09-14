import { pathToFileURL } from "node:url";

import { buildExtension } from "./build.mjs";
import { lintOutput } from "./web-ext.mjs";

export async function lintExtension({
  env = process.env,
  log = process.stdout,
  mode = "development",
} = {}) {
  buildExtension({ env, log, mode });
  await lintOutput({ log });
  log.write("Firefox extension lint passed.\n");
}

if (import.meta.url === pathToFileURL(process.argv[1] || "").href) {
  try {
    await lintExtension();
  } catch (error) {
    process.stderr.write(`${error?.message || error}\n`);
    process.exitCode = 1;
  }
}
