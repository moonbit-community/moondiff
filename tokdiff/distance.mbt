// Copyright 2026 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Weighted token alignment: all-integer Wagner-Fischer scoring (weights x20,
// similarity in permille, stored backpointers) so results are bit-identical
// on every backend. Design and thresholds hardened through adversarial
// review; see README.

///|
/// Same-kind substitution at 1.5x the mean token weight: cheaper than
/// delete+insert so renames align, but expensive enough that two lines with
/// nothing in common score ~250 permille, under the pairing threshold.
/// Cross-kind substitution is not offered; it decomposes into delete+insert.
fn subst_cost(a : Tok, b : Tok) -> Int? {
  if a.kind == b.kind {
    if a.text == b.text {
      Some(0)
    } else {
      Some((alignment_weight(a) + alignment_weight(b)) * 3 / 4)
    }
  } else {
    None
  }
}

///|
fn tok_mass(ts : ArrayView[Tok]) -> Int {
  let mut m = 0
  for t in ts {
    m += alignment_weight(t)
  }
  m
}

///|
/// Weighted token edit distance (scoring only: rolling rows).
fn wdist(a : ArrayView[Tok], b : ArrayView[Tok]) -> Int {
  let n = b.length()
  let mut prev = Array::make(n + 1, 0)
  let mut acc = 0
  for j in 1..<(n + 1) {
    acc += alignment_weight(b[j - 1])
    prev[j] = acc
  }
  let mut cur = Array::make(n + 1, 0)
  for i in 1..<(a.length() + 1) {
    cur[0] = prev[0] + alignment_weight(a[i - 1])
    for j in 1..<(n + 1) {
      let del = prev[j] + alignment_weight(a[i - 1])
      let ins = cur[j - 1] + alignment_weight(b[j - 1])
      let mut best = if del < ins { del } else { ins }
      if subst_cost(a[i - 1], b[j - 1]) is Some(c) {
        if prev[j - 1] + c < best {
          best = prev[j - 1] + c
        }
      }
      cur[j] = best
    }
    let t = prev
    prev = cur
    cur = t
  }
  prev[n]
}

///|
/// Line similarity in permille: `1000 * (mass - dist) / mass` over both
/// sides' weighted mass. Zero-mass lines (empty or filler-only) carry no
/// evidence either way and pair only when textually identical.
pub fn similarity(a : String, b : String) -> Int {
  sim_toks(tokenize_line(a), tokenize_line(b))
}

///|
fn sim_toks(a : ArrayView[Tok], b : ArrayView[Tok]) -> Int {
  let m = tok_mass(a) + tok_mass(b)
  if m == 0 {
    if a.length() != b.length() {
      return 0
    }
    for i in 0..<a.length() {
      if a[i].kind != b[i].kind || a[i].text != b[i].text {
        return 0
      }
    }
    return 1000
  }
  (m - wdist(a, b)) * 1000 / m
}

///|
/// Pairing threshold in permille.
const THETA : Int = 400

///|
/// Monotone alignment of a replacement block, maximizing the total positive
/// margin `sum(sim - THETA)`; a pair is only usable when its margin is
/// positive. Deterministic: integer scores, stored backpointers, tie
/// preference diag > left > up (delete-before-insert in forward order).
fn align(
  olds : Array[Array[Tok]],
  news : Array[Array[Tok]],
) -> Array[(Int?, Int?)] {
  let m = olds.length()
  let n = news.length()
  let dp = FixedArray::makei(m + 1, _ => FixedArray::make(n + 1, 0))
  let bp = FixedArray::makei(m + 1, _ => FixedArray::make(n + 1, 0)) // 1 diag, 2 left, 3 up
  for j in 1..<(n + 1) {
    bp[0][j] = 2
  }
  for i in 1..<(m + 1) {
    bp[i][0] = 3
    for j in 1..<(n + 1) {
      let margin = sim_toks(olds[i - 1][:], news[j - 1][:]) - THETA
      let mut best = dp[i][j - 1]
      let mut way = 2
      if dp[i - 1][j] > best {
        best = dp[i - 1][j]
        way = 3
      }
      if margin > 0 && dp[i - 1][j - 1] + margin >= best {
        best = dp[i - 1][j - 1] + margin
        way = 1
      }
      dp[i][j] = best
      bp[i][j] = way
    }
  }
  let out : Array[(Int?, Int?)] = []
  let mut i = m
  let mut j = n
  while i > 0 || j > 0 {
    match bp[i][j] {
      1 => {
        out.push((Some(i - 1), Some(j - 1)))
        i -= 1
        j -= 1
      }
      2 => {
        out.push((None, Some(j - 1)))
        j -= 1
      }
      _ => {
        out.push((Some(i - 1), None))
        i -= 1
      }
    }
  }
  out.rev_in_place()
  out
}

