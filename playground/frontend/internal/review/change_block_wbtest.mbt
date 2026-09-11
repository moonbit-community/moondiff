///|
test "projection preserves adjacent change block boundaries and source anchors across hunks" {
  let old : @model.DiffLine = {
    index: 2,
    segments: [{ kind: Changed, text: "old", }],
  }
  let new : @model.DiffLine = {
    index: 3,
    segments: [{ kind: Changed, text: "new", }],
  }
  let hunk : @model.DiffHunk = {
    old_start: 0,
    old_len: 5,
    new_start: 0,
    new_len: 5,
    blocks: [
      ContextBlock([{ old_index: 0, new_index: 0, text: "context", }]),
      ChangeBlock([]),
      ChangeBlock([Paired(old, new), OldOnly(old)]),
      ChangeBlock([NewOnly(new)]),
      IgnoredBlock([OldOnly(old), NewOnly(new)]),
      IgnoredBlock([]),
      ChangeBlock([OldOnly(old)]),
    ],
  }
  let patch = parse_canonical_patch(
    "target.mbt",
    Some("@@ -3 +4 @@\n-old\n+new"),
  )
  let rows = project_review_rows(
    7,
    "target.mbt",
    { hunks: [hunk, hunk], },
    patch,
  )
  let expected = [false, true, false, true, false, false, true]
  let twice = expected.copy()
  twice.push_iter(expected.iter())
  assert_eq(rows.map(row => row.change_block_start), twice)
  for row in rows {
    assert_eq(row.file_index, 7)
    if row.kind is ChangeRow {
      if row.old_line is Some(line) {
        assert_eq(line, 3)
        assert_eq(row.old_anchor, canonical_anchor(patch, Left, line))
      }
      if row.new_line is Some(line) {
        assert_eq(line, 4)
        assert_eq(row.new_anchor, canonical_anchor(patch, Right, line))
      }
    }
  }
  for headers in [false, true] {
    let items = project_review_items(
      7,
      "target.mbt",
      { hunks: [hunk, hunk], },
      patch,
      show_hunk_headers=headers,
    )
    let starts = items.filter(item => {
      item is ReviewLine(row) && row.change_block_start
    })
    assert_eq(starts.length(), 6)
  }
}
