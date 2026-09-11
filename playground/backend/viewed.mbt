///|
const VIEWED_SNAPSHOT_QUERY : String =
  #|query ViewedSnapshot($owner: String!, $repo: String!, $number: Int!) {
  #|  repository(owner: $owner, name: $repo) {
  #|    pullRequest(number: $number) { id baseRefOid headRefOid }
  #|  }
  #|}

///|
const VIEWED_FILES_QUERY : String =
  #|query ViewedFiles($owner: String!, $repo: String!, $number: Int!, $cursor: String) {
  #|  repository(owner: $owner, name: $repo) {
  #|    pullRequest(number: $number) {
  #|      id baseRefOid headRefOid
  #|      files(first: 100, after: $cursor) {
  #|        totalCount nodes { path viewerViewedState }
  #|        pageInfo { hasNextPage endCursor }
  #|      }
  #|    }
  #|  }
  #|}

///|
const MARK_VIEWED : String =
  #|mutation MarkViewed($id: ID!, $path: String!) {
  #|  markFileAsViewed(input: {pullRequestId: $id, path: $path}) {
  #|    pullRequest { id baseRefOid headRefOid }
  #|  }
  #|}

///|
const UNMARK_VIEWED : String =
  #|mutation UnmarkViewed($id: ID!, $path: String!) {
  #|  unmarkFileAsViewed(input: {pullRequestId: $id, path: $path}) {
  #|    pullRequest { id baseRefOid headRefOid }
  #|  }
  #|}

///|
fn invalid_viewed_response() -> Error {
  RpcError(
    502, "invalid_github_response", "GitHub returned invalid Viewed data.",
  )
}

///|
fn viewed_snapshot_changed() -> Error {
  RpcError(
    409, "pull_snapshot_changed", "PR updated. Load the latest PR before marking files.",
  )
}

///|
fn graphql_data(value : Json) -> Json raise {
  match field(value, "errors") {
    Null | Array([]) => ()
    Array(errors) => {
      // Reject partial data too. Do not expose arbitrary upstream details.
      let types = errors.map(error => optional_string(error, "type"))
      if types.contains("RATE_LIMITED") {
        raise RpcError(
          429, "rate_limit", "GitHub rate limit exceeded. Try again later.",
        )
      }
      if types.contains("FORBIDDEN") || types.contains("INSUFFICIENT_SCOPES") {
        raise RpcError(
          403, "permission_denied", "GitHub denied access to Viewed state. Check your repository and App access.",
        )
      }
      if types.contains("UNAUTHORIZED") {
        raise RpcError(
          401, "authentication_required", "Your GitHub session expired. Sign in again.",
        )
      }
      if types.contains("NOT_FOUND") {
        raise RpcError(
          404, "not_found_or_not_installed", "GitHub could not find this pull request. Check repository and App access.",
        )
      }
      raise RpcError(
        502, "github_graphql_error", "GitHub could not complete the Viewed request.",
      )
    }
    _ => raise invalid_viewed_response()
  }
  let data = field(value, "data")
  guard data is Object(_) else { raise invalid_viewed_response() }
  data
}

///|
async fn App::graphql(
  self : App,
  session : Session?,
  query : String,
  variables : Json,
) -> Json {
  guard session is Some(s) && !s.tokens.is_empty() else {
    raise RpcError(
      401, "authentication_required", "Sign in to sync Viewed files with GitHub.",
    )
  }
  graphql_data(
    self.github_json(session, "/graphql", meth=Post, body={
      "query": query,
      "variables": variables,
    }),
  )
}

///|
priv struct ViewedSnapshot {
  id : String
  base : String
  head : String
} derive(Eq)

///|
fn viewed_snapshot(value : Json) -> ViewedSnapshot raise {
  guard field(value, "id") is String(id) &&
    !id.is_empty() &&
    field(value, "baseRefOid") is String(base) &&
    valid_sha(base) &&
    field(value, "headRefOid") is String(head) &&
    valid_sha(head) else {
    raise invalid_viewed_response()
  }
  { id, base, head, }
}

///|
fn viewed_variables(p : @protocol.PullViewedGet) -> Json raise {
  let number : Int64 = @json.from_json(p.number.to_json())
  { "owner": p.owner, "repo": p.repo, "number": number.to_int() }
}

