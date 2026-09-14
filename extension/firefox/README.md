# Moondiff redirect extension for Firefox

This desktop Firefox 140+ extension adds a black **Open in Moondiff** button to
GitHub commit and pull-request pages. A trusted mouse or keyboard activation
opens the corresponding canonical path in a configured self-hosted
[Moondiff playground](../../playground/README.md). The extension contains no
review UI, GitHub API client, OAuth flow, credentials, or telemetry.

## Build and temporarily install

Install the locked development dependencies, then build from the repository
root:

```sh
npm --prefix playground ci
MOONDIFF_PLAYGROUND_URL=https://diff.example npm run build:extension:firefox
```

Development builds also accept a loopback URL such as
`MOONDIFF_PLAYGROUND_URL=http://localhost:4173`. Subpaths, query strings,
fragments, credentials, and nonlocal HTTP are rejected.

To load the unpacked build in desktop Firefox:

1. Open `about:debugging#/runtime/this-firefox`.
2. Select **Load Temporary Add-on…**.
3. Select `extension/firefox/dist/manifest.json`.
4. Open a GitHub PR or commit page and verify that navigation alone does not
   open a playground tab.
5. Activate **Open in Moondiff** with the mouse and keyboard, and verify that it
   opens the matching path at the configured playground.

Temporary add-ons are removed when Firefox exits. The build uses a Manifest V3
event page whose classic scripts load in this order: `config.js`, `target.js`,
and `background.js`. Runtime code uses Firefox's native `browser.*` Promise API.

## Build the AMO ZIP

```sh
MOONDIFF_PLAYGROUND_URL=https://diff.example npm run package:extension:firefox
```

Packaging rebuilds in AMO mode, rejects loopback HTTP, runs
`web-ext lint --warnings-as-errors`, and then runs `web-ext build`. The resulting
upload archive is
`extension/firefox/artifacts/moondiff-firefox-0.1.0.zip`. Update
`scripts/version.mjs` for a later Firefox release.

`web-ext` currently reports a known Android-142 compatibility false positive
for a desktop-only Firefox-140 manifest that omits `gecko_android`
([mozilla/web-ext#3561](https://github.com/mozilla/web-ext/issues/3561)). The
wrapper permits only that exact warning under those exact manifest conditions;
every other warning remains an error. This avoids falsely advertising Android
support merely to silence the linter.

The ZIP is intended for manual upload to addons.mozilla.org. This repository
does not sign or publish it and contains no Mozilla API credentials, store
listing automation, or signing keys. A permanent installation in release
Firefox requires Mozilla signing.

## Data collection declaration

The manifest declares required `browsingActivity` data collection. Only after a
user activates the button, the extension sends the repository owner/name and
either a pull-request number or commit SHA as part of the URL opened at the
configured playground. This is needed to select the requested change.

The extension does not transmit GitHub page content, authentication data,
cookies, comments, drafts, telemetry, click statistics, or general browsing
history. It only runs its content script on `https://github.com/*`; permissions
are limited to `storage` and the configured playground origin. See Mozilla's
[built-in data consent categories](https://extensionworkshop.com/documentation/develop/firefox-builtin-data-consent/).

## Navigation and tab reuse

GitHub initial loads and SPA transitions update the button without opening or
activating a destination. PR home, files, and commit-list pages share one
canonical PR path. GitHub `changes/sha` and `commits/sha` aliases share a pull
commit path; standalone commits use a commit path. Casing, query parameters, and
comment anchors do not create duplicates.

Mappings are keyed by source GitHub tab and canonical change path in
`browser.storage.session`, so they survive event-page suspension. Concurrent
requests share one open operation. An existing destination is activated only if
it still has the expected origin and path; a closed or navigated destination is
forgotten, and existing page content is never replaced. Upgrade initialization
deletes credential keys used by older extension versions.

## Tests

```sh
cd playground && npx playwright install firefox && cd ..
npm run test:extension:firefox
MOONDIFF_PLAYGROUND_URL=https://diff.example npm run lint:extension:firefox
```

Node tests cover URL parsing, message validation and Promise responses,
concurrent opens, tab reuse and cleanup, event-page restart, credential cleanup,
the generated manifest, strict production URL validation, AMO linting, and ZIP
location. Playwright runs the content script in Firefox and covers button
display, SPA transitions, redraws, trusted mouse and keyboard input, pending
request disabling, and failure retry.
