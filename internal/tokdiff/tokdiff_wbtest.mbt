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
    let left = StringBuilder()
    let right = StringBuilder()
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
  let buf = StringBuilder()
  for segment in segments {
    match segment.kind {
      Unchanged => buf <+ "U[\{segment.text}]"
      Changed => buf <+ "C[\{segment.text}]"
      Ignored => buf <+ "I[\{segment.text}]"
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

///|
fn fallback_pairs(document : HunkDocument) -> Array[(DiffLine, DiffLine)] {
  let pairs = []
  for hunk in document.hunks {
    for block in hunk.blocks {
      match block {
        ChangeBlock(rows) =>
          for row in rows {
            if row is Paired(old_line, new_line) {
              pairs.push((old_line, new_line))
            }
          }
        ContextBlock(_) | IgnoredBlock(_) => ()
      }
    }
  }
  pairs
}

///|
fn fallback_line_is_refined(line : DiffLine) -> Bool {
  line.segments.any(segment => segment.kind is Changed)
}

///|
test "word fallback budget is shared across semantic hunks" {
  let first_old = "word ".repeat(600) + "old"
  let first_new = "word ".repeat(600) + "new"
  let second_old = "word ".repeat(600) + "gone"
  let second_new = "word ".repeat(600) + "added"
  let old = [first_old, "same one", "same two", "same three", second_old]
  let new = [first_new, "same one", "same two", "same three", second_new]
  let limited = diff_with_refinement_budget(
    old,
    new,
    0,
    false,
    false,
    @worddiff.RefinementBudget::new(
      line_character_limit=4_000,
      character_limit=13_000,
      token_limit=2_402,
    ),
  )
  let abundant = diff_with_refinement_budget(
    old,
    new,
    0,
    false,
    false,
    @worddiff.RefinementBudget::new(
      line_character_limit=4_000,
      character_limit=13_000,
      token_limit=4_804,
    ),
  )
  guard limited.hunks is [first_hunk, second_hunk] else {
    fail("expected two separated semantic hunks")
  }
  assert_eq(
    (
      first_hunk.old_start,
      first_hunk.old_len,
      first_hunk.new_start,
      first_hunk.new_len,
    ),
    (0, 1, 0, 1),
  )
  assert_eq(
    (
      second_hunk.old_start,
      second_hunk.old_len,
      second_hunk.new_start,
      second_hunk.new_len,
    ),
    (4, 1, 4, 1),
  )
  guard fallback_pairs(limited)
    is [(first_old_line, first_new_line), (second_old_line, second_new_line)] else {
    fail("expected one fallback pair in each semantic hunk")
  }
  assert_true(
    fallback_line_is_refined(first_old_line) &&
    fallback_line_is_refined(first_new_line),
  )
  assert_false(
    fallback_line_is_refined(second_old_line) ||
    fallback_line_is_refined(second_new_line),
  )
  assert_eq((first_old_line.index, first_new_line.index), (0, 0))
  assert_eq((second_old_line.index, second_new_line.index), (4, 4))
  assert_eq(
    (first_old_line.text(), first_new_line.text()),
    (first_old, first_new),
  )
  assert_eq(
    (second_old_line.text(), second_new_line.text()),
    (second_old, second_new),
  )
  assert_eq(
    @unified.render_unified_hunks(limited),
    @unified.render_unified_hunks(abundant),
  )
}

///|
test "traceback fallback becomes plain when its shared token budget is empty" {
  let old_line = "x ".repeat(256) + "old"
  let new_line = "x ".repeat(256) + "new"
  let limited = diff_with_refinement_budget(
    [old_line],
    [new_line],
    0,
    false,
    false,
    @worddiff.RefinementBudget::new(
      line_character_limit=600,
      character_limit=1_100,
      token_limit=0,
    ),
  )
  let exact = diff_with_refinement_budget(
    [old_line],
    [new_line],
    0,
    false,
    false,
    @worddiff.RefinementBudget::new(
      line_character_limit=600,
      character_limit=1_030,
      token_limit=1_026,
    ),
  )
  guard fallback_pairs(limited) is [(plain_old, plain_new)] &&
    fallback_pairs(exact) is [(refined_old, refined_new)] else {
    fail("expected one paired traceback fallback")
  }
  assert_false(
    fallback_line_is_refined(plain_old) || fallback_line_is_refined(plain_new),
  )
  assert_true(
    fallback_line_is_refined(refined_old) &&
    fallback_line_is_refined(refined_new),
  )
  assert_eq((plain_old.text(), plain_new.text()), (old_line, new_line))
  assert_eq(
    @unified.render_unified_hunks(limited),
    @unified.render_unified_hunks(exact),
  )
}
