# Browser test synchronization

Browser specs import `test` and `expect` from `../../tests/browser-test.mjs`.
The automatic fixture records requests without intercepting them, attaches
request/timer/render diagnostics on failure, releases gates, waits for in-flight
requests to finish or retire with their document, then removes Page routes and
finally Context routes using `behavior: 'wait'`. Cleanup shares one five-second
real-clock deadline across all pages and handlers, including closed popups.
Callback registration is observed through the public `route`/`unroute` methods
without installing interception rules. This also waits for the tail of callbacks
that caught a route cancellation, or outlived a one-use/removed registration.
Failures preserve request snapshots before closure, spend at most one second on
page diagnostics, then attempt bounded recovery. Ordinary tests keep four
workers and zero retries. `static-cache.spec.mjs` installs no routes, preserving
the browser's real HTTP cache.

## Requests and barriers

Use `createGate('descriptive label')` from `browser-control.mjs`. Both
`release()` and the compatibility alias `resolve()` are idempotent. Gates are
released during teardown even after an assertion fails. Replace local promises
that hold responses with these gates.

`requestsFor(page).checkpoint()` identifies the last request already observed.
Pass it as `after` to `wait({ after, operation, target, generation, phase })` to
avoid accepting an earlier request. `predicate` can match exact arguments or a
previously captured record ID. Generations count requests for the same operation,
URL and arguments. `trackRoute(route)` records fixture response delivery and
only tolerates errors with confirmed request cancellation or page closure.
`metadataFallbackRoute` already uses it, preserving the original request identity
through its protocol proxy.

The request phases have deliberately different meanings:

| Phase | Meaning |
| --- | --- |
| `entered` | Playwright observed the outgoing request. |
| `sent` | The fixture finished fulfilling the route. |
| `response` | The browser received response headers. |
| `received` | The browser finished receiving the body (`requestfinished`). |
| `cancelled` / `failed` | The browser reported a terminal transport failure. |
| `closed` | The page closed before the request reached another terminal phase. |
| `retired` | An observed document commit, Frame detach or page close ended the request's owner. This is cleanup evidence, not a transport result. |

Records carry stable `frameId`, increasing per-Frame `documentId`, and
`ownership` (`document`, `pending-navigation`, or `unknown`). These do not change
the meaning of request `generation`. Navigation requests and redirect chains
belong to a pending navigation until its commit identifies the new document.
Only unfinished requests from the replaced document retire; unknown ownership
continues to block cleanup. Snapshots include current documents and the reason,
time and replacement document for each retirement.

`tests/browser-lifecycle.mjs` isolates the private Playwright Frame `navigated`
event contract. Only a `newDocument` without a navigation error proves a commit.
Hash/history changes, public `framenavigated`, synthetic `pagehide/pageshow` and
failed or aborted navigations do not retire the current document. Existing
popup documents are treated as initial observations, with no inferred history.
Run `npm run test:e2e-config` and the `browser-lifecycle.spec.mjs` compatibility
regressions when upgrading Playwright; incompatible internals must fail clearly.

A cancelled or retired request never proves that the browser received its response. Body
receipt does not prove that the application accepted that response. For late
responses, await the captured request's terminal phase, then assert the current
account, route, version or write permissions. Do not use a handler's boolean
`completed` flag as a substitute for receipt or acceptance.
Chromium can omit terminal events for an intercepted fetch during document
destruction. Retirement only removes that request from cleanup waiting; it does
not fabricate `received`, `cancelled` or `failed`, suppress handler errors, or
count response bytes. Late real events update the same record. Tests asserting
application cancellation must still observe a real `cancelled` event (for
example, dispatch `pagehide` and await cancellation before a deliberate reload).

## Virtual time

Time-related tests call `installClock(page)` **before navigation**. It installs
and pauses Playwright Clock. Every timeout is observed and forwarded to Clock;
no delay value receives special scheduling semantics. Other tests use real time.

- `clock.timer(ms, { after, predicate })` waits for the newest matching pending
  timer to be registered. The record includes its absolute deadline, state and
  application generation/read serials. Filter these when an old timer can still
  exist after a restart.
- `clock.before(timer)` advances to exactly one millisecond before its deadline;
  assert no request/state change there. `clock.fire(timer)` reaches the deadline.
- `clock.frames(n)` advances rendering frames. `clock.until(read, label)` only
  advances time when the instrumented renderer reports pending work, so a slow
  real response cannot consume a retry budget. Boundaries must account for the
  rendering frames already consumed.
