# Moondiff Chrome extension

The Manifest V3 extension adds an **Open in Moondiff** button to supported
GitHub commit and pull-request pages, then opens a tab-specific Side Panel.
Chrome 116 or newer is required.

The panel can browse public changes anonymously. GitHub App sign-in enables
private repository access, pull-request conversation comments, immediate
pull-request line comments and commit comments. It does not create pending
reviews or submit batched reviews.

## GitHub App configuration

Create a dedicated GitHub App with these repository permissions:

- Contents: read
- Pull requests: read and write

Enable both **Device Flow** and **expiring user access tokens**. The extension
shows GitHub's device code in the Side Panel; the user explicitly opens
`https://github.com/login/device` and enters that code. The extension never
opens the verification page automatically.

Provide all configuration at build time:

```sh
export MOONDIFF_GITHUB_CLIENT_ID='...'
export MOONDIFF_GITHUB_INSTALL_URL='https://github.com/apps/.../installations/new'
export MOONDIFF_EXTENSION_PUBLIC_KEY='base64 DER or PEM public key'
npm run build:extension
```

No GitHub client secret is accepted or included in the extension. Device codes
and access tokens are kept in `chrome.storage.session`, refresh tokens are kept
in `chrome.storage.local`, and both stores are restricted to trusted extension
contexts. Closing the Side Panel pauses polling; reopening it restores an
unexpired device authorization.

Load `extension/dist/` from `chrome://extensions` with **Developer mode → Load
unpacked**. Build artifacts are written to:

```text
extension/dist/
extension/artifacts/moondiff-chrome-0.0.1.zip
```

Create the zip with the same three environment variables:

```sh
npm run package:extension
```

`MOONDIFF_EXTENSION_ALLOW_TEST_CONFIG=1` selects a non-production fixture App
configuration for automated tests only.

## Tests

After installing the playground's pinned dependencies and Playwright Chromium:

```sh
npm run test:extension
```

This runs service-worker/content-script unit coverage, package-policy checks,
and Side Panel browser scenarios with a fake Chrome/GitHub bridge.
