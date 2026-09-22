///|
priv struct MergeSnapshot {
  base : String
  head : String
  open : Bool
  draft : Bool
  merged : Bool
  mergeable : Bool?
  rebaseable : Bool?
  mergeable_state : String
}

///|
fn invalid_merge_response(
  message? : String = "GitHub returned invalid pull request merge data.",
) -> Error {
  @common.RpcError(502, "invalid_github_response", message)
}

///|
fn merge_snapshot_changed() -> Error {
  @common.RpcError(
    409, "pull_snapshot_changed", "This pull request changed. Load the latest snapshot before merging.",
  )
}

///|
fn required_upstream_string(value : Json, key : String) -> String raise {
  guard @common.field(value, key) is String(text) && !text.is_empty() else {
    raise invalid_merge_response()
  }
  text
}

///|
fn optional_upstream_string(value : Json, key : String) -> String? raise {
  match @common.field(value, key) {
    Null => None
    String(text) => Some(text)
    _ => raise invalid_merge_response()
  }
}

///|
fn external_details_url(value : String?) -> String? {
  value.filter(url => url.has_prefix("https://") || url.has_prefix("http://"))
}

///|
fn required_upstream_bool(value : Json, key : String) -> Bool raise {
  match @common.field(value, key) {
    True => true
    False => false
    _ => raise invalid_merge_response()
  }
}

///|
fn optional_upstream_bool(value : Json, key : String) -> Bool? raise {
  match @common.field(value, key) {
    Null => None
    True => Some(true)
    False => Some(false)
    _ => raise invalid_merge_response()
  }
}

///|
fn merge_snapshot(value : Json) -> MergeSnapshot raise {
  let base = required_upstream_string(@common.field(value, "base"), "sha")
  let head = required_upstream_string(@common.field(value, "head"), "sha")
  guard @common.valid_sha(base) && @common.valid_sha(head) else {
    raise invalid_merge_response()
  }
  let state = required_upstream_string(value, "state")
  guard state == "open" || state == "closed" else {
    raise invalid_merge_response()
  }
  {
    base,
    head,
    open: state == "open",
    draft: required_upstream_bool(value, "draft"),
    merged: required_upstream_bool(value, "merged"),
    mergeable: optional_upstream_bool(value, "mergeable"),
    rebaseable: optional_upstream_bool(value, "rebaseable"),
    mergeable_state: required_upstream_string(value, "mergeable_state"),
  }
}

///|
fn check_run_state(
  status : String,
  conclusion : String?,
) -> @protocol.ApiCiState {
  if status != "completed" {
    return Pending
  }
  match conclusion {
    Some("success") => Success
    Some(
      "failure"
      | "timed_out"
      | "cancelled"
      | "action_required"
      | "startup_failure"
    ) => Failure
    Some("neutral" | "skipped" | "stale") => Neutral
    Some(_) => Neutral
    None => Pending
  }
}

///|
fn commit_status_state(state : String) -> @protocol.ApiCiState {
  match state {
    "success" => Success
    "pending" => Pending
    "failure" | "error" => Failure
    _ => Neutral
  }
}

///|
fn ci_summary(
  checks : ArrayView[@protocol.ApiCiCheck],
) -> @protocol.ApiCiState? {
  if checks.is_empty() {
    return None
  }
  if checks.any(check => check.state is Failure) {
    Some(Failure)
  } else if checks.any(check => check.state is Pending) {
    Some(Pending)
  } else if checks.any(check => check.state is Success) {
    Some(Success)
  } else {
    Some(Neutral)
  }
}

///|
fn ci_page_count(value : Json) -> Int raise {
  guard @common.field(value, "total_count") is Number(total, ..) &&
    total >= 0 &&
    total <= 10000 &&
    total == total.to_int().to_double() else {
    raise invalid_merge_response(
      message="GitHub returned invalid CI pagination data.",
    )
  }
  total.to_int()
}

