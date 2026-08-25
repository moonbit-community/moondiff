///|
test "plain replacement honors zero and default context" {
  let old = "same\nold\ntail"
  let new = "same\nnew\ntail"
  inspect(
    @cli_diff.render(
      "old.txt",
      old,
      "new.txt",
      new,
      options=@cli_diff.Options::new(context_lines=0),
    ),
    content=(
      #|--- old.txt
      #|+++ new.txt
      #|@@ -2 +2 @@
      #|2 . old
      #|. 2 new
      #|
    ),
  )
  inspect(
    @cli_diff.render("old.txt", old, "new.txt", new),
    content=(
      #|--- old.txt
      #|+++ new.txt
      #|@@ -1,3 +1,3 @@
      #|1 1 same
      #|2 . old
      #|. 2 new
      #|3 3 tail
      #|
    ),
  )
}

///|
test "plain insertion deletion repetition and multiple hunks use Patience" {
  let inserted = @cli_diff.render(
    "old.txt",
    "anchor\nrepeat\nrepeat\ntail",
    "new.txt",
    "anchor\nrepeat\ninserted\nrepeat\ntail",
    options=@cli_diff.Options::new(context_lines=0),
  )
  assert_true(inserted.contains("@@ -2,0 +3 @@"), msg=inserted)
  assert_true(inserted.contains(". 3 inserted"), msg=inserted)

  let deleted = @cli_diff.render(
    "old.txt",
    "anchor\nrepeat\ndeleted\nrepeat\ntail",
    "new.txt",
    "anchor\nrepeat\nrepeat\ntail",
    options=@cli_diff.Options::new(context_lines=0),
  )
  assert_true(deleted.contains("@@ -3 +2,0 @@"), msg=deleted)
  assert_true(deleted.contains("3 . deleted"), msg=deleted)

  let multiple = @cli_diff.render(
    "old.txt",
    "0\nold one\n2\n3\n4\n5\n6\nold two\n8",
    "new.txt",
    "0\nnew one\n2\n3\n4\n5\n6\nnew two\n8",
    options=@cli_diff.Options::new(context_lines=0),
  )
  assert_true(multiple.contains("@@ -2 +2 @@"), msg=multiple)
  assert_true(multiple.contains("@@ -8 +8 @@"), msg=multiple)
}

///|
test "plain empty files and final newline keep explicit line semantics" {
  inspect(
    @cli_diff.render("old.txt", "", "new.txt", ""),
    content=(
      #|--- old.txt
      #|+++ new.txt
      #|No changes.
      #|
    ),
  )
  inspect(
    @cli_diff.render(
      "old.txt",
      "",
      "new.txt",
      "x",
      options=@cli_diff.Options::new(context_lines=0),
    ),
    content=(
      #|--- old.txt
      #|+++ new.txt
      #|@@ -1,0 +1 @@
      #|. 1 x
      #|
    ),
  )
  inspect(
    @cli_diff.render(
      "old.txt",
      "x",
      "new.txt",
      "",
      options=@cli_diff.Options::new(context_lines=0),
    ),
    content=(
      #|--- old.txt
      #|+++ new.txt
      #|@@ -1 +1,0 @@
      #|1 . x
      #|
    ),
  )
  inspect(
    @cli_diff.render("old.txt", "a", "new.txt", "a\n"),
    content="--- old.txt\n+++ new.txt\n@@ -1 +1,2 @@\n1 1 a\n. 2 \n",
  )
}

///|
test "plain calculation uses universal newline splitting" {
  let lf = @cli_diff.render(
    "old.txt",
    "a\nold\nz",
    "new.txt",
    "a\nnew\nz",
    options=@cli_diff.Options::new(context_lines=0),
  )
  let crlf = @cli_diff.render(
    "old.txt",
    "a\r\nold\r\nz",
    "new.txt",
    "a\r\nnew\r\nz",
    options=@cli_diff.Options::new(context_lines=0),
  )
  let cr = @cli_diff.render(
    "old.txt",
    "a\rold\rz",
    "new.txt",
    "a\rnew\rz",
    options=@cli_diff.Options::new(context_lines=0),
  )
  assert_eq(crlf, lf)
  assert_eq(cr, lf)
}

///|
test "plain output reserves full-file widths across digit boundaries" {
  let old10 = Array::make(10, "same")
  let new10 = Array::make(10, "same")
  old10[0] = "old"
  new10[0] = "new"
  let ten = @cli_diff.render(
    "old.txt",
    old10.join("\n"),
    "new.txt",
    new10.join("\n"),
    options=@cli_diff.Options::new(context_lines=0),
  )
  assert_true(ten.contains("\n 1 .. old\n..  1 new\n"), msg=ten)

  let old100 = Array::make(100, "same")
  let new100 = Array::make(100, "same")
  old100[0] = "old"
  new100[0] = "new"
  let hundred = @cli_diff.render(
    "old.txt",
    old100.join("\n"),
    "new.txt",
    new100.join("\n"),
    options=@cli_diff.Options::new(context_lines=0),
  )
  assert_true(hundred.contains("\n  1 ... old\n...   1 new\n"), msg=hundred)
}

///|
test "plain output honors ANSI toggle and mixed paths stay on line diff" {
  let plain = @cli_diff.render(
    "old.mbt",
    "fn broken( { old",
    "new.txt",
    "fn broken( { new",
    options=@cli_diff.Options::new(
      context_lines=0,
      graph_limit=0,
      use_color=false,
      ignore_comments=true,
      ignore_tests=true,
    ),
  )
  assert_false(plain.contains("\u{1b}["))
  assert_false(plain.contains("fallback"), msg=plain)

  let colored = @cli_diff.render(
    "old.txt",
    "old",
    "new.txt",
    "new",
    options=@cli_diff.Options::new(context_lines=0, use_color=true),
  )
  assert_true(colored.has_prefix("\u{1b}[34m--- old.txt"), msg=colored)
  assert_true(
    colored.contains("\u{1b}[31m\u{1b}[1mold\u{1b}[22m\u{1b}[39m"),
    msg=colored,
  )
  assert_true(
    colored.contains("\u{1b}[32m\u{1b}[1mnew\u{1b}[22m\u{1b}[39m"),
    msg=colored,
  )
}
