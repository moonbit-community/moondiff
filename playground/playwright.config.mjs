import { defineConfig } from "@playwright/test";
import { e2eOrigin } from "./tests/e2e-config.mjs";

export default defineConfig({
  testDir: "./frontend/tests",
  testMatch: "*.spec.mjs",
  workers: 4,
  fullyParallel: true,
  reporter: "line",
  expect: {
    timeout: 5_000,
  },
  use: {
    baseURL: e2eOrigin,
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
    video: "off",
  },
  webServer: {
    command: "node ./tests/serve.mjs",
    url: e2eOrigin,
    reuseExistingServer: false,
    timeout: 120_000,
  },
  projects: [
    {
      name: "chromium",
      use: { browserName: "chromium" },
    },
  ],
});
