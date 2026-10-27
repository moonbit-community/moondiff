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
