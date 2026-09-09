///|
test "comment list arguments omit fields that do not apply to the target" {
  json_inspect(comment_list_args(pull_reference("upstream", "project", "17")), content={
    "owner": "upstream",
    "repo": "project",
    "kind": "pull",
    "number": "17",
  })
  json_inspect(
    comment_list_args(commit_reference("upstream", "project", "abcdef1")),
    content={
      "owner": "upstream",
      "repo": "project",
      "kind": "commit",
      "sha": "abcdef1",
    },
  )
  json_inspect(
    comment_list_args(
      pull_commit_reference("upstream", "project", "17", "abcdef1"),
    ),
    content={
      "owner": "upstream",
      "repo": "project",
      "kind": "pull_commit",
      "number": "17",
      "sha": "abcdef1",
    },
  )
}
