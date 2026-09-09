import { defineConfig } from '../playground/node_modules/@playwright/test/index.mjs';
export default defineConfig({
  testDir: './tests', testMatch: 'navigation.spec.mjs', workers: 1,
  reporter: 'line', expect: { timeout: 7000 },
  use: { screenshot: 'only-on-failure', trace: 'retain-on-failure' },
});
