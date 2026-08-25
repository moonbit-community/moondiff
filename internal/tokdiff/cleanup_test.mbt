///|
fn count_substring(text : String, needle : String) -> Int {
  let mut rest = text.view()
  let mut count = 0
  while rest.find(needle) is Some(index) {
    count += 1
    rest = rest.view(start_offset=index + needle.length())
  }
  count
}

///|
test "token cleanup highlights the natural repeated-token boundary" {
  let split = @render_html.side_by_side_html(old=["x x"], new=["x"], context=0)
  assert_true(
    split.contains(
      "<td class=\"del\">x <b class=\"wd\">x</b></td><td class=\"add\">x</td>",
    ),
  )
  let comment = @render_html.unified_html(old=["// foo foo"], new=["// foo"])
  assert_true(comment.contains("// foo <b class=\"wd\">foo</b>"))
  let unicode = @render_html.side_by_side_html(old=["名 名"], new=["名"])
  assert_true(unicode.contains("名 <b class=\"wd\">名</b>"))
}

///|
test "global traceback fixes left-leaning insertion in both renderers" {
  let old = ["    match candidate.normalized_expr_identifier_name() {"]
  let new = [
    "    if candidate.normalized_expr_identifier_name() is Some(candidate_name) {",
  ]
  let expected = "    <b class=\"wa\">if</b> candidate.normalized_expr_identifier_name() <b class=\"wa\">is Some(candidate_name)</b> {"
  let split = @render_html.side_by_side_html(
    old~,
    new~,
    context=0,
    line_cleanup=false,
  )
  let unified = @render_html.unified_html(
    old~,
    new~,
    context=0,
    line_cleanup=false,
  )
  assert_true(split.contains(expected))
  assert_true(unified.contains(expected))
  assert_eq(
    split,
    @render_html.side_by_side_html(old~, new~, context=0, line_cleanup=true),
  )
  assert_eq(
    unified,
    @render_html.unified_html(old~, new~, context=0, line_cleanup=true),
  )
}

///|
test "line cleanup is opt-in and removes a misleading blank anchor" {
  let old = ["let a = old", "", "let b = old", "let c = old"]
  let new = ["let a = new", "let b = new", "let c = new", ""]
  let default_split = @render_html.side_by_side_html(old~, new~, context=0)
  assert_eq(
    default_split,
    @render_html.side_by_side_html(old~, new~, context=0, line_cleanup=false),
  )
  assert_true(count_substring(default_split, "class=\"hunk-header\"") == 2)
  let cleaned = @render_html.side_by_side_html(
    old~,
    new~,
    context=0,
    line_cleanup=true,
  )
  assert_true(
    cleaned.contains(
      "<td class=\"del\">let b = <b class=\"wd\">old</b></td><td class=\"add\">let b = <b class=\"wa\">new</b></td>",
    ),
  )
  assert_true(count_substring(cleaned, "class=\"hunk-header\"") == 1)
}

///|
test "re-aligned identical meaningful line is rendered as context" {
  let old = ["let a = old", "same line", "let b = old", "}", "let c = old", "}"]
  let new = ["let a = new", "}", "same line", "let b = new", "let c = new", "}"]
  let split = @render_html.side_by_side_html(
    old~,
    new~,
    context=1,
    line_cleanup=true,
  )
  assert_true(
    split.contains(
      "<td class=\"ctx\">same line</td><td class=\"ctx\">same line</td>",
    ),
  )
  let unified = @render_html.unified_html(
    old~,
    new~,
    context=1,
    line_cleanup=true,
  )
  assert_true(unified.contains("<span class=\"ctx\"> same line</span>"))
}

///|
test "patience keeps an unchanged branch ahead of repeated tuple boilerplate" {
  let old : Array[String] = (
      #|            false,
      #|        Some({ review: Some({ baseline: ReviewContent(_), .. }), .. }) =>
      #|          ("Diff vs HEAD", "Quick diff against the HEAD version", false, false)
      #|        Some({ review: Some({ baseline: ReviewMissing, .. }), .. }) =>
      #|          (
      #|            "New · no HEAD", "New file compared with an empty HEAD baseline", false,
      #|            false,
      #|          )
      #|        Some({ review: Some({ baseline: ReviewBinary, .. }), .. }) =>
    )
    .split("\n")
    .map(StringView::to_owned)
    .collect()
  let new : Array[String] = (
      #|            false,
      #|        Some({ review: Some({ baseline: ReviewContent(_), .. }), .. }) =>
      #|          (
      #|            "Diff vs baseline", "Quick diff against the review baseline", false,
      #|            false,
      #|          )
      #|        Some({ review: Some({ baseline: ReviewMissing, .. }), .. }) =>
      #|          (
      #|            "New · no baseline", "New file compared with an empty review baseline",
      #|            false, false,
      #|          )
      #|        Some({ review: Some({ baseline: ReviewBinary, .. }), .. }) =>
    )
    .split("\n")
    .map(StringView::to_owned)
    .collect()
  let marker = "        Some({ review: Some({ baseline: ReviewMissing, .. }), .. }) =&gt;"
  let split = @render_html.side_by_side_html(
    old~,
    new~,
    context=1,
    line_cleanup=true,
  )
  assert_true(
    split.contains(
      "<td class=\"ctx\">\{marker}</td><td class=\"ctx\">\{marker}</td>",
    ),
  )
  let unified = @render_html.unified_html(
    old~,
    new~,
    context=1,
    line_cleanup=true,
  )
  assert_true(unified.contains("<span class=\"ctx\"> \{marker}</span>"))
  assert_false(unified.contains("<span class=\"del\">-\{marker}</span>"))
  assert_false(unified.contains("<span class=\"add\">+\{marker}</span>"))
}

