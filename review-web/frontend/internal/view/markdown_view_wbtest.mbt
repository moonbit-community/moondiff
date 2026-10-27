///|
test "GitHub Markdown enables extensions and preserves discussion line breaks" {
  let rendered = markdown_html(
    (
      #|## Summary
      #|
      #|**Bold**, *emphasis*, ~~removed~~ and `inline code`.
      #|First line
      #|Second line
      #|
      #|> A quotation
      #|
      #|- [x] Done
      #|- [ ] Pending
      #|
      #|| Name | Result |
      #|| :--- | ---: |
      #|| Tests | Pass |
      #|
      #|```moonbit
      #|let value = "<escaped>"
      #|```
    ),
  )
  for
    expected in [
      "<h2>Summary</h2>", "<strong>Bold</strong>", "<em>emphasis</em>", "<del>removed</del>",
      "<code>inline code</code>", "First line<br>\nSecond line", "<blockquote>",
      "type=\"checkbox\" disabled checked", "type=\"checkbox\" disabled>", "<table>",
      "<td class=\"right\">Pass</td>", "class=\"language-moonbit\"", "&lt;escaped&gt;",
    ] {
    assert_true(rendered.contains(expected), msg=rendered)
  }
  assert_eq(markdown_html("Plain text"), "<p>Plain text</p>")
  assert_eq(markdown_html(""), "")
}

///|
test "GitHub Markdown strips active HTML and unsafe destinations" {
  let rendered = markdown_html(
    (
      #|<script>window.markdownAttack = true</script>
      #|
      #|before <img src=x onerror="window.markdownAttack=true"> after
      #|
      #|[unsafe](javascript:alert%281%29)
      #|[encoded](jav&#x61;script:alert%281%29)
      #|![unsafe image](data:text/html,attack)
      #|[safe](https://example.com/guide?a=1&b=2)
      #|
      #|```html
      #|<img src=x onerror=alert(1)>
      #|```
    ),
  )
  for
    forbidden in [
      "<script", "<img src=x", "href=\"javascript:", "src=\"data:text/html",
    ] {
    assert_false(rendered.contains(forbidden), msg=rendered)
  }
  assert_true(
    rendered.contains("href=\"https://example.com/guide?a=1&amp;b=2\""),
    msg=rendered,
  )
  assert_true(rendered.contains("&lt;img src=x"), msg=rendered)
}

///|
#warnings("-alert_unstable")
#skip("browser DOM: npm run test:views")
test "comments and PR descriptions mount safe Markdown inside block containers" {
  let source = "## Heading\n\n**Formatted** text.\n\n- item"
  let rendered = render_test_html(() => {
    @html.fragment([
      pull_body_view(Some(source)),
      comment_body_view(
        "author",
        "2026-10-27T00:00:00Z",
        source,
        "https://github.com/owner/repo/pull/1#discussion_r1",
        ReviewComment(1L),
        @comments.Session::new().read_view(),
        Emit(_ => @rabbita.none),
      ),
    ])
  })
  assert_true(
    rendered.contains("aria-label=\"Pull request description\""),
    msg=rendered,
  )
  assert_true(
    rendered.contains("<div class=\"github-comment-body markdown-body\">"),
    msg=rendered,
  )
  assert_eq(rendered.split("<h2>Heading</h2>").count() - 1, 2)
  assert_eq(rendered.split("<strong>Formatted</strong>").count() - 1, 2)
  assert_false(rendered.contains("**Formatted**"), msg=rendered)
  let empty = render_test_html(() => {
    @html.fragment([
      pull_body_view(None),
      pull_body_view(Some("")),
      pull_body_view(Some(" \n\t")),
    ])
  })
  assert_false(empty.contains("pull-description"), msg=empty)
}
