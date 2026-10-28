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

///|
test "ordinary and reference links resolve against their GitHub source page" {
  let markdown = image_test_context()
  for
    (destination, expected) in [
      ("guide.md", "https://github.com/upstream/project/pull/guide.md"),
      ("../issues/18", "https://github.com/upstream/project/issues/18"),
      (
        "/upstream/project/issues/18", "https://github.com/upstream/project/issues/18",
      ),
      (
        "?tab=files&show=all", "https://github.com/upstream/project/pull/17?tab=files&amp;show=all",
      ),
      ("#section", "https://github.com/upstream/project/pull/17#section"),
      ("", "https://github.com/upstream/project/pull/17"),
      ("//example.com/guide", "https://example.com/guide"),
      ("https://example.com/guide", "https://example.com/guide"),
      ("mailto:reader@example.com", "mailto:reader@example.com"),
    ] {
    for
      source in [
        "[label](<\{destination}> \"title\")",
        "[label][ref]\n\n[ref]: <\{destination}> \"title\"",
      ] {
      let rendered = markdown_html(source, markdown~)
      assert_true(
        rendered.contains("href=\"\{expected}\" title=\"title\""),
        msg=rendered,
      )
    }
  }
  // A shared reference definition still uses repository-pinned image rules.
  let rendered = markdown_html(
    "[guide][ref] ![image][ref]\n\n[ref]: image.png",
    markdown~,
  )
  assert_true(
    rendered.contains(
      "href=\"https://github.com/upstream/project/pull/image.png\"",
    ),
    msg=rendered,
  )
  assert_true(
    rendered.contains(
      "data-markdown-src=\"https://raw.githubusercontent.com/contributor/project-fork/\{"a".repeat(40)}/image.png\"",
    ),
    msg=rendered,
  )
}

///|
test "invalid origins and unsafe normalized destinations cannot create local links" {
  for source in ["relative", "../guide", "/root", "?query", "#fragment", ""] {
    let body = "[**label**](<\{source}>)"
    assert_eq(markdown_html(body), "<p><strong>label</strong></p>")
    for
      page_url in [
        "", "invalid", "javascript:alert(1)", "https://other.example/", "https://user@github.com/o/r",
        "http://github.com/o/r",
      ] {
      assert_eq(
        markdown_html(body, markdown={ ..image_test_context(), page_url, }),
        "<p><strong>label</strong></p>",
      )
    }
  }
  for
    source in [
      "javascript:alert%281%29", "jav&#x61;script:alert%281%29", "java&#9;script:alert%281%29",
      "java&#10;script:alert%281%29", "&#32;javascript:alert%281%29", "VBScript:attack",
      "file:///etc/passwd", "data:text/html,attack",
    ] {
    let rendered = markdown_html(
      "[label](<\{source}>)",
      markdown=image_test_context(),
    )
    assert_eq(rendered, "<p>label</p>")
  }
}