///|
/// Tokenized inputs for one bounded line-alignment window.
priv struct AlignmentTokens {
  olds : Array[Array[Tok]]
  news : Array[Array[Tok]]
}

///|
/// Apply the shared replacement-window budgets before invoking `align`:
/// at most 64 lines per side, 1024 tokens per line, and 2M aggregate token
/// DP cells. Returning `None` means the caller must preserve its original
/// structure and render without inferred pairing/highlighting.
fn[T] alignment_tokens(
  old_lines : ArrayView[T],
  new_lines : ArrayView[T],
  line_text : (T) -> String,
) -> AlignmentTokens? {
  if old_lines.length() > 64 || new_lines.length() > 64 {
    return None
  }
  let olds : Array[Array[Tok]] = []
  for line in old_lines {
    let toks = tokenize_line(line_text(line))
    if toks.length() > 1024 {
      return None
    }
    olds.push(toks)
  }
  let news : Array[Array[Tok]] = []
  for line in new_lines {
    let toks = tokenize_line(line_text(line))
    if toks.length() > 1024 {
      return None
    }
    news.push(toks)
  }
  let mut work = 0
  for ta in olds {
    for tb in news {
      work += (ta.length() + 1) * (tb.length() + 1)
      if work > 2_000_000 {
        return None
      }
    }
  }
  Some({ olds, news })
}

///|
priv enum Op {
  OEq(Tok)
  OSub(Tok, Tok)
  ODel(Tok)
  OIns(Tok)
}

///|
/// One semantic token in a replacement window. Whitespace skipped by the
/// lexer is kept in `gap_before`; every other token remains a real atom and
/// retains the position needed to project a traceback back to its source
/// line.
priv struct WindowAtom {
  token : Tok
  line : Int
  token_index : Int
  gap_before : String
}

///|
/// A lossless semantic view over already-tokenized lines. Concatenating every
/// `gap_before`, atom text, and `trailing_gap` reconstructs the window with a
/// synthetic newline between adjacent source lines.
priv struct WindowStream {
  atoms : Array[WindowAtom]
  trailing_gap : String
}

///|
priv enum GapKind {
  Empty
  Horizontal
  Multiline
} derive(Eq)

///|
priv enum PairMode {
  Legacy
  Window
}

///|
/// Traceback steps use source indices so the same four-state kernel can feed
/// both the legacy public-token operations and the window projection.
priv enum PairStep {
  PairEqual(Int, Int)
  PairSub(Int, Int)
  PairDelete(Int)
  PairInsert(Int)
}

///|
/// Naturalness of a boundary between two adjacent token spans. The score is
/// deliberately language-class based (not character based): line ends win,
/// then whitespace/comment filler, punctuation, and a token-kind transition.
fn token_boundary_score(left : Tok?, right : Tok?) -> Int {
  match (left, right) {
    (None, _) | (_, None) => 4
    (Some(a), Some(b)) =>
      if a.kind is (Space | Filler) || b.kind is (Space | Filler) {
        3
      } else if a.kind is Punct || b.kind is Punct {
        2
      } else if a.kind != b.kind {
        1
      } else {
        0
      }
  }
}