///|
test "both renderers preserve exact core hunk headers for all contexts" {
  let old = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"]
  let new = ["a", "B", "c", "d", "e", "f", "g", "H", "i", "j"]
  for
    case in [
      (0, ["@@ -2 +2 @@", "@@ -8 +8 @@"]),
      (1, ["@@ -1,3 +1,3 @@", "@@ -7,3 +7,3 @@"]),
      (3, ["@@ -1,10 +1,10 @@"]),
      (99, ["@@ -1,10 +1,10 @@"]),
    ] {
    let (context, headers) = case
    let split = @render_html.side_by_side_html(
      old~,
      new~,
      context~,
      line_cleanup=true,
    )
    let unified = @render_html.unified_html(
      old~,
      new~,
      context~,
      line_cleanup=true,
    )
    assert_eq(count_substring(split, "class=\"hunk-header\""), headers.length())
    assert_eq(
      count_substring(unified, "class=\"hunk-header\""),
      headers.length(),
    )
    for header in headers {
      assert_true(
        split.contains("<td class=\"hunk-header\" colspan=\"2\">\{header}</td>"),
      )
      assert_true(
        unified.contains("<span class=\"hunk-header\">\{header}</span>"),
      )
    }
  }
}

///|
test "pure insertion and deletion retain file-edge hunk ranges" {
  inspect(
    @render_html.side_by_side_html(
      old=[],
      new=["x", "y"],
      context=0,
      line_cleanup=true,
    ),
    content=(
      #|<table class="split">
      #|<tr><td class="hunk-header" colspan="2">@@ -0,0 +1,2 @@</td></tr>
      #|<tr><td class="empty"></td><td class="add">x</td></tr>
      #|<tr><td class="empty"></td><td class="add">y</td></tr>
      #|</table>
      #|
    ),
  )
  inspect(
    @render_html.unified_html(
      old=["x", "y"],
      new=[],
      context=0,
      line_cleanup=true,
    ),
    content=(
      #|<pre class="unified">
      #|<span class="hunk-header">@@ -1,2 +0,0 @@</span>
      #|<span class="del">-x</span>
      #|<span class="del">-y</span>
      #|</pre>
      #|
    ),
  )
}

///|
fn assert_line_cleanup_budget_fallback(
  old : Array[String],
  new : Array[String],
) -> Unit raise {
  assert_eq(
    @render_html.side_by_side_html(old~, new~, context=0, line_cleanup=true),
    @render_html.side_by_side_html(old~, new~, context=0, line_cleanup=false),
  )
  assert_eq(
    @render_html.unified_html(old~, new~, context=0, line_cleanup=true),
    @render_html.unified_html(old~, new~, context=0, line_cleanup=false),
  )
}

///|
test "line cleanup restores original grouping at all window budgets" {
  let many_old : Array[String] = []
  let many_new : Array[String] = []
  for i in 0..<65 {
    many_old.push("old declaration \{i}")
    many_new.push("new expression \{i}")
  }
  many_old.push("")
  many_new.push("")
  many_old.push("old tail")
  many_new.push("new tail")
  assert_line_cleanup_budget_fallback(many_old, many_new)

  let huge_old = "word ".repeat(600) + "old"
  let huge_new = "word ".repeat(600) + "new"
  assert_line_cleanup_budget_fallback([huge_old, "", "old tail"], [
    huge_new, "", "new tail",
  ])

  let cells_old : Array[String] = []
  let cells_new : Array[String] = []
  for i in 0..<50 {
    cells_old.push(
      "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi OLD\{i}",
    )
    cells_new.push(
      "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi NEW\{i}",
    )
  }
  cells_old.push("")
  cells_new.push("")
  cells_old.push("old tail")
  cells_new.push("new tail")
  assert_line_cleanup_budget_fallback(cells_old, cells_new)
}

///|
test "per-pair traceback budget keeps pairing but omits highlights" {
  let old_line = "x ".repeat(256) + "old"
  let new_line = "x ".repeat(256) + "new"
  let split = @render_html.side_by_side_html(
    old=[old_line],
    new=[new_line],
    context=0,
  )
  assert_false(split.contains("<b class="))
  assert_true(
    split.contains(
      "<td class=\"del\">\{old_line}</td><td class=\"add\">\{new_line}</td>",
    ),
  )
  let unified = @render_html.unified_html(
    old=[old_line],
    new=[new_line],
    context=0,
  )
  assert_false(unified.contains("<b class="))
  assert_true(
    unified.find("class=\"del\"").unwrap() <
    unified.find("class=\"add\"").unwrap(),
  )
}
