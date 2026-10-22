# Browser host bindings

Frontend policy, algorithms and interaction state are written in MoonBit. This
package supplies the missing host primitives and small MoonBit conveniences over
Rabbita 0.16.5's public DOM APIs. It does not import the application, rendering or
view packages. Dependency sources and versions remain unchanged.

The remaining JavaScript performs individual host operations:

- DOM focus availability, URL resolution, CSS numeric conversion, textarea
  selection and synthetic mouse events.
- Browser Date parsing, clock access, UTC/Intl formatting and cryptographic UUIDs.
  These retain browser parsing, timezone and locale behavior.
- Session-storage access, with native exceptions translated into checked MoonBit
  errors before the application processes or validates records.
- Fetch, response metadata, stream reads, AbortController and Promise callbacks.
  Request policy, byte budgets, accumulation, encoding, timeout handling and
  response classification belong to the MoonBit GitHub client.

`property`, `set_property` and `event_property` are direct property-access helpers
for DOM fields absent from Rabbita. They do not run scripts or own business state.
`subscribe` adapts native Promise completion to the existing callback contracts;
its rejection handler also receives exceptions from a success callback, like the
previous Promise chains.

Layout and editor state are owned by the rendering coordinator. Optional scalar
snapshots are written to the existing `__moondiffMetrics` sink only when a browser
test installs it. Tests use these snapshots to check idle frames, pending work,
record counts and listener cleanup. Snapshots never retain DOM nodes or callbacks.
Node fixture-file reads and DOM cloning remain test-only host bindings outside
this package. The clone binding lives in `view/html_fixture_wbtest.mbt`.

Migration verification (2026-10-14):

- `moon -C review-web/frontend check --target js --deny-warn` and formatting checks pass.
- `moon -C review-web/frontend test --target js`: 671 passed.
- `npm run test:review-web`: 20 component tests, 8 harness checks and 451 browser regressions passed.
- `npm run test:review-web:stress`: all 7 rendering pressure cases passed.
- `npm run build` and `npm run test:artifacts`: release build and both artifact checks pass; frontend gzip size is 368,381 bytes.

Inline JavaScript in production MoonBit files is confined to this package's host
declarations. Other business packages have no `extern "js"` declarations.