///|
/// The four traceback states distinguish a closed edit run from an open run
/// that has consumed old tokens, new tokens, or both. Keeping this state in
/// the DP makes opening and closing boundary scores globally composable.
const PAIR_EQUAL : Int = 0

///|
const PAIR_OLD_CHANGED : Int = 1

///|
const PAIR_NEW_CHANGED : Int = 2

///|
const PAIR_BOTH_CHANGED : Int = 3

///|
const PAIR_STATE_COUNT : Int = 4

///|
/// Lexicographic path score. Lower edit cost and run count win; all other
/// fields are maximized in the order used by `pair_score_better`.
priv struct PairScore {
  cost : Int
  high_exact : Int
  exact : Int
  runs : Int
  gap : Int
  boundary : Int
  right : Int
}

///|
fn pair_unreachable_score() -> PairScore {
  {
    cost: 1_000_000_000,
    high_exact: 0,
    exact: 0,
    runs: 0,
    gap: 0,
    boundary: 0,
    right: 0,
  }
}

///|
fn pair_score_better(a : PairScore, b : PairScore) -> Bool {
  if a.cost != b.cost {
    a.cost < b.cost
  } else if a.high_exact != b.high_exact {
    a.high_exact > b.high_exact
  } else if a.exact != b.exact {
    a.exact > b.exact
  } else if a.runs != b.runs {
    a.runs < b.runs
  } else if a.gap != b.gap {
    a.gap > b.gap
  } else if a.boundary != b.boundary {
    a.boundary > b.boundary
  } else {
    a.right > b.right
  }
}

///|
fn pair_score_equal(a : PairScore, b : PairScore) -> Bool {
  a.cost == b.cost &&
  a.high_exact == b.high_exact &&
  a.exact == b.exact &&
  a.runs == b.runs &&
  a.gap == b.gap &&
  a.boundary == b.boundary &&
  a.right == b.right
}

///|
priv struct PairTrace {
  steps : Array[PairStep]
  score : PairScore
}

///|
fn window_stream(lines : ArrayView[Array[Tok]]) -> WindowStream {
  let atoms : Array[WindowAtom] = []
  let mut gap = ""
  for line_index, tokens in lines {
    for token_index, token in tokens {
      if token.kind is Space {
        gap += token.text
      } else {
        atoms.push({ token, line: line_index, token_index, gap_before: gap })
        gap = ""
      }
    }
    if line_index + 1 < lines.length() {
      gap += "\n"
    }
  }
  { atoms, trailing_gap: gap }
}

///|
fn legacy_pair_stream(tokens : ArrayView[Tok]) -> WindowStream {
  let atoms : Array[WindowAtom] = []
  for token_index, token in tokens {
    atoms.push({ token, line: 0, token_index, gap_before: "" })
  }
  { atoms, trailing_gap: "" }
}

///|
fn gap_kind(gap : String) -> GapKind {
  if gap is "" {
    Empty
  } else if gap.contains("\n") || gap.contains("\r") {
    Multiline
  } else {
    Horizontal
  }
}

///|
fn gap_layout_score(old_gap : String, new_gap : String) -> Int {
  if old_gap == new_gap {
    2
  } else if gap_kind(old_gap) == gap_kind(new_gap) {
    1
  } else {
    0
  }
}

///|
fn pair_has_old(state : Int) -> Bool {
  state == PAIR_OLD_CHANGED || state == PAIR_BOTH_CHANGED
}

///|
fn pair_has_new(state : Int) -> Bool {
  state == PAIR_NEW_CHANGED || state == PAIR_BOTH_CHANGED
}

///|
fn pair_changed_state(
  state : Int,
  consumes_old : Bool,
  consumes_new : Bool,
) -> Int {
  let has_old = pair_has_old(state) || consumes_old
  let has_new = pair_has_new(state) || consumes_new
  if has_old && has_new {
    PAIR_BOTH_CHANGED
  } else if has_old {
    PAIR_OLD_CHANGED
  } else {
    PAIR_NEW_CHANGED
  }
}

