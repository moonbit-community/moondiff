import { existsSync, readFileSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

import { outputRoot, repositoryRoot } from "./build.mjs";

const webExtEntry = join(
  repositoryRoot,
  "playground",
  "node_modules",
  "web-ext",
  "index.js",
);

async function loadWebExt() {
  if (!existsSync(webExtEntry)) {
    throw new Error("web-ext is not installed; run npm --prefix playground ci first.");
  }
  return (await import(pathToFileURL(webExtEntry).href)).default;
}

function isKnownDesktopOnlyFalsePositive(warning) {
  if (warning.code !== "KEY_FIREFOX_ANDROID_UNSUPPORTED_BY_MIN_VERSION") return false;
  const manifest = JSON.parse(readFileSync(join(outputRoot, "manifest.json"), "utf8"));
  const settings = manifest.browser_specific_settings;
  const required = settings?.gecko?.data_collection_permissions?.required;
  return settings &&
    !Object.hasOwn(settings, "gecko_android") &&
    settings.gecko.id === "moondiff@moonbit-community.github.io" &&
    settings.gecko.strict_min_version === "140.0" &&
    Array.isArray(required) &&
    required.length === 1 &&
    required[0] === "browsingActivity";
}

function describe(messages) {
  return messages.map(message =>
    `${message.code || "LINT_ERROR"}: ${message.message || message.description || "Unknown lint failure"}`
  ).join("\n");
}

export async function lintOutput({ log = process.stdout } = {}) {
  const webExt = await loadWebExt();
  const result = await webExt.cmd.lint({
    artifactsDir: dirname(outputRoot),
    boring: true,
    enterprise: false,
    ignoreFiles: [],
    metadata: false,
    output: "none",
    pretty: false,
    privileged: false,
    selfHosted: false,
    sourceDir: outputRoot,
    verbose: false,
    warningsAsErrors: true,
  }, { shouldExitProgram: false });

  // addons-linter 10.8.0 (bundled by web-ext 10.5.0) incorrectly applies
  // Android 142 compatibility to desktop-only manifests with no gecko_android
  // key: https://github.com/mozilla/web-ext/issues/3561. Keep the package
  // desktop-only and fail every other warning or error.
  const ignored = result.warnings.filter(isKnownDesktopOnlyFalsePositive);
  const failures = [
    ...result.errors,
    ...result.warnings.filter(warning => !ignored.includes(warning)),
  ];
  if (failures.length) {
    throw new Error(`web-ext lint failed:\n${describe(failures)}`);
  }
  if (ignored.length) {
    log.write("Ignored web-ext issue #3561's desktop-only Android compatibility false positive.\n");
  }
  return result;
}

export async function packageOutput(destination) {
  const webExt = await loadWebExt();
  const result = await webExt.cmd.build({
    artifactsDir: dirname(destination),
    asNeeded: false,
    filename: basename(destination),
    ignoreFiles: [],
    overwriteDest: true,
    sourceDir: outputRoot,
  }, { showReadyMessage: false });
  if (resolve(result.extensionPath) !== resolve(destination)) {
    throw new Error(`web-ext created an unexpected artifact: ${result.extensionPath}`);
  }
  return result;
}
