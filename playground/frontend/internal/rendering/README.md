# Independent playground regions

The application reducer owns the only business model. Rendering inputs are
read-only projections; region state contains only a render revision and lifecycle
information. Rabbita 0.14.2 is used through its public API, without dependency edits.

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

After-commit actions name a target region, a wait scope (`Region` or `PageLayout`),
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

Editor interaction is captured from the registered draft node at the event
boundary and restored in the same region commit, before another browser event can
modify the replacement editor. No global editor query is needed.

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

Run `npm run test:playground` from the repository root for functional browser
regressions. Run `npm run test:playground:stress` (or `npm run test:e2e:stress` from
`playground`) for the six rendering pressure cases in `rendering.stress.mjs`.
The stress configuration reuses the browser/server setup and uses one worker;
the default E2E configuration selects only `*.spec.mjs` and excludes stress cases.
Performance attachments record four alternating file toggles at normal and 6×
CPU speed. Counts, rather than timing thresholds, are the regression contract.
To compare release bundles, build the frontend in both workspaces, then run:

```sh
node playground/tests/benchmark-rendering.mjs /path/to/baseline/workspace results.json
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

- `moon -C playground/frontend test --target js`: 577 passed.
- `navigation-commit.spec.mjs`: all 27 browser cases passed, including Token/Tree
  and Split/Unified. The existing rendering and section-navigation suites were
  also exercised in the targeted run.
- `moon test --target all`: wasm 326, wasm-gc 306, JS 577, native 326 passed.
- `moon -C playground/frontend check --target js --deny-warn`, `moon fmt --check`,
  and `moon info --target all` completed. Generated interface changes are confined
  to the internal application's commit scope.
- Before separating stress cases, the full browser regression
  (`npm --prefix playground run test:e2e -- --reporter=dot`,
  four workers): 322 passed; the synthetic-large, 6× CPU rendering test reached its
  existing 90-second timeout while reading render counters. It passed both the
  preceding isolated run and the final single-worker rerun (1.2 minutes). The
  initial targeted run also timed out on Tree/Unified draft isolation; that case
  passed both its isolated rerun and the full run.

No test timeout values were changed. Isolate the pressure case with:

```sh
npm --prefix playground run test:e2e:stress -- --grep 'synthetic-large, 6x CPU'
```

After separation, CLI discovery selected 317 regular tests and six stress tests
with no overlap. All eight regular rendering tests and all six stress tests
passed through their respective npm commands. The `check` workflow runs stress
tests in their own job and uploads their performance attachments and failure
artifacts.
