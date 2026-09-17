///|
priv struct SearchWindow {
  since : Int64
  until : Int64
  page : Int
  offset : Int
} derive(FromJson, ToJson)

///|
priv struct PullSearchCursor {
  windows : Array[SearchWindow]
  total : Int
  total_confirmed : Bool
} derive(FromJson, ToJson)

///|
fn home_session(session : Session?) -> Session raise {
  guard session is Some(session) && !session.tokens.is_empty() else {
    raise RpcError(
      401, "authentication_required", "Sign in to view your pull requests.",
    )
  }
  session
}

///|
// Authenticated cursors are bound to the session epoch and operation, and cannot
// supply search qualifiers, repository names or GraphQL expressions.
fn[T : ToJson] App::home_cursor(
  self : App,
  session : Session,
  scope : String,
  value : T,
) -> String raise {
  seal(
    self.config.key,
    "home:\{scope}:\{session.epoch}",
    "\{session.id}:\{session.user}",
    @utf8.encode(value.to_json().stringify()),
  )
}

///|
fn[T : FromJson] App::read_home_cursor(
  self : App,
  session : Session,
  scope : String,
  cursor : String,
) -> T raise {
  @json.from_json(
    @json.parse(
      @utf8.decode(
        unseal(
          self.config.key,
          "home:\{scope}:\{session.epoch}",
          "\{session.id}:\{session.user}",
          cursor,
        ),
      ),
    ),
  ) catch {
    _ =>
      raise RpcError(
        400, "invalid_cursor", "This pagination cursor is no longer valid. Refresh the list.",
      )
  }
}

///|
fn search_date(second : Int64) -> String raise {
  @time.unix(second).to_plain_date_time().to_string() + "Z"
}

///|
fn search_second(value : String) -> Int64 raise {
  let date : @time.PlainDateTime = @string.from_str(value.trim_end(chars="Z"))
  date.to_unix_second()
}

///|
fn home_invalid() -> Error {
  RpcError(
    502, "invalid_github_response", "GitHub returned invalid pull request data.",
  )
}

///|
fn home_count(value : Json) -> Int raise {
  guard value is Number(n, ..) &&
    n >= 0 &&
    n <= 2147483647.0 &&
    n == n.to_int().to_double() else {
    raise home_invalid()
  }
  n.to_int()
}

///|
fn pull_summary(value : Json) -> @protocol.ApiPullSummary raise {
  let repository = optional_string(value, "repository_url")
    .split("/")
    .map(StringView::to_owned)
    .collect()
  guard repository.length() >= 2 else { raise home_invalid() }
  let owner = repository[repository.length() - 2]
  let repo = repository[repository.length() - 1]
  guard valid_owner(owner) &&
    valid_repo(repo) &&
    field(value, "title") is String(title) &&
    field(value, "updated_at") is String(updated_at) &&
    field(value, "draft") is (True | False) &&
    field(value, "pull_request") is Object(_) &&
    field(value, "state") == Json::string("open") else {
    raise home_invalid()
  }
  ignore(search_second(updated_at) catch { _ => raise home_invalid() })
  {
    owner,
    repo,
    number: github_id(field(value, "number")),
    title,
    author: optional_string(field(value, "user"), "login"),
    updated_at,
    draft: field(value, "draft") is True,
  }
}

