# Moondiff playground

The static Rabbita playground accepts either of these public GitHub URLs:

```text
https://github.com/{owner}/{repo}/commit/{sha}
https://github.com/{owner}/{repo}/pull/{number}/changes/{sha}
```

Both forms compare the commit with its first parent (or an empty old side for
a root commit). Every changed file receives a card in GitHub's order. Files
whose old or new path ends in `.mbt` use the bundled `tokdiff` engine's
MoonBit-aware lexical diff by default. The global **Lexical / AST** control
switches those files to structural diffing; pure formatting and top-level
reordering become an explicit no-structural-changes state. Parser failures and
whole-file graph-limit failures show a lexical fallback reason; when only one
aligned top-level declaration exceeds the graph limit, the playground labels
that declaration as a partial lexical fallback and keeps AST diffing the rest
of the file. Other valid UTF-8 text files always use a plain line diff. The
selected algorithm survives later
commit navigation in the open app but is not written into share URLs. The
first 20 MoonBit diffs open automatically, while all other files load on
demand. Calculated documents are cached independently by algorithm, so layout
switches and analysis rendering reuse the same hunks.

Each downloaded side is limited to 1 MiB and 20,000 lines. Invalid UTF-8,
NUL-containing, binary, and over-limit content keeps its file card and shows
an explanatory message instead of a rendered diff. The browser fetches
anonymous GitHub REST and raw-content endpoints and never accepts, stores, or
sends a personal access token. Anonymous GitHub API rate limits therefore
apply.

When the playground is served by its optional local Node backend, an
**Analyze changes** action appears. It loads both sides of every changed file
without expanding file cards, uses the current algorithm's cached `context=3`
hunks, and asks OpenSeek to group them by cross-file function in descending
review importance. AST files with no structural changes are listed as skipped;
if the commit has no analyzable hunks, the browser reports that locally without
calling the backend. After analysis, the ordered groups replace the file list:
the most important group opens first, later groups stay collapsed until
requested, and each hunk keeps its file path, highlighted diff, and dedicated
explanation.
Commits over 50 files, 200 text hunks, or 256 KiB of UTF-8 patch data are
rejected as a whole. Invalid UTF-8, NUL-containing, and binary files are listed
as skipped; download failures and the existing 1 MiB/20,000-line source limits
stop the analysis.

GitHub Pages remains a static deployment. If `/api/health` is unavailable,
the analysis action is simply hidden and the normal diff viewer is unchanged.

Submitting a GitHub URL updates the browser to a static-host-friendly share
route:

```text
https://{playground-host}/{base}/#/owner/repo/commit/sha
```

Opening that URL restores and loads the same commit automatically. The result
page also exposes the full URL in a read-only field with a one-click copy
button. Hash routing keeps shared links working on GitHub Pages without a
server-side rewrite rule.

## Local backend and OpenSeek

Install OpenSeek on `PATH` and configure one of its supported providers. For
example:

```sh
export DEEPSEEK='your-api-key'
export OPENSEEK_MODEL='deepseek-v4-pro'
# Optional for a compatible endpoint:
export OPENSEEK_API_URL='https://example.invalid/chat/completions'
```

`KIMI` and Kimi-related configuration are also passed through. Set
`OPENSEEK_BIN` if the executable is not named `openseek`. Build and start the
same-origin site on the default `http://127.0.0.1:4173`:

```sh
cd playground
npm run build
npm start
```

Override `HOST`, `PORT`, or `ANALYSIS_TIMEOUT_MS` when needed. The default
analysis timeout is 180 seconds. A development command that builds once and
restarts the Node server when its module changes is also available:

```sh
cd playground
npm run dev
```

The server has no authentication and is intended only for localhost or a
trusted private network. It enforces same-origin POSTs, a 512 KiB body limit,
one analysis at a time, reduced child-process environment variables, an empty
skills directory, and per-request temporary workspaces. OpenSeek's built-in
tools cannot currently be disabled by this integration, so these controls
reduce exposure but do not replace an OS sandbox. Do not expose this server as
a public multi-tenant service.

## Tests

Create the static release site with:

```sh
cd playground
npm run build
```

The playground also has Chromium end-to-end tests. They build the MoonBit JS
release into a temporary directory, serve it with the static assets in
`playground/public`, and mock every GitHub API and raw-content request. Install
the pinned Node dependencies and Playwright browser once, then run the suite:

```sh
cd playground
npm ci
npx playwright install chromium
npm run server-test
npm run test:e2e
```

On a machine that is missing Chromium system libraries, use
`npx playwright install --with-deps chromium` instead. For an interactive
Playwright session, run `npm run test:e2e:ui`.
