///|
fn invalid_graphql_response() -> Error {
  @common.RpcError(
    502, "invalid_github_response", "GitHub returned invalid Viewed data.",
  )
}

///|
fn graphql_data(value : Json) -> Json raise {
  match @common.field(value, "errors") {
    Null | Array([]) => ()
    Array(errors) => {
      // Reject partial data too. Do not expose arbitrary upstream details.
      let types = errors.map(error => @common.optional_string(error, "type"))
      if types.contains("RATE_LIMITED") {
        raise @common.RpcError(
          429, "rate_limit", "GitHub rate limit exceeded. Try again later.",
        )
      }
      if types.contains("FORBIDDEN") || types.contains("INSUFFICIENT_SCOPES") {
        raise @common.RpcError(
          403, "permission_denied", "GitHub denied access. Check your repository and @storage.App access.",
        )
      }
      if types.contains("UNAUTHORIZED") {
        raise @common.RpcError(
          401, "authentication_required", "Your GitHub session expired. Sign in again.",
        )
      }
      if types.contains("NOT_FOUND") {
        raise @common.RpcError(
          404, "not_found_or_not_installed", "GitHub could not find this pull request. Check repository and @storage.App access.",
        )
      }
      raise @common.RpcError(
        502, "github_graphql_error", "GitHub could not complete the request.",
      )
    }
    _ => raise invalid_graphql_response()
  }
  let data = @common.field(value, "data")
  guard data is Object(_) else { raise invalid_graphql_response() }
  data
}

///|
pub async fn graphql(
  app : @storage.App,
  session : @storage.Session?,
  query : String,
  variables : Json,
) -> Json {
  guard session is Some(active) && !active.tokens.is_empty() else {
    raise @common.RpcError(
      401, "authentication_required", "Sign in to access this GitHub data.",
    )
  }
  graphql_data(
    github_json(app, session, "/graphql", meth=Post, body={
      "query": query,
      "variables": variables,
    }),
  )
}

///|
pub(all) struct PullSnapshot {
  id : String
  base : String
  head : String
} derive(Eq)

///|
pub extend PullSnapshot with Eq::{equal, not_equal}

///|
pub fn pull_snapshot(value : Json) -> PullSnapshot raise {
  guard @common.field(value, "id") is String(id) &&
    !id.is_empty() &&
    @common.field(value, "baseRefOid") is String(base) &&
    @common.valid_sha(base) &&
    @common.field(value, "headRefOid") is String(head) &&
    @common.valid_sha(head) else {
    raise invalid_graphql_response()
  }
  { id, base, head, }
}

///|
pub fn pull_variables(p : @protocol.PullViewedGet) -> Json raise {
  let number : Int64 = @json.from_json(p.number.to_json())
  { "owner": p.owner, "repo": p.repo, "number": number.to_int() }
}

///|
pub fn pull_from_graphql(data : Json) -> Json {
  @common.field(@common.field(data, "repository"), "pullRequest")
}
