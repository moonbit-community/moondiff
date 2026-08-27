///|
test "RenderOptions retains only display controls" {
  let options = @terminal.RenderOptions::new(
    use_color=true,
    old_max_line=10,
    new_max_line=100,
  )
  assert_true(options.use_color)
  assert_true(options.old_max_line is Some(10))
  assert_true(options.new_max_line is Some(100))
  let defaults : @terminal.RenderOptions = Default::default()
  assert_false(defaults.use_color)
  assert_true(defaults.old_max_line is None)
  assert_true(defaults.new_max_line is None)
}

///|
test "render_document highlights changes and keeps ignored text neutral" {
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
  let document : @model.HunkDocument = {
    hunks: [
      {
        old_start: 0,
        old_len: 3,
        new_start: 0,
        new_len: 3,
        rows: [
          Context({ old_index: 0, new_index: 0, text: "fn value() {" }),
          Changed(Paired(old_line, new_line)),
          Neutral(Paired(old_comment, new_comment)),
        ],
      },
    ],
  }

  let plain = @terminal.render_document(
    "old.mbt",
    "new.mbt",
    document,
    options=@terminal.RenderOptions::new(use_color=false),
  )
  assert_eq(
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

  let colored = @terminal.render_document(
    "old.mbt",
    "new.mbt",
    document,
    options=@terminal.RenderOptions::new(use_color=true),
  )
  assert_true(colored.contains("\u{1b}[31m\u{1b}[1m1\u{1b}[22m\u{1b}[39m"))
  assert_true(colored.contains("\u{1b}[32m\u{1b}[1m2\u{1b}[22m\u{1b}[39m"))
  assert_true(colored.contains("\u{1b}[90m // old explanation\u{1b}[39m"))
  assert_true(colored.contains("\u{1b}[90m // new explanation\u{1b}[39m"))
  assert_false(colored.contains("\u{1b}[31m\u{1b}[1m// old docs"))
  assert_false(colored.contains("\u{1b}[32m\u{1b}[1m// new docs"))
}

///|
test "render_document honors 9 to 10 and 99 to 100 width hints" {
  let document : @model.HunkDocument = {
    hunks: [
      {
        old_start: 8,
        old_len: 1,
        new_start: 8,
        new_len: 1,
        rows: [Context({ old_index: 8, new_index: 8, text: "same" })],
      },
    ],
  }
  let rendered = @terminal.render_document(
    "old.txt",
    "new.txt",
    document,
    options=@terminal.RenderOptions::new(old_max_line=10, new_max_line=100),
  )
  assert_true(rendered.contains("\n 9   9 same\n"), msg=rendered)
}
