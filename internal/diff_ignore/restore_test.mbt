///|
fn restore_test_line(index : Int32, text : String) -> @model.DiffLine {
  { index, segments: [{ kind: Changed, text, }], intraline: NotComputed, }
}

///|
fn reverse_restore_block(block : @model.DiffBlock) -> @model.DiffBlock {
  match block {
    ContextBlock(lines) => {
      let reversed : Array[@model.ContextLine] = lines.map(line => {
        old_index: line.new_index,
        new_index: line.old_index,
        text: line.text,
      })
      ContextBlock(reversed[:])
    }
    ChangeBlock(rows) | IgnoredBlock(rows) => {
      let reversed = rows.map(row => {
        match row {
          Paired(old, new) => @model.Paired(new, old)
          OldOnly(line) => NewOnly(line)
          NewOnly(line) => OldOnly(line)
        }
      })
      if block is ChangeBlock(_) {
        ChangeBlock(reversed[:])
      } else {
        IgnoredBlock(reversed[:])
      }
    }
  }
}

///|
// Exact source coverage also checks monotone indexes and prevents duplicate
// lines, including repeated or empty comments. Check both insert and delete.
fn check_restored_rows(
  old_lines : Array[String],
  new_lines : Array[String],
  document : @model.HunkDocument,
  expected : Array[(Int32?, Int32?)],
  old_ignore_comments~ : Bool = true,
  new_ignore_comments~ : Bool = true,
) -> Unit raise {
  for reverse in [false, true] {
    let (old_lines, new_lines, document, expected) = if reverse {
      let hunks : Array[@model.DiffHunk] = document.hunks.map(hunk => {
        old_start: hunk.new_start,
        old_len: hunk.new_len,
        new_start: hunk.old_start,
        new_len: hunk.old_len,
        blocks: hunk.blocks.map(reverse_restore_block)[:],
      })
      let reversed : @model.HunkDocument = { hunks: hunks[:], }
      (new_lines, old_lines, reversed, expected.map(pair => (pair.1, pair.0)))
    } else {
      (old_lines, new_lines, document, expected)
    }
    let restored = @diff_ignore.restore_document(
      document,
      old=@diff_ignore.SourceView::from_source(
        old_lines.join("\n"),
        ignore_comments=if reverse {
          new_ignore_comments
        } else {
          old_ignore_comments
        },
      ),
      new=@diff_ignore.SourceView::from_source(
        new_lines.join("\n"),
        ignore_comments=if reverse {
          old_ignore_comments
        } else {
          new_ignore_comments
        },
      ),
    )
    let positions : Array[(Int32?, Int32?)] = []
    let mut previous_old = -1
    let mut previous_new = -1
    for hunk in restored.hunks {
      let old_seen : Array[(Int32, String)] = []
      let new_seen : Array[(Int32, String)] = []
      for block in hunk.blocks {
        match block {
          ContextBlock(lines) =>
            for line in lines {
              positions.push((Some(line.old_index), Some(line.new_index)))
              old_seen.push((line.old_index, line.text))
              new_seen.push((line.new_index, line.text))
            }
          ChangeBlock(rows) | IgnoredBlock(rows) =>
            for row in rows {
              let (old, new) = match row {
                Paired(old, new) => (Some(old), Some(new))
                OldOnly(line) => (Some(line), None)
                NewOnly(line) => (None, Some(line))
              }
              positions.push(
                (old.map(line => line.index), new.map(line => line.index)),
              )
              if old is Some(line) {
                old_seen.push((line.index, line.text()))
              }
              if new is Some(line) {
                new_seen.push((line.index, line.text()))
              }
              if block is IgnoredBlock(_) {
                for line in [old, new] {
                  if line is Some(line) {
                    assert_true(line.segments.all(s => s.kind is Ignored))
                  }
                }
              }
            }
        }
      }
      assert_eq(old_seen.length(), hunk.old_len)
      assert_eq(new_seen.length(), hunk.new_len)
      for offset, pair in old_seen {
        let (index, text) = pair
        assert_eq(index, hunk.old_start + offset)
        assert_true(index > previous_old)
        assert_eq(text, old_lines[index])
        previous_old = index
      }
      for offset, pair in new_seen {
        let (index, text) = pair
        assert_eq(index, hunk.new_start + offset)
        assert_true(index > previous_new)
        assert_eq(text, new_lines[index])
        previous_new = index
      }
    }
    assert_eq(positions, expected)
  }
}