///|
/// Naturalness of the boundary between atoms `index - 1` and `index`.
/// Window gaps replace legacy `Space` tokens: a newline is a real line edge,
/// horizontal whitespace is a soft boundary, and an empty gap falls back to
/// the adjacent token kinds.
fn pair_boundary(
  atoms : ArrayView[WindowAtom],
  trailing_gap : String,
  index : Int,
  mode : PairMode,
) -> Int {
  match mode {
    Legacy => {
      let left = if index == 0 { None } else { Some(atoms[index - 1].token) }
      let right = if index == atoms.length() {
        None
      } else {
        Some(atoms[index].token)
      }
      token_boundary_score(left, right)
    }
    Window => {
      let gap = if index == atoms.length() {
        trailing_gap
      } else {
        atoms[index].gap_before
      }
      match gap_kind(gap) {
        Multiline => 4
        Horizontal => 3
        Empty => {
          let left = if index == 0 {
            None
          } else {
            Some(atoms[index - 1].token)
          }
          let right = if index == atoms.length() {
            None
          } else {
            Some(atoms[index].token)
          }
          token_boundary_score(left, right)
        }
      }
    }
  }
}

///|
fn pair_open_boundary(
  atoms : ArrayView[WindowAtom],
  trailing_gap : String,
  index : Int,
  mode : PairMode,
) -> Int {
  pair_boundary(atoms, trailing_gap, index, mode)
}

///|
fn pair_close_boundary(
  atoms : ArrayView[WindowAtom],
  trailing_gap : String,
  index : Int,
  mode : PairMode,
) -> Int {
  pair_boundary(atoms, trailing_gap, index, mode)
}

///|
/// Whitespace and comment boilerplate carry no positional evidence. This
/// keeps an equivalent leading/trailing spacer from moving a semantic edit;
/// meaningful changed tokens still resolve otherwise exact ties to the right.
fn pair_changed_position(atoms : ArrayView[WindowAtom], index : Int) -> Int {
  if atoms[index].token.kind is (Space | Filler) {
    0
  } else {
    index
  }
}

///|
fn pair_changed_score(
  score : PairScore,
  state : Int,
  a : ArrayView[WindowAtom],
  b : ArrayView[WindowAtom],
  a_trailing_gap : String,
  b_trailing_gap : String,
  mode : PairMode,
  old_index : Int,
  new_index : Int,
  edit_cost : Int,
) -> PairScore {
  let consumes_old = old_index >= 0
  let consumes_new = new_index >= 0
  let old_line_break = consumes_old &&
    mode is Window &&
    gap_kind(a[old_index].gap_before) is Multiline
  let new_line_break = consumes_new &&
    mode is Window &&
    gap_kind(b[new_index].gap_before) is Multiline
  let split_old = old_line_break && pair_has_old(state)
  let split_new = new_line_break && pair_has_new(state)
  let mut boundary = score.boundary
  if split_old {
    boundary += pair_close_boundary(a, a_trailing_gap, old_index, mode)
    boundary += pair_open_boundary(a, a_trailing_gap, old_index, mode)
  } else if consumes_old && !pair_has_old(state) {
    boundary += pair_open_boundary(a, a_trailing_gap, old_index, mode)
  }
  if split_new {
    boundary += pair_close_boundary(b, b_trailing_gap, new_index, mode)
    boundary += pair_open_boundary(b, b_trailing_gap, new_index, mode)
  } else if consumes_new && !pair_has_new(state) {
    boundary += pair_open_boundary(b, b_trailing_gap, new_index, mode)
  }
  {
    cost: score.cost + edit_cost,
    high_exact: score.high_exact,
    exact: score.exact,
    runs: score.runs +
    (if state == PAIR_EQUAL || old_line_break || new_line_break {
      1
    } else {
      0
    }),
    gap: score.gap,
    boundary,
    right: score.right +
    (if consumes_old { pair_changed_position(a, old_index) } else { 0 }) +
    (if consumes_new { pair_changed_position(b, new_index) } else { 0 }),
  }
}

