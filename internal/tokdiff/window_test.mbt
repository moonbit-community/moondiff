///|
test "pure cross-line reflow keeps row colors without strong token markup" {
  let old = ["call(alpha, beta, gamma)"]
  let new = ["call(", "  alpha, beta,", "  gamma)"]
  let document = @tokdiff.diff(old~, new~, context=0)
  let split = @render_html.render_side_by_side(document)
  let unified = @render_html.render_unified(document)
  assert_true(split.contains("class=\"del\""))
  assert_true(split.contains("class=\"add\""))
  assert_true(unified.contains("class=\"del\""))
  assert_true(unified.contains("class=\"add\""))
  assert_false(split.contains("<b class="))
  assert_false(unified.contains("<b class="))
}

///|
test "expanded reflow highlights inserted tokens on unpaired lines" {
  let old = ["compute(alpha, beta)"]
  let new = ["compute(", "  alpha,", "  beta,", "  gamma < limit,  ", ")"]
  let document = @tokdiff.diff(old~, new~, context=0)
  let split = @render_html.render_side_by_side(document, line_numbers=true)
  let unified = @render_html.render_unified(document, line_numbers=true)
  let beta = "  beta<b class=\"wa\">,</b>"
  let added = "  <b class=\"wa\">gamma &lt; limit,</b>  "
  assert_true(split.contains(beta))
  assert_true(unified.contains(beta))
  assert_true(split.contains(added))
  assert_true(unified.contains(added))
  assert_true(
    split.contains(
      "<td class=\"line-number new-line-number\">4</td><td class=\"add\">\{added}</td>",
    ),
  )
  assert_true(
    unified.contains(
      "<td class=\"line-number new-line-number\">4</td><td class=\"add\">+\{added}</td>",
    ),
  )
  assert_false(split.contains("<b class=\"wd\">"))
  assert_false(unified.contains("<b class=\"wd\">"))
}

///|
test "reflowed substitution and trailing comma stay independently changed" {
  let old = ["call(alpha, old, omega)"]
  let new = ["call(", "  alpha,", "  fresh,", "  omega,", ")"]
  let document = @tokdiff.diff(old~, new~, context=0)
  let split = @render_html.render_side_by_side(document)
  let unified = @render_html.render_unified(document)
  let old_change = "call(alpha, <b class=\"wd\">old</b>, omega)"
  let replacement = "  <b class=\"wa\">fresh</b>,"
  let trailing_comma = "  omega<b class=\"wa\">,</b>"
  for html in [split, unified] {
    assert_true(html.contains(old_change))
    assert_true(html.contains(replacement))
    assert_true(html.contains(trailing_comma))
  }
}

///|
test "rejected multi-line window strongly highlights unpaired lines" {
  let old = ["let total = price", "unrelated old"]
  let new = ["let sum = price", "different new"]
  let document = @tokdiff.diff(old~, new~, context=0)
  let split = @render_html.render_side_by_side(document)
  let unified = @render_html.render_unified(document)
  let old_pair = "let <b class=\"wd\">total</b> = price"
  let new_pair = "let <b class=\"wa\">sum</b> = price"
  let old_unpaired = "<b class=\"wd\">unrelated old</b>"
  let new_unpaired = "<b class=\"wa\">different new</b>"
  for html in [split, unified] {
    assert_true(html.contains(old_pair))
    assert_true(html.contains(new_pair))
    assert_true(html.contains(old_unpaired))
    assert_true(html.contains(new_unpaired))
    assert_false(html.contains("<b class=\"wd\">let total = price</b>"))
    assert_false(html.contains("<b class=\"wa\">let sum = price</b>"))
  }
  assert_true(
    split.contains(
      "<td class=\"del\">\{old_unpaired}</td><td class=\"empty\"></td>",
    ),
  )
  assert_true(
    split.contains(
      "<td class=\"empty\"></td><td class=\"add\">\{new_unpaired}</td>",
    ),
  )
}

///|
test "window traceback cell overflow takes the complete bounded fallback" {
  let old_line = "x ".repeat(256) + "old"
  let new_line = "x ".repeat(256) + "new"
  let old = [old_line, old_line]
  let new = [new_line, new_line]
  let document = @tokdiff.diff(old~, new~, context=0)
  let split = @render_html.render_side_by_side(document)
  let unified = @render_html.render_unified(document)
  assert_false(split.contains("<b class="))
  assert_false(unified.contains("<b class="))
  assert_true(split.contains("<td class=\"del\">\{old_line}</td>"))
  assert_true(split.contains("<td class=\"add\">\{new_line}</td>"))
}

///|
test "context and line cleanup keep meaningful anchors outside the window" {
  let old = [
    "before semantic anchor", "call(alpha, old, omega)", "after semantic anchor",
  ]
  let new = [
    "before semantic anchor", "call(", "  alpha,", "  fresh,", "  omega,", ")", "after semantic anchor",
  ]
  for context in [0, 3] {
    let raw_document = @tokdiff.diff(old~, new~, context~, line_cleanup=false)
    let split = @render_html.render_side_by_side(raw_document)
    let unified = @render_html.render_unified(raw_document)
    assert_true(split.contains("<b class=\"wd\">old</b>"))
    assert_true(split.contains("<b class=\"wa\">fresh</b>"))
    assert_true(unified.contains("<b class=\"wd\">old</b>"))
    assert_true(unified.contains("<b class=\"wa\">fresh</b>"))
    assert_eq(
      split,
      @render_html.render_side_by_side(
        @tokdiff.diff(old~, new~, context~, line_cleanup=true),
      ),
    )
    assert_eq(
      unified,
      @render_html.render_unified(
        @tokdiff.diff(old~, new~, context~, line_cleanup=true),
      ),
    )
  }
}
