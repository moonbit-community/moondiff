///|
#warnings("-alert_unstable")
fn render_syntax_nodes(nodes : Array[@rabbita.Html]) -> String {
  @rabbita.render_to_string(() => @rabbita.Val::constant(@html.div(nodes)))
}

///|
test "syntax ranges intersect diff segments without changing text or markup" {
  let source = "let value = \"中😀<&>\\n\""
  let highlights = @highlight.SourceHighlights::from_spans(source, [
    { start: 0, end: 3, kind: Keyword, },
    { start: 4, end: 9, kind: Variable, },
    { start: 10, end: 11, kind: Operator, },
    { start: 12, end: 19, kind: StringLiteral, },
    { start: 19, end: 21, kind: Escape, },
    { start: 21, end: 22, kind: StringLiteral, },
  ])
  let rendered = render_syntax_nodes(
    review_segment_nodes(
      Some(source),
      Some([
        { kind: Unchanged, text: "let va", },
        { kind: Changed, text: "lue = \"中", },
        { kind: Ignored, text: "😀<&>\\", },
        { kind: Changed, text: "n\"", },
      ]),
      "wa",
      "+",
      highlights=highlights.line(1),
    ),
  )
  inspect(
    rendered,
    content=(
      #|<div><span class="diff-prefix">+</span><span><span class="syntax-keyword">let</span> <span class="syntax-variable">va</span></span><b class="wa"><span class="syntax-variable">lue</span> <span class="syntax-operator">=</span> <span class="syntax-string">"中</span></b><span class="ignored-context"><span class="syntax-string">😀&lt;&amp;&gt;</span><span class="syntax-escape">\</span></span><b class="wa"><span class="syntax-escape">n</span><span class="syntax-string">"</span></b></div>
    ),
  )
  assert_false(rendered.contains("<span class=\"syntax-variable\">+</span>"))
}

///|
test "plain, empty, and out-of-range lines render without syntax assumptions" {
  let source = "\t<script>&\"中文😀\"  \r"
  let plain = render_syntax_nodes(
    review_segment_nodes(Some(source), None, "wd", ""),
  )
  inspect(
    plain,
    content="<div><span>\t&lt;script&gt;&amp;\"中文😀\"  \r</span></div>",
  )
  assert_eq(render_syntax_nodes(syntax_nodes("", [], 0)), "<div></div>")
  let highlights = @highlight.SourceHighlights::from_spans("let x = 1", [])
  assert_eq(source_line_highlights(Some(highlights), Some(99)).length(), 0)
  assert_eq(source_line_highlights(Some(highlights), None).length(), 0)
  assert_eq(source_line_highlights(None, Some(1)).length(), 0)
}

///|
#warnings("-alert_unstable")
test "semantic sections use original lines for highlights after reorder and same-line declarations" {
  let old = ["fn first() { 11 }", "", "let second = 22; let third = 33"]
  let new = ["let second = 44; let third = 55", "", "fn first() { 66 }"]
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  for algorithm in [@change.LexicalAlgorithm, AstAlgorithm] {
    let file = ensure_file_document(
      ready_test_file(fixture_file("code.mbt", "modified"), old, new),
      algorithm,
    )
    for mode in [@change.Split, Unified] {
      let rendered = @rabbita.render_to_string(() => {
        @rabbita.Val::constant(
          file_diff_view(
            file,
            0,
            0,
            mode,
            algorithm,
            false,
            false,
            @comments.Session::new(),
            emit,
          ),
        )
      })
      for number in ["11", "22", "33", "44", "55", "66"] {
        assert_true(
          rendered.contains("class=\"syntax-number\">\{number}</span>"),
          msg=number,
        )
      }
      assert_true(rendered.contains("class=\"syntax-function\">first</span>"))
      assert_true(rendered.contains("class=\"syntax-variable\">second</span>"))
      assert_true(rendered.contains("class=\"syntax-variable\">third</span>"))
    }
  }
}
