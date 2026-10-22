import { defineConfig } from "../../review-web/node_modules/@playwright/test/index.mjs";

export default defineConfig({
  testDir: "./tests",
  testMatch: "navigation.spec.mjs",
  workers: 1,
  reporter: "line",
  expect: { timeout: 7000 },
  use: {
    browserName: "firefox",
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
  },
});
