# Moondiff Chrome extension

This Manifest V3 Chrome extension adds an **Open in Moondiff** button to GitHub commit
and pull-request pages and opens the full diff in a new extension tab. Public changes work
anonymously; GitHub App sign-in adds private repository access and PR or commit
comments. Pending and batched reviews are not supported. Chrome 116 or newer is
required.

## Build locally

Create a dedicated GitHub App with these repository permissions:

- Contents: read
- Pull requests: read and write

Enable **Device Flow** and **expiring user access tokens**. No client secret is
required or included in the extension.

From the repository root, provide the GitHub App configuration and build:

```sh
export MOONDIFF_GITHUB_CLIENT_ID='...'
export MOONDIFF_GITHUB_INSTALL_URL='https://github.com/apps/.../installations/new'
npm run build:extension
```

Load `extension/dist/` from `chrome://extensions` using **Developer mode → Load
unpacked**.

## Package

With the production GitHub App configuration still set, run:

```sh
npm run package:extension
```

The Chrome Web Store ZIP is written to
`extension/artifacts/moondiff-chrome-<version>.zip`. Change `extensionVersion` in
`extension/scripts/version.mjs` when releasing a new version.

## Tests

After installing the playground dependencies and Playwright Chromium, run from
the repository root:

```sh
npm run test:extension
```

This covers the extension scripts, packaging policy, and review-page browser
scenarios.
