///|
test "ignore comments defaults off and removes comment-only hunks" {
  let old = ["fn value() -> Int {", "  1 // old", "}"]
  let new = ["fn value() -> Int {", "  1  // new", "}"]
  assert_true(
    @tokdiff.diff(old~, new~) ==
    @tokdiff.diff(old~, new~, ignore_comments=false),
  )
  assert_false(@tokdiff.diff(old~, new~).hunks.is_empty())
  assert_true(@tokdiff.diff(old~, new~, ignore_comments=true).hunks.is_empty())

  for
    pair in [
      (["// old"], ["// new"]),
      (["/// old docs"], ["/// new docs"]),
      (["///|"], []),
      ([], ["///|"]),
      (["///|UUID(old)"], ["///|UUID(new)"]),
      (["fn f() {}"], ["// inserted", "fn f() {}"]),
      (["// deleted", "fn f() {}"], ["fn f() {}"]),
    ] {
    let (before, after) = pair
    assert_true(
      @tokdiff.diff(old=before, new=after, ignore_comments=true).hunks.is_empty(),
    )
  }
}

///|
test "ignore comments keeps string slashes and real code changes" {
  let string_change = @tokdiff.diff(
    old=["let value = \"//old\""],
    new=["let value = \"//new\""],
    context=0,
    ignore_comments=true,
  )
  assert_false(string_change.hunks.is_empty())

  let code_change = @tokdiff.diff(
    old=["let value = old() // old explanation"],
    new=["let value = new()  // new explanation"],
    context=0,
    ignore_comments=true,
  )
  guard code_change.hunks
    is [{ blocks: [ChangeBlock([Paired(old_line, new_line)])], .. }] else {
    fail("expected one paired code change")
  }
  assert_true(old_line.segments.last().unwrap().kind is Ignored)
  assert_true(new_line.segments.last().unwrap().kind is Ignored)
  assert_eq(old_line.text(), "let value = old() // old explanation")
  assert_eq(new_line.text(), "let value = new()  // new explanation")
}

///|
test "long-line safety path keeps slashes inside strings as code" {
  let prefix = "piece + ".repeat(300)
  let old = "let value = \"\{prefix}//inside\" // old comment"
  let new_comment = "let value = \"\{prefix}//inside\" // new comment"
  assert_true(
    @tokdiff.diff(old=[old], new=[new_comment], ignore_comments=true).hunks.is_empty(),
  )
  let changed = "let value = \"\{prefix}//changed\" // new comment"
  assert_false(
    @tokdiff.diff(old=[old], new=[changed], ignore_comments=true).hunks.is_empty(),
  )
}

///|
test "ignored comments render as neutral context beside a code change" {
  let document = @tokdiff.diff(
    old=["// old docs", "let value = old() // old trailing"],
    new=["// new docs", "let value = new() // new trailing"],
    context=1,
    ignore_comments=true,
  )
  guard document.hunks
    is [
      {
        blocks: [IgnoredBlock([Paired(_, _)]), ChangeBlock([Paired(_, _)])],
        ..,
      },
    ] else {
    fail("expected neutral comment context followed by a code change")
  }
  let split = @tokdiff_html.render_side_by_side(document, line_numbers=true)
  assert_true(
    split.contains(
      "class=\"ctx ignored\"><span class=\"ignored-context\">// old docs</span>",
    ),
  )
  assert_false(split.contains("class=\"del\"><b class=\"wd\">// old docs"))
  assert_true(split.contains("<b class=\"wd\">old</b>"))
  assert_true(split.contains("<b class=\"wa\">new</b>"))
  assert_true(
    split.contains("<span class=\"ignored-context\"> // old trailing</span>"),
  )

  let patch = @tokdiff_text.render_unified_hunks(document).join("")
  assert_true(patch.contains(" // old docs\n // new docs\n"))
  assert_true(patch.contains("-let value = old() // old trailing"))
  assert_true(patch.contains("+let value = new() // new trailing"))
}

