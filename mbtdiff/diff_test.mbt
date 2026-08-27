///|
fn public_section_fragment(
  section : @mbtdiff.DiffSection,
) -> @mbtdiff.DiffFragment {
  match section {
    Matched(diff~, ..) | Deleted(diff~, ..) | Inserted(diff~, ..) => diff
  }
}

///|
fn public_fragments(
  document : @mbtdiff.DiffDocument,
) -> Array[@mbtdiff.DiffFragment] {
  match document {
    Whole(fragment) => [fragment]
    TopLevel(top) => top.sections.map(public_section_fragment)
  }
}

///|
fn public_document_is_empty(document : @mbtdiff.DiffDocument) -> Bool {
  public_fragments(document).all(fragment => fragment.rows.is_empty())
}

///|
fn public_fallbacks(
  document : @mbtdiff.DiffDocument,
) -> Array[@mbtdiff.FallbackReason] {
  let reasons : Array[@mbtdiff.FallbackReason] = []
  for fragment in public_fragments(document) {
    reasons.push_iter(fragment.fallbacks.iter())
  }
  reasons
}

///|
fn public_pair_lines(pair : @mbtdiff.DiffLinePair) -> Array[@mbtdiff.DiffLine] {
  match pair {
    Paired(old_line, new_line) => [old_line, new_line]
    OldOnly(line) | NewOnly(line) => [line]
  }
}

///|
fn public_document_has_changed_segment_containing(
  document : @mbtdiff.DiffDocument,
  expected : String,
) -> Bool {
  for fragment in public_fragments(document) {
    for row in fragment.rows {
      guard row is Changed(pair) else { continue }
      for line in public_pair_lines(pair) {
        for segment in line.segments {
          if segment.kind is Changed && segment.text.contains(expected) {
            return true
          }
        }
      }
    }
  }
  false
}

///|
fn public_document_has_neutral(document : @mbtdiff.DiffDocument) -> Bool {
  public_fragments(document).any(fragment => {
    fragment.rows.any(row => row is Neutral(_))
  })
}

///|
fn assert_complete_public_fragment(
  fragment : @mbtdiff.DiffFragment,
  old_len : Int?,
  new_len : Int?,
) -> Unit raise {
  let old_indices : Array[Int] = []
  let new_indices : Array[Int] = []
  for row in fragment.rows {
    match row {
      Context(line) => {
        old_indices.push(line.old_index)
        new_indices.push(line.new_index)
      }
      Changed(pair) | Neutral(pair) =>
        match pair {
          Paired(old_line, new_line) => {
            old_indices.push(old_line.index)
            new_indices.push(new_line.index)
          }
          OldOnly(line) => old_indices.push(line.index)
          NewOnly(line) => new_indices.push(line.index)
        }
    }
  }
  match old_len {
    Some(limit) => {
      assert_eq(old_indices.length(), limit)
      for expected, actual in old_indices {
        assert_eq(actual, expected)
      }
    }
    None => assert_true(old_indices.is_empty())
  }
  match new_len {
    Some(limit) => {
      assert_eq(new_indices.length(), limit)
      for expected, actual in new_indices {
        assert_eq(actual, expected)
      }
    }
    None => assert_true(new_indices.is_empty())
  }
}

///|
test "public status priority uses the semantic document" {
  let identical = @mbtdiff.diff("fn broken(", "fn broken(")
  assert_true(identical.status() is Identical)
  assert_true(identical.document() is Whole(_))
  assert_true(public_document_is_empty(identical.document()))

  let formatting = @mbtdiff.diff("fn f() { 1 }", "fn f() {\n  1\n}")
  assert_true(formatting.status() is NoStructuralChanges)
  assert_true(formatting.document() is TopLevel(_))
  assert_true(public_document_is_empty(formatting.document()))

  let changed = @mbtdiff.diff("fn f() { 1 }", "fn f() { 2 }")
  assert_true(changed.status() is Changed)
  assert_false(public_document_is_empty(changed.document()))

  let reordered = @mbtdiff.diff(
    "fn first() {}\nfn second() {}", "fn second() {}\nfn first() {}",
  )
  assert_true(reordered.status() is Reordered)
  assert_true(public_document_is_empty(reordered.document()))
}

///|
test "default and explicit AST modes are identical" {
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
}

///|
test "top-level sections preserve both source orders and complete local rows" {
  let result = @mbtdiff.diff(
    "fn first() { old_value() }\nfn removed() {}", "fn inserted() {}\nfn first() { new_value() }",
  )
  guard result.document() is TopLevel(top) else {
    fail("expected top-level semantic pairings")
  }
  assert_true(top.old_order is [0, 1])
  assert_true(top.new_order is [2, 0])
  guard top.sections
    is [
      Matched(old={ start: 0, len: 1 }, new={ start: 1, len: 1 }, diff=matched),
      Deleted(old={ start: 1, len: 1 }, diff=deleted),
      Inserted(new={ start: 0, len: 1 }, diff=inserted),
    ] else {
    fail("expected matched, deleted, and inserted section variants")
  }
  assert_complete_public_fragment(matched, Some(1), Some(1))
  assert_complete_public_fragment(deleted, Some(1), None)
  assert_complete_public_fragment(inserted, None, Some(1))
}

