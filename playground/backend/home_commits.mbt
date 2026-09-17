///|
priv enum CommitPosition {
  GraphQL(String)
  Compare(Int)
} derive(FromJson, ToJson)

///|
priv struct CommitCursor {
  position : CommitPosition
  base : String
  head : String
  loaded : Int
  total : Int
} derive(FromJson, ToJson)

///|
const PULL_COMMITS_SNAPSHOT_QUERY : String =
  #|query PullCommitsSnapshot($owner: String!, $repo: String!, $number: Int!) {
  #|  repository(owner: $owner, name: $repo) {
  #|    pullRequest(number: $number) {
  #|      id baseRefOid headRefOid
  #|      commits(first: 1) { totalCount }
  #|    }
  #|  }
  #|}

///|
const PULL_COMMITS_QUERY : String =
  #|query PullCommits($owner: String!, $repo: String!, $number: Int!, $cursor: String) {
  #|  repository(owner: $owner, name: $repo) {
  #|    pullRequest(number: $number) {
  #|      id baseRefOid headRefOid
  #|      commits(first: 100, after: $cursor) {
  #|        totalCount
  #|        nodes { commit { oid messageHeadline committedDate author { name user { login } } } }
  #|        pageInfo { hasNextPage endCursor }
  #|      }
  #|    }
  #|  }
  #|}

///|
fn commits_changed() -> Error {
  RpcError(
    409, "pull_commits_changed", "This PR changed. Reload its commits to see the latest version.",
  )
}

///|
fn graphql_commit_summary(node : Json) -> @protocol.ApiCommitSummary raise {
  let commit = field(node, "commit")
  guard field(commit, "oid") is String(sha) &&
    valid_sha(sha) &&
    field(commit, "messageHeadline") is String(message) &&
    field(commit, "committedDate") is String(committed_at) else {
    raise home_invalid()
  }
  let author = field(commit, "author")
  let login = optional_string(field(author, "user"), "login")
  {
    sha,
    message,
    committed_at,
    author: if login.is_empty() {
      optional_string(author, "name")
    } else {
      login
    },
  }
}

///|
fn compare_commit_summary(value : Json) -> @protocol.ApiCommitSummary raise {
  let commit = field(value, "commit")
  guard field(value, "sha") is String(sha) &&
    valid_sha(sha) &&
    field(commit, "message") is String(message) &&
    field(field(commit, "committer"), "date") is String(committed_at) else {
    raise home_invalid()
  }
  let login = optional_string(field(value, "author"), "login")
  {
    sha,
    message: message
    .split("\n")
    .next()
    .unwrap_or("")
    .trim_end(chars="\r")
    .to_owned(),
    committed_at,
    author: if login.is_empty() {
      optional_string(field(commit, "author"), "name")
    } else {
      login
    },
  }
}

///|
async fn App::pull_commits(
  self : App,
  session : Session?,
  p : @protocol.PullCommitsGet,
) -> @protocol.ApiPullCommits {
  let session = home_session(session)
  let scope = "commits:\{p.owner}/\{p.repo}/\{p.number}"
  let previous : CommitCursor? = p.cursor.map(cursor => {
    self.read_home_cursor(session, scope, cursor)
  })
  let variables = viewed_variables({
    owner: p.owner,
    repo: p.repo,
    number: p.number,
  })
  guard variables is Object(variables) else { raise home_invalid() }
  let position = previous.map(c => c.position)
  let query = match position {
    Some(Compare(_)) => PULL_COMMITS_SNAPSHOT_QUERY
    _ => {
      variables["cursor"] = match position {
        Some(GraphQL(after)) => Json::string(after)
        _ => Json::null()
      }
      PULL_COMMITS_QUERY
    }
  }
  let pull = viewed_pull(
    self.graphql(Some(session), query, Json::object(variables)),
  )
  let snapshot = viewed_snapshot(pull)
  guard snapshot.base.length() == 40 && snapshot.head.length() == 40 else {
    raise home_invalid()
  }
  if previous is Some(old) &&
    (snapshot.base != old.base || snapshot.head != old.head) {
    raise commits_changed()
  }
  let connection = field(pull, "commits")
  let total_count = home_count(field(connection, "totalCount"))
  if previous is Some(old) && old.total != total_count {
    raise commits_changed()
  }
  let already_loaded = previous.map(c => c.loaded).unwrap_or(0)
  guard already_loaded >= 0 && already_loaded <= total_count else {
    raise home_invalid()
  }
  let (items, next_position) = if total_count > 250 {
    let page = match position {
      None => 1
      Some(Compare(page)) => page
      _ => raise home_invalid()
    }
    guard already_loaded % 100 == 0 &&
      page == already_loaded / 100 + 1 &&
      already_loaded < total_count else {
      raise home_invalid()
    }
    // Start large PRs at compare page one, never append REST to GraphQL rows.
    // Full OIDs resolve fork commits in the PR's base repository network.
    let raw = self.github_json(
      Some(session),
      "/repos/\{p.owner}/\{p.repo}/compare/\{snapshot.base}...\{snapshot.head}?per_page=100&page=\{page}",
    )
    guard home_count(field(raw, "total_commits")) == total_count &&
      field(raw, "commits") is Array(commits) &&
      commits.length() == Int::min(100, total_count - already_loaded) else {
      raise home_invalid()
    }
    (
      commits.map(compare_commit_summary),
      if already_loaded + commits.length() < total_count {
        Some(Compare(page + 1))
      } else {
        None
      },
    )
  } else {
    guard !(position is Some(Compare(_))) &&
      field(connection, "nodes") is Array(nodes) &&
      nodes.length() <= 100 &&
      nodes.length() <= total_count - already_loaded else {
      raise home_invalid()
    }
    let info = field(connection, "pageInfo")
    let loaded = already_loaded + nodes.length()
    let next_position = match field(info, "hasNextPage") {
      False => {
        guard loaded == total_count else { raise home_invalid() }
        None
      }
      True => {
        guard !nodes.is_empty() &&
          field(info, "endCursor") is String(after) &&
          !after.is_empty() &&
          !(position is Some(GraphQL(old)) && old == after) &&
          loaded < total_count else {
          raise home_invalid()
        }
        Some(GraphQL(after))
      }
      _ => raise home_invalid()
    }
    (nodes.map(graphql_commit_summary), next_position)
  }
  let seen : Map[String, Bool] = Map([])
  for item in items {
    guard !seen.contains(item.sha) else { raise home_invalid() }
    seen[item.sha] = true
  }
  let verified_pull = viewed_pull(
    self.graphql(
      Some(session),
      PULL_COMMITS_SNAPSHOT_QUERY,
      viewed_variables({ owner: p.owner, repo: p.repo, number: p.number, }),
    ),
  )
  guard viewed_snapshot(verified_pull) == snapshot &&
    home_count(field(field(verified_pull, "commits"), "totalCount")) ==
    total_count else {
    raise commits_changed()
  }
  let next_cursor = next_position.map(position => {
    self.home_cursor(session, scope, CommitCursor::{
      position,
      base: snapshot.base,
      head: snapshot.head,
      loaded: already_loaded + items.length(),
      total: total_count,
    })
  })
  {
    items,
    total_count,
    next_cursor,
    base_sha: snapshot.base,
    head_sha: snapshot.head,
  }
}
