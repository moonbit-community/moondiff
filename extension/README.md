# Moondiff redirect extensions

Moondiff provides separate redirect extensions for desktop Chrome and Firefox.
Both add an **Open in Moondiff** button to supported GitHub pull-request and
commit pages, then open the canonical change URL in a configured self-hosted
playground.

- [Chrome development and packaging](chrome/README.md)
- [Firefox development and AMO packaging](firefox/README.md)

The two implementations intentionally keep independent source, build, test, and
version files. A browser-specific release can therefore be changed and reviewed
without coupling its runtime to the other browser.

From the repository root, the commands without a browser suffix process Chrome
first and Firefox second:

```sh
MOONDIFF_PLAYGROUND_URL=https://diff.example npm run build:extension
npm run test:extension
MOONDIFF_PLAYGROUND_URL=https://diff.example npm run package:extension
```

Use the `:chrome` or `:firefox` suffix to process only one implementation, for
example `build:extension:firefox`, `test:extension:firefox`, or
`package:extension:firefox`. Production packages embed the destination and only
accept an HTTPS root URL. Development builds additionally allow loopback HTTP.