///|
async fn pull_check_runs(
  app : @storage.App,
  session : @storage.Session?,
  owner : String,
  repo : String,
  head : String,
) -> Array[@protocol.ApiCiCheck] {
  let checks : Array[@protocol.ApiCiCheck] = []
  for page in 1..<=100 {
    let value = @github.github_json(
      app,
      session,
      "/repos/\{owner}/\{repo}/commits/\{head}/check-runs?per_page=100&page=\{page}",
    )
    let total = ci_page_count(value)
    guard @common.field(value, "check_runs") is Array(runs) &&
      runs.length() <= 100 else {
      raise invalid_merge_response(
        message="GitHub returned invalid check run data.",
      )
    }
    for run in runs {
      let name = required_upstream_string(run, "name")
      let status = required_upstream_string(run, "status")
      let conclusion = optional_upstream_string(run, "conclusion")
      let details_url = match
        external_details_url(optional_upstream_string(run, "details_url")) {
        Some(url) => Some(url)
        _ => external_details_url(optional_upstream_string(run, "html_url"))
      }
      let title = optional_upstream_string(
        @common.field(run, "output"),
        "title",
      )
      checks.push({
        name,
        state: check_run_state(status, conclusion),
        description: title
        .filter(title => !title.is_empty())
        .unwrap_or(conclusion.unwrap_or(status)),
        details_url,
        source: CheckRun,
      })
    }
    guard checks.length() <= total else {
      raise invalid_merge_response(
        message="GitHub returned inconsistent check run pagination.",
      )
    }
    if checks.length() == total {
      return checks
    }
    guard runs.length() == 100 else {
      raise invalid_merge_response(
        message="GitHub returned an incomplete check run page.",
      )
    }
  }
  raise @common.RpcError(
    422, "pagination_limit", "GitHub returned more check runs than Moondiff can safely load.",
  )
}

///|
async fn pull_commit_statuses(
  app : @storage.App,
  session : @storage.Session?,
  owner : String,
  repo : String,
  head : String,
) -> Array[@protocol.ApiCiCheck] {
  let checks : Array[@protocol.ApiCiCheck] = []
  for page in 1..<=100 {
    let value = @github.github_json(
      app,
      session,
      "/repos/\{owner}/\{repo}/commits/\{head}/status?per_page=100&page=\{page}",
    )
    let total = ci_page_count(value)
    guard @common.field(value, "statuses") is Array(statuses) &&
      statuses.length() <= 100 else {
      raise invalid_merge_response(
        message="GitHub returned invalid commit status data.",
      )
    }
    for status in statuses {
      let name = required_upstream_string(status, "context")
      let raw_state = required_upstream_string(status, "state")
      let description = optional_upstream_string(status, "description")
      let details_url = external_details_url(
        optional_upstream_string(status, "target_url"),
      )
      checks.push({
        name,
        state: commit_status_state(raw_state),
        description: description
        .filter(description => !description.is_empty())
        .unwrap_or(raw_state),
        details_url,
        source: CommitStatus,
      })
    }
    guard checks.length() <= total else {
      raise invalid_merge_response(
        message="GitHub returned inconsistent commit status pagination.",
      )
    }
    if checks.length() == total {
      return checks
    }
    guard statuses.length() == 100 else {
      raise invalid_merge_response(
        message="GitHub returned an incomplete commit status page.",
      )
    }
  }
  raise @common.RpcError(
    422, "pagination_limit", "GitHub returned more commit statuses than Moondiff can safely load.",
  )
}

///|
pub async fn pull_merge_status(
  app : @storage.App,
  session : @storage.Session?,
  p : @protocol.PullMergeStatusGet,
) -> @protocol.ApiPullMergeStatus {
  let snapshot = merge_snapshot(
    @github.github_json(
      app,
      session,
      "/repos/\{p.owner}/\{p.repo}/pulls/\{p.number}",
    ),
  )
  guard snapshot.base == p.expected_base_sha &&
    snapshot.head == p.expected_head_sha else {
    raise merge_snapshot_changed()
  }
  let checks : Array[@protocol.ApiCiCheck] = []
  let warnings : Array[String] = []
  let check_runs : Result[Array[@protocol.ApiCiCheck], Error] = Ok(
    pull_check_runs(app, session, p.owner, p.repo, snapshot.head),
  ) catch {
    error => Err(error)
  }
  match check_runs {
    Ok(values) => checks.append(values)
    Err(_) =>
      warnings.push("Check runs could not be read; CI results are incomplete.")
  }
  let statuses : Result[Array[@protocol.ApiCiCheck], Error] = Ok(
    pull_commit_statuses(app, session, p.owner, p.repo, snapshot.head),
  ) catch {
    error => Err(error)
  }
  match statuses {
    Ok(values) => checks.append(values)
    Err(_) =>
      warnings.push(
        "Commit statuses could not be read; CI results are incomplete.",
      )
  }
  {
    base_sha: snapshot.base,
    head_sha: snapshot.head,
    open: snapshot.open,
    draft: snapshot.draft,
    merged: snapshot.merged,
    mergeable: snapshot.mergeable,
    rebaseable: snapshot.rebaseable,
    mergeable_state: snapshot.mergeable_state,
    ci_summary: ci_summary(checks),
    ci_checks: checks,
    ci_warnings: warnings,
  }
}