///|
fn pair_diagonal_gap_score(
  mode : PairMode,
  a : ArrayView[WindowAtom],
  b : ArrayView[WindowAtom],
  old_index : Int,
  new_index : Int,
) -> Int {
  match mode {
    Legacy => 0
    Window => gap_layout_score(a[old_index].gap_before, b[new_index].gap_before)
  }
}

///|
fn pair_high_exact_evidence(token : Tok, mode : PairMode) -> Int {
  match mode {
    Legacy => 0
    Window =>
      if token.kind is (Word | Str | Marker) {
        alignment_weight(token)
      } else {
        0
      }
  }
}

///|
fn pair_equal_score(
  score : PairScore,
  state : Int,
  a : ArrayView[WindowAtom],
  b : ArrayView[WindowAtom],
  a_trailing_gap : String,
  b_trailing_gap : String,
  mode : PairMode,
  old_index : Int,
  new_index : Int,
) -> PairScore {
  let mut boundary = score.boundary
  if pair_has_old(state) {
    boundary += pair_close_boundary(a, a_trailing_gap, old_index, mode)
  }
  if pair_has_new(state) {
    boundary += pair_close_boundary(b, b_trailing_gap, new_index, mode)
  }
  let evidence = alignment_weight(a[old_index].token)
  {
    cost: score.cost,
    high_exact: score.high_exact +
    pair_high_exact_evidence(a[old_index].token, mode),
    exact: score.exact + (if evidence > 0 { evidence } else { 1 }),
    runs: score.runs,
    gap: score.gap + pair_diagonal_gap_score(mode, a, b, old_index, new_index),
    boundary,
    right: score.right,
  }
}

///|
fn pair_finish_score(
  score : PairScore,
  state : Int,
  a : ArrayView[WindowAtom],
  b : ArrayView[WindowAtom],
  a_trailing_gap : String,
  b_trailing_gap : String,
  mode : PairMode,
) -> PairScore {
  if score.cost == pair_unreachable_score().cost {
    return score
  }
  let mut boundary = score.boundary
  if pair_has_old(state) {
    boundary += pair_close_boundary(a, a_trailing_gap, a.length(), mode)
  }
  if pair_has_new(state) {
    boundary += pair_close_boundary(b, b_trailing_gap, b.length(), mode)
  }
  let trailing_layout = match mode {
    Legacy => 0
    Window => gap_layout_score(a_trailing_gap, b_trailing_gap)
  }
  { ..score, gap: score.gap + trailing_layout, boundary }
}

///|
fn pair_row_index(column : Int, state : Int) -> Int {
  column * PAIR_STATE_COUNT + state
}

///|
fn pair_backpointer_index(
  row : Int,
  column : Int,
  width : Int,
  state : Int,
) -> Int {
  (row * width + column) * PAIR_STATE_COUNT + state
}

///|
/// Store one candidate. Backpointer ways are 1 diagonal, 2 insert, 3 delete;
/// their numeric order supplies the final deterministic tie preference.
fn pair_consider(
  scores : FixedArray[PairScore],
  score_index : Int,
  backpointers : FixedArray[Int],
  backpointer_index : Int,
  candidate : PairScore,
  previous_state : Int,
  way : Int,
) -> Unit {
  let current = scores[score_index]
  let current_way = backpointers[backpointer_index] % PAIR_STATE_COUNT
  if pair_score_better(candidate, current) ||
    (
      pair_score_equal(candidate, current) &&
      (current_way == 0 || way < current_way)
    ) {
    scores[score_index] = candidate
    backpointers[backpointer_index] = previous_state * PAIR_STATE_COUNT + way
  }
}

