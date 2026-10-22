# Independent review app regions

The application reducer owns the only business model. Rendering inputs are
read-only projections; region state contains only a render revision and lifecycle
information. Rabbita 0.16.5 is used through its public API, without dependency edits.

PR interval links use the application’s shared target validation. Plain clicks
and Enter carry the page generation and resolve the accepted selection in the
reducer; deferred navigation retains the destination computed at activation.
The coordinator keeps only a `(generation, href?)` projection and synchronizes
the mounted selector link at every model update, after regional paints, and in
capture listeners before native link interactions. Valid modified clicks,
middle clicks, context menus and drags retain browser defaults. Retired or
invalid links lose their `href`, and selector unmounts remove the listeners.
`range.spec.mjs` freezes selector paints to exercise these paths, real new tabs,
history restoration, old DOM callbacks and comment submission outcomes.

PR overviews continuously prefetch all recognized MoonBit source sides after the
file list loads for signed-in readers. Anonymous readers load only initially
expanded files and files opened manually or while scrolling. The application admits
at most four sides through the existing shared source transport, prioritizing the
initially expanded files and explicit demand. Changed `pkg.generated.mbti` files
lead the list, including those matching a rename's previous path. Anonymous
visits expand at most twenty files in total. Signed-in visits expand every
interface; other MoonBit files use the remaining slots in the twenty-file budget. Later sides are validated and retained in the current `ChangeView` without
computing diffs or highlights. The shared cache remains limited to 32 MiB and
historical parsed pages to 4 MiB.
An individual failure does not interrupt the remaining PR. A rate limit pauses
both source schedulers, including manual demand, with no source retry button or
timer. In-flight successes remain readable. Anonymous sign-in resumes missing
sources after PR snapshot validation; authenticated limits ask for a later page
refresh. Changing auth controls and removing the limit notice preserve the loaded
file's reading anchor after regional layout commits. Hidden pages and identity checks pause new automatic reads. Generation
changes retire the old requests and reject their results.

The coordinator owns one IntersectionObserver for eligible collapsed PR cards,
with a bottom margin equal to the current viewport height. After scrolling, the
shared layout batch remeasures current positions and expands at most two cards in
the viewport or the next screen. It waits for all regional commits and repeats
after geometry changes. Viewed files and manual collapse preferences are excluded;
those preferences are saved with the page version. Navigation, history restoration
and comment editing pause automatic expansion. Automatic actions preserve focus and the
reading anchor, and carry the page generation and file path instead of toggling
state. After navigation, fresh wheel, touch, pointer or scrolling-key input
re-enables expansion, so delayed native history/focus scroll events cannot move
the restored page. PR history restoration also waits for snapshot checking to settle,
resolves shifted focus indices by stable labels and temporarily suppresses native
scroll anchoring across status-notice removal. The original anchoring style is
restored on new scrolling input or disposal. User input cancels pending automatic
history restoration through a shared token bound to the generation and history
entry. Both the queued render action and its focus/scroll command recheck this
token. Private scheduler bridge clicks do not count as user interaction.
Explicit navigation supersedes a pending history position and remains available
after cancellation. Commits and intervals use the same interface ordering and
default expansions through the shared source queue.

`pull-progressive.spec.mjs` exercises forty-file PRs, source priority/coalescing,
visibility, failures, local expansion with source networking blocked, navigation,
history, editor focus and observer cleanup. `pull_sources_wbtest.mbt` covers the
application scheduler and resource validation. The large-PR case in
`rendering.stress.mjs` downloads over 32 MiB, then opens both evicted shared-cache
entries and distant files from current-page sources. Its
`pull-prefetch-performance.json` attachment records first-screen and scroll
expansion timings, long tasks, source concurrency and cumulative JS heap samples.

One local Chromium run of the 60-file fixture (38.15 MiB of source, with roughly
0.5 MiB comment lines in each later side) measured 1.03 s to the first twenty
files and 1.82 s from scrolling until the automatic expansion batches settled.
It recorded 18 long tasks, the longest at 784 ms. JS heap samples were 45.6 MiB
at the first screen, 923.6 MiB after all source arrived, 844.8 MiB after local
expansion, and 10.2 MiB after leaving and collecting garbage. The samples before
GC include transient decoding and validation allocations. All retired file-state
WeakRefs were collected, and opening retained sources made no new source request
or shared-cache lookup despite 72 cache evictions. These are single-run pressure
measurements, not timing guarantees: retaining a complete large PR and computing
its diffs synchronously still carries substantial memory and main-thread costs.

Verification for PR prefetch and progressive expansion:

