///|
/// Exact image origins shared by the Markdown renderer and the server CSP.
/// Redirects must stay within this list; never learn origins from responses.
pub fn markdown_image_hosts() -> ReadOnlyArray[String] {
  [
    "github.com", "user-images.githubusercontent.com", "private-user-images.githubusercontent.com",
    "raw.githubusercontent.com", "camo.githubusercontent.com", "github-production-user-asset-6210df.s3.amazonaws.com",
  ]
}

///|
pub fn markdown_image_csp_sources() -> String {
  markdown_image_hosts().iter().map(host => "https://" + host).join(" ")
}
