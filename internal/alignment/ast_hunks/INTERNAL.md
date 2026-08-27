# AST Line Alignment and Hunk Construction

[中文版](./INTERNAL_CN.md)

The `ast_hunks` package turns syntax-level match positions into the line-level geometry needed to render an AST diff. The AST matcher describes which source spans are unchanged or novel; a renderer instead needs ordered left/right rows, compact changed regions, and context windows. This package is the bridge between those representations.

It does not decide syntax-node identity, compute intraline highlight ranges, or build final diff blocks. Those responsibilities remain with the AST matcher and the surrounding alignment pipeline.

## Two Parallel Products

The package deliberately builds two related products independently:

1. A complete line-pair table for rendering, produced by `all_matched_lines_filled`.
2. Sparse changed cores, produced by `matched_pos_to_hunks`.

The complete table preserves source order and lines with no syntax position, while a hunk records only the lines implicated by novel syntax. `contextual_index_range_for_hunk` later locates a sparse core in the complete table and adds context. Keeping these products separate prevents context and syntax-free lines from being mistaken for changes.

## Input and Coordinate Model

Each side supplies an ordered sequence of `MatchedPos` values. A position contains a single-line source span and one of two kinds:

- `Unchanged` carries an array of spans for the corresponding syntax on the opposite side. The array can be empty after source filtering.
- `Novel` marks syntax that has no unchanged counterpart.

Input spans use one-based line numbers. Every line number exposed by this package is converted to a zero-based index relative to the source-line arrays passed by the caller. In a per-declaration diff, these are declaration-local indexes, not whole-file indexes.

A line pair `(Int?, Int?)` is a display row:

| Pair | Meaning |
| --- | --- |
| `(Some(lhs), Some(rhs))` | Show the two source lines on the same row. |
| `(Some(lhs), None)` | Show a left-only row. |
| `(None, Some(rhs))` | Show a right-only row. |
| `(None, None)` | Invalid and never intentionally emitted. |

A two-sided pair is not, by itself, a claim that the lines are equal. It may come from an unchanged anchor, from a changed line that retains unchanged syntax, or from compacting a one-line replacement for display. Consumers must use novel-line membership and source text, rather than pair shape alone, to distinguish context from change.

## Hunk Representation

An `AstHunk` contains three pieces of information:

- `lines` is the sparse, ordered changed core. Context is not stored here.
- `novel_lhs` is the set of left line indexes containing at least one novel span in this hunk.
- `novel_rhs` is the corresponding set for the right side.

The novel sets are side-specific. A paired row may be novel only on one side, which is common when a line keeps some unchanged tokens while gaining or losing other tokens.

## Building the Complete Line-Pair Table

### Conservative Unchanged Anchors

All unchanged span correspondences are first collapsed to line-to-line relations. Several syntax positions on one line may point to several positions on another line, so this collapse can be ambiguous.

A two-sided anchor is accepted only when the relation is unique in both directions: the current line points to exactly one opposite line, and that opposite line points back only to the current line. Accepted anchors must also increase on both sides. Duplicate positions on the same line and crossing correspondences therefore cannot create repeated or backward rows.

Ambiguous many-to-many relations are not guessed. Their lines are inserted later as one-sided rows, preserving content without asserting a questionable alignment.

### Restore Every Observable Line

After establishing anchors, the algorithm merges in every line mentioned by syntax positions on either side. It then uses the source-line arrays to restore lines that syntax positions do not describe:

- Leading and trailing lines are aligned positionally while both sides have lines, with any excess emitted one-sided.
- Exactly empty lines immediately preceding two-sided anchors are paired backward on both sides.
- Missing indexes between observed lines are inserted as one-sided rows so each side remains contiguous.

The result is ordered independently on each side: ignoring `None`, present left indexes increase, and present right indexes increase. The table is display geometry, so it can preserve a complete fragment without requiring every row to have a semantic anchor.

### Compact Only the Smallest Replacement Gap

Contiguity filling can create a run of left-only rows followed by right-only rows. If that run contains exactly one line from each side, it is compacted into one paired row. This makes a simple one-line replacement render side by side.

Larger gaps remain as separate left-only and right-only rows. Pairing them by position would imply a correspondence for which the AST supplied no evidence.

## Building Changed Hunk Cores

### Collect and Order Novel Lines

Any line containing at least one `Novel` position is a changed line. Novel positions have no direct opposite span, so their cross-side order is inferred from surrounding unchanged positions.

Within a region between unchanged anchors, ordering is deterministic:

