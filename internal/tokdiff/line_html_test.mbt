///|
test "plain split pairs replacement lines by position and leaves extras empty" {
  let fewer_new_document = @tokdiff.line_diff(
    old=["old <one>", "old two"],
    new=["new & one"],
    context=0,
  )
  let fewer_new = @render_html.render_side_by_side(
    fewer_new_document,
    line_numbers=true,
  )
  assert_true(
    fewer_new.contains(
      "<td class=\"line-number old-line-number\">1</td><td class=\"del\">old &lt;one&gt;</td><td class=\"line-number new-line-number\">1</td><td class=\"add\">new &amp; one</td>",
    ),
  )
  assert_true(
    fewer_new.contains(
      "<td class=\"line-number old-line-number\">2</td><td class=\"del\">old two</td><td class=\"line-number new-line-number\"></td><td class=\"empty\"></td>",
    ),
  )

  let fewer_old_document = @tokdiff.line_diff(
    old=["old"],
    new=["new one", "new two"],
    context=0,
  )
  let fewer_old = @render_html.render_side_by_side(fewer_old_document)
  assert_true(
    fewer_old.contains(
      "<td class=\"empty\"></td><td class=\"add\">new two</td>",
    ),
  )
  assert_false(fewer_new.contains("<b class=\"wd\">"))
  assert_false(fewer_new.contains("<b class=\"wa\">"))
  assert_false(fewer_old.contains("<b class=\"wd\">"))
  assert_false(fewer_old.contains("<b class=\"wa\">"))
}

///|
test "plain split preserves requested context and absolute line numbers" {
  let old = ["0", "old", "2", "3", "4", "5", "6", "gone", "8"]
  let new = ["0", "new", "2", "3", "4", "5", "6", "added", "8"]
  let document = @tokdiff.line_diff(old~, new~, context=1)
  let html = @render_html.render_side_by_side(document, line_numbers=true)
  assert_true(html.contains("@@ -1,3 +1,3 @@"))
  assert_true(html.contains("@@ -7,3 +7,3 @@"))
  assert_true(
    html.contains(
      "<td class=\"line-number old-line-number\">7</td><td class=\"ctx\">6</td><td class=\"line-number new-line-number\">7</td><td class=\"ctx\">6</td>",
    ),
  )
  assert_true(
    html.contains(
      "<td class=\"line-number old-line-number\">8</td><td class=\"del\">gone</td><td class=\"line-number new-line-number\">8</td><td class=\"add\">added</td>",
    ),
  )
}

///|
test "plain unified emits deletions before insertions without token markup" {
  let document = @tokdiff.line_diff(
    old=["before", "old <one>", "old two", "after"],
    new=["before", "new & one", "new two", "new three", "after"],
    context=1,
  )
  let html = @render_html.render_unified(document, line_numbers=true)
  let first_delete = html.find("class=\"del\">-old &lt;one&gt;").unwrap()
  let second_delete = html.find("class=\"del\">-old two").unwrap()
  let first_insert = html.find("class=\"add\">+new &amp; one").unwrap()
  let last_insert = html.find("class=\"add\">+new three").unwrap()
  assert_true(first_delete < second_delete)
  assert_true(second_delete < first_insert)
  assert_true(first_insert < last_insert)
  assert_true(html.contains("class=\"hunk-header\" colspan=\"3\""))
  assert_true(
    html.contains(
      "<td class=\"line-number old-line-number\">1</td><td class=\"line-number new-line-number\">1</td><td class=\"ctx\"> before</td>",
    ),
  )
  assert_false(html.contains("<b class=\"wd\">"))
  assert_false(html.contains("<b class=\"wa\">"))
}

///|
test "plain unified keeps the historical unnumbered wrapper" {
  inspect(
    @render_html.render_unified(
      @tokdiff.line_diff(old=["<old>"], new=["&new"], context=0),
    ),
    content=(
      #|<pre class="unified">
      #|<span class="hunk-header">@@ -1 +1 @@</span>
      #|<span class="del">-&lt;old&gt;</span>
      #|<span class="add">+&amp;new</span>
      #|</pre>
      #|
    ),
  )
}
