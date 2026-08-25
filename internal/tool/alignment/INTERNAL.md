# Top-Level Alignment Principles

[中文版](./INTERNAL_CN.md)

Top-level alignment decides which declarations in an old source file correspond to declarations in a new source file. It runs before the detailed diff inside declarations, so its decisions determine whether a change is presented as an edit to an existing declaration, a deletion, an insertion, or a movement.

The strategy is intentionally conservative. A wrong pairing can make an unrelated rewrite look like a small edit, which is more misleading than showing a deletion and an insertion. The matcher therefore prefers missing a plausible correspondence over accepting an ambiguous one.

## Mental Model

The source file is viewed as an ordered sequence of declaration units. A unit contains one top-level declaration together with leading material that belongs to it, such as documentation and separators. Standalone material at the end of a file remains an independent unit so that it is not lost.

Alignment has two responsibilities:

1. Establish declaration identity across the two versions.
2. Choose whether the detailed diff should compare declarations independently or compare the files as a whole.

It does not decide the fine-grained changes inside a declaration. That work belongs to the later structural or textual diff.

## Guiding Principles

### Identity Before Similarity

Evidence that directly expresses identity is considered before visual or structural resemblance. A stable identity marker is stronger than a declaration name; a declaration's semantic role is stronger than a merely similar body.

This ordering prevents a highly similar new declaration from stealing the counterpart of a declaration whose identity is already known.

### Stronger Decisions Become Anchors

Once a correspondence is established with strong evidence, it becomes an anchor. Later heuristic matching may use anchors to understand local context, but it cannot overturn them.

Anchors divide the file into regions. A heuristic candidate is considered only when it occupies the same region relative to the surrounding anchors on both sides. This protects against confusing a move across a known declaration with a rename in place.

### Ambiguity Means No Match

A plausible candidate is not enough. Heuristic matching requires one candidate to be clearly preferred in both directions: the old declaration must prefer the new declaration, and the new declaration must prefer the old declaration.

Ties are not broken by source order. If two candidates are equally convincing, the result remains a deletion and insertion.

### Determinism Over Global Optimization

The matcher uses a staged evidence hierarchy rather than solving one global optimization problem. Each stage consumes only unmatched declarations, and earlier, stronger stages have priority.

This makes the result stable and explainable. Adding an unrelated declaration should not arbitrarily reshuffle otherwise established pairs.

### Graceful Degradation

Alignment is optional guidance for the detailed diff, not a prerequisite for producing output. If parsing fails, computation becomes too expensive, or no reliable declaration pair can be found, the system falls back to comparing a larger scope.

The fallback may be less precise, but it must remain complete and must never hide a real textual change.

## Evidence Hierarchy

The general strategy progresses from strongest to weakest evidence.

### Explicit Identity

Some declarations carry stable identity metadata. When that metadata is consistently available, it is authoritative even if declarations move or their contents change substantially.

Repeated identities are handled deterministically by occurrence order. When identity metadata is only partially present, the matches it does establish become anchors and unmatched declarations continue through the remaining stages.

When comments are intentionally ignored, comment-based identity metadata is ignored as well. Otherwise an ignored comment could silently change declaration identity.

### Semantic Identity

Without explicit identity, declarations are compared by semantic role. Relevant information includes declaration category, declared name, receiver, trait context, and similar ownership boundaries.

Semantic identity handles common changes such as insertion, deletion, and reordering without depending on physical line positions. Repeated declarations with the same semantic identity are paired deterministically by occurrence order rather than guessed from body similarity.

### Exact Structural Identity

Still-unmatched units can be paired when their complete structural fingerprints are identical and unique on both sides. This is useful for moved or anonymous content that has no semantic identity.

Uniqueness is essential. If the same structure appears multiple times, the fingerprint proves equivalence but not which occurrence corresponds to which, so no pair is chosen at this stage.

### Constrained Fuzzy Similarity

The final evidence source is fuzzy similarity. It combines two ideas:

- Structural continuity: most of the declaration retains the same syntactic shape.
- Name continuity: the old and new names resemble one another.

The declaration name is conceptually separated from the rest of the structure so that a rename does not destroy structural similarity, while name resemblance still contributes supporting evidence.

