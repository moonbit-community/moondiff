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

///|
fn window_changed_text(
  tokens : ArrayView[Tok],
  changed : ArrayView[Bool],
) -> String {
  let out : Array[String] = []
  for index, token in tokens {
    if changed[index] {
      out.push(token.text)
    }
  }
  out.join("")
}

///|
fn pair_step_signature(steps : ArrayView[PairStep]) -> String {
  steps
  .map(step => {
    match step {
      PairEqual(old_index, new_index) => "=\{old_index}:\{new_index}"
      PairSub(old_index, new_index) => "~\{old_index}:\{new_index}"
      PairDelete(old_index) => "-\{old_index}"
      PairInsert(new_index) => "+\{new_index}"
    }
  })
  .join("|")
}

///|
fn reconstruct_window(stream : WindowStream) -> String {
  let out = StringBuilder::new()
  for atom in stream.atoms {
    out <+ "\{atom.gap_before}\{atom.token.text}"
  }
  out <+ "\{stream.trailing_gap}"
  out.to_string()
}

///|
test "window stream preserves gaps empty lines trailing space and positions" {
  let lines = ["  alpha  ", "", "\tbeta "].map(tokenize_line)
  let stream = window_stream(lines)
  assert_eq(stream.atoms.length(), 2)
  assert_eq(stream.atoms[0].token.text, "alpha")
  assert_eq(stream.atoms[0].line, 0)
  assert_eq(stream.atoms[0].token_index, 1)
  assert_eq(stream.atoms[0].gap_before, "  ")
  assert_eq(stream.atoms[1].token.text, "beta")
  assert_eq(stream.atoms[1].line, 2)
  assert_eq(stream.atoms[1].token_index, 1)
  assert_eq(stream.atoms[1].gap_before, "  \n\n\t")
  assert_eq(stream.trailing_gap, " ")
  assert_eq(reconstruct_window(stream), "  alpha  \n\n\tbeta ")

  let touching = window_stream(["a+b", "c"].map(tokenize_line))
  assert_eq(touching.atoms[0].gap_before, "")
  assert_eq(touching.atoms[1].gap_before, "")
  assert_eq(touching.atoms[2].gap_before, "")
  assert_eq(touching.atoms[3].gap_before, "\n")
  assert_eq(touching.trailing_gap, "")

  let trailing_empty = window_stream(["x", ""].map(tokenize_line))
  assert_eq(trailing_empty.trailing_gap, "\n")
  assert_eq(reconstruct_window(trailing_empty), "x\n")
}

///|
test "window stream keeps every non-Space token as a real atom" {
  let stream = window_stream(["\"a b\", x // note"].map(tokenize_line))
  assert_true(stream.atoms[0].token.kind is Str)
  assert_true(stream.atoms[1].token.kind is Punct)
  assert_true(stream.atoms[2].token.kind is Word)
  assert_true(stream.atoms[3].token.kind is Filler)
  assert_true(stream.atoms[4].token.kind is Filler)
  assert_true(stream.atoms[5].token.kind is Comment)
  assert_eq(stream.atoms[2].gap_before, " ")
  assert_eq(stream.atoms[3].gap_before, " ")
  assert_eq(stream.atoms[4].gap_before, "")
  assert_eq(reconstruct_window(stream), "\"a b\", x // note")
}

///|
test "gap classification and layout evidence follow the priority table" {
  assert_true(gap_kind("") is Empty)
  assert_true(gap_kind(" \t") is Horizontal)
  assert_true(gap_kind("  \n\t") is Multiline)
  assert_eq(gap_layout_score(" ", " "), 2)
  assert_eq(gap_layout_score(" ", "\t"), 1)
  assert_eq(gap_layout_score("\n", " \n"), 1)
  assert_eq(gap_layout_score("", " "), 0)

  let same = pair_trace(
    window_stream(["x "].map(tokenize_line)),
    window_stream(["x "].map(tokenize_line)),
    Window,
  )
  let same_class = pair_trace(
    window_stream(["x "].map(tokenize_line)),
    window_stream(["x\t"].map(tokenize_line)),
    Window,
  )
  assert_eq(same.score.gap, 4)
  assert_eq(same_class.score.gap, 3)
}

///|
test "pure one-to-many reflow projects every real token as unchanged" {
  let olds = ["call(alpha, beta, gamma)"].map(tokenize_line)
  let news = ["call(", "  alpha, beta,", "  gamma)"].map(tokenize_line)
  guard window_changes(olds, news) is Some(changes) else {
    fail("expected the cross-line traceback to be accepted")
  }
  assert_false(changes.old_changed.any(row => row.contains(true)))
  assert_false(changes.new_changed.any(row => row.contains(true)))
}

