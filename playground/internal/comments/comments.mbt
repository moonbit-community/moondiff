///|
pub(all) struct ApiCommentUser {
  login : String
} derive(Eq, FromJson)

///|
pub(all) struct ApiIssueComment {
  id : Int64
  body : String
  html_url : String
  created_at : String
  user : ApiCommentUser?
} derive(Eq, FromJson)

///|
pub(all) struct ApiReviewComment {
  id : Int64
  body : String
  html_url : String
  created_at : String
  user : ApiCommentUser?
  path : String
  line : Int?
  side : String?
  position : Int?
  commit_id : String
  in_reply_to_id : Int64?
} derive(Eq, FromJson)

///|
pub(all) struct ApiCommitComment {
  id : Int64
  body : String
  html_url : String
  created_at : String
  user : ApiCommentUser?
  path : String?
  position : Int?
  line : Int?
} derive(Eq, FromJson)

///|
pub(all) struct ApiCommentBundle {
  issue_comments : Array[ApiIssueComment]
  review_comments : Array[ApiReviewComment]
  commit_comments : Array[ApiCommitComment]
} derive(Eq, FromJson)

///|
pub(all) struct ApiDeviceFlow {
  flow_id : String
  user_code : String
  verification_uri : String
  expires_in : Int
  poll_after : Int
} derive(FromJson)

///|
pub(all) struct ApiAuthStatus {
  authenticated : Bool
  login : String?
  install_url : String?
  device_flow : ApiDeviceFlow?
} derive(FromJson)

///|
pub(all) enum DeviceCodeCopyStatus {
  DeviceCodeCopyReady
  DeviceCodeCopyDone
  DeviceCodeCopyError(String)
} derive(Eq)

///|
pub(all) struct DeviceAuthorization {
  flow_id : String
  user_code : String
  verification_uri : String
  expires_in : Int
  poll_after : Int
  install_url : String?
  copy_status : DeviceCodeCopyStatus
} derive(Eq)

///|
pub(all) enum AuthStatus {
  WebReadOnly
  AuthChecking
  Anonymous(String?)
  DeviceAuthorizing(DeviceAuthorization)
  DeviceCancelling(DeviceAuthorization)
  SignedIn(String?)
  AuthFailed(String)
} derive(Eq)

///|
pub(all) enum CommentsStatus {
  CommentsDisabled
  CommentsLoading
  CommentsReady(ApiCommentBundle)
  CommentsFailed(String)
} derive(Eq)

///|
pub(all) enum DraftKind {
  OverallDraft
  InlineDraft(Int, ReviewAnchor)
  ReplyDraft(Int64)
} derive(Eq)

///|
pub(all) struct CommentDraft {
  kind : DraftKind
  body : String
  submitting : Bool
  error : String?
} derive(Eq)

///|
pub(all) struct ReviewState {
  auth : AuthStatus
  last_authenticated_login : String?
  comments : CommentsStatus
  draft : CommentDraft?
} derive(Eq)

///|
pub fn initial_review_state() -> ReviewState {
  if extension_host_enabled() {
    {
      auth: AuthChecking,
      last_authenticated_login: None,
      comments: CommentsLoading,
      draft: None,
    }
  } else {
    {
      auth: WebReadOnly,
      last_authenticated_login: None,
      comments: CommentsDisabled,
      draft: None,
    }
  }
}

///|
pub fn review_can_comment(review : ReviewState) -> Bool {
  review.auth is SignedIn(_)
}

///|
pub fn auth_status_from_api(status : ApiAuthStatus) -> AuthStatus {
  if status.authenticated {
    SignedIn(status.login)
  } else if status.device_flow is Some(flow) {
    DeviceAuthorizing({
      flow_id: flow.flow_id,
      user_code: flow.user_code,
      verification_uri: flow.verification_uri,
      expires_in: flow.expires_in,
      poll_after: flow.poll_after,
      install_url: status.install_url,
      copy_status: DeviceCodeCopyReady,
    })
  } else {
    Anonymous(status.install_url)
  }
}

///|
pub fn auth_status_from_api_preserving(
  status : ApiAuthStatus,
  previous : AuthStatus,
) -> AuthStatus {
  let next = auth_status_from_api(status)
  match (next, previous) {
    (DeviceAuthorizing(device), DeviceAuthorizing(old)) if device.flow_id ==
      old.flow_id =>
      DeviceAuthorizing({ ..device, copy_status: old.copy_status, })
    (DeviceAuthorizing(device), DeviceCancelling(old)) if device.flow_id ==
      old.flow_id =>
      DeviceCancelling({ ..device, copy_status: old.copy_status, })
    _ => next
  }
}

