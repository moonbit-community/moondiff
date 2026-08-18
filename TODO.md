# TODO

## High Priority

- [ ] Support CR-only line endings without crashing or rendering blank changed lines.
  - Affected areas: `elab/cst_elab.mbt`, `span/span.mbt`, and `tool/render/render.mbt`.
  - [ ] Use the same universal-newline splitting logic for LF, CRLF, and CR in every layer.
  - [ ] Add end-to-end structured-diff and line-diff tests for all three line-ending formats.
  - [ ] Validate syntax positions against the rendered line array and fall back to a regular line diff when positions are out of bounds.

- [ ] Bound quadratic Levenshtein and LCS computations independently of `graph_limit`.
  - Affected areas: `astdiff/graph.mbt`, `astdiff/levenshtein.mbt`, `astdiff/dijkstra.mbt`, `astdiff/unchanged.mbt`, and `syntax/positions.mbt`.
  - [ ] Add DP-cell budgets, such as a limit on `lhs_len × rhs_len`.
  - [ ] Use banded or thresholded similarity algorithms, or algorithms that support early termination.
  - [ ] Check the remaining computation budget before generating expensive graph neighbors.
  - [ ] Fall back immediately to a regular line diff for the affected unit when a limit is exceeded.
  - [ ] Add a regression/performance test for large strings that differ near the end.

## Medium Priority

- [ ] Ensure real textual changes never result in empty CLI output.
  - Affected areas: `tool/alignment/root_alignment.mbt`, `tool/diff_text.mbt`, and `main.mbt`.
  - [ ] Define and implement an explicit output contract for `has_changes && rendered.is_empty()`.
  - [ ] For formatting-only changes, report that the text changed but no structural change was found; for top-level reordering, show a move summary or fall back to a regular line diff.
  - [ ] Add regression tests for reordered top-level declarations and ignored Unicode whitespace changes.

- [ ] Reuse the graph node whose parent stack exactly matches the requested state.
  - Affected area: `astdiff/graph.mbt` (`allocate_if_new`).
  - [ ] Search for an exact `parents` match before enforcing the two-state limit.
  - [ ] Apply the two-state limit only when no exact parent-stack state exists.
  - [ ] Add a regression test covering reuse of the first state after two states have been stored for the same graph key.

- [ ] Make the `mbtdiff.DiffResult` ownership and mutability contract explicit.
  - Affected areas: `mbtdiff/types.mbt`, `model/diff_document.mbt`, and `model/result_metadata.mbt`.
  - [ ] Decide whether returned documents and fallback metadata are immutable views or independently mutable snapshots.
  - [ ] If the result is immutable, avoid exposing shared mutable arrays through `document()` and deep-copy nested arrays such as `ParseError.sides` in `fallbacks()`.
  - [ ] Add a consumer regression test that mutates an accessor result and verifies that later accessor calls cannot observe unintended changes.

## Testing and Engineering

- [ ] Prevent the pre-commit script from staging changes that were originally unstaged.
  - Affected area: `scripts/pre-commit.sh`.
  - [ ] Detect partially staged files and refuse to continue, or format and update only the content already in the index.
  - [ ] Add a test that stages only part of a file and verifies that the remaining working-tree changes stay unstaged.
