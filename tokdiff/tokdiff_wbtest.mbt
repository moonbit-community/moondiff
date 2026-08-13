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
test "alignment objective is positive margin, not raw similarity" {
  // One strong pair (margin ~510) must beat two above-threshold moderate
  // diagonal pairs (raw-sim total ~1280, margins ~240 each).
  let a = "alpha beta gamma delta epsilon zeta eta theta"
  let y = "alpha beta gamma delta epsilon zeta eta CHANGED"
  let x = "alpha beta gamma delta ONE TWO THREE FOUR"
  let b = "FIVE SIX SEVEN EIGHT epsilon zeta eta CHANGED"
  let olds = [a, b].map(tokenize_line)
  let news = [x, y].map(tokenize_line)
  @debug.debug_inspect(
    align(olds, news),
    content="[(None, Some(0)), (Some(0), Some(1)), (Some(1), None)]",
  )
}

///|
test "unrelated block orders delete before insert" {
  let a = ["aaa bbb ccc"].map(tokenize_line)
  let b = ["xxx yyy zzz"].map(tokenize_line)
  @debug.debug_inspect(
    align(a, b),
    content="[(Some(0), None), (None, Some(0))]",
  )
}

///|
test "comma carries less alignment evidence than structural punctuation" {
  let comma = Tok::{ kind: Punct, text: "," }
  let close = Tok::{ kind: Punct, text: ")" }
  assert_eq(Punct.weight(), 6)
  assert_eq(alignment_weight(comma), 1)
  assert_eq(alignment_weight(close), 6)
  assert_true(similarity("old,", "new,") < THETA)
  assert_true(similarity("old)", "new)") > THETA)
}

///|
test "pair_ops reconstruction property" {
  for
    pair in [
      ("let total = a", "let sum = a"),
      ("f(x, 1) // old note", "g(x, 2) // new note"),
      ("let 名 = \"é😀\"", "let 名 = \"z\""),
      ("", "only new"),
    ] {
    let (oa, ob) = pair
    let left = StringBuilder::new()
    let right = StringBuilder::new()
    for op in pair_ops(tokenize_line(oa), tokenize_line(ob)) {
      match op {
        OEq(t) => {
          left <+ "\{t.text}"
          right <+ "\{t.text}"
        }
        OSub(a, b) => {
          left <+ "\{a.text}"
          right <+ "\{b.text}"
        }
        ODel(a) => left <+ "\{a.text}"
        OIns(b) => right <+ "\{b.text}"
      }
    }
    assert_eq(left.to_string(), oa)
    assert_eq(right.to_string(), ob)
  }
}

///|
test "strong crossing pair beats weak monotone pairs" {
  // The strong pair sits on the anti-diagonal; taking it forbids the weak
  // diagonal pairs. Margin scoring must still prefer it.
  let olds = ["unrelated_one thing here", "let total = price * count"].map(
    tokenize_line,
  )
  let news = ["let total = price * count + tax", "other_stuff entirely now"].map(
    tokenize_line,
  )
  @debug.debug_inspect(
    align(olds, news),
    content="[(Some(0), None), (Some(1), Some(0)), (None, Some(1))]",
  )
}

///|
test "long-line fallback is selected before the recursive lexer and is lossless" {
  let line = "let 名 = " + "value + ".repeat(300) + "😀 < end"
  assert_false(lexer_complexity_within_limit(line))
  assert_eq(fallback_tokenize_line(line).map(t => t.text).join(""), line)
  assert_eq(tokenize_line(line).map(t => t.text).join(""), line)
}

///|
test "long-line fallback preserves marker comments Unicode and empty runs" {
  let line = "///| " + "说明/word  ".repeat(300) + "😀"
  assert_false(lexer_complexity_within_limit(line))
  assert_eq(tokenize_line(line).map(t => t.text).join(""), line)
  assert_true(tokenize_line(line)[0].kind is Marker)

  let punctuation = "(".repeat(2000) + "😀" + ")".repeat(2000)
  assert_false(lexer_complexity_within_limit(punctuation))
  assert_eq(tokenize_line(punctuation).map(t => t.text).join(""), punctuation)

  let interpolation = "\\" + "{value} + "
  let slash_in_string = "let url = \"https://example.test/" +
    interpolation.repeat(300) +
    "\""
  assert_false(lexer_complexity_within_limit(slash_in_string))
  assert_eq(
    tokenize_line(slash_in_string).map(t => t.text).join(""),
    slash_in_string,
  )
}

