import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig } from "../playground/node_modules/@playwright/test/index.mjs";

const extensionRoot = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(extensionRoot, "..");

export default defineConfig({
  testDir: "./tests",
  testMatch: "panel.spec.mjs",
  fullyParallel: false,
  reporter: "line",
  expect: { timeout: 7_000 },
  use: {
    baseURL: "http://127.0.0.1:4184",
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
    video: "off",
  },
  webServer: {
    command: "node extension/tests/serve.mjs",
    cwd: repositoryRoot,
    url: "http://127.0.0.1:4184/panel.html",
    reuseExistingServer: false,
    timeout: 120_000,
  },
  projects: [{ name: "chromium", use: { browserName: "chromium" } }],
});
