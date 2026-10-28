///|
test "unsupported HTML preserves block and inline content as escaped text" {
  for
    source in [
      "<details>\n<summary>Summary</summary>\nImportant **body**\n</details>", "<div>Before <img src='https://camo.githubusercontent.com/image'> after</div>",
      "<script>\nwindow.attack = true;\nfetch('https://evil.example/request');\n</script>",
      "<style>body { background: url(https://evil.example/image); }</style>", "<iframe src='https://evil.example/frame'>fallback</iframe>",
      "<div broken=\"unterminated>\nBody after malformed HTML", "<!-- comment --> visible body",
    ] {
    let rendered = markdown_html(source)
    assert_true(rendered.contains(markdown_escape(source)), msg=rendered)
    assert_false(rendered.contains("<img"), msg=rendered)
    assert_false(rendered.contains("<script"), msg=rendered)
    assert_false(rendered.contains("<iframe"), msg=rendered)
    assert_true(rendered.contains("class=\"markdown-html-raw\""), msg=rendered)
  }
  let inline = markdown_html("Before <span title='x'>body</span> after")
  assert_true(inline.contains("&lt;span title=&#39;x&#39;&gt;"), msg=inline)
  assert_true(inline.contains("body"), msg=inline)
  assert_true(inline.contains("&lt;/span&gt;"), msg=inline)
  assert_eq(markdown_html("<!-- hidden -->"), "")
  assert_eq(markdown_html("<!-- one -->\n<!-- two -->"), "")
  for comment in ["<!-->", "<!--->", "<!---->", "<!-- a\n b -->"] {
    assert_eq(markdown_html("before \{comment} after"), "<p>before  after</p>")
  }
  assert_eq(
    markdown_html("before <!-- hidden --> after"),
    "<p>before  after</p>",
  )
}
