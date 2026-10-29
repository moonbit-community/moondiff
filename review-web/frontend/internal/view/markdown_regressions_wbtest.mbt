///|
test "unsupported HTML preserves block and inline content as escaped text" {
  for
    source in [
      "<details>\n<summary>Summary</summary>\nImportant **body**\n</details>", "<div>Before <img src='https://camo.githubusercontent.com/image'> after</div>",
      "<script>\nwindow.attack = true;\nfetch('https://evil.example/request');\n</script>",
      "<style>body { background: url(https://evil.example/image); }</style>", "<iframe src='https://evil.example/frame'>fallback</iframe>",
      "<div broken=\"unterminated>\nBody after malformed HTML", "<!-- comment --> visible body",
    ] {
    let rendered = markdown_html(source, scope="html")
    assert_true(rendered.contains(markdown_escape(source)), msg=rendered)
    assert_false(rendered.contains("<img"), msg=rendered)
    assert_false(rendered.contains("<script"), msg=rendered)
    assert_false(rendered.contains("<iframe"), msg=rendered)
    assert_true(rendered.contains("class=\"markdown-html-raw\""), msg=rendered)
  }
  let inline = markdown_html(
    "Before <span title='x'>body</span> after",
    scope="html",
  )
  assert_true(inline.contains("&lt;span title=&#39;x&#39;&gt;"), msg=inline)
  assert_true(inline.contains("body"), msg=inline)
  assert_true(inline.contains("&lt;/span&gt;"), msg=inline)
  assert_eq(markdown_html("<!-- hidden -->", scope="html"), "")
  assert_eq(markdown_html("<!-- one -->\n<!-- two -->", scope="html"), "")
  for comment in ["<!-->", "<!--->", "<!---->", "<!-- a\n b -->"] {
    assert_eq(
      markdown_html("before \{comment} after", scope="html"),
      "<p>before  after</p>",
    )
  }
  assert_eq(
    markdown_html("before <!-- hidden --> after", scope="html"),
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
      let rendered = markdown_html(source, scope="links", markdown~)
      assert_true(
        rendered.contains("href=\"\{expected}\" title=\"title\""),
        msg=rendered,
      )
    }
  }
  // A shared reference definition still uses repository-pinned image rules.
  let rendered = markdown_html(
    "[guide][ref] ![image][ref]\n\n[ref]: image.png",
    scope="links",
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
    assert_eq(
      markdown_html(body, scope="links"),
      "<p><strong>label</strong></p>",
    )
    for
      page_url in [
        "", "invalid", "javascript:alert(1)", "https://other.example/", "https://user@github.com/o/r",
        "http://github.com/o/r",
      ] {
      assert_eq(
        markdown_html(body, scope="links", markdown={
          ..image_test_context(),
          page_url,
        }),
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
      scope="links",
      markdown=image_test_context(),
    )
    assert_eq(rendered, "<p>label</p>")
  }
}

///|
test "footnotes have stable disjoint IDs including Unicode and repeated references" {
  let body =
    #|First[^说明🙂], again[^说明🙂], [named][^说明🙂], separate[^a b] and distinct[^a-b].
    #|
    #|[^说明🙂]: Unicode definition with [source](#section).
    #|[^a b]: Space definition.
    #|[^a-b]: Dash definition.
  let scopes = [
    "7:pull-description", "7:issue:1", "7:review:1", "7:review:2", "7:commit:1",
    "8:issue:1",
  ]
  let all_ids : Map[String, Bool] = Map([])
  for scope in scopes {
    let rendered = markdown_html(body, scope~, markdown=image_test_context())
    assert_eq(
      markdown_html(body, scope~, markdown=image_test_context()),
      rendered,
    )
    assert_eq(rendered.split("role=\"doc-noteref\"").count() - 1, 5)
    assert_eq(rendered.split("role=\"doc-backlink\"").count() - 1, 5)
    assert_true(rendered.contains("Unicode definition"), msg=rendered)
    assert_true(
      rendered.contains("https://github.com/upstream/project/pull/17#section"),
      msg=rendered,
    )
    let ids = rendered
      .split(" id=\"")
      .drop(1)
      .map(s => s.split("\"").next().unwrap().to_owned())
      .collect()
    assert_eq(ids.length(), 8)
    for id in ids {
      assert_false(all_ids.contains(id), msg=id)
      all_ids[id] = true
      assert_true(rendered.contains("href=\"#\{id}\""), msg=rendered)
    }
  }
}

