///|
test "canonical patch maps sides, source lines, and multi-hunk positions" {
  let patch = parse_canonical_patch(
    "src/main.mbt",
    Some(
      "@@ -1,3 +1,3 @@\n context\n-old\n+new\n tail\n@@ -10 +10,2 @@ fn later\n-old10\n+new10\n+extra\n\\ No newline at end of file",
    ),
  )
  assert_true(patch_is_commentable(patch))
  assert_eq(
    canonical_anchor(patch, Right, 1),
    Some({ path: "src/main.mbt", line: 1, side: Right, position: Some(1), }),
  )
  assert_eq(canonical_anchor(patch, Left, 2).unwrap().position, Some(2))
  assert_eq(canonical_anchor(patch, Right, 2).unwrap().position, Some(3))
  assert_eq(canonical_anchor(patch, Right, 3).unwrap().position, Some(4))
  assert_eq(canonical_anchor(patch, Left, 10).unwrap().position, Some(6))
  assert_eq(canonical_anchor(patch, Right, 10).unwrap().position, Some(7))
  assert_eq(canonical_anchor(patch, Right, 11).unwrap().position, Some(8))
  assert_eq(canonical_anchor(patch, Left, 1), None)
}

///|
test "canonical patch maps complete declaration context to absolute anchors" {
  let patch_text =
    $|@@ -1,15 +1,15 @@
    $| fn unchanged_before() {}
    $| \{""}
    $| /// structural docs
    $| fn structural() {
    $|-  old_call("<script>&safe")
    $|+  new_call("<script>&safe")
    $|   stable_one()
    $|   stable_two()
    $| \{""}
    $|   stable_three()
    $|   stable_four()
    $|   stable_five()
    $|-  old_tail()
    $|+  new_tail()
    $| }
    $| \{""}
    $| fn unchanged_after() {}
  let patch = parse_canonical_patch("src/structural.mbt", Some(patch_text))
  assert_true(patch_is_commentable(patch))
  assert_eq(canonical_anchor(patch, Right, 3).unwrap().line, 3)
  assert_eq(canonical_anchor(patch, Left, 12).unwrap().line, 12)
  assert_eq(canonical_anchor(patch, Right, 12).unwrap().line, 12)
}

///|
test "canonical patch handles default counts and truly empty lines" {
  let patch = parse_canonical_patch(
    "empty.txt",
    Some("@@ -4 +7 @@\n-\n+\n\\ No newline at end of file"),
  )
  assert_eq(canonical_anchor(patch, Left, 4).unwrap().position, Some(1))
  assert_eq(canonical_anchor(patch, Right, 7).unwrap().position, Some(2))
}

///|
test "missing truncated and malformed patches are not commentable" {
  for
    patch in [
      None,
      Some(""),
      Some("@@ -1,2 +1,2 @@\n-old\n+new"),
      Some("@@ -1 +1 @@\n?bad"),
      Some("@@ -x +1 @@\n-old\n+new"),
      Some("diff --git a/a b/a\n@@ -1 +1 @@\n-old\n+new"),
    ] {
    assert_false(patch_is_commentable(parse_canonical_patch("a", patch)))
  }
}

///|
test "review rows only expose anchors present in the canonical patch" {
  let document = @linediff.line_diff(old=["context", "old", "tail"], new=[
    "context", "new", "tail",
  ])
  let patch = parse_canonical_patch(
    "src/main.mbt",
    Some("@@ -1,3 +1,3 @@\n context\n-old\n+new\n tail"),
  )
  let rows = project_review_rows(4, "src/main.mbt", document, patch)
  assert_true(rows.length() >= 3)
  guard rows[0].new_line == Some(1) else {
    fail("expected the leading context row")
  }
  assert_eq(rows[0].old_anchor, None)
  assert_true(rows[0].new_anchor is Some(_))
  guard rows[1].old_line == Some(2) && rows[1].new_line == Some(2) else {
    fail("expected an aligned replacement row")
  }
  assert_true(rows[1].old_anchor is Some(_))
  assert_true(rows[1].new_anchor is Some(_))
  assert_eq(rows[1].file_index, 4)

  let disabled = project_review_rows(
    4,
    "src/main.mbt",
    document,
    parse_canonical_patch("src/main.mbt", None),
  )
  assert_true(
    disabled.all(row => row.old_anchor is None && row.new_anchor is None),
  )
}

///|
test "section-local review rows map to absolute GitHub anchors" {
  let document = @linediff.line_diff(old=["old"], new=["new"], context=0)
  let patch = parse_canonical_patch(
    "src/main.mbt",
    Some("@@ -11 +21 @@\n-old\n+new"),
  )
  let rows = project_review_rows(
    2,
    "src/main.mbt",
    document,
    patch,
    old_base=10,
    new_base=20,
  )
  guard rows is [row] else { fail("expected one local replacement row") }
  assert_true(row.old_line == Some(11))
  assert_true(row.new_line == Some(21))
  guard row.old_anchor is Some(old_anchor) else {
    fail("expected an absolute old-side anchor")
  }
  guard row.new_anchor is Some(new_anchor) else {
    fail("expected an absolute new-side anchor")
  }
  assert_true(old_anchor.side is Left)
  assert_eq(old_anchor.line, 11)
  assert_true(new_anchor.side is Right)
  assert_eq(new_anchor.line, 21)

  guard project_review_items(
      2,
      "src/main.mbt",
      document,
      patch,
      old_base=10,
      new_base=20,
    )
    is [ReviewHunk("@@ -11 +21 @@"), ReviewLine(_)] else {
    fail("expected the hunk heading to use absolute section coordinates")
  }

  guard project_review_items(
      2,
      "src/main.mbt",
      document,
      patch,
      old_base=10,
      new_base=20,
      hunk_context="fn target() {",
    )
    is [ReviewHunk("@@ -11 +21 @@ fn target() {"), ReviewLine(_)] else {
    fail("expected the declaration context on the hunk heading")
  }

  guard project_review_items(
      2,
      "src/main.mbt",
      document,
      patch,
      old_base=10,
      new_base=20,
      show_hunk_headers=false,
    )
    is [ReviewLine(hidden)] else {
    fail("expected hidden headings to retain the projected review row")
  }
  assert_true(hidden.old_line == Some(11))
  assert_true(hidden.new_line == Some(21))
  assert_eq(hidden.old_anchor.unwrap().line, 11)
  assert_eq(hidden.new_anchor.unwrap().line, 21)

  let two_hunks : @model.HunkDocument = {
    hunks: [
      { old_start: 0, old_len: 1, new_start: 0, new_len: 1, blocks: [], },
      { old_start: 7, old_len: 1, new_start: 9, new_len: 1, blocks: [], },
    ],
  }
  guard project_review_items(
      2,
      "src/main.mbt",
      two_hunks,
      patch,
      old_base=10,
      new_base=20,
      hunk_context="fn target() {",
    )
    is [
      ReviewHunk("@@ -11 +21 @@ fn target() {"),
      ReviewHunk("@@ -18 +30 @@ fn target() {"),
    ] else {
    fail("expected every hunk heading to share the section context")
  }
}
