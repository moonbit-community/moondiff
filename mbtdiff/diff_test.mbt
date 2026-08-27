///|
fn document_has_changed_segment_containing(
  document : @mbtdiff.DiffDocument,
  expected : String,
) -> Bool {
  for hunk in document.hunks {
    for block in hunk.blocks {
      guard block is ChangeBlock(rows) else { continue }
      for row in rows {
        let lines = match row {
          Paired(old_line, new_line) => [old_line, new_line]
          OldOnly(line) | NewOnly(line) => [line]
        }
        for line in lines {
          for segment in line.segments {
            if segment.kind is Changed && segment.text.contains(expected) {
              return true
            }
          }
        }
      }
    }
  }
  false
}

///|
test "public status contract" {
  let identical = @mbtdiff.diff("fn broken(", "fn broken(")
  assert_true(identical.status() is Identical)
  assert_true(identical.fallbacks().is_empty())
  assert_true(identical.document().hunks.is_empty())

  let formatting = @mbtdiff.diff("fn f() { 1 }", "fn f() {\n  1\n}")
  assert_true(formatting.status() is NoStructuralChanges)
  assert_true(formatting.document().hunks.is_empty())

  let changed = @mbtdiff.diff("fn f() { 1 }", "fn f() { 2 }")
  assert_true(changed.status() is Changed)
  assert_false(changed.document().hunks.is_empty())

  let ignored = @mbtdiff.diff(
    "fn f() { 1 // old\n}",
    "fn f() { 1 // new\n}",
    options=DiffOptions(ignore_comments=true),
  )
  assert_true(ignored.status() is IgnoredOnly)
  assert_true(ignored.document().hunks.is_empty())

  let ignored_tests = @mbtdiff.diff(
    "test \"sample\" { old_value() }",
    "test \"sample\" { new_value() }",
    options=DiffOptions(ignore_tests=true),
  )
  assert_true(ignored_tests.status() is IgnoredOnly)
  assert_true(ignored_tests.document().hunks.is_empty())

  let tests_default = @mbtdiff.diff(
    "test \"sample\" { old_value() }", "test \"sample\" { new_value() }",
  )
  assert_true(tests_default.status() is Changed)
  assert_false(tests_default.document().hunks.is_empty())
}

///|
test "default and explicit AST modes are compatible" {
  let old_source = "fn f() { old_value() }"
  let new_source = "fn f() { new_value() }"
  let default_result = @mbtdiff.diff(old_source, new_source)
  let explicit_result = @mbtdiff.diff(
    old_source,
    new_source,
    options=DiffOptions(mode=@mbtdiff.DiffMode::Ast),
  )
  assert_true(default_result.status() == explicit_result.status())
  assert_true(default_result.document() == explicit_result.document())
  assert_true(default_result.fallbacks() == explicit_result.fallbacks())
  assert_true(default_result.layout() == explicit_result.layout())
}

///|
test "public result retains layout and source labels in parse diagnostics" {
  let sectioned = @mbtdiff.diff(
    "fn first() { old_value() }\nfn second() {}", "fn first() { new_value() }\nfn second() {}",
  )
  guard sectioned.layout() is TopLevelSections(sections) else {
    fail("expected a sectioned structural layout")
  }
  let _ : ArrayView[@mbtdiff.DiffSection] = sections
  assert_false(sections.is_empty())

  let parsed = @mbtdiff.diff(
    "fn broken( {",
    "fn okay() {}",
    old_name="before.mbt",
    new_name="after.mbt",
  )
  guard parsed.fallbacks()
    is [{ reason: ParseError(detail~, ..), scope: WholeFile }] else {
    fail("expected a parse fallback")
  }
  assert_true(detail.contains("before.mbt"), msg=detail)
}

///|
test "lexical mode renders text changes and ignores the graph limit" {
  let old_source = "fn format() { 1 }"
  let new_source = "fn format() {\n  1\n}"
  let lexical = @mbtdiff.diff(
    old_source,
    new_source,
    options=DiffOptions(graph_limit=0, mode=@mbtdiff.DiffMode::Lexical),
  )
  assert_true(lexical.status() is Changed)
  assert_false(lexical.document().hunks.is_empty())
  assert_true(lexical.fallbacks().is_empty())

  let normal_limit = @mbtdiff.diff(
    old_source,
    new_source,
    options=DiffOptions(mode=@mbtdiff.DiffMode::Lexical),
  )
  assert_true(lexical.document() == normal_limit.document())
}

