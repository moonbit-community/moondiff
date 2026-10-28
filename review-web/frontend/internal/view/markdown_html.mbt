///|
fn markdown_only_html_comments(source : String) -> Bool {
  let mut rest = source[:].trim()
  while !rest.is_empty() {
    guard rest.has_prefix("<!--") else { return false }
    // CommonMark also recognizes these two abruptly closed HTML comments.
    let end = if rest.has_prefix("<!-->") {
      5
    } else if rest.has_prefix("<!--->") {
      6
    } else {
      guard rest[4:].find("-->") is Some(end) else { return false }
      end + 7
    }
    rest = rest[end:].trim()
  }
  true
}

///|
fn markdown_raw_html(
  source : String,
  markdown : MarkdownContext?,
  linked : Bool,
  block~ : Bool,
) -> String {
  if parse_html_images(source) is Some(images) {
    return images
      .iter()
      .map(image => markdown_image_html(image, markdown, linked))
      .join("")
  }
  if markdown_only_html_comments(source) {
    return ""
  }
  let tag = if block { "div" } else { "span" }
  "<\{tag} class=\"markdown-html-raw\">\{markdown_escape(source)}</\{tag}>"
}
