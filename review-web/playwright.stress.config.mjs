import { defineConfig } from "@playwright/test";
import baseConfig from "./playwright.config.mjs";

export default defineConfig({
  ...baseConfig,
  testMatch: "*.stress.mjs",
  workers: 1,
  fullyParallel: false,
  // DOM snapshots on every action serialize the whole large fixture while its
  // renderer is CPU-throttled. Keep action traces/screenshots and the shared
  // request/render diagnostics without making that serialization the benchmark.
  use: {
    ...baseConfig.use,
    trace: { mode: "retain-on-failure", snapshots: false, screenshots: true, sources: true },
  },
});
