///|
test "public IR retains hunk ranges, block boundaries, and source text" {
  let document = @tokdiff.diff(
    old=["context", "  let old = 1", "tail"],
    new=["context", "    let new = 1", "tail"],
    context=1,
  )
  guard document.hunks is [hunk] else { fail("expected one hunk") }
  assert_eq(
    (hunk.old_start, hunk.old_len, hunk.new_start, hunk.new_len),
    (0, 3, 0, 3),
  )
  guard hunk.blocks
    is [ContextBlock(before), ChangeBlock(rows), ContextBlock(after)] else {
    fail("expected context/change/context blocks")
  }
  guard before is [before_line] && after is [after_line] else {
    fail("expected one context line on each side of the change")
  }
  assert_eq(
    (before_line.old_index, before_line.new_index, before_line.text),
    (0, 0, "context"),
  )
  assert_eq(
    (after_line.old_index, after_line.new_index, after_line.text),
    (2, 2, "tail"),
  )
  guard rows is [Paired(old_line, new_line)] else {
    fail("expected one paired change row")
  }
  assert_eq(old_line.index, 1)
  assert_eq(new_line.index, 1)
  assert_eq(old_line.text(), "  let old = 1")
  assert_eq(new_line.text(), "    let new = 1")
  assert_true(old_line.segments.any(segment => segment.kind is Changed))
  assert_true(new_line.segments.any(segment => segment.kind is Changed))
}

///|
test "public IR distinguishes blank inserted lines from a missing old side" {
  let document = @linediff.line_diff(old=[], new=["x", ""], context=0)
  guard document.hunks is [hunk] else { fail("expected one insertion hunk") }
  assert_eq(
    (hunk.old_start, hunk.old_len, hunk.new_start, hunk.new_len),
    (0, 0, 0, 2),
  )
  guard hunk.blocks is [ChangeBlock([NewOnly(first), NewOnly(blank)])] else {
    fail("expected two present new-side rows")
  }
  assert_eq((first.index, first.text()), (0, "x"))
  assert_eq((blank.index, blank.text()), (1, ""))
  assert_eq(blank.segments.length(), 0)
}

///|
test "plain line diff refines only equal-width replacements" {
  let document = @linediff.line_diff(
    old=["alpha old omega"],
    new=["alpha new omega"],
    context=0,
  )
  guard document.hunks is [{ blocks: [ChangeBlock(rows)], .. }] else {
    fail("expected one change block")
  }
  guard rows is [Paired(old_line, new_line)] else {
    fail("expected one positional pair")
  }
  assert_true(old_line.segments.any(segment => segment.kind is Changed))
  assert_true(new_line.segments.any(segment => segment.kind is Changed))
  assert_eq(old_line.text(), "alpha old omega")
  assert_eq(new_line.text(), "alpha new omega")

  let unequal = @linediff.line_diff(
    old=["old one", "old two"],
    new=["new one"],
    context=0,
  )
  guard unequal.hunks is [{ blocks: [ChangeBlock(unequal_rows)], .. }] else {
    fail("expected one unequal change block")
  }
  for row in unequal_rows {
    match row {
      Paired(old_line, new_line) => {
        assert_true(old_line.segments.all(segment => segment.kind is Unchanged))
        assert_true(new_line.segments.all(segment => segment.kind is Unchanged))
      }
      OldOnly(line) | NewOnly(line) =>
        assert_true(line.segments.all(segment => segment.kind is Unchanged))
    }
  }
}

///|
test "calculation IR retains raw text without renderer markup or escaping" {
  let document = @tokdiff.diff(
    old=["x < old && y"],
    new=["x < new && y"],
    context=0,
  )
  guard document.hunks
    is [{ blocks: [ChangeBlock([Paired(old_line, new_line)])], .. }] else {
    fail("expected one paired semantic row")
  }
  assert_eq(old_line.text(), "x < old && y")
  assert_eq(new_line.text(), "x < new && y")
  for line in [old_line, new_line] {
    for segment in line.segments {
      assert_false(segment.text.contains("<b"))
      assert_false(segment.text.contains("&lt;"))
      assert_false(segment.text.contains("&amp;"))
    }
  }
}

///|
test "DiffDocument rebase updates ranges context and changed indexes" {
  let original = @tokdiff.diff(
    old=["before", "let old = 1", "after"],
    new=["before", "let new = 2", "after"],
    context=1,
  )
  let rebased = original.rebase(10, 20)
  guard rebased.hunks is [hunk] else { fail("expected one rebased hunk") }
  assert_eq(
    (hunk.old_start, hunk.old_len, hunk.new_start, hunk.new_len),
    (10, 3, 20, 3),
  )
  guard hunk.blocks
    is [
      ContextBlock([before]),
      ChangeBlock([Paired(old_line, new_line)]),
      ContextBlock([after]),
    ] else {
    fail("expected rebased context/change/context blocks")
  }
  assert_eq((before.old_index, before.new_index), (10, 20))
  assert_eq((old_line.index, new_line.index), (11, 21))
  assert_eq((after.old_index, after.new_index), (12, 22))

  let insertion = @linediff.line_diff(old=[], new=["new"], context=0).rebase(
    7, 12,
  )
  guard insertion.hunks is [insert_hunk] else {
    fail("expected one insertion hunk")
  }
  guard insert_hunk.blocks is [ChangeBlock([NewOnly(inserted)])] else {
    fail("expected one inserted line")
  }
  assert_eq(inserted.index, 12)
}