///|
fn viewed_pull(data : Json) -> Json {
  field(field(data, "repository"), "pullRequest")
}

///|
async fn App::pull_viewed(
  self : App,
  session : Session?,
  p : @protocol.PullViewedGet,
) -> @protocol.ApiPullViewed {
  let files : Array[@protocol.ApiFileViewed] = []
  let paths : Map[String, Bool] = Map([])
  let cursors : Map[String, Bool] = Map([])
  let mut cursor : Json = Json::null()
  let mut snapshot : ViewedSnapshot? = None
  let mut total : Int? = None
  for _page in 0..<30 {
    let variables = viewed_variables(p)
    guard variables is Object(variables) else {
      raise invalid_viewed_response()
    }
    variables["cursor"] = cursor
    let pull = viewed_pull(
      self.graphql(session, VIEWED_FILES_QUERY, Json::object(variables)),
    )
    let current = viewed_snapshot(pull)
    if snapshot is Some(previous) && previous != current {
      raise viewed_snapshot_changed()
    }
    snapshot = Some(current)
    let connection = field(pull, "files")
    guard field(connection, "totalCount") is Number(n, ..) &&
      n >= 0 &&
      n <= 3000 &&
      n == n.to_int().to_double() else {
      raise RpcError(
        422, "pagination_limit", "Viewed supports up to 3,000 files per PR.",
      )
    }
    if total is Some(previous) && previous != n.to_int() {
      raise viewed_snapshot_changed()
    }
    total = Some(n.to_int())
    guard field(connection, "nodes") is Array(nodes) && nodes.length() <= 100 else {
      raise invalid_viewed_response()
    }
    for node in nodes {
      guard field(node, "path") is String(path) &&
        @protocol.valid_repository_path(path) &&
        !paths.contains(path) else {
        raise invalid_viewed_response()
      }
      let state : @protocol.FileViewedState = match
        field(node, "viewerViewedState") {
        String("VIEWED") => Viewed
        String("UNVIEWED") => Unviewed
        String("DISMISSED") => Dismissed
        _ => raise invalid_viewed_response()
      }
      paths[path] = true
      files.push({ path, state, })
    }
    guard files.length() <= n.to_int() else { raise invalid_viewed_response() }
    let info = field(connection, "pageInfo")
    match field(info, "hasNextPage") {
      False => {
        guard files.length() == n.to_int() else {
          raise invalid_viewed_response()
        }
        let verified = viewed_snapshot(
          viewed_pull(
            self.graphql(session, VIEWED_SNAPSHOT_QUERY, viewed_variables(p)),
          ),
        )
        guard verified == current else { raise viewed_snapshot_changed() }
        return { base_sha: current.base, head_sha: current.head, files, }
      }
      True => {
        guard !nodes.is_empty() &&
          field(info, "endCursor") is String(next) &&
          !next.is_empty() &&
          !cursors.contains(next) else {
          raise invalid_viewed_response()
        }
        cursors[next] = true
        cursor = Json::string(next)
      }
      _ => raise invalid_viewed_response()
    }
  }
  raise RpcError(
    422, "pagination_limit", "GitHub returned too many Viewed file pages.",
  )
}

///|
async fn App::set_file_viewed(
  self : App,
  session : Session?,
  p : @protocol.PullFileViewedSet,
) -> @protocol.ApiFileViewedResult {
  let snapshot = viewed_snapshot(
    viewed_pull(
      self.graphql(
        session,
        VIEWED_SNAPSHOT_QUERY,
        viewed_variables({ owner: p.owner, repo: p.repo, number: p.number, }),
      ),
    ),
  )
  guard snapshot.base == p.base_sha && snapshot.head == p.head_sha else {
    raise viewed_snapshot_changed()
  }
  let data = self.graphql(
    session,
    if p.viewed {
      MARK_VIEWED
    } else {
      UNMARK_VIEWED
    },
    { "id": snapshot.id, "path": p.path },
  )
  let result = viewed_snapshot(
    field(
      field(
        data,
        if p.viewed {
          "markFileAsViewed"
        } else {
          "unmarkFileAsViewed"
        },
      ),
      "pullRequest",
    ),
  )
  guard result == snapshot else { raise viewed_snapshot_changed() }
  {
    base_sha: result.base,
    head_sha: result.head,
    file: { path: p.path, state: if p.viewed { Viewed } else { Unviewed }, },
  }
}