///|
fn merge_http_error(error : Error) -> Error {
  match error {
    @common.RpcError(401, _, _) =>
      @common.RpcError(
        401, "authentication_required", "Your GitHub session expired. Sign in again before merging.",
      )
    @common.RpcError(403 | 429 as status, "rate_limit", message) =>
      @common.RpcError(status, "rate_limit", message)
    @common.RpcError(403, _, _) =>
      @common.RpcError(
        403, "merge_permission_denied", "GitHub denied permission to merge this pull request.",
      )
    @common.RpcError(405, _, _) =>
      @common.RpcError(
        405, "merge_blocked", "Repository rules currently block this rebase merge.",
      )
    @common.RpcError(422, _, _) =>
      @common.RpcError(
        422, "merge_rejected", "GitHub rejected this rebase merge. Check repository rules and try again.",
      )
    @common.RpcError(status, _, _) if status >= 500 =>
      @common.RpcError(
        status, "merge_upstream_failure", "GitHub could not complete the rebase merge.",
      )
    _ => error
  }
}

///|
pub async fn pull_rebase_merge(
  app : @storage.App,
  session : @storage.Session?,
  p : @protocol.PullRebaseMerge,
) -> @protocol.ApiPullMergeResult {
  guard session is Some(session) && !session.tokens.is_empty() else {
    raise @common.RpcError(
      401, "authentication_required", "Sign in to merge this pull request.",
    )
  }
  let snapshot = merge_snapshot(
    @github.github_json(
      app,
      Some(session),
      "/repos/\{p.owner}/\{p.repo}/pulls/\{p.number}",
    ) catch {
      error => raise merge_http_error(error)
    },
  )
  guard snapshot.base == p.expected_base_sha &&
    snapshot.head == p.expected_head_sha else {
    raise merge_snapshot_changed()
  }
  guard !snapshot.merged else {
    raise @common.RpcError(
      409, "pull_already_merged", "This pull request is already merged.",
    )
  }
  guard snapshot.open else {
    raise @common.RpcError(409, "pull_closed", "This pull request is closed.")
  }
  guard !snapshot.draft else {
    raise @common.RpcError(
      422, "pull_is_draft", "Mark this pull request ready for review before merging.",
    )
  }
  guard snapshot.mergeable is Some(true) && snapshot.rebaseable is Some(true) else {
    if snapshot.mergeable is None || snapshot.rebaseable is None {
      raise @common.RpcError(
        409, "mergeability_unknown", "GitHub is still calculating whether this pull request can be rebased.",
      )
    }
    raise @common.RpcError(
      409, "merge_conflict", "This pull request has conflicts and cannot be rebased automatically.",
    )
  }
  guard snapshot.mergeable_state != "blocked" else {
    raise @common.RpcError(
      405, "merge_blocked", "Repository rules currently block this rebase merge.",
    )
  }
  let value = @github.github_json(
    app,
    Some(session),
    "/repos/\{p.owner}/\{p.repo}/pulls/\{p.number}/merge",
    meth=Put,
    body={ "sha": p.expected_head_sha, "merge_method": "rebase" },
  ) catch {
    @common.RpcError(409, _, _) => raise merge_snapshot_changed()
    error => raise merge_http_error(error)
  }
  let result : @protocol.ApiPullMergeResult = @common.decode_github(value)
  guard (match (result.merged, result.sha) {
    (true, Some(sha)) => @common.valid_sha(sha)
    (true, None) => false
    (false, Some(sha)) => @common.valid_sha(sha)
    (false, None) => true
  }) else {
    raise invalid_merge_response(
      message="GitHub returned an invalid merge commit SHA.",
    )
  }
  if result.message.is_empty() {
    {
      ..result,
      message: if result.merged {
        "Pull request merged."
      } else {
        "GitHub did not merge this pull request."
      },
    }
  } else {
    result
  }
}