///|
fn check_attribute_restore(
  old_lines : Array[String],
  new_lines : Array[String],
  expected : Array[(Int32?, Int32?)],
) -> Unit raise {
  let old = @diff_ignore.SourceView::from_source(
    old_lines.join("\n"),
    ignore_comments=true,
  )
  let new = @diff_ignore.SourceView::from_source(
    new_lines.join("\n"),
    ignore_comments=true,
  )
  let rows : Array[@model.DiffRow] = []
  let extra = new.lines().length() - old.lines().length()
  for index in 0..<extra {
    rows.push(NewOnly(restore_test_line(index, new.lines()[index])))
  }
  let blocks : Array[@model.DiffBlock] = [ChangeBlock(rows[:])]
  if !old.lines().is_empty() {
    blocks.push(
      ContextBlock([{ old_index: 0, new_index: extra, text: old.lines()[0], }]),
    )
  }
  check_restored_rows(
    old_lines,
    new_lines,
    {
      hunks: [
        {
          old_start: 0,
          old_len: old.lines().length(),
          new_start: 0,
          new_len: new.lines().length(),
          blocks: blocks[:],
        },
      ],
    },
    expected,
  )
}

///|
test "restore pairs identical ignored prefixes before attributes in both directions" {
  check_attribute_restore(
    ["///|", "/// 相同 docs 🌓", "", "fn f() {}"],
    ["///|", "/// 相同 docs 🌓", "", "#intrinsic(\"view\")", "fn f() {}"],
    [
      (Some(0), Some(0)),
      (Some(1), Some(1)),
      (Some(2), Some(2)),
      (None, Some(3)),
      (Some(3), Some(4)),
    ],
  )
}

///|
test "restore consumes shared comments only once across consecutive insertions" {
  check_attribute_restore(
    ["/// shared", "fn f() {}"],
    ["/// shared", "#intrinsic(\"view\")", "#deprecated", "fn f() {}"],
    [(Some(0), Some(0)), (None, Some(1)), (None, Some(2)), (Some(1), Some(3))],
  )
  check_attribute_restore(
    ["/// first", "/// second", "fn f() {}"],
    [
      "/// first", "#intrinsic(\"view\")", "/// second", "#deprecated", "fn f() {}",
    ],
    [
      (Some(0), Some(0)),
      (None, Some(1)),
      (Some(1), Some(2)),
      (None, Some(3)),
      (Some(2), Some(4)),
    ],
  )
}

///|
test "restore pairs only the exact prefix and does not search past different comments" {
  check_attribute_restore(
    ["/// shared", "/// old", "/// later", "fn f() {}"],
    ["/// shared", "/// new", "/// later", "#intrinsic(\"view\")", "fn f() {}"],
    [
      (Some(0), Some(0)),
      (None, Some(1)),
      (None, Some(2)),
      (None, Some(3)),
      (Some(1), None),
      (Some(2), None),
      (Some(3), Some(4)),
    ],
  )
}

