import { defineConfig } from "@playwright/test";

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
    baseURL: "http://127.0.0.1:4173",
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
    video: "off",
  },
  webServer: {
    command: "node ./tests/serve.mjs",
    url: "http://127.0.0.1:4173",
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
