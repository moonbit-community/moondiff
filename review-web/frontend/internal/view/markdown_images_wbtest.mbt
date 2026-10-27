///|
fn image_test_context() -> MarkdownContext {
  {
    page_url: "https://github.com/upstream/project/pull/17",
    repository: { owner: "contributor", repo: "project-fork", },
    sha: "a".repeat(40),
  }
}

///|
test "Markdown image origins require exact hosts HTTPS no credentials and the default port" {
  for host in @protocol.markdown_image_hosts() {
    let path = if host == "github.com" {
      "/user-attachments/assets/abc-123"
    } else {
      "/image.png"
    }
    let url = "https://\{host}\{path}"
    assert_true(image_destination(url, None).unwrap().automatic, msg=url)
  }
  for
    url in [
      "http://raw.githubusercontent.com/o/r/main/image.png", "https://raw.githubusercontent.com:444/o/r/main/image.png",
      "https://user@raw.githubusercontent.com/image.png", "https://:password@raw.githubusercontent.com/image.png",
      "https://raw.githubusercontent.com.attacker.example/image.png", "https://raw.githubusercontent.com./image.png",
      "https://attacker.example/raw.githubusercontent.com/image.png", "https://raw.githubusercontent.com@attacker.example/image.png",
      "https://sub.raw.githubusercontent.com/image.png", "https://github-production-user-asset-other.s3.amazonaws.com/image.png",
      "https://avatars.githubusercontent.com/image.png",
    ] {
    let destination = image_destination(url, None).unwrap()
    assert_false(destination.automatic, msg=url)
    let rendered = markdown_html("![image](\{url})")
    assert_true(rendered.contains("<a href="), msg=rendered)
    assert_false(rendered.contains("<img"), msg=rendered)
  }
  assert_true(
    image_destination("https://RAW.GITHUBUSERCONTENT.COM:443/a.png", None).unwrap().automatic,
  )
  for
    url in [
      "javascript:alert(1)", "jav\nascript:alert(1)", "data:image/png;base64,abc",
      "file:///tmp/image", "blob:https://github.com/id", "http://[", "", "image.png",
      "/image.png",
    ] {
    assert_true(image_destination(url, None) is None, msg=url)
  }
}

///|
test "GitHub images accept only complete attachment paths or normalized blob and raw paths" {
  for
    path in [
      "/user-attachments/assets/abc-123", "/owner/repo/assets/123/abc-123",
    ] {
    assert_true(
      image_destination("https://github.com" + path, None).unwrap().automatic,
    )
  }
  for
    path in [
      "/owner/repo", "/user-attachments/assets/", "/user-attachments/assets/id/extra",
      "/user-attachments/assets/id/", "/user-attachments/assets/id%2fextra", "/owner/repo/assets/uploader",
      "/owner/repo/assets/uploader/id/extra", "/owner/repo/issues/1", "/User-attachments/assets/id",
    ] {
    assert_false(
      image_destination("https://github.com" + path, None).unwrap().automatic,
      msg=path,
    )
  }
  for kind in ["blob", "raw"] {
    let destination = image_destination(
      "https://github.com/o/r/\{kind}/main/docs/a%20b.png?raw=true#image",
      None,
    ).unwrap()
    assert_true(destination.automatic)
    assert_eq(
      destination.href,
      "https://raw.githubusercontent.com/o/r/main/docs/a%20b.png?raw=true#image",
    )
  }
  assert_false(
    image_destination("https://user@github.com/o/r/blob/main/a.png", None).unwrap().automatic,
  )
  assert_false(
    image_destination("http://github.com/o/r/blob/main/a.png", None).unwrap().automatic,
  )
}

///|
test "relative Markdown images use the fork snapshot and explicit GitHub repository branch syntax" {
  let context = image_test_context()
  let root = "https://raw.githubusercontent.com/contributor/project-fork/" +
    context.sha
  for
    (source, path) in [
      ("docs/image.png", "/docs/image.png"),
      ("./image.png", "/image.png"),
      ("/assets/a.png", "/assets/a.png"),
      ("../assets/a.png", "/assets/a.png"),
      ("docs/../a%20b.png?x=1&y=2", "/a%20b.png?x=1&y=2"),
    ] {
    assert_eq(
      image_destination(source, Some(context)).unwrap().href,
      root + path,
    )
  }
  for
    source in [
      "../blob/main/image.png?raw=true", "../../../upstream/project/blob/main/image.png?raw=true",
    ] {
    assert_eq(
      image_destination(source, Some(context)).unwrap().href,
      "https://raw.githubusercontent.com/upstream/project/main/image.png?raw=true",
    )
  }
  assert_eq(
    image_destination(
      "../../../another/repo/blob/release/image.png",
      Some(context),
    ).unwrap().href,
    "https://raw.githubusercontent.com/another/repo/release/image.png",
  )
  assert_eq(
    image_destination("//example.com/image.png", None).unwrap().href,
    "https://example.com/image.png",
  )
  assert_true(
    image_destination("./image.png", Some({ ..context, sha: "HEAD", })) is None,
  )
  let rendered = markdown_html("![relative](image.png)")
  assert_eq(rendered, "<p>relative</p>")
}

///|
test "Markdown and reference images emit escaped links and inert hidden images" {
  let rendered = markdown_html(
    (
      #|![a **bold** & "quoted" &lt;alt&gt;](https://raw.githubusercontent.com/o/r/main/a.png?x=1&y=2 "a & title")
      #|![reference][screenshot]
      #|![][screenshot]
      #|![outside](https://example.com/a.png)
      #|![danger](jav&#x61;script:alert%281%29)
      #|
      #|[screenshot]: https://github.com/user-attachments/assets/id
    ),
  )
  assert_eq(rendered.split("<img ").count() - 1, 3)
  assert_false(rendered.contains(" src="), msg=rendered)
  assert_true(
    rendered.contains("alt=\"a bold &amp; &quot;quoted&quot; &lt;alt&gt;\""),
    msg=rendered,
  )
  assert_true(rendered.contains("title=\"a &amp; title\""), msg=rendered)
  assert_true(rendered.contains("a.png?x=1&amp;y=2"), msg=rendered)
  assert_true(rendered.contains("查看图片 · github.com"), msg=rendered)
  assert_true(rendered.contains("rel=\"noopener noreferrer\""), msg=rendered)
  assert_false(rendered.contains("javascript:"), msg=rendered)
  assert_true(rendered.contains("danger"), msg=rendered)
}

///|
test "linked Markdown images reuse the safe outer anchor" {
  for
    source in [
      "[![linked](https://camo.githubusercontent.com/image)](https://example.com/destination)",
      "[![linked](https://example.com/image)](https://example.com/destination)",
    ] {
    let rendered = markdown_html(source)
    assert_eq(rendered.split("<a ").count() - 1, 1, msg=rendered)
    assert_true(
      rendered.contains("href=\"https://example.com/destination\""),
      msg=rendered,
    )
    assert_true(rendered.contains("linked"), msg=rendered)
  }
}