///|
test "restore keeps comments after attributes and unmatched comments in source order" {
  for
    (old_lines, new_lines, expected) in [
      (
        ["/// shared", "fn f() {}"],
        ["#intrinsic(\"view\")", "/// shared", "fn f() {}"],
        [(None, Some(0)), (Some(0), Some(1)), (Some(1), Some(2))],
      ),
      (
        ["fn f() {}"],
        ["/// new", "#intrinsic(\"view\")", "fn f() {}"],
        [(None, Some(0)), (None, Some(1)), (Some(0), Some(2))],
      ),
      (
        ["/// old", "fn f() {}"],
        ["#intrinsic(\"view\")", "fn f() {}"],
        [(None, Some(0)), (Some(0), None), (Some(1), Some(1))],
      ),
      (
        ["/// same", "fn f() {}"],
        ["/// same ", "#intrinsic(\"view\")", "fn f() {}"],
        [(None, Some(0)), (None, Some(1)), (Some(0), None), (Some(1), Some(2))],
      ),
    ] {
    check_attribute_restore(old_lines, new_lines, expected)
  }
}

///|
test "restore handles empty and fully ignored opposite sides" {
  check_attribute_restore([], ["/// docs", "#intrinsic(\"view\")"], [
    (None, Some(0)),
    (None, Some(1)),
  ])
  check_attribute_restore(["/// docs"], ["/// docs", "#intrinsic(\"view\")"], [
    (Some(0), Some(0)),
    (None, Some(1)),
  ])
  check_attribute_restore(
    ["/// docs"],
    ["/// docs", "/// extra", "#intrinsic(\"view\")"],
    [(Some(0), Some(0)), (None, Some(1)), (None, Some(2))],
  )
}

///|
test "restore respects hunk boundaries without consuming intervening visible code" {
  check_restored_rows(
    [
      "/// shared", "fn first() {}", "fn skipped() {}", "/// shared", "fn last() {}",
    ],
    [
      "/// shared", "#deprecated", "fn first() {}", "fn skipped() {}", "/// shared",
      "#deprecated", "fn last() {}",
    ],
    {
      hunks: [
        {
          old_start: 0,
          old_len: 0,
          new_start: 0,
          new_len: 1,
          blocks: [ChangeBlock([NewOnly(restore_test_line(0, "#deprecated"))])],
        },
        {
          old_start: 2,
          old_len: 1,
          new_start: 3,
          new_len: 2,
          blocks: [
            ChangeBlock([NewOnly(restore_test_line(3, "#deprecated"))]),
            ContextBlock([{ old_index: 2, new_index: 4, text: "fn last() {}", }]),
          ],
        },
      ],
    },
    [
      (Some(0), Some(0)),
      (None, Some(1)),
      (Some(3), Some(4)),
      (None, Some(5)),
      (Some(4), Some(6)),
    ],
  )
}

///|
test "restore flushes buffered rows before pairing a shared ignored prefix" {
  check_restored_rows(
    ["fn f() {", "// shared", "}"],
    ["fn f() {", "// shared", "  added()", "}"],
    {
      hunks: [
        {
          old_start: 0,
          old_len: 2,
          new_start: 0,
          new_len: 3,
          blocks: [
            ChangeBlock([
              Paired(
                restore_test_line(0, "fn f() {"),
                restore_test_line(0, "fn f() {"),
              ),
              NewOnly(restore_test_line(1, "  added()")),
              Paired(restore_test_line(1, "}"), restore_test_line(2, "}")),
            ]),
          ],
        },
      ],
    },
    [
      (Some(0), Some(0)),
      (Some(1), Some(1)),
      (None, Some(2)),
      (Some(2), Some(3)),
    ],
  )
}

///|
test "restore never pairs ignored text with an identical visible line" {
  // Different views can retain text on just one side, as with ignored ranges.
  // Even an exact text match must stop at the opposite visible line.
  check_restored_rows(
    ["// shared", "fn next() {}"],
    ["// shared", "#deprecated", "// shared", "fn next() {}"],
    {
      hunks: [
        {
          old_start: 0,
          old_len: 1,
          new_start: 0,
          new_len: 1,
          blocks: [
            ChangeBlock([
              NewOnly(restore_test_line(0, "#deprecated")),
              OldOnly(restore_test_line(0, "// shared")),
            ]),
          ],
        },
      ],
    },
    [(None, Some(0)), (None, Some(1)), (Some(0), None), (None, Some(2))],
    old_ignore_comments=false,
  )
}
