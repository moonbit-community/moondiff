///|
fn canonical_github_url(reference : CommitRef) -> String {
  match reference.target {
    Commit(sha) =>
      "https://github.com/\{reference.owner}/\{reference.repo}/commit/\{sha}"
    PullRequest(number) =>
      "https://github.com/\{reference.owner}/\{reference.repo}/pull/\{number}"
    PullCommit(number, sha) =>
      "https://github.com/\{reference.owner}/\{reference.repo}/pull/\{number}/commits/\{sha}"
  }
}

///|
fn playground_route(reference : CommitRef) -> String {
  match reference.target {
    Commit(sha) => "#/\{reference.owner}/\{reference.repo}/commit/\{sha}"
    PullRequest(number) =>
      "#/\{reference.owner}/\{reference.repo}/pull/\{number}"
    PullCommit(number, sha) =>
      "#/\{reference.owner}/\{reference.repo}/pull/\{number}/commits/\{sha}"
  }
}

///|
fn reference_from_route(fragment : String?) -> Result[CommitRef?, String] {
  guard fragment is Some(value) && !value.is_empty() else { return Ok(None) }
  let parts : Array[String] = value
    .split("/")
    .map(StringView::to_owned)
    .collect()
  let reference = match parts {
    ["", owner, repo, "commit", sha] | [owner, repo, "commit", sha] =>
      commit_reference(owner, repo, sha)
    ["", owner, repo, "pull", number] | [owner, repo, "pull", number] =>
      pull_reference(owner, repo, number)
    ["", owner, repo, "pull", number, "commits", sha]
    | [owner, repo, "pull", number, "commits", sha] =>
      pull_commit_reference(owner, repo, number, sha)
    _ => return Err("This shared playground link is not valid.")
  }
  let valid_target = match reference.target {
    Commit(sha) => valid_sha(sha)
    PullRequest(number) => valid_pull_number(number)
    PullCommit(number, sha) => valid_pull_number(number) && valid_sha(sha)
  }
  if !valid_owner(reference.owner) ||
    !valid_repo(reference.repo) ||
    !valid_target {
    return Err("This shared playground link is not valid.")
  }
  Ok(Some(reference))
}

///|
fn reference_from_playground_url(input : String) -> Result[CommitRef?, String] {
  let parsed = try @url.parse(input) catch {
    _ => return Err("This shared playground link is not valid.")
  } noraise {
    parsed => parsed
  }
  reference_from_route(parsed.fragment)
}

///|
extern "js" fn browser_current_url() -> String = "() => globalThis.window?.location?.href || 'http://localhost/'"

///|
extern "js" fn browser_base_url() -> String = "() => globalThis.window?.location ? window.location.origin + window.location.pathname : 'http://localhost/'"

///|
fn playground_share_url(reference : CommitRef) -> String {
  "\{browser_base_url()}\{playground_route(reference)}"
}
