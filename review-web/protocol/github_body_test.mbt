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

///|
test "pull authors accept present null or missing users and survive snapshots" {
  let cases : Array[(Json?, @protocol.ApiCommentUser?)] = [
    (
      Some({ "login": "pull-author", "id": 42 }),
      Some({ login: "pull-author", }),
    ),
    (Some(Json::null()), None),
    (None, None),
  ]
  for (user, expected) in cases {
    let fields : Map[String, Json] = {
      "title": "PR",
      "body": "**Description**",
      "html_url": "https://github.com/owner/repo/pull/1",
      "base": { "sha": "a", "repo": null },
      "head": { "sha": "b", "repo": null },
      "additions": 1,
      "deletions": 0,
      "changed_files": 1,
    }
    if user is Some(user) {
      fields["user"] = user
    }
    let pull : @protocol.ApiPull = @protocol.decode_github(
      @protocol.normalize_github(Json::object(fields)),
    )
    assert_true(pull.user == expected)
    roundtrip(@protocol.RpcValue::Pull(pull))
    let comparison : @protocol.ApiCompare = {
      merge_base_commit: { sha: "c", },
    }
    let results : Array[@protocol.ApiPullSnapshotResult] = [
      Complete({
        metadata: pull,
        comparison,
        files: [],
        signature: @protocol.snapshot_signature(pull, comparison),
      }),
      MetadataOnly(pull),
    ]
    for result in results {
      roundtrip(
        @protocol.Response::Success(
          value=@protocol.RpcValue::PullSnapshot(result),
        ),
      )
    }
  }
}
