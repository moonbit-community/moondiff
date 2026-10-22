# Snapshot loading and prefetch

Auth status and device commands accept an optional `finished` notification. It is
queued once after the business result, including on failure; cancellation queues
only completion. Recovery bookkeeping must use this notification rather than
counting business results. Commands without a completion hook retain multiple
result delivery, such as a cached snapshot followed by its validation result.
Starting a newer identity check or accepting a valid
device response immediately aborts and settles superseded status requests, even
if their network responses never arrive. Late responses cannot restore old auth
or CSRF state.

Snapshots and immutable source payloads share a 32 MiB session-memory LRU.
Metadata has a separate key, so refreshing metadata cannot replace a complete
snapshot. Complete snapshots have no hard expiry. Thirty seconds is the minimum
background revalidation interval; an absent update hint means unknown, and a
changed known hint requests revalidation without deleting readable content.
Every actual PR visit independently confirms metadata before enabling writes.

The application also retains the two most recent non-current `ChangeView` pages,
including source, diff and highlight results, scoped to account, route and exact
version. Pages above 4 MiB of source fall back to lightweight restoration. Drafts
retain lightweight metadata for their original version even after a parsed page
is evicted. No DOM, editor, renderer or request object is retained. Restoration
resumes missing source reads, preserves folding and position, and shows cached
content while metadata confirmation runs.

Same-version confirmation refreshes title, URL and statistics without replacing
file caches or original draft anchors. A changed version prepares its snapshot
and first target file while the previous page remains usable. Immediately before
installation, the application checks again for drafts, comment writes, Viewed
writes, merging and identity checks. A blocked replacement keeps the previous
version and offers retry after the draft or write is finished. Validation or
source-preparation errors also preserve readable content and disable writes.

`snapshot_loader.mbt` uses `PullSnapshotGet` for a signed-in cold load without a
reusable task or cache. The shared protocol owns `ApiPullSnapshot` and
`ApiPullSnapshotResult`: `Complete(snapshot)` or `MetadataOnly(metadata)`.
The backend aggregates at most 300 files and an 8 MiB encoded response. Larger
results use the existing frontend pagination, with the existing interval selector
above GitHub's 3,000-file limit. Anonymous reads retain direct public GitHub
transport.

The aggregate and foreground fallback overlap the fixed-SHA comparison with the
sequential file-page chain, using at most two upstream reads. An independent
metadata read starts only after both complete. Version drift rebuilds at most
once per loader. The backend's process-wide 64 MiB LRU isolates entries by session
and auth epoch; even a cache hit reads fresh metadata before returning a version.
No SQLite changes are needed; deploy frontend and backend together.

`shared_reads.mbt` shares in-flight reads by resource, stage and session epoch.
Validation uses unique keys in both authenticated and public transports.
Foreground visits attach and promote before releasing homepage subscriptions,
including starting a pending file chain alongside an in-flight comparison.
Task IDs and session epochs own background results; route generations own page
results. Fixed-SHA content keys include the actual repository and exact path.
Source concurrency is four, prioritizing changed `pkg.generated.mbti` files,
the first displayed file, replacement targets and explicitly selected files over
queued default expansions. Interfaces lead the diff list in their original order,
including renames matching either path. Anonymous initial expansion shares a
twenty-file budget between interfaces and other MoonBit files, requesting at most
forty source sides. Confirmed signed-in visits expand every interface; other
MoonBit files use the remaining slots. Restored and manually changed folding is
preserved when signing in.

Rate limits pause both source schedulers and settle queued reads as paused,
without timers or a rate-limit retry button. In-flight successes remain readable.
Anonymous visitors are offered the existing GitHub sign-in flow; successful
sign-in resumes missing sources after PR version validation (or immediately for
fixed revisions). A changed PR uses the guarded snapshot replacement flow.
Authenticated limits ask the visitor to refresh later. Scroll, file selection,
and visibility changes cannot bypass a pause. Rate-limit results retain their
dispatch identity so late anonymous responses cannot pause signed-in loading.

After the homepage commits, a 250 ms timer selects at most five distinct PRs from
the current tab. At most two get a complete snapshot and first-file source pair;
the rest get metadata only. Snapshots of up to 300 files include PR #123-sized
changes. Each completed snapshot immediately warms its source pair before the
next candidate, choosing the first changed interface when present and honoring
merge-base, fork and renamed paths. A stable hover or keyboard focus of 100 ms
moves an eligible candidate forward within the same budget. Metadata acquired
within thirty seconds can start pinned compare/files
directly; the final independent PR validation still runs.

Background upstream concurrency is one. Only a visible, authenticated homepage
with a user ID starts prefetch. Leaving home or hiding the page cancels remaining
background subscriptions; completed cache data and promoted foreground reads
survive. Resuming waits for commit and the 250 ms delay again. Rate limits stop
the round; errors remain suppressed until candidates or list revision change.
Sign-out, reauthorization, account changes and authentication invalidation clear
private caches, saved pages, drafts and tasks according to existing identity rules.
Identity checking pauses private cache adoption and writes.

Diagnostics use an optional `globalThis.__moondiffMetrics` sink:

- `timings.click_to_diff`, `click_to_diff_cold`, `click_to_diff_prefetch` and
  `back_restore` contain samples and P50/P95 in milliseconds.
- `prefetch` reports payload bytes, visits, hits and hit rate.
- `counters` reports request/response bytes, snapshot/metadata/source hits,
  `page_cache_hits`, joins, evictions and promoted tasks.

`prefetch.spec.mjs` reports navigation metrics. `responsiveness.spec.mjs` holds
metadata and new-version source responses to verify restoration and replacement.
`responsiveness.stress.mjs` reports cold, five-minute repeat and history P50/P95,
requests, response bytes, hit rates and computation counts over eight rounds.
It models 25 ms browser round-trip plus 25 ms per upstream stage. Set
`MOONDIFF_BASELINE_JS` to a release frontend bundle from a separate baseline
checkout to interleave both builds. These are reproducible fixture measurements,
not production network estimates.

```sh
moon -C review-web/frontend test --target js
npm run test:review-web
npm run test:review-web:stress -- responsiveness.stress.mjs
npm run test:server
```