///|
/// Shared global minimum-cost traceback. Equal-cost paths are selected by
/// high-weight exact matches, total exact evidence, changed-run count, gap
/// layout, natural boundaries, and rightmost changed-token placement, then
/// diagonal > insert > delete. Legacy mode zeros the two new tie-break fields
/// and therefore retains the historical byte-for-byte operation sequence.
fn pair_trace(a : WindowStream, b : WindowStream, mode : PairMode) -> PairTrace {
  let m = a.atoms.length()
  let n = b.atoms.length()
  let width = n + 1
  let row_size = width * PAIR_STATE_COUNT
  let impossible = pair_unreachable_score()
  let mut prev = FixedArray::make(row_size, impossible)
  let mut cur = FixedArray::make(row_size, impossible)
  let backpointers = FixedArray::make((m + 1) * width * PAIR_STATE_COUNT, 0)
  prev[pair_row_index(0, PAIR_EQUAL)] = {
    cost: 0,
    high_exact: 0,
    exact: 0,
    runs: 0,
    gap: 0,
    boundary: 0,
    right: 0,
  }
  for j in 1..<(n + 1) {
    for state in 0..<PAIR_STATE_COUNT {
      let source = prev[pair_row_index(j - 1, state)]
      if source.cost == impossible.cost {
        continue
      }
      let candidate = pair_changed_score(
        source,
        state,
        a.atoms,
        b.atoms,
        a.trailing_gap,
        b.trailing_gap,
        mode,
        -1,
        j - 1,
        alignment_weight(b.atoms[j - 1].token),
      )
      let next_state = pair_changed_state(state, false, true)
      pair_consider(
        prev,
        pair_row_index(j, next_state),
        backpointers,
        pair_backpointer_index(0, j, width, next_state),
        candidate,
        state,
        2,
      )
    }
  }
  for i in 1..<(m + 1) {
    cur.fill(impossible)
    for state in 0..<PAIR_STATE_COUNT {
      let source = prev[pair_row_index(0, state)]
      if source.cost == impossible.cost {
        continue
      }
      let candidate = pair_changed_score(
        source,
        state,
        a.atoms,
        b.atoms,
        a.trailing_gap,
        b.trailing_gap,
        mode,
        i - 1,
        -1,
        alignment_weight(a.atoms[i - 1].token),
      )
      let next_state = pair_changed_state(state, true, false)
      pair_consider(
        cur,
        pair_row_index(0, next_state),
        backpointers,
        pair_backpointer_index(i, 0, width, next_state),
        candidate,
        state,
        3,
      )
    }
    for j in 1..<(n + 1) {
      for state in 0..<PAIR_STATE_COUNT {
        let delete_source = prev[pair_row_index(j, state)]
        if delete_source.cost != impossible.cost {
          let candidate = pair_changed_score(
            delete_source,
            state,
            a.atoms,
            b.atoms,
            a.trailing_gap,
            b.trailing_gap,
            mode,
            i - 1,
            -1,
            alignment_weight(a.atoms[i - 1].token),
          )
          let next_state = pair_changed_state(state, true, false)
          pair_consider(
            cur,
            pair_row_index(j, next_state),
            backpointers,
            pair_backpointer_index(i, j, width, next_state),
            candidate,
            state,
            3,
          )
        }
        let insert_source = cur[pair_row_index(j - 1, state)]
        if insert_source.cost != impossible.cost {
          let candidate = pair_changed_score(
            insert_source,
            state,
            a.atoms,
            b.atoms,
            a.trailing_gap,
            b.trailing_gap,
            mode,
            -1,
            j - 1,
            alignment_weight(b.atoms[j - 1].token),
          )
          let next_state = pair_changed_state(state, false, true)
          pair_consider(
            cur,
            pair_row_index(j, next_state),
            backpointers,
            pair_backpointer_index(i, j, width, next_state),
            candidate,
            state,
            2,
          )
        }
        let diagonal_source = prev[pair_row_index(j - 1, state)]
        if diagonal_source.cost != impossible.cost {
          if a.atoms[i - 1].token.kind == b.atoms[j - 1].token.kind &&
            a.atoms[i - 1].token.text == b.atoms[j - 1].token.text {
            let candidate = pair_equal_score(
              diagonal_source,
              state,
              a.atoms,
              b.atoms,
              a.trailing_gap,
              b.trailing_gap,
              mode,
              i - 1,
              j - 1,
            )
            pair_consider(
              cur,
              pair_row_index(j, PAIR_EQUAL),
              backpointers,
              pair_backpointer_index(i, j, width, PAIR_EQUAL),
              candidate,
              state,
              1,
            )
          } else if subst_cost(a.atoms[i - 1].token, b.atoms[j - 1].token)
            is Some(cost) {
            let changed = pair_changed_score(
              diagonal_source,
              state,
              a.atoms,
              b.atoms,
              a.trailing_gap,
              b.trailing_gap,
              mode,
              i - 1,
              j - 1,
              cost,
            )
            let candidate = {
              ..changed,
              gap: changed.gap +
              pair_diagonal_gap_score(mode, a.atoms, b.atoms, i - 1, j - 1),
            }
            let next_state = pair_changed_state(state, true, true)
            pair_consider(
              cur,
              pair_row_index(j, next_state),
              backpointers,
              pair_backpointer_index(i, j, width, next_state),
              candidate,
              state,
              1,
            )
          }
        }
      }
    }
    let tmp = prev
    prev = cur
    cur = tmp
  }
  let mut best_state = PAIR_EQUAL
  let mut best = impossible
  let mut best_way = PAIR_STATE_COUNT
  for state in 0..<PAIR_STATE_COUNT {
    let candidate = pair_finish_score(
      prev[pair_row_index(n, state)],
      state,
      a.atoms,
      b.atoms,
      a.trailing_gap,
      b.trailing_gap,
      mode,
    )
    let way = backpointers[pair_backpointer_index(m, n, width, state)] %
      PAIR_STATE_COUNT
    if pair_score_better(candidate, best) ||
      (pair_score_equal(candidate, best) && way < best_way) {
      best = candidate
      best_state = state
      best_way = way
    }
  }
  let out : Array[PairStep] = []
  let mut i = m
  let mut j = n
  let mut state = best_state
  while i > 0 || j > 0 {
    let pointer = backpointers[pair_backpointer_index(i, j, width, state)]
    let way = pointer % PAIR_STATE_COUNT
    let previous_state = pointer / PAIR_STATE_COUNT
    match way {
      1 => {
        if a.atoms[i - 1].token.kind == b.atoms[j - 1].token.kind &&
          a.atoms[i - 1].token.text == b.atoms[j - 1].token.text {
          out.push(PairEqual(i - 1, j - 1))
        } else {
          out.push(PairSub(i - 1, j - 1))
        }
        i -= 1
        j -= 1
      }
      2 => {
        out.push(PairInsert(j - 1))
        j -= 1
      }
      _ => {
        out.push(PairDelete(i - 1))
        i -= 1
      }
    }
    state = previous_state
  }
  out.rev_in_place()
  { steps: out, score: best }
}