///|
test "lexical mode exposes reordering and parse fallbacks" {
  let reordered = @mbtdiff.diff(
    "fn first() {}\nfn second() {}",
    "fn second() {}\nfn first() {}",
    options=DiffOptions(mode=@mbtdiff.DiffMode::Lexical),
  )
  assert_true(reordered.status() is Changed)
  assert_false(reordered.document().hunks.is_empty())
  assert_true(
    reordered.fallbacks() is [{ reason: TopLevelReordering, scope: WholeFile }],
  )

  let parsed = @mbtdiff.diff(
    "fn broken( {",
    "fn okay() {}",
    options=DiffOptions(mode=@mbtdiff.DiffMode::Lexical),
  )
  assert_true(
    parsed.fallbacks()
    is [{ reason: ParseError(sides=[Old], ..), scope: WholeFile }],
  )
}

///|
test "lexical mode preserves identical and filtering statuses" {
  let options = @mbtdiff.DiffOptions(mode=@mbtdiff.DiffMode::Lexical)
  let identical = @mbtdiff.diff("fn stable() {}", "fn stable() {}", options~)
  assert_true(identical.status() is Identical)
  assert_true(identical.document().hunks.is_empty())
  assert_true(identical.fallbacks().is_empty())

  let comments = @mbtdiff.diff(
    "fn f() { 1 // old\n}",
    "fn f() { 1 // new\n}",
    options=DiffOptions(ignore_comments=true, mode=@mbtdiff.DiffMode::Lexical),
  )
  assert_true(comments.status() is IgnoredOnly)
  assert_true(comments.document().hunks.is_empty())

  let tests = @mbtdiff.diff(
    "test \"sample\" { old_value() }",
    "test \"sample\" { new_value() }",
    options=DiffOptions(ignore_tests=true, mode=@mbtdiff.DiffMode::Lexical),
  )
  assert_true(tests.status() is IgnoredOnly)
  assert_true(tests.document().hunks.is_empty())
}

///|
test "public test filtering composes and keeps production changes" {
  let old_source =
    #|/// old docs
    #|fn production() { old_value() }
    #|test "sample" { old_test() }
  let new_source =
    #|/// new docs
    #|fn production() { new_value() }
    #|test "sample" { new_test() }
  let result = @mbtdiff.diff(
    old_source,
    new_source,
    options=DiffOptions(ignore_comments=true, ignore_tests=true),
  )
  assert_true(result.status() is Changed)
  assert_true(
    document_has_changed_segment_containing(result.document(), "old_value"),
  )
  assert_true(
    document_has_changed_segment_containing(result.document(), "new_value"),
  )
  assert_false(
    document_has_changed_segment_containing(result.document(), "old_test"),
  )
  assert_false(
    document_has_changed_segment_containing(result.document(), "new_test"),
  )
}

///|
test "AST diff always bridges internal whitespace in inserted and deleted units" {
  let stable = "fn stable() {}"
  let added = "fn inserted() { let total = 1 }"
  let with_insertion = "\{stable}\n\{added}"
  for ignore_comments in [false, true] {
    let options = @mbtdiff.DiffOptions(ignore_comments~)
    let inserted = @mbtdiff.diff(stable, with_insertion, options~)
    assert_true(inserted.status() is Changed)
    assert_true(
      document_has_changed_segment_containing(inserted.document(), "let total"),
      msg="inserted AST whitespace was not bridged when ignore_comments=\{ignore_comments}",
    )

    let deleted = @mbtdiff.diff(with_insertion, stable, options~)
    assert_true(deleted.status() is Changed)
    assert_true(
      document_has_changed_segment_containing(deleted.document(), "let total"),
      msg="deleted AST whitespace was not bridged when ignore_comments=\{ignore_comments}",
    )
  }
}

///|
fn one_sided_line_indexes(
  document : @mbtdiff.DiffDocument,
) -> (Array[Int], Array[Int]) {
  let old_indexes : Array[Int] = []
  let new_indexes : Array[Int] = []
  for hunk in document.hunks {
    for block in hunk.blocks {
      guard block is ChangeBlock(rows) else { continue }
      for row in rows {
        match row {
          Paired(old_line, new_line) => {
            old_indexes.push(old_line.index)
            new_indexes.push(new_line.index)
          }
          OldOnly(line) => old_indexes.push(line.index)
          NewOnly(line) => new_indexes.push(line.index)
        }
      }
    }
  }
  (old_indexes, new_indexes)
}