- Frontend JS tests: 765 passed. `moon test --target all`: wasm 342, wasm-gc 319,
  JS 765 and native 342 passed. Formatting, interface generation and the JS
  warning-denying check completed.
- The eight new browser cases passed in the full suite; the navigation/history
  case also passed ten consecutive repeats, including delayed scroll notifications.
- The full browser run passed 532 cases. The existing comment-menu layout case
  and unconfirmed Viewed/Load latest case failed during that run; each passed
  three isolated single-worker repeats afterwards. The separate pressure suite
  was running concurrently with that full run. No test timeouts were increased.
- All nine pressure cases passed against the final implementation. The large-PR
  case also independently verified cache evictions, local expansion, observer
  disposal and collection of every retired file-state WeakRef.

| Region | Invalidating inputs |
| --- | --- |
| Shell | generation, phase, file identities, drawer, width, layout signature |
| Toolbar | URL, auth on landing, file count, drawer, display options |
| File tree | path/status metadata, tree controls, Viewed markers |
| Navigation | generation, whether any expanded unviewed file has changes |
| Viewed summary | auth, Viewed aggregate, snapshot staleness |
| Overall discussion | overall comments, auth/refresh notices, permission summary, its draft |
| File and fallback discussions | that FileState identity, display options, its Viewed state, its comment group and draft, permission summary |

No input compares source text, a diff document, or the entire Model. File identity
is generation plus path; a separate mount instance rejects callbacks from retired
roots. A local update may scan file metadata, but must not inspect unrelated diff
rows or build/traverse unrelated VDOM.

Region state and its lifetime subscription are created inside the central assoc
scope. Each region has its own Rabbita root and scheduler. A forwarding emitter
always sends business events and async results to the central scheduler. The
central root only renders empty hosts; mounting occurs after those hosts commit.
Disposal invalidates callbacks, releases waiting UI actions and observers, removes
the host, and drops derived inputs/caches. Pending durable Viewed operations retain
their existing reducer ownership rules.

After-commit actions name a target region, a wait scope (`Region`, `PageLayout`,
or cancellable `HistoryLayout`),
and a navigation policy. Ordinary focus and Viewed persistence use `Region`;
Viewed operations still complete their ownership cleanup across navigation.
`OpenFile` and `NavigateChange` use `PageLayout`. Opening a file scrolls and, when
leaving the drawer, transfers focus in one cancellable action.

The coordinator assigns a monotonically increasing navigation sequence and
replaces its single pending navigation as soon as the reducer accepts a valid
request, before the central projection or any region commits. Navigation waits
for the latest central revision and every scheduled region update in the current
generation. Updates scheduled during the wait join it; network requests that have
not returned do not. The coordinator tracks only commit metadata and never
invalidates an unrelated file to satisfy this wait.

A region ticket contains generation, mount instance, and revision. Only a current
ticket clears its pending entry; older callbacks cannot acknowledge a newer
revision. Central and regional completion is acknowledged after the shared layout
batch has measured dirty regions and written sticky offsets. Committing a region
explicitly marks its geometry dirty instead of relying on ResizeObserver delivery
order. Immediately before execution, navigation rechecks its sequence, generation,
target mount, and the current pending updates. A route change or target unmount
cancels it, including its focus transfer.

Authentication, reactivation, manual comment refresh and rate-limit recovery have
a separate reading lifetime. The application passes a `ReadingRecovery` token
through `Transition`; it contains
only an ID, generation, history entry, cancellation flag and request ownership.
Status and device requests each register a request ID and auth revision in the
current recovery. Their optional completion notification runs once on success,
failure or cancellation, after any business result has registered follow-up work.
Cancellation emits no business failure. A newer status query or valid device
response aborts and completes older status requests immediately; cleanup from an
old recovery, revision or request cannot retire newer work. Viewed and merge
reads use epoch/serial, and comments use refresh ID, including manual refresh.
Queued comment refreshes are registered when their
commands are constructed, before dispatch. Viewed storage and its remote read,
and comment metadata, list and validation, remain continuous work. Completion,
failure and supersession release that work. Source prefetch and subsequent CI
polls do not extend this lifetime; a first Pending CI result completes its read.

