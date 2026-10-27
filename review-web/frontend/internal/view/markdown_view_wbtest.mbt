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
