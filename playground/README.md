# Moondiff playground

The static Rabbita playground accepts these public GitHub URLs:

```text
https://github.com/{owner}/{repo}/commit/{sha}
https://github.com/{owner}/{repo}/pull/{number}
https://github.com/{owner}/{repo}/pull/{number}/files
https://github.com/{owner}/{repo}/pull/{number}/commits
https://github.com/{owner}/{repo}/pull/{number}/changes/{sha}
https://github.com/{owner}/{repo}/pull/{number}/commits/{sha}
```

GitHub may rewrite PR commit-detail URLs between the `changes/{sha}` and
`commits/{sha}` forms; the playground accepts both and treats them equivalently.
The PR commits-list form (`pull/{number}/commits`) is treated like the base PR
URL.
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
switches those files to structural diffing. After reliable top-level alignment,
Lexical compares declaration-owned sections independently and displays every
changed declaration in full, including its documentation, internal blank lines,
and stable lines far from the edits. Unchanged declarations remain omitted.
Whitespace-only lines outside every section—before the first declaration,
between declarations, or after the last declaration—are intentionally omitted;
if they are the only difference, the result is **No structural changes**.
Whole-file lexical results and AST lexical fallbacks still use compact context.
Pure formatting inside a declaration
becomes an explicit no-structural-changes state in AST mode, while pure top-level
reordering shows a compact reordering summary. Reliable top-level matches retain
both source orders: the main view follows the new order, and deleted declarations
appear in a separate old-order group. Parser failures and top-level planning
limits produce one whole-file lexical fragment. When a graph limit, invalid
syntax position, or local computation limit affects only one aligned top-level
declaration, the playground labels that declaration as a partial lexical
fallback and keeps AST diffing the rest of the file. The
default-off **Ignore comments** control applies to MoonBit
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
filtering is not guaranteed. Other valid UTF-8 text files always use a
Patience line diff. Equal-width replacement blocks receive bounded,
position-by-position whitespace-word highlights; unequal replacements and
pure insertions or deletions retain their plain line structure. These files
remain unaffected by either control. Word refinement is capped at 16,384
UTF-16 code units per side of a line and shares fixed per-document allowances
of 1,048,576 attempted code units and 65,536 diff tokens. Reaching a limit only
removes word-level emphasis from later eligible rows; line text, line numbers,
hunks, and unified patches remain unchanged. At the API level, `line_diff`
treats a negative context radius as zero.

Each displayed top-level section owns a fragment-local diff rather than an
implicit whole-file patch. Split and unified layouts render that fragment, then
map its local line numbers back through the section's exact source ranges.
Review comments are consequently anchored by side and absolute source line,
including when matched declarations cross between the old and new orders.
The playground hides `@@ ... @@` hunk headings only for these complete
top-level Lexical sections; section titles, absolute line numbers, and review
comment anchors remain visible. AST sections, Whole documents, fallbacks, and
ordinary text diffs keep their hunk headings.

The selected algorithm and both filter settings survive later change navigation
in the open app but are not written into share URLs; a refresh restores Lexical
mode with both filters off. The first 20 MoonBit diffs open automatically, while
all other files load on demand. LineDiff keeps one shared cache. MoonBit files
cache all eight Lexical/AST × comments/tests combinations independently, so
layout switches reuse the same semantic document and stable fragment hunks.

Each downloaded side is limited to 1 MiB and 20,000 universal-newline lines.
LF (`\n`), CRLF (`\r\n`), and bare CR (`\r`) each terminate one line; empty
input is one line, and a trailing terminator retains the final empty line.
Exactly 20,000 lines are accepted and 20,001 are rejected. Invalid UTF-8,
NUL-containing, binary, and over-limit content keeps its file card and shows
an explanatory message instead of a rendered diff. The browser fetches
anonymous GitHub REST and raw-content endpoints and never accepts, stores, or
sends a personal access token. Anonymous GitHub API rate limits therefore
apply.

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

## Local preview

Build and start the static site on the default `http://127.0.0.1:4173`:

```sh
cd playground
npm run build
npm start
```

Override `HOST` or `PORT` when needed. A development command that builds once
and restarts the static server when its module changes is also available:

```sh
cd playground
npm run dev
```

The preview server only serves files from `playground/dist`; it rejects path
traversal and symbolic links that escape that directory.

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
node --test tests/server.test.mjs
npm run test:e2e
```

On a machine that is missing Chromium system libraries, use
`npx playwright install --with-deps chromium` instead. For an interactive
Playwright session, run `npm run test:e2e:ui`.
