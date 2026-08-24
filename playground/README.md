# Moondiff playground

The static Rabbita playground accepts these public GitHub URLs:

```text
https://github.com/{owner}/{repo}/commit/{sha}
https://github.com/{owner}/{repo}/pull/{number}
https://github.com/{owner}/{repo}/pull/{number}/files
https://github.com/{owner}/{repo}/pull/{number}/changes/{sha}
https://github.com/{owner}/{repo}/pull/{number}/commits/{sha}
```

GitHub may rewrite PR commit-detail URLs between the `changes/{sha}` and
`commits/{sha}` forms; the playground accepts both and treats them equivalently.
Commit URLs and either PR commit-detail form compare one commit with its first
parent (or an empty old side for a root commit). Pull request URLs load the PR's
current head and aggregate the complete **Files changed** result. The
old revision is `merge_base_commit.sha` from the
[Compare API](https://docs.github.com/en/rest/commits/commits#compare-two-commits)
response for pinned `base.sha...head.sha`, matching GitHub's merge-base-to-head
[three-dot comparison](https://docs.github.com/en/pull-requests/reference/branches#three-dot-and-two-dot-git-diff-comparisons).
The playground captures PR metadata before loading the comparison and paginated
files, then fetches metadata again before showing or downloading any source. If
the base, head, or changed-file count moved—or the first files response was
incomplete—it automatically retries once using the latest metadata. A PR that
changes again fails explicitly; a stable but still incomplete response keeps
the incomplete-files error.
The files endpoint is fetched in 100-file pages. GitHub caps that endpoint at
[3,000 files](https://docs.github.com/en/rest/pulls/pulls#list-pull-requests-files),
so larger or incomplete responses fail explicitly instead of showing a partial
PR. Every changed file receives a card in GitHub's order. Files
whose old or new path ends in `.mbt` use the bundled `mbtdiff` engine's
MoonBit-aware lexical diff by default. The global **Lexical / AST** control
switches those files to structural diffing; pure formatting and top-level
reordering become an explicit no-structural-changes state. Parser failures and
whole-file graph-limit failures show a lexical fallback reason; when only one
aligned top-level declaration exceeds the graph limit, the playground labels
that declaration as a partial lexical fallback and keeps AST diffing the rest
of the file. The default-off **Ignore comments** control applies to MoonBit
files in both Lexical and AST mode. It ignores ordinary and documentation
comments, generated `///|UUID(...)` markers, and the separating whitespace
before a comment while keeping strings such as `"//not a comment"` intact. It
also ignores empty lines, lines containing only Unicode whitespace, blank-line
count changes, and a missing or added final newline. Pure comment and blank-line
changes produce no hunks. When nearby code also changes, the original comments
and blank lines remain visible as neutral context without addition, deletion,
or intraline highlighting. The separate default-off **Ignore tests** control
excludes top-level `test` and `async test` blocks after both MoonBit inputs parse
successfully, including their leading documentation comments, UUID markers,
and `///|` separators. Test-only changes produce no hunks; mixed changes report
only production code, while an `import { ... } for "test"` declaration remains
part of the diff. Ignore comments and Ignore tests compose independently. If
parsing fails, the existing whole-file lexical fallback is retained and test
filtering is not guaranteed. Other valid UTF-8 text files always use a plain
line diff and are unaffected by either control.

The selected algorithm and both filter settings survive later change navigation
in the open app but are not written into share URLs; a refresh restores Lexical
mode with both filters off. The first 20 MoonBit diffs open automatically, while
all other files load on demand. LineDiff keeps one shared cache. MoonBit files
cache all eight Lexical/AST × comments/tests combinations independently, so
layout switches and analysis rendering reuse the same stable hunks.

Each downloaded side is limited to 1 MiB and 20,000 lines. Invalid UTF-8,
NUL-containing, binary, and over-limit content keeps its file card and shows
an explanatory message instead of a rendered diff. The browser fetches
anonymous GitHub REST and raw-content endpoints and never accepts, stores, or
sends a personal access token. Anonymous GitHub API rate limits therefore
apply.

When the playground is served by its optional local Node backend, an
**Analyze changes** action appears. It loads both sides of every changed file
without expanding file cards, uses the current algorithm's cached `context=3`
hunks (including both current filter settings), and asks OpenSeek to group them
by cross-file function in descending review importance. AST files with no
structural changes and MoonBit files containing only ignored tests, comments,
or blank-line changes are listed as skipped; if the change has no analyzable
hunks, the browser reports that locally without calling the backend. After
analysis, the ordered groups replace the file list:
the most important group opens first, later groups stay collapsed until
requested, and each hunk keeps its file path, highlighted diff, and dedicated
explanation.
The analysis service remains on payload version 1: a pull request is represented
by `sha = head`, `parent_sha = merge base`, and `message = PR title` in the
existing commit-shaped field.
Changes over 50 files, 200 text hunks, or 256 KiB of UTF-8 patch data are
rejected as a whole. Invalid UTF-8, NUL-containing, and binary files are listed
as skipped; download failures and the existing 1 MiB/20,000-line source limits
stop the analysis.

GitHub Pages remains a static deployment. If `/api/health` is unavailable,
the analysis action is simply hidden and the normal diff viewer is unchanged.

Submitting a GitHub URL updates the browser to a static-host-friendly share
route:

```text
https://{playground-host}/{base}/#/owner/repo/commit/sha
https://{playground-host}/{base}/#/owner/repo/pull/number
https://{playground-host}/{base}/#/owner/repo/pull/number/commits/sha
```

The playground normalizes either GitHub PR commit-detail form to its
`pull/number/commits/sha` hash route.

Opening a commit route restores the same SHA automatically. Opening a pull
request route fetches that PR again, so the same shared URL follows its latest
head. The result page also exposes the full URL in a read-only field with a
one-click copy button. Hash routing keeps shared links working on GitHub Pages
without a server-side rewrite rule.

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