///|
test "ignored comment lines do not split code hunks" {
  let document = @tokdiff.diff(
    old=["let first = 1", "// old bridge", "let second = 1"],
    new=["let first = 2", "// new bridge", "let second = 2"],
    context=0,
    ignore_comments=true,
  )
  guard document.hunks
    is [
      {
        old_start: 0,
        old_len: 3,
        new_start: 0,
        new_len: 3,
        blocks: [
          ChangeBlock([Paired(first_old, first_new)]),
          IgnoredBlock([Paired(old_comment, new_comment)]),
          ChangeBlock([Paired(second_old, second_new)]),
        ],
      },
    ] else {
    fail("expected one code-driven hunk with neutral comment context")
  }
  assert_eq(old_comment.index, 1)
  assert_eq(new_comment.index, 1)
  assert_eq(old_comment.text(), "// old bridge")
  assert_eq(new_comment.text(), "// new bridge")
  assert_eq(
    (first_old.text(), first_new.text()),
    ("let first = 1", "let first = 2"),
  )
  assert_eq(
    (second_old.text(), second_new.text()),
    ("let second = 1", "let second = 2"),
  )
}

///|
test "ignore comments also ignores empty and Unicode whitespace-only lines" {
  for blank in ["", "   ", "\t", "\u{a0}\u{2003}\u{3000}"] {
    assert_false(@tokdiff.diff(old=[], new=[blank]).hunks.is_empty())
    assert_true(
      @tokdiff.diff(old=[], new=[blank], ignore_comments=true).hunks.is_empty(),
    )
  }

  assert_true(
    @tokdiff.diff(
      old=["fn stable() {}", "", "\t", "\u{2003}"],
      new=["fn stable() {}", "  "],
      ignore_comments=true,
    ).hunks.is_empty(),
  )
  assert_true(
    @tokdiff.diff(
      old=["fn stable() {}"],
      new=["fn stable() {}", ""],
      ignore_comments=true,
    ).hunks.is_empty(),
  )
  assert_true(
    @tokdiff.diff(
      old=["fn stable() {}", "\u{2003}"],
      new=["fn stable() {}", "// explanation"],
      ignore_comments=true,
    ).hunks.is_empty(),
  )
}

///|
test "ignore comments retains trailing whitespace on code lines" {
  let document = @tokdiff.diff(
    old=["let value = 1"],
    new=["let value = 1\t"],
    ignore_comments=true,
  )
  assert_false(document.hunks.is_empty())
}

///|
test "blank lines beside code changes are neutral source-faithful context" {
  let document = @tokdiff.diff(
    old=["fn value() {", "  old()", "", "\t", "}"],
    new=["fn value() {", "  new()", "  ", "}"],
    context=0,
    ignore_comments=true,
  )
  guard document.hunks
    is [
      {
        old_start: 1,
        old_len: 3,
        new_start: 1,
        new_len: 2,
        blocks: [
          ChangeBlock([Paired(_, _)]),
          IgnoredBlock([Paired(old_empty, new_spaces), OldOnly(old_tab)]),
        ],
      },
    ] else {
    fail("expected changed code followed by neutral blank-line context")
  }
  assert_eq((old_empty.index, old_empty.text()), (2, ""))
  assert_eq((new_spaces.index, new_spaces.text()), (2, "  "))
  assert_eq((old_tab.index, old_tab.text()), (3, "\t"))
  assert_true(new_spaces.segments.all(segment => segment.kind is Ignored))
  assert_true(old_tab.segments.all(segment => segment.kind is Ignored))

  let split = @tokdiff_html.render_side_by_side(document, line_numbers=true)
  assert_true(split.contains("class=\"ctx ignored\""), msg=split)
  assert_false(split.contains("class=\"del\"><span class=\"ignored-context\">"))
  assert_false(split.contains("class=\"add\"><span class=\"ignored-context\">"))

  let unified = @tokdiff_html.render_unified(document, line_numbers=true)
  assert_true(unified.contains("class=\"ctx ignored\""), msg=unified)
  assert_false(
    unified.contains("class=\"del\"><span class=\"ignored-context\">"),
  )
  assert_false(
    unified.contains("class=\"add\"><span class=\"ignored-context\">"),
  )

  let patch = @tokdiff_text.render_unified_hunks(document).join("")
  assert_true(patch.contains("-  old()\n+  new()\n \n   \n \t\n"), msg=patch)
}

///|
test "plain line diff still reports blank-line changes" {
  assert_false(
    @tokdiff.line_diff(old=["plain text"], new=["plain text", ""]).hunks.is_empty(),
  )
  assert_false(@tokdiff.line_diff(old=[], new=["\u{2003}"]).hunks.is_empty())
}