Fuzzy matching is constrained by declaration category and ownership. A method cannot drift to another receiver, a reference-receiver method cannot become a value-receiver match merely because the bodies look alike, and declarations of incompatible kinds are not candidates.

It is also constrained by anchors, rejects conflicting explicit identities, rejects ties, and accepts only mutual best matches. Without any reliable anchor, fuzzy similarity is not used to invent a global correspondence.

## Preserving Continuity Across Helper Extraction

A special ambiguity arises when an old declaration is split into two new declarations:

- The original name remains as a small wrapper.
- Most of the old implementation moves into a newly named helper.

Name-based semantic identity favors the wrapper, while implementation continuity favors the helper. Pairing only by name makes the large preserved body appear newly inserted; pairing only by body loses the continuity of the public wrapper.

The strategy resolves this conservatively in favor of implementation continuity, but only when the refactoring shape is unusually clear:

- The wrapper directly delegates at its end to one nearby helper.
- The helper belongs to the same declaration context.
- The wrapper is small relative to the old implementation.
- The helper preserves a strong and distinctive portion of the old body.
- No other old declaration is an equally plausible source for that helper.

Body continuity is judged by how much of the old computation structure survives in the helper, while discounting incidental changes such as comments and the helper's new name.

When the evidence is accepted, the old declaration is aligned with the body-bearing helper, while the wrapper is presented as inserted. The wrapper is then excluded from later rematching. This is a narrow policy for one recognizable refactoring pattern, not a general model for arbitrary splits and merges.

If any part of the evidence is weak—nonlocal helper, conditional delegation, ownership mismatch, substantial body retained in the wrapper, competing helpers, or competing old declarations—the ordinary semantic pairing remains in place.

## From Correspondences to a Diff Plan

When at least one trustworthy correspondence exists, declarations are compared independently:

- Paired declarations are diffed against each other.
- Unpaired old declarations are deletions.
- Unpaired new declarations are insertions.

This isolates edits inside moved declarations from the movement itself and preserves original source locations for reporting.

If no trustworthy correspondence exists, the matcher avoids arbitrary pairings and compares the complete declaration lists or files together. The broader comparison retains global context and gives the lower-level diff a chance to find useful structure on its own.

Pure reordering deserves special treatment. A structural view may legitimately report no internal structural changes, because every declaration is unchanged. A textual view must still show that the file text changed, so it falls back to a whole-file presentation when independent declaration diffs would otherwise be empty.

## Resource Bounds

Some heuristic work can grow quickly with the number and size of unmatched declarations. Similarity calculations therefore participate in a shared computation budget.

If the budget is exhausted, alignment stops and the diff expands to a safer, larger scope instead of returning a partial or unstable pairing.

## Expected Behavior in Common Scenarios

| Scenario | Conceptual result |
| --- | --- |
| A declaration is inserted before unchanged declarations | Existing declarations retain their identities; the new declaration is inserted. |
| Declarations are reordered | Strong identities follow the declarations rather than their line positions. |
| A declaration is renamed beside stable neighbors | It may be paired by constrained fuzzy similarity within the same anchor region. |
| A similar declaration moves across a stable anchor | It remains a deletion and insertion rather than being guessed as a rename. |
| Several candidates are equally similar | No heuristic pair is formed. |
| Identical anonymous content appears once on each side | It can be paired by exact structural identity. |
| Identical anonymous content is duplicated | It remains ambiguous at the structural-fingerprint stage. |
| A large body is extracted into a nearby helper | The helper may preserve the old implementation's continuity; the wrapper appears inserted. |
| Parsing or alignment exceeds its limits | The diff falls back to a whole-file or whole-list comparison. |

## Deliberate Limitations

The strategy intentionally does not:

- Treat similarity as proof of identity.
- Match heuristically across established anchor boundaries.
- Use source order to hide similarity ties.
- Guess correspondences among duplicated exact structures.
- Reconsider strong matches after weaker evidence appears.
- Model arbitrary many-to-many declaration splits and merges.
- Sacrifice complete output when precise alignment is unavailable.

These limitations favor predictable false negatives over misleading false positives. The central invariant is simple: every accepted pair should have a clear identity story, and every uncertain case should remain visibly uncertain.