///|
test "fallback tokens still feed the existing alignment budgets" {
  let old = "word + ".repeat(600) + "old"
  let new = "word + ".repeat(600) + "new"
  let old_tokens = tokenize_line(old)
  let new_tokens = tokenize_line(new)
  assert_true(old_tokens.length() > 1024)
  assert_true(new_tokens.length() > 1024)
  assert_true(alignment_tokens([old], [new], line => line) is None)
}

///|
fn diff_segment_signature(segments : ArrayView[DiffSegment]) -> String {
  let buf = StringBuilder::new()
  for segment in segments {
    match segment.kind {
      Unchanged => buf <+ "U[\{segment.text}]"
      Changed => buf <+ "C[\{segment.text}]"
    }
  }
  buf.to_string()
}

///|
test "pair calculation trims whitespace at every changed-run boundary" {
  let space = Tok::{ kind: Space, text: " " }
  let old = Tok::{ kind: Word, text: "old" }
  let new = Tok::{ kind: Word, text: "new" }
  let (both_left, both_right) = pair_row_segments([
    OSub(space, space),
    OSub(old, new),
    OSub(space, space),
  ])
  assert_eq(diff_segment_signature(both_left), "U[ ]C[old]U[ ]")
  assert_eq(diff_segment_signature(both_right), "U[ ]C[new]U[ ]")

  let (before, _) = pair_row_segments([ODel(space), ODel(old)])
  assert_eq(diff_segment_signature(before), "U[ ]C[old]")
  let (after, _) = pair_row_segments([ODel(old), ODel(space)])
  assert_eq(diff_segment_signature(after), "C[old]U[ ]")
}

///|
test "pair calculation uses token text and trims each side independently" {
  let (left, right) = pair_row_segments([
    OSub({ kind: Filler, text: "\t" }, { kind: Word, text: "new" }),
    OSub({ kind: Word, text: "old" }, { kind: Filler, text: " " }),
  ])
  assert_eq(diff_segment_signature(left), "U[\t]C[old]")
  assert_eq(diff_segment_signature(right), "C[new]U[ ]")

  let (_, internal) = pair_row_segments([
    OIns({ kind: Word, text: "a" }),
    OIns({ kind: Space, text: " " }),
    OIns({ kind: Punct, text: ":" }),
    OIns({ kind: Filler, text: " " }),
    OIns({ kind: Word, text: "Int" }),
  ])
  assert_eq(diff_segment_signature(internal), "C[a : Int]")

  let (plain, _) = pair_row_segments([
    ODel({ kind: Space, text: " " }),
    ODel({ kind: Filler, text: "\t" }),
  ])
  assert_eq(diff_segment_signature(plain), "U[ \t]")

  let (_, comment) = pair_row_segments([
    OIns({ kind: Filler, text: "//" }),
    OIns({ kind: Filler, text: " " }),
    OIns({ kind: Comment, text: "word" }),
    OIns({ kind: Filler, text: " " }),
  ])
  assert_eq(diff_segment_signature(comment), "C[// word]U[ ]")
}

///|
test "full-line calculation trims whitespace and skips empty emphasis" {
  assert_eq(
    diff_segment_signature(
      full_line_segments(tokenize_line(" \t<old & gone>  ")),
    ),
    "U[ \t]C[<old & gone>]U[  ]",
  )
  assert_eq(
    diff_segment_signature(
      full_line_segments(tokenize_line("\tnew & <value> ")),
    ),
    "U[\t]C[new & <value>]U[ ]",
  )
  assert_eq(
    diff_segment_signature(full_line_segments(tokenize_line(" \t  "))),
    "U[ \t  ]",
  )
  assert_eq(diff_segment_signature(full_line_segments(tokenize_line(""))), "")
}