///|
pub fn review_state_with_auth(
  review : ReviewState,
  auth : AuthStatus,
) -> ReviewState {
  {
    auth,
    last_authenticated_login: review.last_authenticated_login,
    comments: review.comments,
    draft: review.draft,
  }
}

///|
pub fn review_state_with_comments(
  review : ReviewState,
  comments : CommentsStatus,
) -> ReviewState {
  {
    auth: review.auth,
    last_authenticated_login: review.last_authenticated_login,
    comments,
    draft: review.draft,
  }
}

///|
pub fn review_state_with_draft(
  review : ReviewState,
  draft : CommentDraft?,
) -> ReviewState {
  {
    auth: review.auth,
    last_authenticated_login: review.last_authenticated_login,
    comments: review.comments,
    draft,
  }
}

///|
priv struct CommentListArgs {
  owner : String
  repo : String
  kind : String
  number : String?
  sha : String?
} derive(ToJson)

///|
priv struct IssueCommentArgs {
  owner : String
  repo : String
  number : String
  body : String
} derive(ToJson)

///|
priv struct ReviewCommentArgs {
  owner : String
  repo : String
  number : String
  commit_id : String
  path : String
  line : Int
  side : String
  body : String
} derive(ToJson)

///|
priv struct CommitCommentArgs {
  owner : String
  repo : String
  sha : String
  path : String
  position : Int
  body : String
} derive(ToJson)

///|
priv struct ReviewReplyArgs {
  owner : String
  repo : String
  number : String
  comment_id : Int64
  body : String
} derive(ToJson)

///|
priv struct DeviceFlowArgs {
  flow_id : String
} derive(ToJson)

///|
pub fn auth_status_request(
  emit : @rabbita.Emit[Result[ApiAuthStatus, Error]],
) -> @rabbita.Cmd {
  extension_rpc_json("auth.status", "{}", 0, emit)
}

///|
pub fn auth_device_start_request(
  emit : @rabbita.Emit[Result[ApiAuthStatus, Error]],
) -> @rabbita.Cmd {
  extension_rpc_json("auth.device.start", "{}", 0, emit)
}

///|
pub fn auth_device_poll_request(
  flow_id : String,
  emit : @rabbita.Emit[Result[ApiAuthStatus, Error]],
) -> @rabbita.Cmd {
  extension_rpc_request(
    "auth.device.poll",
    DeviceFlowArgs::{ flow_id, },
    0,
    emit,
  )
}

///|
pub fn auth_device_cancel_request(
  flow_id : String,
  emit : @rabbita.Emit[Result[ApiAuthStatus, Error]],
) -> @rabbita.Cmd {
  extension_rpc_request(
    "auth.device.cancel",
    DeviceFlowArgs::{ flow_id, },
    0,
    emit,
  )
}

///|
pub fn auth_logout_request(
  emit : @rabbita.Emit[Result[ApiAuthStatus, Error]],
) -> @rabbita.Cmd {
  extension_rpc_json("auth.logout", "{}", 0, emit)
}

///|
fn comment_list_args(reference : CommitRef) -> CommentListArgs {
  let (kind, number, sha) = match reference.target {
    PullRequest(number) => ("pull", Some(number), None)
    Commit(sha) => ("commit", None, Some(sha))
    PullCommit(number, sha) => ("pull_commit", Some(number), Some(sha))
  }
  { owner: reference.owner, repo: reference.repo, kind, number, sha, }
}

///|
pub fn comments_request(
  reference : CommitRef,
  generation : Int,
  emit : @rabbita.Emit[Result[ApiCommentBundle, Error]],
) -> @rabbita.Cmd {
  extension_rpc_request(
    "github.comments.list",
    comment_list_args(reference),
    generation,
    emit,
  )
}

///|
pub fn comment_head_request(
  reference : CommitRef,
  number : String,
  generation : Int,
  emit : @rabbita.Emit[Result[ApiPull, Error]],
) -> @rabbita.Cmd {
  gateway_json_request(
    "github.pull.get",
    reference_repository(reference),
    number,
    "",
    0,
    generation,
    emit,
  )
}

///|
pub fn create_issue_comment_request(
  reference : CommitRef,
  number : String,
  body : String,
  generation : Int,
  emit : @rabbita.Emit[Result[ApiIssueComment, Error]],
) -> @rabbita.Cmd {
  extension_rpc_request(
    "github.issue.comment.create",
    IssueCommentArgs::{
      owner: reference.owner,
      repo: reference.repo,
      number,
      body,
    },
    generation,
    emit,
  )
}