///|
async fn App::viewer_pulls(
  self : App,
  session : Session?,
  p : @protocol.ViewerPullsGet,
) -> @protocol.ApiViewerPulls {
  let session = home_session(session)
  let qualifier = match p.kind {
    ReviewRequested => "user-review-requested:@me"
    Authored => "author:@me"
  }
  let scope = "pulls:\{qualifier}"
  let initial : PullSearchCursor = match p.cursor {
    Some(cursor) => self.read_home_cursor(session, scope, cursor)
    None =>
      {
        windows: [{ since: 0, until: now(), page: 1, offset: 0, }],
        total: 0,
        total_confirmed: false,
      }
  }
  let windows = initial.windows.copy()
  let mut total = initial.total
  let mut total_confirmed = initial.total_confirmed
  let result : Array[@protocol.ApiPullSummary] = []
  // Bound work per RPC so large searches can make progress within GitHub's
  // search rate limit. Each cursor preserves the remaining disjoint windows.
  for _ in 0..<8 {
    guard windows.get(0) is Some(window) else {
      return {
        items: result,
        total_count: total,
        next_cursor: None,
        incomplete: None,
      }
    }
    let query = "is:pr is:open \{qualifier} updated:\{search_date(window.since)}..\{search_date(window.until)}"
    let raw = self.github_json(
      Some(session),
      "/search/issues?q=\{encode_component(query)}&sort=updated&order=desc&per_page=50&page=\{window.page}",
    )
    let count = home_count(field(raw, "total_count"))
    if !total_confirmed {
      total = count
    }
    guard field(raw, "incomplete_results") is (True | False) &&
      field(raw, "items") is Array(values) &&
      values.length() <= 50 else {
      raise home_invalid()
    }
    if field(raw, "incomplete_results") is True {
      return {
        items: result,
        total_count: total,
        next_cursor: Some(
          self.home_cursor(session, scope, PullSearchCursor::{
            windows,
            total,
            total_confirmed,
          }),
        ),
        incomplete: Some(
          "GitHub returned an incomplete search. Retry to continue loading this page.",
        ),
      }
    }
    // Confirm the original window's count before splitting or advancing it.
    // Incomplete retries can revise the total until this first complete search.
    total_confirmed = true
    let items = values.map(pull_summary)
    if count > 1000 {
      if window.since == window.until {
        return {
          items: result,
          total_count: total,
          next_cursor: Some(
            self.home_cursor(session, scope, PullSearchCursor::{
              windows,
              total,
              total_confirmed,
            }),
          ),
          incomplete: Some(
            "More than 1,000 PRs share the same update time. GitHub cannot return the complete list. Retry or refresh later.",
          ),
        }
      }
      // Split near the 50th result. Keep every PR sharing the boundary second
      // in one window, avoiding dropped ties at GitHub's 1,000-result ceiling.
      let oldest = match items.last() {
        Some(item) => search_second(item.updated_at)
        None => raise home_invalid()
      }
      guard oldest >= window.since && oldest <= window.until else {
        raise home_invalid()
      }
      let pivot = if oldest == window.since { window.since + 1 } else { oldest }
      windows[0] = { since: pivot, until: window.until, page: 1, offset: 0, }
      windows.insert(1, {
        since: window.since,
        until: pivot - 1,
        page: 1,
        offset: 0,
      })
      continue
    }
    // Fill the logical page across window boundaries. An offset lets the next
    // request resume a partially consumed GitHub page without putting PR data
    // into the cursor or loading more than 50 rows in the browser at once.
    let offset = Int::min(window.offset, items.length())
    let take = Int::min(50 - result.length(), items.length() - offset)
    for item in items[offset:offset + take] {
      result.push(item)
    }
    let consumed = (window.page - 1) * 50 + offset + take
    if offset + take < items.length() {
      windows[0] = { ..window, offset: offset + take, }
    } else if consumed < count {
      guard !items.is_empty() && window.page < 20 else { raise home_invalid() }
      windows[0] = { ..window, page: window.page + 1, offset: 0, }
    } else {
      ignore(windows.remove(0))
    }
    if result.length() == 50 || windows.is_empty() {
      return {
        items: result,
        total_count: total,
        incomplete: None,
        next_cursor: if windows.is_empty() {
          None
        } else {
          Some(
            self.home_cursor(session, scope, PullSearchCursor::{
              windows,
              total,
              total_confirmed,
            }),
          )
        },
      }
    }
  }
  {
    items: result,
    total_count: total,
    next_cursor: Some(
      self.home_cursor(session, scope, PullSearchCursor::{
        windows,
        total,
        total_confirmed,
      }),
    ),
    incomplete: Some(
      "The search is still narrowing update windows. Retry to continue loading.",
    ),
  }
}
