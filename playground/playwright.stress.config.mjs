import { defineConfig } from "@playwright/test";
import baseConfig from "./playwright.config.mjs";

export default defineConfig({
  ...baseConfig,
  testMatch: "*.stress.mjs",
  workers: 1,
  fullyParallel: false,
});