///|
test "formatted multiline call isolates the new trailing comma" {
  let olds = ["call(alpha, beta, gamma)"].map(tokenize_line)
  let news = ["call(", "  alpha,", "  beta,", "  gamma,", ")"].map(
    tokenize_line,
  )
  guard window_changes(olds, news) is Some(changes) else {
    fail("expected the formatted cross-line traceback to be accepted")
  }
  assert_false(changes.old_changed.any(row => row.contains(true)))
  let changed_text : Array[String] = []
  for index, tokens in news {
    changed_text.push(window_changed_text(tokens, changes.new_changed[index]))
  }
  assert_eq(changed_text, ["", "", "", ",", ""])
}

///|
test "expanded reflow changes only inserted semantic tokens and commas" {
  let olds = ["compute(alpha, beta)"].map(tokenize_line)
  let news = ["compute(", "  alpha,", "  beta,", "  gamma < limit,", ")"].map(
    tokenize_line,
  )
  guard window_changes(olds, news) is Some(changes) else {
    fail("expected the expanded cross-line traceback to be accepted")
  }
  assert_false(changes.old_changed.any(row => row.contains(true)))
  assert_eq(window_changed_text(news[0], changes.new_changed[0]), "")
  assert_eq(window_changed_text(news[1], changes.new_changed[1]), "")
  assert_eq(window_changed_text(news[2], changes.new_changed[2]), ",")
  assert_eq(
    window_changed_text(news[3], changes.new_changed[3]),
    "gamma<limit,",
  )
  assert_eq(window_changed_text(news[4], changes.new_changed[4]), "")
}

///|
test "repeated tokens use gap evidence for a stable window traceback" {
  let old_stream = window_stream(["x x", "x"].map(tokenize_line))
  let new_stream = window_stream(["x", "x"].map(tokenize_line))
  let first = pair_trace(old_stream, new_stream, Window)
  let second = pair_trace(old_stream, new_stream, Window)
  assert_eq(pair_step_signature(first.steps), "=0:0|-1|=2:1")
  assert_eq(pair_step_signature(second.steps), pair_step_signature(first.steps))
}

///|
test "newline gaps split changed runs in the shared traceback" {
  let trace = pair_trace(
    window_stream(["old", "old"].map(tokenize_line)),
    window_stream(["new", "new"].map(tokenize_line)),
    Window,
  )
  assert_eq(trace.score.runs, 2)

  let old_stream = window_stream(["first", "second"].map(tokenize_line))
  let new_stream = window_stream(["new"].map(tokenize_line))
  let prior : PairScore = {
    cost: 0,
    high_exact: 0,
    exact: 0,
    runs: 1,
    gap: 0,
    boundary: 0,
    right: 0,
  }
  let next = pair_changed_score(
    prior,
    PAIR_NEW_CHANGED,
    old_stream.atoms,
    new_stream.atoms,
    old_stream.trailing_gap,
    new_stream.trailing_gap,
    Window,
    1,
    -1,
    20,
  )
  assert_eq(next.runs, 2)
}

///|
test "window acceptance rejects weak exact coverage and unsafe cell counts" {
  let olds = ["common(alpha)", "other(beta)"].map(tokenize_line)
  let news = ["prefix(gamma)", "common(delta)", "other(epsilon)"].map(
    tokenize_line,
  )
  assert_true(window_changes(olds, news) is None)

  let fully_renamed_old = ["alpha(beta)", "gamma(delta)"].map(tokenize_line)
  let fully_renamed_new = ["one(two)", "three(four)", "five(six)"].map(
    tokenize_line,
  )
  assert_true(window_changes(fully_renamed_old, fully_renamed_new) is None)

  let same_lines = ["same(alpha)", "old(beta)"].map(tokenize_line)
  let same_positions = ["same(alpha)", "new(beta)"].map(tokenize_line)
  assert_true(window_changes(same_lines, same_positions) is None)

  assert_true(traceback_cells_within_limit(511, 511))
  assert_false(traceback_cells_within_limit(512, 512))
  assert_true(traceback_cells_within_limit(TRACEBACK_CELL_LIMIT - 1, 0))
  assert_false(traceback_cells_within_limit(TRACEBACK_CELL_LIMIT, 0))
}

///|
test "unpaired-line highlighting fixture reaches the rejected window path" {
  let old = ["let total = price", "unrelated old"]
  let new = ["let sum = price", "different new"]
  guard alignment_tokens(old, new, line => line) is Some(tokens) else {
    fail("expected line alignment to stay within its budgets")
  }
  assert_true(window_changes(tokens.olds, tokens.news) is None)
}
