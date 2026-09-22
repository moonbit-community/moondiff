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
  @common.RpcError(
    502, "invalid_github_response", "GitHub returned invalid Viewed data.",
  )
}

///|
fn viewed_snapshot_changed() -> Error {
  @common.RpcError(
    409, "pull_snapshot_changed", "PR updated. Load the latest PR before marking files.",
  )
}

///|
pub async fn pull_viewed(
  app : @storage.App,
  session : @storage.Session?,
  p : @protocol.PullViewedGet,
) -> @protocol.ApiPullViewed {
  let files : Array[@protocol.ApiFileViewed] = []
  let paths : Map[String, Bool] = Map([])
  let cursors : Map[String, Bool] = Map([])
  let mut cursor : Json = Json::null()
  let mut snapshot : @github.PullSnapshot? = None
  let mut total : Int? = None
  for _page in 0..<30 {
    let variables = @github.pull_variables(p)
    guard variables is Object(variables) else {
      raise invalid_viewed_response()
    }
    variables["cursor"] = cursor
    let pull = @github.pull_from_graphql(
      @github.graphql(app, session, VIEWED_FILES_QUERY, Json::object(variables)),
    )
    let current = @github.pull_snapshot(pull)
    if snapshot is Some(previous) && previous != current {
      raise viewed_snapshot_changed()
    }
    snapshot = Some(current)
    let connection = @common.field(pull, "files")
    guard @common.field(connection, "totalCount") is Number(n, ..) &&
      n >= 0 &&
      n <= 3000 &&
      n == n.to_int().to_double() else {
      raise @common.RpcError(
        422, "pagination_limit", "Viewed supports up to 3,000 files per PR.",
      )
    }
    if total is Some(previous) && previous != n.to_int() {
      raise viewed_snapshot_changed()
    }
    total = Some(n.to_int())
    guard @common.field(connection, "nodes") is Array(nodes) &&
      nodes.length() <= 100 else {
      raise invalid_viewed_response()
    }
    for node in nodes {
      guard @common.field(node, "path") is String(path) &&
        @protocol.valid_repository_path(path) &&
        !paths.contains(path) else {
        raise invalid_viewed_response()
      }
      let state : @protocol.FileViewedState = match
        @common.field(node, "viewerViewedState") {
        String("VIEWED") => Viewed
        String("UNVIEWED") => Unviewed
        String("DISMISSED") => Dismissed
        _ => raise invalid_viewed_response()
      }
      paths[path] = true
      files.push({ path, state, })
    }
    guard files.length() <= n.to_int() else { raise invalid_viewed_response() }
    let info = @common.field(connection, "pageInfo")
    match @common.field(info, "hasNextPage") {
      False => {
        guard files.length() == n.to_int() else {
          raise invalid_viewed_response()
        }
        let verified = @github.pull_snapshot(
          @github.pull_from_graphql(
            @github.graphql(
              app,
              session,
              VIEWED_SNAPSHOT_QUERY,
              @github.pull_variables(p),
            ),
          ),
        )
        guard verified == current else { raise viewed_snapshot_changed() }
        return { base_sha: current.base, head_sha: current.head, files, }
      }
      True => {
        guard !nodes.is_empty() &&
          @common.field(info, "endCursor") is String(next) &&
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
  raise @common.RpcError(
    422, "pagination_limit", "GitHub returned too many Viewed file pages.",
  )
}

///|
pub async fn set_file_viewed(
  app : @storage.App,
  session : @storage.Session?,
  p : @protocol.PullFileViewedSet,
) -> @protocol.ApiFileViewedResult {
  let snapshot = @github.pull_snapshot(
    @github.pull_from_graphql(
      @github.graphql(
        app,
        session,
        VIEWED_SNAPSHOT_QUERY,
        @github.pull_variables({
          owner: p.owner,
          repo: p.repo,
          number: p.number,
        }),
      ),
    ),
  )
  guard snapshot.base == p.base_sha && snapshot.head == p.head_sha else {
    raise viewed_snapshot_changed()
  }
  let data = @github.graphql(
    app,
    session,
    if p.viewed {
      MARK_VIEWED
    } else {
      UNMARK_VIEWED
    },
    { "id": snapshot.id, "path": p.path },
  )
  let result = @github.pull_snapshot(
    @common.field(
      @common.field(
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
