///|
test "public origins canonicalize browser defaults and reject unsafe deployments" {
  assert_eq(root_url("https://DIFF.example:443/"), "https://diff.example")
  assert_eq(root_url("http://LOCALHOST:80"), "http://localhost")
  assert_eq(root_url("http://[::1]:4173"), "http://[::1]:4173")
  for
    url in [
      "http://diff.example", "https://diff.example/path", "https://user@diff.example",
      "https://diff.example?x=1", "https://diff.example#x", "https://a:0", "https://a:65536",
      "https://a..b", "https://a]", "//diff.example",
    ] {
    try root_url(url) catch {
      _ => ()
    } noraise {
      _ => fail("accepted \{url}")
    }
  }
  try root_url("https://example.com", local_only=true) catch {
    _ => ()
  } noraise {
    _ => fail("allowed remote test stub")
  }
}