///|
test "pure and mixed reorders retain crossing identities" {
  let pure = @mbtdiff.diff(
    "fn first() {}\nfn second() {}", "fn second() {}\nfn first() {}",
  )
  guard pure.document() is TopLevel(pure_top) else {
    fail("expected a pure top-level reorder")
  }
  assert_true(pure.status() is Reordered)
  assert_true(pure_top.reordered)
  assert_true(pure_top.old_order is [0, 1])
  assert_true(pure_top.new_order is [1, 0])
  assert_true(public_fallbacks(pure.document()).is_empty())

  let mixed = @mbtdiff.diff(
    "fn first() { old_value() }\nfn second() {}", "fn second() {}\nfn first() { new_value() }",
  )
  guard mixed.document() is TopLevel(mixed_top) else {
    fail("expected a mixed top-level reorder")
  }
  assert_true(mixed.status() is Changed)
  assert_true(mixed_top.reordered)
  assert_true(
    public_document_has_changed_segment_containing(
      mixed.document(),
      "new_value",
    ),
  )
}

///|
test "lexical mode keeps fragment-local text changes" {
  let lexical = @mbtdiff.diff(
    "fn format() { 1 }",
    "fn format() {\n  1\n}",
    options=DiffOptions(graph_limit=0, mode=@mbtdiff.DiffMode::Lexical),
  )
  assert_true(lexical.status() is Changed)
  assert_false(public_document_is_empty(lexical.document()))
  assert_true(public_fallbacks(lexical.document()).is_empty())

  let reordered = @mbtdiff.diff(
    "fn first() {}\nfn second() {}",
    "fn second() {}\nfn first() {}",
    options=DiffOptions(mode=@mbtdiff.DiffMode::Lexical),
  )
  assert_true(reordered.status() is Reordered)
  guard reordered.document() is TopLevel(top) else {
    fail("lexical mode must retain semantic pairings")
  }
  assert_true(top.reordered)
}

///|
test "filters classify ignored-only changes and restore neutral rows beside code" {
  for mode in [@mbtdiff.DiffMode::Ast, @mbtdiff.DiffMode::Lexical] {
    let comments = @mbtdiff.diff(
      "fn f() { 1 // old\n}",
      "fn f() { 1 // new\n}",
      options=DiffOptions(ignore_comments=true, mode~),
    )
    assert_true(comments.status() is IgnoredOnly)
    assert_true(public_document_is_empty(comments.document()))

    let tests = @mbtdiff.diff(
      "test \"sample\" { old_value() }",
      "test \"sample\" { new_value() }",
      options=DiffOptions(ignore_tests=true, mode~),
    )
    assert_true(tests.status() is IgnoredOnly)
    assert_true(public_document_is_empty(tests.document()))
  }

  let mixed = @mbtdiff.diff(
    "fn production() {\n  old_value()\n  // old note\n}",
    "fn production() {\n  new_value()\n  // new note\n}",
    options=DiffOptions(ignore_comments=true),
  )
  assert_true(mixed.status() is Changed)
  assert_true(public_document_has_neutral(mixed.document()))
  assert_true(
    public_document_has_changed_segment_containing(
      mixed.document(),
      "new_value",
    ),
  )
  assert_false(
    public_document_has_changed_segment_containing(mixed.document(), "new note"),
  )
}

///|
test "parse and graph fallbacks preserve ownership" {
  let parsed = @mbtdiff.diff(
    "fn old_broken( {",
    "fn new_broken( [",
    old_name="before.mbt",
    new_name="after.mbt",
  )
  guard parsed.document()
    is Whole({ rows, fallbacks: [ParseError(sides=[Old, New], detail~)] }) else {
    fail("expected a two-sided Whole parse fallback")
  }
  assert_false(rows.is_empty())
  assert_true(detail.contains("before.mbt"), msg=detail)
  assert_true(detail.contains("after.mbt"), msg=detail)

  let graph = @mbtdiff.diff(
    "fn first() { old_one() }\nfn second() { old_two() }",
    "fn first() { new_one() }\nfn second() { new_two() }",
    options=DiffOptions(graph_limit=0),
  )
  guard graph.document() is TopLevel(top) else {
    fail("expected reliable top-level sections")
  }
  assert_eq(top.sections.length(), 2)
  for section in top.sections {
    let fragment = public_section_fragment(section)
    assert_true(fragment.fallbacks is [GraphLimitExceeded(limit=0)])
    assert_false(fragment.rows.is_empty())
  }
}

///|
test "universal newlines and empty files preserve semantic status" {
  for
    sources in [
      ("fn f() {\n  1\n}", "fn f() {\n  2\n}"),
      ("fn f() {\r\n  1\r\n}", "fn f() {\r\n  2\r\n}"),
      ("fn f() {\r  1\r}", "fn f() {\r  2\r}"),
    ] {
    let (old_source, new_source) = sources
    let result = @mbtdiff.diff(old_source, new_source)
    assert_true(result.status() is Changed)
    assert_false(public_document_is_empty(result.document()))
  }

  let newline_style = @mbtdiff.diff(
    "fn f() {\n  1\n}\n", "fn f() {\r\n  1\r\n}\r\n",
  )
  assert_true(newline_style.status() is NoStructuralChanges)
  assert_true(public_document_is_empty(newline_style.document()))

  let empty = @mbtdiff.diff("", "")
  assert_true(empty.status() is Identical)
  let inserted = @mbtdiff.diff("", "fn f() {}")
  assert_true(inserted.status() is Changed)
  assert_false(public_document_is_empty(inserted.document()))
}
