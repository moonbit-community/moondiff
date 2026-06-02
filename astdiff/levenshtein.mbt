///|UUID(c0abf901-d36b-4322-8f46-9bee7e92d798)
/// Calculate the Levenshtein distance between two strings using dynamic programming.
/// This function calculates the Levenshtein distance between two input strings `lhs` and `rhs`,
/// which is defined as the minimum number of single-character edits (insertions, deletions,
/// or substitutions) required to transform string `lhs` into string `rhs`.
fn levenshtein(lhs~ : Array[Char], rhs~ : Array[Char]) -> Int {
  let m = lhs.length()
  let n = rhs.length()
  let s = [[], []]
  // create Array of length n+1 with elements initialized to 0
  s[0] = Array::make(n + 1, 0)
  s[1] = Array::make(n + 1, 0)
  let mut j = 1
  while j <= n {
    s[0][j] = j
    j = j + 1
  }
  let mut i = 1
  while i <= m {
    s[i & 1][0] = i
    let mut j = 1
    while j <= n {
      s[i & 1][j] = if lhs[i - 1] == rhs[j - 1] {
        s[(i - 1) & 1][j - 1]
      } else {
        1 +
        @cmp.minimum(
          @cmp.minimum(s[(i - 1) & 1][j - 1], s[(i - 1) & 1][j]),
          s[i & 1][j - 1],
        )
      }
      j = j + 1
    }
    i = i + 1
  }
  s[m & 1][n]
}

///|UUID(98dd7927-df59-420c-9c4d-a0a68ec9bfbf)
fn normalized_levenshtein(lhs~ : String, rhs~ : String) -> Double {
  let lhs = lhs.to_array()
  let rhs = rhs.to_array()
  if lhs.is_empty() && rhs.is_empty() {
    return 1.0
  }
  1.0 -
  levenshtein(lhs~, rhs~).to_double() /
  @cmp.maximum(lhs.length(), rhs.length()).to_double()
}
