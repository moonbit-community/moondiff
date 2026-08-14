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

- [ ] Match renamed top-level declarations before finalizing `PerUnit` delete/insert edits.
  - Problem: method semantic keys include the complete method name, while `content_id` represents exact syntax identity rather than similarity. A rename such as `JobHandle::spawn_unix` to `JobHandle::spawn_unix_ffi`, especially when its signature also changes, therefore misses both matching mechanisms.
  - Root cause: when any other declaration in the file produces a `Replace`, `top_level_plan` selects `PerUnit`. The unmatched old and new declarations are then finalized as separate `Delete` and `Insert` edits before the AST matcher can compare them, so the structural similarity algorithm never sees the intended pair.
  - Expected behavior: a sufficiently similar renamed declaration should be rendered as one paired modification hunk, while genuinely unrelated or ambiguous declarations must remain separate delete/insert edits.
  - Affected areas: `tool/alignment/cst_units.mbt`, `tool/alignment/root_alignment.mbt`, and `tool/alignment/diff_document.mbt`.
  - [ ] Keep UUID, semantic-key, and unique exact-`content_id` matches as reliable anchors; the fuzzy pass must not replace or override these higher-confidence matches.
  - [ ] Partition unmatched declarations into gaps between adjacent anchors before fuzzy matching. This prevents a local rename from crossing stable declarations or being mistaken for an unrelated top-level move elsewhere in the file.
  - [ ] Within each gap, run a constrained second matching pass. Limit candidates by compatible declaration kind and, for methods, by receiver so that structurally similar methods on different types cannot be paired.
  - [ ] Combine name similarity with syntax similarity computed independently of the declared name. Removing the name from the structural score lets renames remain comparable, while retaining a separate name score helps distinguish several methods under the same receiver.
  - [ ] Accept only unique mutual-best candidates above a documented threshold. Keep ties, low-confidence candidates, and other ambiguous cases as delete/insert pairs to avoid inventing misleading edits.
  - [ ] Generate the final `PerUnit` edit sequence only after the second matching pass, then pass every accepted pair to the normal Lexical or AST comparison instead of comparing either side with an empty unit.
  - [ ] Add focused regression tests for the stable-declaration-plus-rename cliff, multiple simultaneous changes under one receiver, cross-receiver lookalikes, reordered declarations, both Lexical and AST modes, and UUID precedence.
  - [ ] Use CLI fixture `20260814` as the end-to-end acceptance test. After the fix, update `cli_test/snapshot/20260814.txt` so `JobHandle::spawn_unix` and `JobHandle::spawn_unix_ffi` appear as one paired modification hunk—not one full deletion followed by one full insertion—and verify that the fixture has no parser fallback.
  - [ ] Run `bash scripts/cli_test.sh && git diff --exit-code cli_test`; the `20260814` case should return to the expected passing state together with the existing CLI regression suite.

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

## Testing and Engineering

- [ ] Prevent the pre-commit script from staging changes that were originally unstaged.
  - Affected area: `scripts/pre-commit.sh`.
  - [ ] Detect partially staged files and refuse to continue, or format and update only the content already in the index.
  - [ ] Add a test that stages only part of a file and verifies that the remaining working-tree changes stay unstaged.