///|
pub fn create_review_comment_request(
  reference : CommitRef,
  number : String,
  commit_id : String,
  anchor : ReviewAnchor,
  body : String,
  generation : Int,
  emit : @rabbita.Emit[Result[ApiReviewComment, Error]],
) -> @rabbita.Cmd {
  extension_rpc_request(
    "github.review.comment.create",
    ReviewCommentArgs::{
      owner: reference.owner,
      repo: reference.repo,
      number,
      commit_id,
      path: anchor.path,
      line: anchor.line,
      side: if anchor.side is Left {
        "LEFT"
      } else {
        "RIGHT"
      },
      body,
    },
    generation,
    emit,
  )
}

///|
pub fn create_commit_comment_request(
  reference : CommitRef,
  sha : String,
  anchor : ReviewAnchor,
  body : String,
  generation : Int,
  emit : @rabbita.Emit[Result[ApiCommitComment, Error]],
) -> @rabbita.Cmd {
  guard anchor.position is Some(position) else { return @rabbita.none }
  extension_rpc_request(
    "github.commit.comment.create",
    CommitCommentArgs::{
      owner: reference.owner,
      repo: reference.repo,
      sha,
      path: anchor.path,
      position,
      body,
    },
    generation,
    emit,
  )
}

///|
pub fn create_review_reply_request(
  reference : CommitRef,
  number : String,
  comment_id : Int64,
  body : String,
  generation : Int,
  emit : @rabbita.Emit[Result[ApiReviewComment, Error]],
) -> @rabbita.Cmd {
  extension_rpc_request(
    "github.review.reply.create",
    ReviewReplyArgs::{
      owner: reference.owner,
      repo: reference.repo,
      number,
      comment_id,
      body,
    },
    generation,
    emit,
  )
}

///|
pub fn notify_github_page_command() -> @rabbita.Cmd {
  @cmd.custom_cmd(_scheduler => notify_github_page())
}

///|
extern "js" fn notify_github_page() -> Unit =
  #| () => globalThis.__MOONDIFF_EXTENSION_HOST__?.notifyCommentsChanged?.()

///|
pub fn author_label(user : ApiCommentUser?) -> String {
  user.map(user => user.login).unwrap_or("ghost")
}

///|
fn review_side_from_api(side : String?) -> ReviewSide? {
  match side {
    Some("LEFT") => Some(Left)
    Some("RIGHT") => Some(Right)
    _ => None
  }
}

///|
fn find_file_index(view : ChangeView, path : String) -> Int? {
  for index, file in view.files {
    if file.file.filename == path {
      return Some(index)
    }
  }
  None
}

///|
fn review_comment_outdated(
  view : ChangeView,
  comment : ApiReviewComment,
) -> Bool {
  if comment.position is None || comment.commit_id != view.sha {
    return true
  }
  guard comment.line is Some(line) &&
    review_side_from_api(comment.side) is Some(side) &&
    find_file_index(view, comment.path) is Some(index) else {
    return true
  }
  let file = view.files[index].file
  canonical_anchor(parse_canonical_patch(file.filename, file.patch), side, line)
  is None
}

///|
fn commit_comment_outdated(
  view : ChangeView,
  comment : ApiCommitComment,
) -> Bool {
  guard comment.path is Some(path) &&
    comment.position is Some(position) &&
    find_file_index(view, path) is Some(index) else {
    return true
  }
  guard parse_canonical_patch(path, view.files[index].file.patch)
    is Commentable(anchors) else {
    return true
  }
  !anchors.any(anchor => anchor.position == Some(position))
}

///|
pub(all) struct ReviewThread {
  root : ApiReviewComment
  replies : Array[ApiReviewComment]
  file_index : Int?
  outdated : Bool
}

///|
pub fn review_threads(
  view : ChangeView,
  comments : ArrayView[ApiReviewComment],
) -> Array[ReviewThread] {
  let threads : Array[ReviewThread] = []
  for root in comments {
    if root.in_reply_to_id is Some(_) {
      continue
    }
    let replies : Array[ApiReviewComment] = []
    for reply in comments {
      if reply.in_reply_to_id == Some(root.id) {
        replies.push(reply)
      }
    }
    threads.push({
      root,
      replies,
      file_index: find_file_index(view, root.path),
      outdated: review_comment_outdated(view, root),
    })
  }
  threads
}

///|
pub(all) struct CommitDiscussion {
  comment : ApiCommitComment
  file_index : Int?
  outdated : Bool
}

///|
pub fn commit_discussions(
  view : ChangeView,
  comments : ArrayView[ApiCommitComment],
) -> Array[CommitDiscussion] {
  comments.map(comment => {
    let file_index = if comment.path is Some(path) {
      find_file_index(view, path)
    } else {
      None
    }
    { comment, file_index, outdated: commit_comment_outdated(view, comment), }
  })
}
