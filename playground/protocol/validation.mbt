///|
fn decimal(value : String) -> Bool {
  !value.is_empty() &&
  value.length() <= 20 &&
  value[0] != '0' &&
  value.iter().all(c => c >= '0' && c <= '9')
}

///|
fn alnum(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
}

///|
pub fn valid_owner(value : String) -> Bool {
  !value.is_empty() &&
  value.length() <= 39 &&
  alnum(value[0].to_char().unwrap_or('\ufffd')) &&
  alnum(value[value.length() - 1].to_char().unwrap_or('\ufffd')) &&
  value.iter().all(c => alnum(c) || c == '-')
}

///|
pub fn valid_repo(value : String) -> Bool {
  !value.is_empty() &&
  value.length() <= 100 &&
  value != "." &&
  value != ".." &&
  value.iter().all(c => alnum(c) || c == '-' || c == '_' || c == '.')
}

///|
pub fn valid_sha(value : String) -> Bool {
  value.length() >= 7 &&
  value.length() <= 64 &&
  value
  .iter()
  .all(c => {
    (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
  })
}

///|
pub fn valid_path(path : String) -> Bool {
  !path.is_empty() &&
  path.length() <= 4096 &&
  path.iter().all(c => c.to_int() >= 32 && c.to_int() != 127 && c != '\\') &&
  path.split("/").all(p => p != "" && p != "." && p != "..")
}

///|
/// Validate a Git repository path without normalizing its filename characters.
/// Slashes delimit components; backslashes and control characters except NUL
/// are literal filename characters. Local/static paths use `valid_path` instead.
pub fn valid_repository_path(path : String) -> Bool {
  !path.is_empty() &&
  path.length() <= 4096 &&
  !path.contains("\u0000") &&
  path.split("/").all(p => p != "" && p != "." && p != "..")
}

///|
pub suberror ProtocolError {
  ProtocolError(String, String)
}

///|
pub fn[T : FromJson + ToJson] decode(value : Json) -> T raise {
  let decoded : T = @json.from_json(value)
  guard ToJson::to_json(decoded) == value else {
    raise ProtocolError(
      "invalid_arguments", "Unexpected fields or noncanonical values.",
    )
  }
  decoded
}

///|
pub fn decode_request(value : Json) -> GitHubRequest raise {
  let envelope : RpcRequest = decode(value)
  guard envelope.v == 2 else {
    raise ProtocolError("operation_not_allowed", "Unsupported RPC version.")
  }
  envelope.request.validate()
  envelope.request
}

///|
pub fn GitHubRequest::encode(self : GitHubRequest) -> Json {
  ToJson::to_json(RpcRequest::{ v: 2, request: self, })
}

///|
pub fn valid_attempt_id(id : String) -> Bool {
  id.length() >= 16 &&
  id.length() <= 128 &&
  id.iter().all(c => alnum(c) || c == '-' || c == '_')
}

///|
fn require(valid : Bool, code : String, message : String) -> Unit raise {
  guard valid else { raise ProtocolError(code, message) }
}

///|
fn check_number(number : String) -> Unit raise {
  require(decimal(number), "invalid_arguments", "Invalid identifier.")
  let id : Int64 = @json.from_json(number.to_json())
  require(id > 0, "invalid_arguments", "Identifier out of range.")
}

///|
fn check_body(body : String) -> Unit raise {
  require(
    !body.trim().is_empty() && @utf8.encode(body).length() <= 65536,
    "invalid_comment",
    "A comment must contain between 1 and 65,536 UTF-8 bytes.",
  )
}

///|
fn check_sha(sha : String) -> Unit raise {
  require(valid_sha(sha), "invalid_sha", "Invalid commit revision.")
}

///|
fn check_path(path : String) -> Unit raise {
  require(
    valid_repository_path(path),
    "invalid_path",
    "Invalid repository path.",
  )
}

///|
pub fn GitHubRequest::is_write(self : GitHubRequest) -> Bool {
  match self {
    CommitGet(_) => false
    PullGet(_) => false
    PullViewedGet(_) => false
    PullFileViewedSet(_) => true
    CompareGet(_) => false
    PullFiles(_) => false
    ContentGet(_) => false
    CommentsList(_) => false
    IssueCommentCreate(_) => true
    ReviewCommentCreate(_) => true
    CommitCommentCreate(_) => true
    ReviewReplyCreate(_) => true
    IssueCommentDelete(_) => true
    ReviewCommentDelete(_) => true
    CommitCommentDelete(_) => true
  }
}

///|
pub fn GitHubRequest::validate(self : GitHubRequest) -> Unit raise {
  let (owner, repo) = match self {
    CommitGet(p) => (p.owner, p.repo)
    PullGet(p) => (p.owner, p.repo)
    PullViewedGet(p) => (p.owner, p.repo)
    PullFileViewedSet(p) => (p.owner, p.repo)
    CompareGet(p) => (p.owner, p.repo)
    PullFiles(p) => (p.owner, p.repo)
    ContentGet(p) => (p.owner, p.repo)
    CommentsList(p) => (p.owner, p.repo)
    IssueCommentCreate(p) => (p.owner, p.repo)
    ReviewCommentCreate(p) => (p.owner, p.repo)
    CommitCommentCreate(p) => (p.owner, p.repo)
    ReviewReplyCreate(p) => (p.owner, p.repo)
    IssueCommentDelete(p) => (p.owner, p.repo)
    ReviewCommentDelete(p) => (p.owner, p.repo)
    CommitCommentDelete(p) => (p.owner, p.repo)
  }
  require(
    valid_owner(owner) && valid_repo(repo),
    "invalid_repository",
    "Invalid repository owner or name.",
  )
  match self {
    CommitGet(p) => {
      check_sha(p.sha)
      require(
        p.page >= 1 && p.page <= 10000,
        "invalid_arguments",
        "Invalid page.",
      )
    }
    PullGet(p) => check_number(p.number)
    PullViewedGet(p) => check_pull_number(p.number)
    PullFileViewedSet(p) => {
      check_pull_number(p.number)
      check_path(p.path)
      check_sha(p.base_sha)
      check_sha(p.head_sha)
    }
    CompareGet(p) => {
      check_sha(p.base)
      check_sha(p.head)
    }
    PullFiles(p) => {
      check_number(p.number)
      require(
        p.page >= 1 && p.page <= 10000,
        "invalid_arguments",
        "Invalid page.",
      )
    }
    ContentGet(p) => {
      check_path(p.path)
      check_sha(p.revision)
    }
    CommentsList(p) =>
      match p.target {
        Commit(sha~) => check_sha(sha)
        Pull(number~) => check_number(number)
        PullCommit(number~, sha~) => {
          check_number(number)
          check_sha(sha)
        }
      }
    IssueCommentCreate(p) => {
      check_number(p.number)
      check_body(p.body)
    }
    ReviewCommentCreate(p) => {
      check_number(p.number)
      check_sha(p.commit_id)
      check_path(p.path)
      require(p.line >= 1, "invalid_arguments", "Invalid line.")
      check_body(p.body)
    }
    CommitCommentCreate(p) => {
      check_sha(p.sha)
      check_path(p.path)
      require(p.position >= 1, "invalid_arguments", "Invalid position.")
      check_body(p.body)
    }
    ReviewReplyCreate(p) => {
      check_number(p.number)
      require(
        p.comment_id > 0,
        "invalid_arguments",
        "Invalid comment identifier.",
      )
      check_body(p.body)
    }
    IssueCommentDelete(p) =>
      require(
        p.comment_id > 0,
        "invalid_arguments",
        "Invalid comment identifier.",
      )
    ReviewCommentDelete(p) =>
      require(
        p.comment_id > 0,
        "invalid_arguments",
        "Invalid comment identifier.",
      )
    CommitCommentDelete(p) =>
      require(
        p.comment_id > 0,
        "invalid_arguments",
        "Invalid comment identifier.",
      )
  }
}

///|
// GraphQL's Int is signed 32-bit, unlike REST identifiers.
fn check_pull_number(number : String) -> Unit raise {
  check_number(number)
  let id : Int64 = @json.from_json(number.to_json())
  require(
    id <= 2147483647L,
    "invalid_arguments",
    "Pull request number out of range.",
  )
}
