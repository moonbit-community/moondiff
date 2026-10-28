///|
fn markdown_link_destination(
  source : String,
  markdown : MarkdownContext?,
) -> String? {
  let url = if @browser.parse_url(source) is Some(url) {
    url
  } else {
    // Relative links belong to the GitHub source page, never the app's origin.
    guard markdown is Some(markdown) &&
      @browser.parse_url(markdown.page_url) is Some(base) &&
      image_https_origin(base) &&
      base.hostname() == "github.com" else {
      return None
    }
    guard @browser.parse_url(source, base=base.href()) is Some(url) else {
      return None
    }
    url
  }
  let destination = url.href()
  // URL parsing normalizes whitespace and protocols before the safety check.
  if @cmark.InlineLink::is_unsafe(destination) {
    None
  } else {
    Some(destination)
  }
}
