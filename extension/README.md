# Moondiff redirect extension

The extension adds a black **Open in Moondiff** button to the bottom-right corner
of GitHub commit and pull-request pages. Click it to open the corresponding page
in your self-hosted [Moondiff playground](../playground/README.md). It contains no
review UI, GitHub API client, OAuth flow or credentials. Authentication and
comments belong to the playground backend.

## Build and install

Set the destination at build time, from the repository root:

```sh
MOONDIFF_PLAYGROUND_URL=https://diff.example npm run build:extension
```

Load `extension/dist/` using **Load unpacked** in Chrome's extension developer
mode. Development builds also accept a loopback URL such as
`MOONDIFF_PLAYGROUND_URL=http://localhost:4173`. Subpaths, query strings,
fragments, credentials and nonlocal HTTP are rejected. The build copies only
extension scripts, configuration and icons; MoonBit and the frontend are not
built by this command.

For a Chrome Web Store ZIP:

```sh
MOONDIFF_PLAYGROUND_URL=https://diff.example npm run package:extension
```

Production packages require an HTTPS root URL. Update `scripts/version.mjs` for
a new release. The ZIP is written to `extension/artifacts/`. The destination is fixed in the package; rebuild to
change it.

## Navigation and tab reuse

GitHub first loads and SPA transitions update the button without opening or
activating playground tabs. The button is removed on unsupported pages and
restored after page redraws. It supports mouse and keyboard activation, and is
temporarily disabled while opening; after a failed request, click again to retry.

Each click uses the current GitHub URL. PR home,
Files changed and commit-list pages all map to `/owner/repo/pull/number`.
`changes/sha` and `commits/sha` both map to
`/owner/repo/pull/number/commits/sha`. Commit pages map to
`/owner/repo/commit/sha`. Repository/SHA casing, query parameters and comment
anchors do not create duplicate destinations.

Mappings are keyed by source GitHub tab ID plus canonical change path and saved
in `chrome.storage.session`, surviving service worker restarts. Concurrent requests
share one open operation. Different changes open and activate separate tabs.
Clicking the button for the same change activates its existing tab if it still has the
matching origin and path. Closed or navigated-away destinations are forgotten;
the extension never navigates an existing tab to replace its content or draft.
Two source GitHub tabs have independent mappings.

Permissions are limited to `storage`, a content script on `https://github.com/*`,
and the configured playground origin. The destination host permission lets the
worker inspect a candidate tab's URL before reusing it, as described in the
[Chrome tabs documentation](https://developer.chrome.com/docs/extensions/reference/api/tabs).
There are no GitHub API/OAuth host permissions or general `tabs` permission.
Upgrade initialization deletes the old extension's credential keys from local
and session storage. Users must sign in again on the playground.

## Tests

```sh
npm --prefix playground ci
cd playground && npx playwright install chromium && cd ..
npm run test:extension
```

Unit tests cover aliases, permission/config validation, concurrent opens, worker
restart, old credential cleanup and tab lifecycle. Chromium loads the real
extension against local route fixtures for GitHub and the destination, covering
button appearance, click-only opening, SPA navigation, page redraws, safe reuse,
closed/navigated tabs and distinct source tabs. Content-script browser tests also
cover trusted clicks, keyboard activation, pending requests and failure retries.
The former review tests now live under `playground/frontend/tests/` and use
same-origin HTTP fixtures.
