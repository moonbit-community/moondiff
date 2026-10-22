import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import test from 'node:test';
import { chromium } from '@playwright/test';

const repository = resolve(import.meta.dirname, '../..');
const packageName = 'moonbit-community/moondiff-review-web/internal/view';
const browserAttribute = '#skip("browser DOM: npm run test:views")';

test('MoonBit view components in Chromium', { timeout: 120_000 }, async t => {
  const target = mkdtempSync(join(tmpdir(), 'moondiff-view-tests-'));
  t.after(() => rmSync(target, { recursive: true, force: true }));
  const build = spawnSync('moon', [
    'test', 'review-web/frontend/internal/view', '--target', 'js',
    '--build-only', '--include-skipped', '--target-dir', target,
  ], { cwd: repository, encoding: 'utf8', maxBuffer: 10 * 1024 * 1024 });
  assert.ifError(build.error);
  assert.equal(build.status, 0, build.stdout + build.stderr);
  const report = build.stdout.split('\n').flatMap(line => {
    try { return [JSON.parse(line)]; } catch { return []; }
  }).find(value => Array.isArray(value.artifacts_path));
  assert.ok(report, `Missing MoonBit build report:\n${build.stdout}`);
  const artifact = report.artifacts_path.find(path => path.endsWith('/view.whitebox_test.js'));
  assert.ok(artifact, 'Missing MoonBit white-box test artifact');
  const source = readFileSync(artifact, 'utf8');
  const info = JSON.parse(readFileSync(join(dirname(artifact), '__whitebox_test_info.json'), 'utf8'));
  const entries = Object.entries(info.tests).flatMap(([file, cases]) =>
    cases.filter(entry => entry.attrs.includes(browserAttribute))
      .map(entry => ({ file, ...entry })));
  assert.ok(entries.length > 0, 'No browser view fixtures were discovered');

  const browser = await chromium.launch();
  t.after(() => browser.close());
  for (const entry of entries) {
    await t.test(`${entry.file}:${entry.line_number} ${entry.name}`, async () => {
      const page = await browser.newPage();
      try {
        // Avatar URLs are fixture data; component assertions need no network.
        await page.route('**/*', route => route.abort());
        await page.setContent('<!doctype html><title>MoonBit view fixture</title>');
        await page.evaluate(({ packageName, file, index }) => {
          // The generated MoonBit test driver expects argv and CommonJS exports.
          // Supply only those runner interfaces; window/document remain Chromium's.
          globalThis.process = {
            argv: ['node', 'view.whitebox_test.js', JSON.stringify({
              package: packageName,
              file_and_index: [[file, [{ start: index, end: index + 1 }]]],
            })],
            exit(code) { throw new Error(`MoonBit test driver exited with ${code}`); },
          };
          globalThis.exports = {};
          globalThis.__moonbitViewResults = { records: [], errors: [] };
          addEventListener('error', event => __moonbitViewResults.errors.push(event.message));
          addEventListener('unhandledrejection', event =>
            __moonbitViewResults.errors.push(String(event.reason)));
          const log = console.log.bind(console);
          let inResult = false;
          console.log = (...args) => {
            log(...args);
            const line = args[0];
            if (line === '----- BEGIN MOON TEST RESULT -----') inResult = true;
            else if (line === '----- END MOON TEST RESULT -----') inResult = false;
            else if (inResult) {
              try { __moonbitViewResults.records.push(JSON.parse(line)); }
              catch { __moonbitViewResults.errors.push(`Invalid MoonBit test result: ${line}`); }
            }
          };
        }, { packageName, file: entry.file, index: entry.index });
        // Execute the compiler's unmodified artifact, including its white-box
        // fixtures and assertions. Each case gets a fresh page and DOM.
        await page.addScriptTag({ content: source });
        const { records, errors } = await page.evaluate(() => __moonbitViewResults);
        assert.deepEqual(errors, [], errors.join('\n'));
        assert.equal(records.length, 2, `Expected one start and one result:\n${JSON.stringify(records)}`);
        assert.deepEqual(records[0], { type: 'start', file: entry.file, index: entry.index });
        assert.equal(records[1].type, 'result');
        assert.equal(records[1].file, entry.file);
        assert.equal(records[1].index, entry.index);
        assert.equal(records[1].message, '', records[1].message);
      } finally {
        await page.close();
      }
    });
  }
});
