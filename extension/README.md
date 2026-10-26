# Moondiff redirect extensions

Moondiff provides separate redirect extensions for desktop Chrome and Firefox.
Both add an **Open in Moondiff** button to supported GitHub pull-request and
commit pages, then open the canonical change URL in a configured self-hosted
Moondiff Review app.

- [Chrome development and packaging](chrome/README.md)
- [Firefox development and AMO packaging](firefox/README.md)

The two implementations intentionally keep independent source, build, test, and
version files. A browser-specific release can therefore be changed and reviewed
without coupling its runtime to the other browser.

Builds use `MOONDIFF_REVIEW_URL` for the deployed Moondiff Review origin.

From the repository root, the commands without a browser suffix process Chrome
first and Firefox second:

```sh
MOONDIFF_REVIEW_URL=https://diff.example npm run build:extension
npm run test:extension
MOONDIFF_REVIEW_URL=https://diff.example npm run package:extension
```

Use the `:chrome` or `:firefox` suffix to process only one implementation, for
example `build:extension:firefox`, `test:extension:firefox`, or
`package:extension:firefox`. Production packages embed the destination and only
accept an HTTPS root URL. Development builds additionally allow loopback HTTP.

`npm run test:extension:unit` runs both unit suites without a browser.
`npm run test:extension:e2e` runs only the Playwright suites; use
`test:extension:chrome:e2e` or `test:extension:firefox:e2e` to select one browser.
CI runs the unit suites in the `check` workflow and the browser suites in
separate jobs in the `playwright` workflow.
