# TODO

## High Priority

- [ ] Refactor playground rendering to update individual file cards independently.
  - Affected areas: `playground/frontend/main/main.mbt`,
    `playground/frontend/internal/application/`,
    `playground/frontend/internal/view/view.mbt`,
    `playground/frontend/internal/view/review_projection.mbt`,
    `playground/frontend/internal/view/inline_discussions.mbt`, and
    `playground/frontend/tests/`.
  - Reproduction: load [parser PR #183, commit 836b5e03](https://github.com/moonbitlang/parser/pull/183/changes/836b5e037954fee5e8b233aca8e3587621842875)
    in Token mode, keep Ignore tests enabled, then collapse and expand
    `test/manual_test/parser_sync_regression_test.mbt` after loading finishes.
    The user reports a temporary freeze in Edge. A Chromium fixture using the
    same commit and current release bundle renders 3,973 diff rows and about
    38,000 DOM elements; expanding the ignored file reconstructs 43 fragments
    across 11 unrelated files, despite making zero diff-calculation calls.
    The measured response is about 200 ms, or 1.2 seconds with 6x CPU throttling.
  - [ ] Define update boundaries for the page shell, toolbar, file tree,
    aggregate review controls, and individual file cards. Record which state
    changes affect each boundary before changing state ownership.
  - [ ] Replace the single whole-model `app_view` subscription with independent
    reactive views. Keep reducer state authoritative and give each card only
    its file state, relevant display options, and file-specific review state.
    Use the change generation and file path as stable identity; dispose card
    subscriptions on navigation or removal and preserve stale-response guards.
    Avoid copying reducer state into a second mutable store or comparing the
    entire model/diff document to decide whether an unrelated card updates.
  - [ ] Move canonical patch parsing, review-row projection, inline discussion
    placement, and diff-row construction into the corresponding file boundary.
    Remove the unconditional whole-change `review_projection` pass from local
    interactions. File toggles, source arrivals, viewed changes, and draft edits
    should update affected cards and required aggregate controls; global
    algorithm, layout, and ignore options must still update all affected views.
  - [ ] Reuse the existing diff/highlight caches within these boundaries and
    keep ignored-file notices lightweight. Verify that unchanged cards skip
    both view construction and virtual-DOM traversal, rather than only reusing
    calculation results. Migrate incrementally, starting with file expand and
    collapse, then source loading and review interactions.
  - [ ] Scope sticky-layout observation and measurement to structural or size
    changes. Batch necessary reads and writes after rendering, preserve change
    navigation landing behavior, and clean up observers with their owning view.
  - [ ] Add focused interaction regressions for expansion, section navigation,
    source loading, viewed state, comment anchors, and draft/focus preservation
    across Token/Tree and Split/Unified modes, including change navigation while
    source requests are pending.
  - [ ] Add render/projection instrumentation to the browser regression fixture.
    Acceptance: toggling the ignored file does not reconstruct, reproject, or
    traverse unrelated file subtrees, and does not recompute cached diffs or
    highlights. Compare main-thread long tasks before and after, including CPU
    throttling and increasing unrelated diff sizes; use update counts as the
    deterministic regression check rather than machine-specific timing alone.

- [ ] Improve worst-case similarity work beyond the existing budget fallback.
  - Affected areas: `astdiff/graph.mbt`, `astdiff/levenshtein.mbt`,
    `astdiff/dijkstra.mbt`, `astdiff/unchanged.mbt`, and
    `syntax/positions.mbt`.
  - [ ] Use banded or thresholded similarity algorithms, or algorithms that
    support early termination.
  - [ ] Check the remaining computation budget before generating expensive
    graph neighbors.
  - [ ] Add a regression/performance test for large strings that differ near
    the end.

## Medium Priority

- [ ] Keep changed-file navigation responsive at the supported 3,000-file limit.
  - Affected areas: `playground/frontend/internal/view/file_tree.mbt`,
    `playground/frontend/internal/view/view.mbt`, and
    `playground/frontend/tests/playground.spec.mjs`.
  - The current worst-case probe renders 9,001 tree rows, 3,000 file cards,
    and roughly 66,000 DOM elements; entering a 13-character search takes
    about 2.5 seconds in headless Chromium.
  - Build on the independent file-card updates from the rendering refactor above.
  - [ ] Cache the file-tree structure and avoid rebuilding every file card on
    each search keystroke.
  - [ ] Debounce search updates and/or virtualize the tree and file-card lists.
  - [ ] Add a browser performance regression test for the unfiltered 3,000-file
    view and sequential search input.

- [ ] Ensure real textual changes never result in empty CLI output.
  - Affected areas: `alignment/root_alignment.mbt`, `render/terminal/diff_text.mbt`, and `main.mbt`.
  - [ ] Define and implement an explicit output contract for `has_changes && rendered.is_empty()`.
  - [ ] For formatting-only changes, report that the text changed but no structural change was found; for top-level reordering, show a move summary or fall back to a regular line diff.
  - [ ] Add regression tests for reordered top-level declarations and ignored Unicode whitespace changes.

- [ ] Reuse the graph node whose parent stack exactly matches the requested state.
  - Affected area: `astdiff/graph.mbt` (`allocate_if_new`).
  - [ ] Search for an exact `parents` match before enforcing the two-state limit.
  - [ ] Apply the two-state limit only when no exact parent-stack state exists.
  - [ ] Add a regression test covering reuse of the first state after two states have been stored for the same graph key.

## Testing and Engineering

- [ ] Prevent the pre-commit script from staging changes that were originally unstaged.
  - Affected area: `scripts/pre-commit.sh`.
  - [ ] Detect partially staged files and refuse to continue, or format and update only the content already in the index.
  - [ ] Add a test that stages only part of a file and verifies that the remaining working-tree changes stay unstaged.

## Deferred

- [ ] Known issue: documentation-example syntax highlighting can overflow the lexer stack.
  - **Status: Intentionally deferred; no current plan to fix.**
  - Affected areas: `playground/frontend/internal/highlight/moonbit/docs.mbt`,
    `playground/frontend/internal/highlight/moonbit/classify.mbt`, and
    `playground/frontend/internal/change/diff_cache.mbt`.
  - Reproduced with a MoonBit fenced code example inside `///` comments whose
    string interpolation contains an array of about 4,000 string literals
    (approximately 16 KB for the complete source file).
  - Highlighting masks the comment prefixes and lexes the example as code.
    The lexer's mutually recursive interpolation scanners can then throw
    `RangeError: Maximum call stack size exceeded`; the highlighter's
    `depth >= 32` guard does not bound recursion inside the lexer.
  - The original Token and Tree diff calculations succeed on this input, but
    the added highlighting step leaves the browser showing
    `Loading file contents…` without a diff.