///|
/// Legacy wrapper retained for white-box compatibility and for proving that
/// the shared kernel still reconstructs the minimum-cost per-line script.
fn pair_ops_min(a : ArrayView[Tok], b : ArrayView[Tok]) -> Array[Op] {
  let trace = pair_trace(legacy_pair_stream(a), legacy_pair_stream(b), Legacy)
  trace.steps.map(step => {
    match step {
      PairEqual(old_index, _) => OEq(a[old_index])
      PairSub(old_index, new_index) => OSub(a[old_index], b[new_index])
      PairDelete(old_index) => ODel(a[old_index])
      PairInsert(new_index) => OIns(b[new_index])
    }
  })
}

///|
fn pair_ops(a : Array[Tok], b : Array[Tok]) -> Array[Op] {
  pair_ops_min(a, b)
}

///|
const TRACEBACK_CELL_LIMIT : Int = 262144

///|
/// Division-first limit check avoids overflowing the backend-independent
/// `Int` representation before allocating the traceback matrix.
fn traceback_cells_within_limit(old_atoms : Int, new_atoms : Int) -> Bool {
  if old_atoms < 0 ||
    new_atoms < 0 ||
    old_atoms >= TRACEBACK_CELL_LIMIT ||
    new_atoms >= TRACEBACK_CELL_LIMIT {
    return false
  }
  let old_width = old_atoms + 1
  let new_width = new_atoms + 1
  old_width <= TRACEBACK_CELL_LIMIT / new_width
}