- A `clock.until` callback must return promptly so the helper can advance pending
  renders. Return `false` when an element has not mounted yet. Use immediate DOM
  reads or `locator.isVisible()`; methods such as `locator.isEnabled()` and
  assertions can wait for a missing element and block the frames that mount it.
- `clock.jump(ms)` models a long suspension; `clock.advance(ms)` runs all timers
  in a short interval. After cancellation, drive the old deadline and rendering
  opportunities, then check that request counts did not increase.

All facility deadlines use Node's real clock. Waiting for a real response or
`requestfinished` never advances browser time. Deliberate server/fixture latency
uses Node timers and is distinct from synchronization.

## Business state, DOM commits and native scrolling

`instrumentRenderProbe` is injected before minification into temporary bundles,
including fixtures that serve their own static assets. It publishes detached
snapshots of cache keys, navigation and identity generations, scheduler state,
and accepted Viewed/CI state. No mutable application objects are exposed.
Release artifact checks reject these test hooks.

`waitForPrefetch(page, { owner, repo, number, sources })` waits for that PR's
snapshot and exact source arguments to be cached, then waits for DOM commits.
Use request increments for that target to check reuse. A strict whole-round
budget assertion instead uses `waitForPrefetchRound` before inspecting totals.
When refreshing an already completed round, capture its `round` first and pass
`{ afterRound }` so the wait cannot match the previous round.

`waitForState(page, predicate, label)` waits for a business condition, then calls
`settleRegions`. `settleRegions` requires the temporary probe and waits for two
consecutive idle animation frames, including central/regional paints and layout
callbacks. It supports a controlled clock. Render idleness alone says nothing
about an outstanding network request or whether its result has been accepted.
Capture identity/application generations before changing accounts and wait for
the new generations and completed business state with `waitForState`. Then assert
the account and controls in the settled DOM. Confirm business acceptance and DOM
rendering separately instead of combining auto-waiting locators in a clock poll.

For trusted wheel/key interactions use
`scrollAndWait(page, () => page.keyboard.press('PageDown'))`. It registers
`scroll` and `scrollend` listeners **before** the action, requires scrolling to
occur and end, and checks three consecutive frames at the same position. Keep
the exact final scroll position, focus and selection assertions after it.

Do not use `waitForTimeout` as a synchronization condition. Confirm the relevant
business pause/cancellation state and drive its timers/rendering opportunities
before asserting that no later requests occur.

## Verification and performance reports

From `review-web`:

```sh
npm run test:browser-controls
npm run test:e2e -- browser-control.spec.mjs
npm run test:e2e -- --workers=4 --repeat-each=10 --grep 'business probe reports accepted generations|Viewed confirmation timers stop after account change'
MOONDIFF_TEST_CPU_RATE=6 npm run test:e2e -- --workers=4 --repeat-each=10 --grep 'business probe reports accepted generations|Viewed confirmation timers stop after account change'
npm run test:e2e -- --workers=4 --repeat-each=10 --grep 'stable (hover|keyboard focus)|wheel cancels history restoration during queued|PR authenticated limit drains|late restored validation cannot'
MOONDIFF_TEST_CPU_RATE=6 npm run test:e2e -- --workers=4 --repeat-each=10 --grep 'stable (hover|keyboard focus)|wheel cancels history restoration during queued|PR authenticated limit drains|late restored validation cannot'
npm run test:e2e
npm run test:e2e:stress
```

`writePerformanceReport` writes an actual JSON file under `testInfo.outputPath`
and attaches that file. Reports include raw samples, sample counts, p50, p95,
fixture parameters and CPU rates. Two-mode comparisons use two AB/BA rounds,
with one warm-up and two recorded samples per mode per round. Timings are
reports only; functionality, completed operations, request budgets, concurrency,
render isolation and resource cleanup remain blocking assertions. CI uploads
results for successful runs as well as failures. When running suites concurrently,
use separate `PORT` and `--output` values.

Response byte reports use the serialized fixture payload and include it only
after the recorder confirms browser body receipt. They do not retrieve old
response bodies through CDP after navigation between benchmark scenarios.

Stress traces omit per-action DOM/network snapshots, whose serialization can
dominate large fixtures at 6x CPU. They retain action traces, screenshots and
source references; the shared fixture records requests and render state in JSON.
Ordinary browser tests retain their full failure traces.
