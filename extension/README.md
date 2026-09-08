# Moondiff Chrome extension

This Manifest V3 Chrome extension adds an **Open in Moondiff** button to GitHub commit
and pull-request pages and opens the full diff in a new extension tab. Public changes work
anonymously; GitHub App sign-in adds private repository access and PR or commit
comments. Pending and batched reviews are not supported. Chrome 116 or newer is
required.

## Build locally

Create a dedicated GitHub App with these repository permissions:

- Contents: read and write
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

Code soft-wraps in both Split and Unified views. Ignore comments and Ignore tests
start on each page load; choices stay in the current session and are never saved
in share links or local storage. Both controls show an icon and label,
with OpenSeek GUI's soft blue (`#EEF2FE`) background, primary blue (`#3B6EF5`)
border, and strong blue (`#2A55CC`) text when on in either theme. On narrow
screens they show only their icons (**//**
and **T**), without On/Off badges; their pressed states remain available to
assistive technology.

Published line comments and editors appear above their source line, with file,
side and line labels. Hidden lines fall back to file discussions; outdated
comments show their original line when available. Only your own comments offer
deletion, with an inline confirmation and retryable errors.

Existing GitHub App installations need an administrator to accept the updated
**Contents: write** and **Pull requests: write** permissions for full comment
deletion support.

Replies require an existing top-level comment. If its root is deleted, remaining replies stay visible with Reply disabled. Send or cancel a reply draft (including an empty draft) before deleting its root. A root being deleted cannot receive a new reply draft. If a refresh discovers that a draft's root has disappeared, the draft appears once in the Comments overview, where its text can be copied or the draft cancelled; posting is disabled. An already pending post finishes normally.

PR updates are loaded manually. Comment refreshes verify the PR's base/head SHAs,
repositories, and file count before and after reading comments against the
current diff. A mismatch displays **PR updated** and **Load latest**, keeping the
current diff, verified comments, and draft. Line authoring pauses until the new
snapshot is loaded; overall comments and valid thread replies remain available.
Successful line posts show a GitHub link before a verified refresh places them
inline. Network failures retain existing comments and can be retried with Refresh.

One draft is retained at a time, including empty drafts. Repeated clicks on its
target keep its state; switching targets requires sending or cancelling it.
Comment entry buttons are disabled during submission. **Load latest** is disabled
while a draft, submission, or deletion is pending. Drafts on an outdated snapshot
can still be edited, copied, or cancelled. Late refresh and submission responses
cannot replace newer results or clear another draft.
