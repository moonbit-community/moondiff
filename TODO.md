# TODO

## High Priority

- [x] Finish universal-newline support at the remaining input boundaries.
  - [x] Use the same LF, CRLF, and CR splitting rules in the core parser,
    source-position, structural-diff, and rendering paths.
  - [x] Add an end-to-end structured-diff test for all three line-ending
    formats.
  - [x] Make Playground source validation and splitting recognize bare CR as a
    line ending.
  - [x] Add Playground and line-diff regression tests for CR-only input,
    including enforcement of the 20,000-line limit.
  - [x] Validate syntax positions against the rendered line array and fall back
    to a regular line diff when positions are out of bounds.

- [x] Bound quadratic Levenshtein and LCS computations independently of
  `graph_limit`.
  - [x] Charge DP matrix cells against an overflow-safe shared per-file
    computation budget before allocation.
  - [x] Report a typed computation-limit reason and fall back to a regular line
    diff for the affected file or unit when the budget is exhausted.

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