1. Novel positions on the previous anchor line come first.
2. Positions on lines with no unchanged line relation come next.
3. Positions attached to the following anchor come last.

For a changed line that also contains unchanged syntax, the algorithm may use the next increasing opposite-line relation to place both sides on one row. Lines without such evidence remain one-sided. After this ordering pass, all novel line sets are merged back in so no changed line can be omitted merely because it lacked a usable anchor.

### Enforce Monotonicity

The ordered candidates are normalized so each side increases strictly. If one coordinate repeats or moves backward, that coordinate becomes `None`; the other side is retained when possible. A row is discarded only if both coordinates disappear.

This rule favors a stable, renderable sequence over preserving a dubious two-sided pairing.

### Form Raw Hunks

Normalized changed rows are grouped into raw hunks. A row stays in the current hunk when its left coordinate is within four lines of the latest present left coordinate in the core or its right coordinate is within four lines of the latest present right coordinate. Otherwise a new hunk starts.

The proximity test is intentionally side-aware: insertions and deletions can remain together when they are locally continuous on either side, even if the other side has a larger line-number jump. Each raw hunk then receives only the novel-line sets represented by its core rows.

## Locating Context and Merging Hunks

Hunk cores are sparse, but context is sliced from the complete line-pair table. Before locating a core, the package fills the line-number intervals between consecutive changed pairs. It then finds the first and last table rows touching any core line on either side.

`contextual_index_range_for_hunk` expands that half-open table-index range by the requested radius and clamps it to the table bounds. The radius counts rows in the aligned table, not independent physical distances on the two source files. If a core cannot be located, the defensive result is the whole table rather than an empty or truncated range.

`merge_adjacent_hunks` computes context windows using `context_lines + 1`. Hunks whose windows overlap or meet are merged, so immediately adjacent rendered regions do not produce artificial separators. Merging:

- unions the two novel-line sets;
- concatenates the changed cores;
- removes duplicate line indexes independently on each side;
- preserves the nonduplicate side of a row by replacing only the duplicated coordinate with `None`.

That last rule matters when overlapping cores mention the same line on one side but different lines on the other.

## Integration with the Alignment Pipeline

The surrounding alignment package uses `ast_hunks` in this order:

1. Validate and map AST positions into the current filtered source view.
2. Call `all_matched_lines_filled` to build the render-row table.
3. Call `matched_pos_to_hunks`, then `merge_adjacent_hunks`, to obtain display regions.
4. Call `contextual_index_range_for_hunk` for each region and slice the row table.
5. Use novel-line sets plus exact source-text equality to classify context and changed rows; use the original novel spans for intraline highlighting.

Out-of-bounds position handling and lexical fallback happen before or around this package. `ast_hunks` assumes its position streams and source arrays already refer to the same local coordinate space.

## Expected Behavior in Common Scenarios

| Scenario | Conceptual result |
| --- | --- |
| A line gains a token but retains unchanged tokens | The old and new lines can share a row; only the side containing the novel span is marked novel. |
| One line has several unchanged positions pointing to the same opposite line | The de-duplicated one-to-one line relation can still be an anchor. |
| A line maps to multiple opposite lines | No unchanged anchor is asserted for that relation. |
| Unchanged relations would cross | Later non-increasing coordinates are dropped instead of reordering the display. |
| Empty lines occur immediately before matching syntax | The empty lines are paired backward as stable context. |
| One unanchored line exists on each side of a gap | The two rows are compacted into a visual one-line replacement. |
| Several unanchored lines exist on either side | They remain one-sided rather than being paired speculatively. |
| Changed rows are at most four lines apart on either side | They remain in one raw hunk. |
| Separate raw hunks have overlapping context windows | They merge into one rendered region without duplicate line numbers. |

## Deliberate Limitations

The package intentionally does not:

- Run a textual LCS or similarity matcher to invent additional line correspondences.
- Treat a paired display row as proof of unchanged text.
- Choose among ambiguous many-to-many unchanged relations.
- Preserve crossing or repeated coordinates at the cost of monotonic output.
- Pair larger replacement blocks line by line without AST evidence.
- Treat whitespace-only lines as exactly empty when matching preceding blanks.
- Make the four-line raw-hunk threshold depend on the caller's context setting.
- Validate spans, choose fallback policy, or translate local indexes back to whole-file coordinates.

The central invariant is that every source line kept in a two-sided semantic anchor has an unambiguous, increasing identity story. Everything else may still be displayed, but only with the weaker status of visual alignment or a one-sided row.
