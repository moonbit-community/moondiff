///|
pub(all) struct MarkdownContext {
  page_url : String
  repository : @github.RepositoryRef
  sha : String
} derive(Eq)

///|
#deprecated
pub extend MarkdownContext with Eq::{equal, not_equal}

///|
fn markdown_context(model : Model) -> MarkdownContext? {
  match model.phase {
    Showing(view) =>
      Some({
        page_url: view.html_url,
        repository: view.new_revision.repository,
        sha: view.new_revision.sha,
      })
    ShowingPullSelector(pull) =>
      model.route.map(reference => {
        page_url: pull.html_url,
        repository: @github.branch_repository(
          pull.head,
          @github.reference_repository(reference),
        ),
        sha: pull.head.sha,
      })
    _ => None
  }
}

///|
priv struct MarkdownImage {
  src : String
  alt : String
  title : String?
  width : String?
  height : String?
}

///|
priv struct ImageDestination {
  href : String
  host : String
  automatic : Bool
}

///|
fn image_https_origin(url : @browser.URL) -> Bool {
  url.protocol() == "https:" &&
  url.username().is_empty() &&
  url.password().is_empty() &&
  url.port().is_empty()
}

///|
fn image_path_segment(segment : String) -> Bool {
  !segment.is_empty() &&
  segment
  .iter()
  .all(c => c is ('a'..<='z' | 'A'..<='Z' | '0'..<='9' | '-' | '_' | '.'))
}

///|
fn github_attachment_path(path : String) -> Bool {
  match path.split("/").map(StringView::to_owned).collect() {
    ["", "user-attachments", "assets", id] => image_path_segment(id)
    ["", owner, repo, "assets", uploader, id] =>
      @protocol.valid_owner(owner) &&
      @protocol.valid_repo(repo) &&
      image_path_segment(uploader) &&
      image_path_segment(id)
    _ => false
  }
}

///|
fn github_raw_image(url : @browser.URL) -> @browser.URL? {
  guard image_https_origin(url) && url.hostname() == "github.com" else {
    return None
  }
  match url.pathname().split("/").map(StringView::to_owned).collect() {
    ["", owner, repo, "blob" | "raw", revision, .. path] if @protocol.valid_owner(
        owner,
      ) &&
      @protocol.valid_repo(repo) &&
      !revision.is_empty() &&
      !path.is_empty() =>
      @browser.parse_url(
        "https://raw.githubusercontent.com/\{owner}/\{repo}/\{revision}/\{path.join("/")}\{url.search()}\{url.hash()}",
      )
    _ => None
  }
}

///|
fn image_destination(
  source : String,
  markdown : MarkdownContext?,
) -> ImageDestination? {
  let source = source.trim().to_owned()
  guard !source.is_empty() else { return None }
  let url = if @browser.parse_url(source) is Some(url) {
    url
  } else if source.has_prefix("//") {
    guard @browser.parse_url(source, base="https://github.com/") is Some(url) else {
      return None
    }
    url
  } else {
    // Never resolve a repository image against this application's origin.
    guard markdown is Some(markdown) &&
      !source.contains("\\") &&
      !source.split("/").next().unwrap_or("").contains(":") else {
      return None
    }
    let github = @browser.parse_url(source, base=markdown.page_url)
    if github.bind(github_raw_image) is Some(raw) {
      raw
    } else {
      guard @protocol.valid_owner(markdown.repository.owner) &&
        @protocol.valid_repo(markdown.repository.repo) &&
        @protocol.valid_sha(markdown.sha) else {
        return None
      }
      // Normalize dot segments at a synthetic repository root, so ../ cannot
      // escape the pinned repository and commit on raw.githubusercontent.com.
      guard @browser.parse_url(source, base="https://repository.invalid/")
        is Some(path) else {
        return None
      }
      guard path.hostname() == "repository.invalid" else { return None }
      guard @browser.parse_url(
          "https://raw.githubusercontent.com/\{markdown.repository.owner}/\{markdown.repository.repo}/\{markdown.sha}\{path.pathname()}\{path.search()}\{path.hash()}",
        )
        is Some(raw) else {
        return None
      }
      raw
    }
  }
  guard url.protocol() == "https:" || url.protocol() == "http:" else {
    return None
  }
  let url = github_raw_image(url).unwrap_or(url)
  let host = url.hostname()
  Some({
    href: url.href(),
    host,
    automatic: image_https_origin(url) &&
    @protocol.markdown_image_hosts().contains(host) &&
    (host != "github.com" || github_attachment_path(url.pathname())),
  })
}

///|
fn markdown_escape(source : String) -> String {
  let result = StringBuilder()
  for c in source {
    match c {
      '&' => result.write_string("&amp;")
      '<' => result.write_string("&lt;")
      '>' => result.write_string("&gt;")
      '"' => result.write_string("&quot;")
      '\'' => result.write_string("&#39;")
      '\u{0}' => result.write_char('\u{FFFD}')
      _ => result.write_char(c)
    }
  }
  result.to_string()
}