///|
test "top-level one-sided edits keep source cursors in lexical and AST modes" {
  let first = "fn first() {}"
  let middle = "fn middle() {}"
  let last = "fn last() {}"
  let without_middle = "\{first}\n\{last}"
  let with_middle = "\{first}\n\{middle}\n\{last}"
  let cases : Array[
    (
      String,
      String,
      String,
      (Int, Int, Int, Int),
      String,
      Array[Int],
      Array[Int],
    ),
  ] = [
    (
      "insert at start",
      without_middle,
      "\{middle}\n\{without_middle}",
      (0, 0, 0, 1),
      "@@ -0,0 +1 @@",
      [],
      [0],
    ),
    (
      "delete at start",
      "\{middle}\n\{without_middle}",
      without_middle,
      (0, 1, 0, 0),
      "@@ -1 +0,0 @@",
      [0],
      [],
    ),
    (
      "insert in middle",
      without_middle,
      with_middle,
      (1, 0, 1, 1),
      "@@ -1,0 +2 @@",
      [],
      [1],
    ),
    (
      "delete in middle",
      with_middle,
      without_middle,
      (1, 1, 1, 0),
      "@@ -2 +1,0 @@",
      [1],
      [],
    ),
    (
      "insert at end",
      without_middle,
      "\{without_middle}\n\{middle}",
      (2, 0, 2, 1),
      "@@ -2,0 +3 @@",
      [],
      [2],
    ),
    (
      "delete at end",
      "\{without_middle}\n\{middle}",
      without_middle,
      (2, 1, 2, 0),
      "@@ -3 +2,0 @@",
      [2],
      [],
    ),
  ]
  for mode in [@mbtdiff.DiffMode::Lexical, Ast] {
    for case in cases {
      let (
        name,
        old_source,
        new_source,
        expected_range,
        expected_header,
        expected_old_indexes,
        expected_new_indexes,
      ) = case
      let result = @mbtdiff.diff(
        old_source,
        new_source,
        options=DiffOptions(context_lines=0, mode~),
      )
      assert_true(result.fallbacks().is_empty(), msg=name)
      assert_eq(result.document().hunks.length(), 1)
      let hunk = result.document().hunks[0]
      assert_true(
        (hunk.old_start, hunk.old_len, hunk.new_start, hunk.new_len) ==
        expected_range,
        msg=name,
      )
      let (old_indexes, new_indexes) = one_sided_line_indexes(result.document())
      assert_true(old_indexes == expected_old_indexes, msg=name)
      assert_true(new_indexes == expected_new_indexes, msg=name)
      let patch = @unified.render_unified_hunks(result.document()).join("")
      assert_true(patch.has_prefix("\{expected_header}\n"), msg=name)
    }
  }
}

///|
test "parse and graph fallbacks are typed" {
  let parsed = @mbtdiff.diff("fn broken( {", "fn okay() {}")
  guard parsed.fallbacks()
    is [{ reason: ParseError(sides=[Old], detail~), scope: WholeFile }] else {
    fail("expected an old-side whole-file parse fallback")
  }
  assert_true(detail.contains("old:"), msg=detail)

  let new_only = @mbtdiff.diff("fn okay() {}", "fn broken( {")
  assert_true(
    new_only.fallbacks()
    is [{ reason: ParseError(sides=[New], ..), scope: WholeFile }],
  )

  let limited = @mbtdiff.diff(
    "fn f() { old_value() }",
    "fn f() { new_value() }",
    options=DiffOptions(graph_limit=0),
  )
  guard limited.fallbacks()
    is [{ reason: GraphLimitExceeded(limit=0), scope: Region(old~, new~) }] else {
    fail("expected a local graph fallback")
  }
  assert_true(old is Some({ start: 0, len: 1 }))
  assert_true(new is Some({ start: 0, len: 1 }))
}

///|
test "parse fallback records both sides in source order" {
  let result = @mbtdiff.diff("fn old_broken( {", "fn new_broken( [")
  guard result.fallbacks()
    is [{ reason: ParseError(sides=[Old, New], detail~), scope: WholeFile }] else {
    fail("expected a two-sided whole-file parse fallback")
  }
  assert_true(detail.contains("old:"), msg=detail)
  assert_true(detail.contains("new:"), msg=detail)
}

