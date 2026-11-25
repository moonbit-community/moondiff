///|UUID(c0abf901-d36b-4322-8f46-9bee7e92d798)
/// Calculate the Levenshtein distance between two strings using dynamic programming.
/// This function calculates the Levenshtein distance between two input strings `lhs` and `rhs`,
/// which is defined as the minimum number of single-character edits (insertions, deletions,
/// or substitutions) required to transform string `lhs` into string `rhs`.
fn levenshtein_impl(
  lhs~ : Array[Char],
  rhs~ : Array[Char],
  budget : @computation.ScopeBudget,
) -> Int32 raise @computation.ScopeLimitExceeded {
  budget.charge_matrix(lhs.length() + 1, rhs.length() + 1, SyntaxMatching)
  @core_diff.edit_distance(lhs, rhs)
}

///|UUID(98dd7927-df59-420c-9c4d-a0a68ec9bfbf)
fn normalized_levenshtein(
  lhs~ : String,
  rhs~ : String,
  budget : @computation.ScopeBudget,
) -> Double raise @computation.ScopeLimitExceeded {
  let lhs = lhs.to_array()
  let rhs = rhs.to_array()
  if lhs.is_empty() && rhs.is_empty() {
    return 1.0
  }
  1.0 -
  levenshtein_impl(budget, lhs~, rhs~).to_double() /
  @cmp.maximum(lhs.length(), rhs.length()).to_double()
}