///|
fn markdown_image_html(
  image : MarkdownImage,
  markdown : MarkdownContext?,
  linked : Bool,
) -> String {
  guard image_destination(image.src, markdown) is Some(destination) else {
    return markdown_escape(image.alt)
  }
  let text = markdown_escape(
    if image.alt.trim().is_empty() {
      "查看图片 · " + destination.host
    } else {
      image.alt
    },
  )
  let result = StringBuilder()
  if !linked {
    result.write_string(
      "<a href=\"\{markdown_escape(destination.href)}\" target=\"_blank\" rel=\"noopener noreferrer\">",
    )
  }
  if destination.automatic {
    result.write_string(
      "<span class=\"markdown-image\"><span class=\"markdown-image-fallback\">\{text}</span><img hidden data-markdown-src=\"\{markdown_escape(destination.href)}\" alt=\"\{markdown_escape(image.alt)}\" referrerpolicy=\"no-referrer\"",
    )
    for
      (name, value) in [
        ("title", image.title),
        ("width", image.width),
        ("height", image.height),
      ] {
      if value is Some(value) {
        result.write_string(" \{name}=\"\{markdown_escape(value)}\"")
      }
    }
    result.write_string("></span>")
  } else {
    result.write_string(text)
  }
  if !linked {
    result.write_string("</a>")
  }
  result.to_string()
}

///|
fn image_html_space(c : UInt16) -> Bool {
  c is (' ' | '\t' | '\n' | '\r' | '\u000C')
}

///|
fn image_html_attribute(value : String) -> String {
  // HTML attributes also permit numeric character references without a trailing
  // semicolon. Canonicalize them before CommonMark's entity decoder, including
  // long runs of leading zeroes, so encoded protocols get the same URL policy.
  let normalized = StringBuilder()
  for start = 0, i = 0; i < value.length(); {
    if value[i] == '&' && i + 2 < value.length() && value[i + 1] == '#' {
      let hex = value[i + 2] is ('x' | 'X')
      let digits = i + (if hex { 3 } else { 2 })
      let mut end = digits
      let mut code = 0
      while end < value.length() {
        let digit = match value[end] {
          '0'..<='9' as c => c.to_int() - 48
          'a'..<='f' as c if hex => c.to_int() - 87
          'A'..<='F' as c if hex => c.to_int() - 55
          _ => break
        }
        code = Int32::min(0x110000, code * (if hex { 16 } else { 10 }) + digit)
        end += 1
      }
      if end > digits {
        normalized.write_view(value[start:i])
        normalized.write_string("&#\{code};")
        if end < value.length() && value[end] == ';' {
          end += 1
        }
        continue end, end
      }
    }
    continue start, i + 1
  } nobreak {
    normalized.write_view(value[start:])
  }
  let value = normalized.to_string()
  @cmark_char.utf_16_clean_unref(
    StringBuilder(),
    value,
    first=0,
    last=value.length() - 1,
  )
}

///|
fn image_html_dimension(value : String?) -> String? {
  value.filter(s => {
    !s.is_empty() &&
    s.iter().all(c => c is ('0'..<='9')) &&
    s.iter().any(c => c != '0')
  })
}

///|
// Accept complete img tags and whitespace only. Parse attributes ourselves and
// rebuild the markup; raw HTML never reaches the DOM or starts image requests.
fn parse_html_images(source : String) -> Array[MarkdownImage]? {
  let images : Array[MarkdownImage] = []
  let mut i = 0
  while i < source.length() {
    if image_html_space(source[i]) {
      i += 1
      continue
    }
    guard i + 4 < source.length() &&
      source[i] == '<' &&
      source[i + 1] is ('i' | 'I') &&
      source[i + 2] is ('m' | 'M') &&
      source[i + 3] is ('g' | 'G') &&
      (image_html_space(source[i + 4]) || source[i + 4] is ('/' | '>')) else {
      return None
    }
    i += 4
    let attrs : Map[String, String] = Map([])
    let mut closed = false
    while i < source.length() {
      let before_space = i
      while i < source.length() && image_html_space(source[i]) {
        i += 1
      }
      if source[i:].has_prefix("/>") {
        i += 2
        closed = true
        break
      }
      if i < source.length() && source[i] == '>' {
        i += 1
        closed = true
        break
      }
      guard i > before_space else { return None }
      let start = i
      while i < source.length() &&
            !image_html_space(source[i]) &&
            !(source[i] is ('/' | '>' | '=' | '<' | '"' | '\'' | '\u{0}')) {
        i += 1
      }
      guard i > start else { return None }
      let name = source[start:i].to_owned().to_lower()
      let after_name = i
      while i < source.length() && image_html_space(source[i]) {
        i += 1
      }
      let value = if i < source.length() && source[i] == '=' {
        i += 1
        while i < source.length() && image_html_space(source[i]) {
          i += 1
        }
        guard i < source.length() else { return None }
        if source[i] is ('"' | '\'') {
          let quote = source[i]
          i += 1
          let start = i
          while i < source.length() && source[i] != quote {
            i += 1
          }
          guard i < source.length() else { return None }
          let value = source[start:i].to_owned()
          i += 1
          value
        } else {
          let start = i
          while i < source.length() &&
                !image_html_space(source[i]) &&
                source[i] != '>' {
            guard !(source[i] is ('<' | '"' | '\'' | '=' | '`' | '\u{0}')) else {
              return None
            }
            i += 1
          }
          guard i > start else { return None }
          source[start:i].to_owned()
        }
      } else {
        i = after_name
        ""
      }
      // Match HTML's first-attribute-wins behavior, including mixed casing.
      if !attrs.contains(name) {
        attrs[name] = image_html_attribute(value)
      }
    }
    guard closed else { return None }
    images.push({
      src: attrs.get("src").unwrap_or(""),
      alt: attrs.get("alt").unwrap_or(""),
      title: attrs.get("title"),
      width: image_html_dimension(attrs.get("width")),
      height: image_html_dimension(attrs.get("height")),
    })
  }
  if images.is_empty() {
    None
  } else {
    Some(images)
  }
}