Before any affected paint, the coordinator locates the loaded file at the reading
edge and captures a visible source row below the sticky file and section headers.
Split and Unified source rows expose `data-reading-row` using their existing
stable row keys. Only visible tables in this file are queried; binary search over
their ordered row positions finds the first unobscured row without measuring all
rows or visiting other files' rows. If no source row is visible, the file card is
the fallback anchor. The record holds the original node, viewport top and file
mount instance. Later updates merge into it without sampling a new baseline,
including when inline comments above the row are inserted, removed or resized.
Each completed layout
batch compensates `currentTop - savedTop` immediately, within the document's
scroll range. This never takes the navigation slot, transfers focus, or sets
`navigation_locked`. A valid navigation or history restoration wins immediately.
The record is retired after its requests finish and two animation frames see no
new central, regional or measured layout work. While waiting for the network,
there is no animation loop and native scroll anchoring remains available.
When a sign-in modal intercepts hit testing, capture uses the loaded card's
geometry at the same reading edge behind the backdrop, then uses the same source
row selection. The modal retains control
of its inert background's scroll position; compensation resumes if authentication
closes it automatically, while interaction in the dialog still cancels recovery.

History and reading share native anchoring ownership. The first owner saves the
inline `overflow-anchor` value and priority, and the last owner restores both.
Reading holds ownership before paint until the batch is stable, even when every
file is expanded. Capturing wheel, touch, pointer, click, keyboard or input intent
synchronously cancels reading; the private non-bubbling scheduler click is
excluded. Cancellation releases listeners, the scheduled frame and DOM references.
Every callback checks token ID, cancellation/retirement, generation and mount instance;
disconnected or collapsed anchors are discarded without selecting another row.
An unscrolled page, unloaded code or missing anchor finishes synchronously without
marking recovery blocked. Navigation, invalid mounts and user intent still cancel.
ID-tagged cleanup clears the
application token; retirement already prevents recapture before that message is
processed. Late responses cannot restart a cancelled round, while a new
explicit sign-in or manual refresh can create a new one. File-internal folding
and Viewed's normal automatic folding are unchanged.

`reading-recovery.spec.mjs` gates auth/metadata responses and regional paints to
test overlapping layouts, delayed Viewed/comments/merge batches, synchronous
input cancellation, route and mount replacement, native styles, and completion
with source requests and Pending CI outstanding. It also covers overlapping
identity checks in both response orders, an unresponsive superseded request,
latest-request failure, and device authorization superseding a status query.
The inline-comment matrix covers insertion, growth and deletion in Token/Tree
and Split/Unified, through reactivation, manual refresh and modal sign-in.
Probes retain only scalar
coordinates, counters and lifetime flags. Assertions preserve the same DOM line
within 2px, focus, and unrelated file render counts. Before the fix, the delayed
Viewed case moved by 61.28px and both regional release orders failed; the same
three cases also failed on parent commit `71894f8` (before the directory rename).
The additional regressions reproduced recovery remaining active after overlapping
identity requests, page-top capture preventing later recovery (90.39px drift when
a delayed rate limit appeared), and a 142px reading line shift after an inline
comment was inserted above it. The regressions require the same connected source
line to remain within 2px and `active`, `metadata`, `listening` to be false and
`frame` to be zero after completion.

The same shared layout batch establishes browser rendering isolation for file
cards. It first measures each card's real content-box height, writes that value as
its intrinsic block-size fallback, and only then enables `content-visibility`.
When a file region commits, its containment marker is removed before the next
read batch and restored after the new exact height is written. This preserves
scroll geometry and sticky navigation while allowing unrelated page-height
changes, such as opening CI details, to skip offscreen diff subtrees. The region
host remains `display: contents`; containment belongs to the file card so region
mounting and grid layout keep their existing box semantics.

Editor interaction is captured from the registered draft node at the event
boundary and restored in the same region commit, before another browser event can
modify the replacement editor. No global editor query is needed.

The coordinator owns typed MoonBit layout and editor records. Layout measurements,
read/write batching, callback queues and interaction restoration no longer live
in JavaScript globals. The application owns the navigation landing snapshot and
clears it on geometry changes, scrolling away or a new generation. File-tree
pointer sessions are MoonBit records released when the tree region unloads.
Missing host primitives are isolated in `../browser`; all existing DOM operations
use Rabbita's public bindings.

Browser tests observe scalar snapshots in `__moondiffMetrics.layout` (`frame`,
`dirty`, `callbacks`, `records`) and `__moondiffMetrics.editor` (`records`, `active`,
`listening`). These are diagnostic copies, not the live state. They preserve the
idle and cleanup assertions without exposing or retaining nodes and closures.

Completed commit callbacks clear their captured payloads, and central messages
use envelopes emptied on receipt. This avoids retaining retired source snapshots
or child roots through consumed scheduler queue slots, without accessing runtime
internals. Forwarded DOM commands remain repeatable.