///|
test "root and declaration graph fallbacks have typed scopes" {
  let root = @mbtdiff.diff(
    "/// trailing old",
    "/// trailing new",
    options=DiffOptions(graph_limit=0),
  )
  assert_true(
    root.fallbacks()
    is [{ reason: GraphLimitExceeded(limit=0), scope: WholeFile }],
  )

  let local_result = @mbtdiff.diff(
    "fn first() { old_one() }\nfn second() { old_two() }",
    "fn first() { new_one() }\nfn second() { new_two() }",
    options=DiffOptions(context_lines=0, graph_limit=0),
  )
  assert_true(
    local_result.fallbacks()
    is [
      {
        reason: GraphLimitExceeded(limit=0),
        scope: Region(
          old=Some({ start: 0, len: 1 }),
          new=Some({ start: 0, len: 1 })
        ),
      },
      {
        reason: GraphLimitExceeded(limit=0),
        scope: Region(
          old=Some({ start: 1, len: 1 }),
          new=Some({ start: 1, len: 1 })
        ),
      },
    ],
  )
}

///|
test "formatting reorder and ignored whitespace stay renderer-free" {
  let reordered = @mbtdiff.diff(
    "fn first() {}\nfn second() {}", "fn second() {}\nfn first() {}",
  )
  assert_true(reordered.status() is NoStructuralChanges)
  assert_true(reordered.document().hunks.is_empty())

  let blank_only = @mbtdiff.diff(
    "fn stable() {}\n",
    "fn stable() {}\n\n \n",
    options=DiffOptions(ignore_comments=true),
  )
  assert_true(blank_only.status() is IgnoredOnly)
  assert_true(blank_only.document().hunks.is_empty())

  let clamped = @mbtdiff.diff(
    "fn f() { 1 }",
    "fn f() { 2 }",
    options=DiffOptions(context_lines=-20),
  )
  let zero = @mbtdiff.diff(
    "fn f() { 1 }",
    "fn f() { 2 }",
    options=DiffOptions(context_lines=0),
  )
  assert_true(clamped.document() == zero.document())
}

///|
test "source calculation accepts universal newlines and empty files" {
  let lf = @mbtdiff.diff("fn f() {\n  1\n}", "fn f() {\n  2\n}")
  let crlf = @mbtdiff.diff("fn f() {\r\n  1\r\n}", "fn f() {\r\n  2\r\n}")
  let cr = @mbtdiff.diff("fn f() {\r  1\r}", "fn f() {\r  2\r}")
  for result in [lf, crlf, cr] {
    assert_true(result.status() is Changed)
    assert_false(result.document().hunks.is_empty())
  }

  let newline_style = @mbtdiff.diff(
    "fn f() {\n  1\n}\n", "fn f() {\r\n  1\r\n}\r\n",
  )
  assert_true(newline_style.status() is NoStructuralChanges)
  assert_true(newline_style.document().hunks.is_empty())

  let trailing = @mbtdiff.diff("fn f() { 1 }", "fn f() { 1 }\n")
  assert_true(trailing.status() is NoStructuralChanges)
  assert_true(trailing.document().hunks.is_empty())

  let empty = @mbtdiff.diff("", "")
  assert_true(empty.status() is Identical)
  assert_true(empty.document().hunks.is_empty())
  let inserted = @mbtdiff.diff("", "fn f() {}")
  assert_true(inserted.status() is Changed)
  assert_false(inserted.document().hunks.is_empty())
}

///|
test "Unicode intraline changes remain structured" {
  let result = @mbtdiff.diff(
    "fn message() { \"你好，世界🌙\" }", "fn message() { \"你好，月球🌕\" }",
  )
  assert_true(result.status() is Changed)
  let mut changed_text = ""
  for hunk in result.document().hunks {
    for block in hunk.blocks {
      guard block is ChangeBlock(rows) else { continue }
      for row in rows {
        let lines = match row {
          Paired(old_line, new_line) => [old_line, new_line]
          OldOnly(line) | NewOnly(line) => [line]
        }
        for line in lines {
          for segment in line.segments {
            if segment.kind is Changed {
              changed_text += segment.text
            }
          }
        }
      }
    }
  }
  assert_true(
    changed_text.contains("世界") || changed_text.contains("月球"),
  )
}
