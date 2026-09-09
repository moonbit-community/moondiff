# Comment invariants

`Session::new` creates an empty session. Its fields are read-only outside this
package, and editor state, context, receipts and mutable collections are private.
`update(session, event)` is the only mutation entry point. It never mutates the
previous session and has no browser, RPC or Rabbita dependency. Collection reads
(`comments`, `refresh`, `deleted`) return detached copies.

| Invariant | Owner |
| --- | --- |
| Exactly one draft, including an empty draft | `editor.mbt`, `permissions.mbt`, `comment_submission.mbt` |
| Editing and submitting cannot coexist; posted text is frozen | Private `EditorState` and `Operation` in `editor.mbt` |
| Reopening the same path/side/line preserves identity | `DraftId`, `same_draft_target`; file index is only a display hint |
| Failed writes retain the draft and can retry | `update.mbt`, `model_updates.mbt` |
| Responses must match generation, operation number and phase | `owns_response`, `owns_submission`, refresh/deletion transitions |
| A duplicate or old response has no state change or effects | Stage guards consume successful and failed responses once |
| Writes invalidate an already pending list immediately | `merge_cache` in `cache.mbt`, during the write response transition |
| Deleted comments cannot reappear from an old or eventual-consistency list | Session deletion tombstones in `merge_cache` |
| Issue/commit receipts survive until observed, without duplicate IDs | Receipt overlay in `merge_cache` |
| PR review writes display only their receipt before verification | `PublishedReview`, followed by a fresh metadata/list/metadata cycle |
| Verified comments and line drafts belong to a snapshot | `Snapshot`, `verified_snapshot`, `DraftData.snapshot`, `target_permission` |
| Only live root comments can receive replies | `valid_reply_target`; `ReviewThread.id` always uses the original root ID |
| Buttons and transitions use the same operation rules | `permission(session, action)` returns `Allowed` or `Denied(reason)` |

## Application boundary

`application/auth_types.mbt` and the auth reducer own device sign-in, session state
and GitHub user-ID identity. Comments receive only comment permission and the resolved
login. The application converts the route, generation and loaded diff snapshot
into `ContextChanged`, interprets effects in `comment_effects.mbt`, and converts
transport errors before delivering response events. RPC operations and JSON
arguments live in `comment_requests`; the external GitHub protocol is unchanged.

Route changes, confirmed sign-out and account switches use the application
load/reset path with a new generation. Same-account credential recovery retains
an editing draft, including its ID and snapshot; a draft bound to a different
snapshot cannot be posted. Do not add a second reset path or directly construct
comment state in application code. Integration fixtures also establish state by
sending events.

For a new asynchronous operation, allocate a fresh number when starting the
request, capture generation and number in its response constructor, and consume
that response only in its expected phase. Put write acknowledgements in
`merge_cache`; never separately update the list and schedule its invalidation.

## Projection and browser interaction

`view/review_projection.mbt` collects visible source rows before HTML rendering.
It maps each file/side/line to the first expanded, visible fragment and source-row
ordinal; hunk-heading visibility does not change that ordinal. Both comment
cards and editors read this projection. When declarations share a line, folding
the first moves its discussions and draft to the next expanded declaration.
If none is visible, they fall back to the file's discussion area; a missing path
falls back to the overview. Each discussion and the active draft have exactly one
placement. Rendering does not claim placements or mutate a `shown` flag.

`change/FileState.collapsed_sections` owns declaration folding for the current
snapshot. Section keys use old/new ranges plus a duplicate ordinal counted before
filtering. The controlled `details.open` and projection use the same state.
Summary clicks (including native Enter/Space activation) prevent the browser's
default toggle and dispatch `LoadMsg.ToggleSection`; the reducer checks generation
and file index and updates the file without mutating earlier states. Layout,
algorithm and filter changes, background refresh and file reopening retain these
choices. Loading a new snapshot starts with all declarations expanded. Folding
does not change draft identity or body, and is not persisted in the URL or storage.

Comment lists use generation plus typed comment IDs. Threads retain the original
root ID after root deletion. Draft keys use generation plus a separate draft
sequence. Source rows, semantic sections and file containers also have stable
keys, so inserting replies or other cards cannot replace an active editor.

`application/editor_lifecycle.mbt` is the only browser interaction adapter. It
captures selection direction, scroll and focus before an application update and
restores selection after a remount, keyed by `DraftId`. It focuses only a new
draft or an editor focused immediately before the update. Finished draft records
are removed; nothing is persisted to browser storage. Ordinary refreshes must
retain the actual node, including during composition, rather than relying on
selection restoration to mask a replacement.

## Regression checks

- `session_wbtest.mbt`: cache aliasing, immutable previous states, deletion
  retries, duplicate/old responses, receipt merging, draft and orphaned-thread IDs.
- Application tests: deterministic cross-flow refresh, submit, delete, auth,
  cancellation and snapshot sequences, constructed through domain events;
  `section_collapse_wbtest.mbt` covers immutable folding, stale events and snapshot
  lifetime.
- `view/review_projection_wbtest.mbt`: first-expanded occurrence placement for
  matched/inserted/deleted declarations, rendering in a different order,
  Split/Unified and hidden hunk headings.
- `playground/frontend/tests/review.spec.mjs`: Token/Tree, Split/Unified, filters, collapsed
  and missing files; node identity, forward/backward selections, subsequent
  typing, synthetic composition events, remount focus and interaction cleanup;
  same-line folding also checks unique placement, scroll, mouse/keyboard
  activation and snapshot reset. Layout measurements wait for the target table's
  layout class and poll dimensions before screenshots.

Run `moon test --target js` from `playground/frontend`, the playground browser suite and Wasm API integration tests. Run `moon fmt` and `moon info --target
js` when changing internal interfaces. CI explicitly checks all internal packages.