Verification lives in `region_wbtest.mbt`, `commit_wbtest.mbt`, the
view/comment/application regional input tests, `../../tests/rendering.spec.mjs`,
and `../../tests/navigation-commit.spec.mjs`. The browser suite covers
Token/Tree and Split/Unified, source races, same-frame operations, Viewed storage
failure after the real checkbox commits, editor migration, and repeated route
entry/exit. It checks active stores/subscriptions/observers and uses WeakRefs plus
Chromium GC to verify that retired file snapshots and DOM nodes are collectable.
Navigation cases compare final positions against measured sticky offsets and
record scroll/focus effects. The regional frame barrier can release selected
regions in either order, covering a collapse above the target, replacement by an
already expanded target, two targets awaiting updates, interleaved file/change
navigation, later revisions, route cancellation, and outstanding source requests.

Counters are opt-in through `__moondiffMetrics`. VDOM traversal and actual runtime
store counts are instrumented only in the temporary test bundle by
`../../../tests/render-probe.mjs`; dependency sources and production bundles are
not modified. The parser reproduction is pinned as an offline fixture, alongside
synthetic cases with 4 × 12 and 12 × 80 file/declaration sizes.

Run `npm run test:review-web` from the repository root for functional browser
regressions. Run `npm run test:review-web:stress` (or `npm run test:e2e:stress` from
`review-web`) for the seven rendering pressure cases in `rendering.stress.mjs`.
The stress configuration reuses the browser/server setup and uses one worker;
the default E2E configuration selects only `*.spec.mjs` and excludes stress cases.
Performance attachments record four alternating file toggles at normal and 6×
CPU speed. Their render counts, rather than timing thresholds, are the regression
contract. The CI disclosure case separately sends trusted pointer input through
CDP and measures through the second animation frame. On the synthetic-large page
at 6× CPU it requires the contained median to stay below 80% of a same-page
`content-visibility: visible` baseline and attaches the raw samples.
To compare release bundles, build the frontend in both workspaces, then run:

```sh
node review-web/tests/benchmark-rendering.mjs /path/to/baseline/workspace results.json
```

A local Chromium run against pre-change commit `eed1cc8` used identical fixtures,
1280 × 720 viewports and uninstrumented release bundles. Median input-to-DOM-commit
time (not paint time) and the longest observed main-thread task, in milliseconds:

| Fixture | CPU | Commit before → after | Longest task before → after |
| --- | --- | --- | --- |
| parser: 21 files, 3,973 rows | 1× | 156 → 12 | 201 → none ≥ 50 ms |
| parser: 21 files, 3,973 rows | 6× | 828 → 9 | 1,115 → 291 |
| synthetic: 4 files, 144 rows | 1× | 28 → 16 | none ≥ 50 ms → none ≥ 50 ms |
| synthetic: 4 files, 144 rows | 6× | 105 → 18 | 181 → 83 |
| synthetic: 12 files, 3,520 rows | 1× | 313 → 7 | 396 → 55 |
| synthetic: 12 files, 3,520 rows | 6× | 1,985 → 10 | 2,471 → 436 |

These are comparisons, not timing guarantees. Browser style/layout work remains;
the deterministic checks ensure unrelated files perform no additional view,
patch, review-row, visible-projection, diff, highlight or VDOM work.

Navigation commit verification:

- `moon -C review-web/frontend test --target js`: 577 passed.
- `navigation-commit.spec.mjs`: all 27 browser cases passed, including Token/Tree
  and Split/Unified. The existing rendering and section-navigation suites were
  also exercised in the targeted run.
- `moon test --target all`: wasm 326, wasm-gc 306, JS 577, native 326 passed.
- `moon -C review-web/frontend check --target js --deny-warn`, `moon fmt --check`,
  and `moon info --target all` completed. Generated interface changes are confined
  to the internal application's commit scope.
- Before separating stress cases, the full browser regression
  (`npm --prefix review-web run test:e2e -- --reporter=dot`,
  four workers): 322 passed; the synthetic-large, 6× CPU rendering test reached its
  existing 90-second timeout while reading render counters. It passed both the
  preceding isolated run and the final single-worker rerun (1.2 minutes). The
  initial targeted run also timed out on Tree/Unified draft isolation; that case
  passed both its isolated rerun and the full run.

No test timeout values were changed. Isolate the pressure case with:

```sh
npm --prefix review-web run test:e2e:stress -- --grep 'synthetic-large, 6x CPU'
```

After separation, CLI discovery selected 317 regular tests and six stress tests
with no overlap. All eight regular rendering tests and all six stress tests
passed through their respective npm commands. The `check` workflow runs stress
tests in their own job and uploads their performance attachments and failure
artifacts.
