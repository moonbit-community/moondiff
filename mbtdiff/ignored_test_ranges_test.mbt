///|
fn assert_ignored_test_ranges(
  result : @mbtdiff.DiffResult,
  side : @mbtdiff.DiffSide,
  expected : ArrayView[(Int, Int)],
) -> Unit raise {
  let actual : ArrayView[@mbtdiff.LineRange] = result.ignored_test_ranges(side)
  assert_eq(actual.length(), expected.length())
  for index in 0..<actual.length() {
    assert_eq((actual[index].start, actual[index].len), expected[index])
  }
}

///|
fn ignored_range_document_is_empty(document : @mbtdiff.DiffDocument) -> Bool {
  match document {
    Whole(fragment) => fragment.document.hunks.is_empty()
    TopLevel(top) =>
      top.sections.all(section => {
        match section {
          Matched(diff~, ..) | Deleted(diff~, ..) | Inserted(diff~, ..) =>
            diff.document.hunks.is_empty()
        }
      })
  }
}

///|
test "ignored test insertion exposes new-side geometry in both modes" {
  let old_source = "fn production() {}"
  let new_source =
    #|fn production() {}
    #|
    #|/// test docs
    #|///|UUID(test-id)
    #|async test "sample" {
    #|  inspect(1)
    #|}
  for mode in [@mbtdiff.DiffMode::Ast, Lexical] {
    let result = @mbtdiff.diff(
      old_source,
      new_source,
      options=DiffOptions(ignore_tests=true, mode~),
    )
    assert_true(result.status() is IgnoredOnly)
    assert_true(ignored_range_document_is_empty(result.document()))
    assert_ignored_test_ranges(result, Old, [])
    assert_ignored_test_ranges(result, New, [(2, 5)])
  }
}

///|
test "ignored test deletion, movement, and height changes keep side geometry" {
  let documented_test =
    #|fn production() {}
    #|
    #|/// test docs
    #|///|UUID(test-id)
    #|async test "sample" {
    #|  inspect(1)
    #|}
  let production_only = "fn production() {}"
  let deleted = @mbtdiff.diff(
    documented_test,
    production_only,
    options=DiffOptions(ignore_tests=true),
  )
  assert_ignored_test_ranges(deleted, Old, [(2, 5)])
  assert_ignored_test_ranges(deleted, New, [])

  let moved = @mbtdiff.diff(
    "test \"moved\" {}\nfn keep() {}",
    "fn keep() {}\ntest \"moved\" {}",
    options=DiffOptions(ignore_tests=true),
  )
  assert_true(moved.status() is IgnoredOnly)
  assert_ignored_test_ranges(moved, Old, [(0, 1)])
  assert_ignored_test_ranges(moved, New, [(1, 1)])

  let resized = @mbtdiff.diff(
    "test \"sample\" {\n  old_value()\n}",
    "test \"sample\" {\n  first_value()\n  second_value()\n}",
    options=DiffOptions(ignore_tests=true),
  )
  assert_true(resized.status() is IgnoredOnly)
  assert_ignored_test_ranges(resized, Old, [(0, 3)])
  assert_ignored_test_ranges(resized, New, [(0, 4)])
}

///|
test "consecutive tests own docs but not ordinary comments or blank lines" {
  let old_source =
    #|// retained before
    #|
    #|/// docs for a
    #|///|UUID(a)
    #|test "a" { old_a() }
    #|async test "b" {
    #|  old_b()
    #|}
    #|
    #|// retained after
  let new_source =
    #|// retained before
    #|
    #|/// docs for a
    #|///|UUID(a)
    #|test "a" { new_a() }
    #|async test "b" {
    #|  new_b()
    #|}
    #|
    #|// retained after
  let result = @mbtdiff.diff(
    old_source,
    new_source,
    options=DiffOptions(ignore_tests=true),
  )
  assert_true(result.status() is IgnoredOnly)
  assert_ignored_test_ranges(result, Old, [(2, 3), (5, 3)])
  assert_ignored_test_ranges(result, New, [(2, 3), (5, 3)])
}

///|
test "comparison whitespace masking does not enlarge public test ranges" {
  let baseline = "fn before() {}\nfn after() {}"
  let test_gap = @mbtdiff.diff(
    baseline,
    "fn before() {}\ntest \"hidden\" {}\nfn after() {}",
    options=DiffOptions(ignore_comments=true, ignore_tests=true),
  )
  let blank_gap = @mbtdiff.diff(
    baseline,
    "fn before() {}\n\nfn after() {}",
    options=DiffOptions(ignore_comments=true, ignore_tests=true),
  )
  assert_true(test_gap.status() is IgnoredOnly)
  assert_true(blank_gap.status() is IgnoredOnly)
  assert_true(test_gap.document() == blank_gap.document())
  assert_ignored_test_ranges(test_gap, New, [(1, 1)])
  assert_ignored_test_ranges(blank_gap, New, [])
}
