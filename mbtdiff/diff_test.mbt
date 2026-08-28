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
  public_fragments(document).all(fragment => fragment.document.hunks.is_empty())
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
fn public_document_has_changed_segment_containing(
  document : @mbtdiff.DiffDocument,
  expected : String,
) -> Bool {
  for fragment in public_fragments(document) {
    for hunk in fragment.document.hunks {
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
  }
  false
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
test "top-level sections preserve both source orders and local ranges" {
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
      Matched(
        old={ start: 0, len: 1 },
        new={ start: 1, len: 1 },
        old_context=Some("fn first() { old_value() }"),
        new_context=Some("fn first() { new_value() }"),
        diff=matched
      ),
      Deleted(
        old={ start: 1, len: 1 },
        old_context=Some("fn removed() {}"),
        diff=deleted
      ),
      Inserted(
        new={ start: 0, len: 1 },
        new_context=Some("fn inserted() {}"),
        diff=inserted
      ),
    ] else {
    fail("expected matched, deleted, and inserted section variants")
  }
  for hunk in matched.document.hunks {
    assert_true(hunk.old_start >= 0 && hunk.old_start + hunk.old_len <= 1)
    assert_true(hunk.new_start >= 0 && hunk.new_start + hunk.new_len <= 1)
  }
  for hunk in deleted.document.hunks {
    assert_true(hunk.old_start >= 0 && hunk.old_start + hunk.old_len <= 1)
  }
  for hunk in inserted.document.hunks {
    assert_true(hunk.new_start >= 0 && hunk.new_start + hunk.new_len <= 1)
  }
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
  let old_source = "fn format() { 1 }"
  let new_source = "fn format() {\n  1\n}"
  let lexical = @mbtdiff.diff(
    old_source,
    new_source,
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
test "sectioned lexical mode ignores context_lines and returns full declarations" {
  let old_source =
    #|fn target() {
    #|  stable_prefix_one()
    #|  stable_prefix_two()
    #|  stable_prefix_three()
    #|  stable_prefix_four()
    #|  old_head()
    #|  stable_one()
    #|  stable_two()
    #|  stable_three()
    #|  stable_four()
    #|  old_tail()
    #|  stable_suffix_one()
    #|  stable_suffix_two()
    #|  stable_suffix_three()
    #|  stable_suffix_four()
    #|}
  let new_source =
    #|fn target() {
    #|  stable_prefix_one()
    #|  stable_prefix_two()
    #|  stable_prefix_three()
    #|  stable_prefix_four()
    #|  new_head()
    #|  stable_one()
    #|  stable_two()
    #|  stable_three()
    #|  stable_four()
    #|  new_tail()
    #|  stable_suffix_one()
    #|  stable_suffix_two()
    #|  stable_suffix_three()
    #|  stable_suffix_four()
    #|}
  for context_lines in [0, 3] {
    let result = @mbtdiff.diff(
      old_source,
      new_source,
      options=DiffOptions(context_lines~, mode=@mbtdiff.DiffMode::Lexical),
    )
    guard result.document()
      is TopLevel({ sections: [Matched(old~, new~, diff~, ..)], .. }) else {
      fail("expected one sectioned lexical declaration")
    }
    guard diff.document.hunks is [hunk] else {
      fail("expected one complete lexical hunk")
    }
    assert_eq(hunk.old_start, 0)
    assert_eq(hunk.old_len, old.len)
    assert_eq(hunk.new_start, 0)
    assert_eq(hunk.new_len, new.len)
  }
}

///|
test "comment and test filters classify IgnoredOnly" {
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
}

///|
test "filters compose while retaining production changes" {
  let result = @mbtdiff.diff(
    "/// old docs\nfn production() { old_value() }\ntest \"t\" { old_test() }",
    "/// new docs\nfn production() { new_value() }\ntest \"t\" { new_test() }",
    options=DiffOptions(ignore_comments=true, ignore_tests=true),
  )
  assert_true(result.status() is Changed)
  assert_true(
    public_document_has_changed_segment_containing(
      result.document(),
      "old_value",
    ),
  )
  assert_true(
    public_document_has_changed_segment_containing(
      result.document(),
      "new_value",
    ),
  )
  assert_false(
    public_document_has_changed_segment_containing(
      result.document(),
      "old_test",
    ),
  )
}

///|
test "parse fallbacks are Whole and preserve source labels and sides" {
  let parsed = @mbtdiff.diff(
    "fn old_broken( {",
    "fn new_broken( [",
    old_name="before.mbt",
    new_name="after.mbt",
  )
  guard parsed.document()
    is Whole(
      {
        document: parsed_document,
        fallbacks: [ParseError(sides=[Old, New], detail~)],
      }
    ) else {
    fail("expected a two-sided Whole parse fallback")
  }
  assert_false(parsed_document.hunks.is_empty())
  assert_true(detail.contains("before.mbt"), msg=detail)
  assert_true(detail.contains("after.mbt"), msg=detail)
}

///|
test "graph fallbacks remain local to their sections" {
  let result = @mbtdiff.diff(
    "fn first() { old_one() }\nfn second() { old_two() }",
    "fn first() { new_one() }\nfn second() { new_two() }",
    options=DiffOptions(context_lines=0, graph_limit=0),
  )
  guard result.document() is TopLevel(top) else {
    fail("expected reliable top-level sections")
  }
  assert_eq(top.sections.length(), 2)
  for section in top.sections {
    let fragment = public_section_fragment(section)
    assert_true(fragment.fallbacks is [GraphLimitExceeded(limit=0)])
    assert_false(fragment.document.hunks.is_empty())
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

///|
test "negative context is clamped before fragment calculation" {
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
