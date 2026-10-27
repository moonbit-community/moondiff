///|
test "pull descriptions preserve Markdown and accept missing or null bodies" {
  let description = "## Summary\n\n- [x] **Implemented**\n\n```mbt\nlet x = 1\n```"
  let missing : @protocol.ApiPull = @protocol.decode_github(
    @protocol.normalize_github({
      "title": "PR",
      "html_url": "https://github.com/owner/repo/pull/1",
      "base": { "sha": "a", "repo": null },
      "head": { "sha": "b", "repo": null },
      "additions": 1,
      "deletions": 0,
      "changed_files": 1,
    }),
  )
  assert_true(missing.body is None)
  for body in [Json::null(), Json::string(description)] {
    let pull : @protocol.ApiPull = @protocol.decode_github(
      @protocol.normalize_github({
        "title": "PR",
        "body": body,
        "html_url": "https://github.com/owner/repo/pull/1",
        "base": { "sha": "a", "repo": null },
        "head": { "sha": "b", "repo": null },
        "additions": 1,
        "deletions": 0,
        "changed_files": 1,
      }),
    )
    let expected = if body is Null { None } else { Some(description) }
    assert_true(pull.body == expected)
    let decoded : @protocol.ApiPull = @protocol.decode(ToJson::to_json(pull))
    assert_true(decoded == pull)
  }
}
