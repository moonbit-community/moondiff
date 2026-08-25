///|
test "RenderOptions clamps negative context lines to zero" {
  let options = RenderOptions::new(context_lines=-1)
  assert_eq(options.context_lines, 0)
  let rendered = render_line_diff(
    "old.txt",
    "unchanged before\nold value\nunchanged after",
    "new.txt",
    "unchanged before\nnew value\nunchanged after",
    None,
    None,
    options,
  )
  assert_true(rendered.contains("old value"))
  assert_true(rendered.contains("new value"))
  assert_false(rendered.contains("unchanged before"))
  assert_false(rendered.contains("unchanged after"))
}

///|UUID(0d1a0a7b-5a0d-4d9e-8fd3-e90428d09cc1)
test "display_line_no colors missing placeholder dots gray for every line style" {
  @debug.assert_eq(
    display_line_no(None, 2, 1, Deleted, true),
    "\u{1b}[90m..\u{1b}[39m",
  )
  @debug.assert_eq(
    display_line_no(None, 2, 1, Added, true),
    "\u{1b}[90m..\u{1b}[39m",
  )
  @debug.assert_eq(
    display_line_no(None, 2, 1, Context, true),
    "\u{1b}[90m..\u{1b}[39m",
  )
  @debug.assert_eq(display_line_no(None, 2, 1, Added, false), "..")
}

///|
test "render_diff_document highlights changes and keeps ignored text neutral" {
  let old_line : @model.DiffLine = {
    index: 1,
    segments: [
      { kind: Unchanged, text: "let value = " },
      { kind: Changed, text: "1" },
      { kind: Ignored, text: " // old explanation" },
    ],
  }
  let new_line : @model.DiffLine = {
    index: 1,
    segments: [
      { kind: Unchanged, text: "let value = " },
      { kind: Changed, text: "2" },
      { kind: Ignored, text: " // new explanation" },
    ],
  }
  let old_comment : @model.DiffLine = {
    index: 2,
    segments: [{ kind: Ignored, text: "// old docs" }],
  }
  let new_comment : @model.DiffLine = {
    index: 2,
    segments: [{ kind: Ignored, text: "// new docs" }],
  }
  let document : @model.DiffDocument = {
    hunks: [
      {
        old_start: 0,
        old_len: 3,
        new_start: 0,
        new_len: 3,
        blocks: [
          ContextBlock([{ old_index: 0, new_index: 0, text: "fn value() {" }]),
          ChangeBlock([Paired(old_line, new_line)]),
          IgnoredBlock([Paired(old_comment, new_comment)]),
        ],
      },
    ],
  }

  let plain = render_diff_document(
    "old.mbt",
    "new.mbt",
    document,
    RenderOptions::new(use_color=false),
  )
  @debug.assert_eq(
    plain,
    (
      #|--- old.mbt
      #|+++ new.mbt
      #|@@ -1,3 +1,3 @@
      #|1 1 fn value() {
      #|2 . let value = 1 // old explanation
      #|. 2 let value = 2 // new explanation
      #|3 . // old docs
      #|. 3 // new docs
      #|
    ),
  )
  assert_false(plain.contains("\u{1b}["))

  let colored = render_diff_document(
    "old.mbt",
    "new.mbt",
    document,
    RenderOptions::new(use_color=true),
  )
  assert_true(colored.contains("\u{1b}[31m\u{1b}[1m1\u{1b}[22m\u{1b}[39m"))
  assert_true(colored.contains("\u{1b}[32m\u{1b}[1m2\u{1b}[22m\u{1b}[39m"))
  assert_true(colored.contains("\u{1b}[90m // old explanation\u{1b}[39m"))
  assert_true(colored.contains("\u{1b}[90m // new explanation\u{1b}[39m"))
  assert_false(colored.contains("\u{1b}[31m\u{1b}[1m// old docs"))
  assert_false(colored.contains("\u{1b}[32m\u{1b}[1m// new docs"))
}