///|
test "scoping footnotes preserves nested link definitions and case folded references" {
  let rendered = markdown_html(
    "Footnote[^Mixed] and again[^MIXED].\n\n[^mixed]: [Nested reference][guide].\n\n    [guide]: ../guide",
    scope="nested",
    markdown=image_test_context(),
  )
  assert_eq(rendered.split("role=\"doc-noteref\"").count() - 1, 2)
  assert_eq(rendered.split("role=\"doc-backlink\"").count() - 1, 2)
  assert_true(
    rendered.contains(
      "href=\"https://github.com/upstream/project/guide\" target=\"_blank\" rel=\"noopener noreferrer\">Nested reference</a>",
    ),
    msg=rendered,
  )
}

///|
test "web links open new tabs while mail and generated footnotes retain native behavior" {
  let rendered = markdown_html(
    "[ordinary](https://example.com/a?x=1&y=2 \"a & b\") [reference][ref] <http://example.com/auto> [![image](https://example.com/image.png)](/root) [mail](mailto:reader@example.com) <reader@example.com> Note[^note].\n\n[ref]: ../guide\n\n[^note]: footnote",
    scope="targets",
    markdown=image_test_context(),
  )
  assert_eq(
    rendered.split("target=\"_blank\" rel=\"noopener noreferrer\"").count() - 1,
    4,
    msg=rendered,
  )
  assert_true(
    rendered.contains(
      "href=\"https://example.com/a?x=1&amp;y=2\" title=\"a &amp; b\" target=\"_blank\"",
    ),
  )
  assert_true(rendered.contains("href=\"mailto:reader@example.com\">mail</a>"))
  assert_true(
    rendered.contains(
      "href=\"mailto:reader@example.com\">reader@example.com</a>",
    ),
  )
  assert_true(rendered.contains("role=\"doc-noteref\""))
  assert_true(rendered.contains("role=\"doc-backlink\""))
  let image_reference = markdown_html(
    "[![image](https://example.com/image.png)][^note]\n\n[^note]: Footnote.",
    scope="image-reference",
  )
  assert_eq(image_reference.split("<a ").count() - 1, 2, msg=image_reference)
  assert_false(
    image_reference.contains("target=\"_blank\""),
    msg=image_reference,
  )
}

///|
#warnings("-alert_unstable")
#skip("browser DOM: npm run test:views")
test "mounted descriptions and comment types isolate footnotes and escape raw HTML" {
  let id = create_view_fixture()
  defer remove_view_fixture(id)
  let source = "<details>Readable body</details>\n\nFirst[^note], repeat[^note].\n\n[^note]: [Source](#source)."
  let markdown = image_test_context()
  let review = @comments.Session::new().read_view()
  @rabbita.new(() => {
    let bodies = [pull_body_view(Some(source), None, generation=0, markdown~)]
    for
      id in [
        @comments.CommentId::IssueComment(1L),
        ReviewComment(1L),
        CommitComment(1L),
      ] {
      bodies.push(
        comment_body_view(
          "author",
          "2026-10-28T00:00:00Z",
          source,
          markdown.page_url,
          id,
          review,
          Emit(_ => @rabbita.none),
          markdown~,
        ),
      )
    }
    @rabbita.Val::constant(@html.fragment(bodies))
  }).mount(id)
  let root = @browser.element(id).unwrap()
  assert_true(root.query_selector("details") is None)
  let ids : Map[String, Bool] = Map([])
  for body in root.query_selector_all(".markdown-body").iter() {
    assert_eq(
      @browser.property(
        body.query_selector(".markdown-html-raw").unwrap(),
        "textContent",
      ),
      "<details>Readable body</details>",
    )
    for node in body.query_selector_all("[id]").iter() {
      let id = node.get_attribute("id").unwrap()
      assert_false(ids.contains(id), msg=id)
      ids[id] = true
    }
    for link in body.query_selector_all("a[href]").iter() {
      let href = link.get_attribute("href").unwrap()
      if href.has_prefix("#") {
        let target = @browser.element(href[1:].to_owned()).unwrap()
        assert_true(
          @browser.same(target.closest(".markdown-body").unwrap(), body),
        )
      } else {
        assert_eq(href, markdown.page_url + "#source")
      }
    }
  }
  assert_eq(ids.length(), 12)
}