///|
priv struct WindowChanges {
  old_changed : Array[Array[Bool]]
  new_changed : Array[Array[Bool]]
}

///|
fn high_quality_kind(kind : TokKind) -> Bool {
  kind is (Word | Str | Marker)
}

///|
/// Attempt one semantic traceback over the complete replacement window. A
/// result is returned only when cross-line exact evidence, overall weighted
/// similarity, high-quality Dice coverage, and the traceback budget all prove
/// that the global projection is safer than the legacy per-line fallback.
fn window_changes(
  olds : Array[Array[Tok]],
  news : Array[Array[Tok]],
) -> WindowChanges? {
  if olds.length() <= 1 && news.length() <= 1 {
    return None
  }
  let old_stream = window_stream(olds)
  let new_stream = window_stream(news)
  if !traceback_cells_within_limit(
      old_stream.atoms.length(),
      new_stream.atoms.length(),
    ) {
    return None
  }
  let trace = pair_trace(old_stream, new_stream, Window)
  let mut mass = 0
  let mut quality_mass = 0
  for atom in old_stream.atoms {
    let token_weight = alignment_weight(atom.token)
    mass += token_weight
    if high_quality_kind(atom.token.kind) {
      quality_mass += token_weight
    }
  }
  for atom in new_stream.atoms {
    let token_weight = alignment_weight(atom.token)
    mass += token_weight
    if high_quality_kind(atom.token.kind) {
      quality_mass += token_weight
    }
  }
  if mass == 0 || 5 * (mass - trace.score.cost) <= 2 * mass {
    return None
  }
  let mut matched_quality_mass = 0
  let mut crosses_line = false
  for step in trace.steps {
    match step {
      PairEqual(old_index, new_index) => {
        let old_atom = old_stream.atoms[old_index]
        let new_atom = new_stream.atoms[new_index]
        let token_weight = alignment_weight(old_atom.token)
        if token_weight > 0 && old_atom.line != new_atom.line {
          crosses_line = true
        }
        if high_quality_kind(old_atom.token.kind) {
          matched_quality_mass += token_weight
        }
      }
      _ => ()
    }
  }
  if !crosses_line ||
    quality_mass == 0 ||
    10 * matched_quality_mass < 3 * quality_mass {
    return None
  }
  let old_changed = olds.map(tokens => Array::make(tokens.length(), false))
  let new_changed = news.map(tokens => Array::make(tokens.length(), false))
  for step in trace.steps {
    match step {
      PairEqual(_, _) => ()
      PairSub(old_index, new_index) => {
        let old_atom = old_stream.atoms[old_index]
        let new_atom = new_stream.atoms[new_index]
        old_changed[old_atom.line][old_atom.token_index] = true
        new_changed[new_atom.line][new_atom.token_index] = true
      }
      PairDelete(old_index) => {
        let atom = old_stream.atoms[old_index]
        old_changed[atom.line][atom.token_index] = true
      }
      PairInsert(new_index) => {
        let atom = new_stream.atoms[new_index]
        new_changed[atom.line][atom.token_index] = true
      }
    }
  }
  Some({ old_changed, new_changed })
}
