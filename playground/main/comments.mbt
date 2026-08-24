///|
priv struct ApiCommentUser {
  login : String
} derive(Eq, FromJson)

///|
priv struct ApiIssueComment {
  id : Int64
  body : String
  html_url : String
  created_at : String
  user : ApiCommentUser?
} derive(Eq, FromJson)

///|
priv struct ApiReviewComment {
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
priv struct ApiCommitComment {
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
priv struct ApiCommentBundle {
  issue_comments : Array[ApiIssueComment]
  review_comments : Array[ApiReviewComment]
  commit_comments : Array[ApiCommitComment]
} derive(Eq, FromJson)

///|
priv struct ApiDeviceFlow {
  flow_id : String
  user_code : String
  verification_uri : String
  expires_in : Int
  poll_after : Int
} derive(FromJson)

///|
priv struct ApiAuthStatus {
  authenticated : Bool
  login : String?
  install_url : String?
  device_flow : ApiDeviceFlow?
} derive(FromJson)

///|
priv enum DeviceCodeCopyStatus {
  DeviceCodeCopyReady
  DeviceCodeCopyDone
  DeviceCodeCopyError(String)
} derive(Eq)

///|
priv struct DeviceAuthorization {
  flow_id : String
  user_code : String
  verification_uri : String
  expires_in : Int
  poll_after : Int
  install_url : String?
  copy_status : DeviceCodeCopyStatus
} derive(Eq)

///|
priv enum AuthStatus {
  WebReadOnly
  AuthChecking
  Anonymous(String?)
  DeviceAuthorizing(DeviceAuthorization)
  DeviceCancelling(DeviceAuthorization)
  SignedIn(String?)
  AuthFailed(String)
} derive(Eq)

///|
priv enum CommentsStatus {
  CommentsDisabled
  CommentsLoading
  CommentsReady(ApiCommentBundle)
  CommentsFailed(String)
} derive(Eq)

///|
priv enum DraftKind {
  OverallDraft
  InlineDraft(Int, ReviewAnchor)
  ReplyDraft(Int64)
} derive(Eq)

///|
priv struct CommentDraft {
  kind : DraftKind
  body : String
  submitting : Bool
  error : String?
} derive(Eq)

///|
priv struct ReviewState {
  auth : AuthStatus
  comments : CommentsStatus
  draft : CommentDraft?
} derive(Eq)

///|
fn initial_review_state() -> ReviewState {
  if extension_host_enabled() {
    { auth: AuthChecking, comments: CommentsLoading, draft: None }
  } else {
    { auth: WebReadOnly, comments: CommentsDisabled, draft: None }
  }
}

///|
fn review_can_comment(review : ReviewState) -> Bool {
  review.auth is SignedIn(_)
}

///|
fn auth_status_from_api(status : ApiAuthStatus) -> AuthStatus {
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
fn auth_status_from_api_preserving(
  status : ApiAuthStatus,
  previous : AuthStatus,
) -> AuthStatus {
  let next = auth_status_from_api(status)
  match (next, previous) {
    (DeviceAuthorizing(device), DeviceAuthorizing(old)) if device.flow_id ==
      old.flow_id =>
      DeviceAuthorizing({ ..device, copy_status: old.copy_status })
    _ => next
  }
}

///|
fn review_state_with_auth(
  review : ReviewState,
  auth : AuthStatus,
) -> ReviewState {
  { auth, comments: review.comments, draft: review.draft }
}

///|
fn review_state_with_comments(
  review : ReviewState,
  comments : CommentsStatus,
) -> ReviewState {
  { auth: review.auth, comments, draft: review.draft }
}

///|
fn review_state_with_draft(
  review : ReviewState,
  draft : CommentDraft?,
) -> ReviewState {
  { auth: review.auth, comments: review.comments, draft }
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
fn[A : ToJson, T : FromJson] extension_rpc_request(
  operation : String,
  args : A,
  generation : Int,
  msg : @rabbita.Emit[Result[T, Error]],
) -> @rabbita.Cmd {
  extension_rpc_json(
    operation,
    ToJson::to_json(args).stringify(),
    generation,
    msg,
  )
}

///|
fn[T : FromJson] extension_rpc_json(
  operation : String,
  args_json : String,
  generation : Int,
  msg : @rabbita.Emit[Result[T, Error]],
) -> @rabbita.Cmd {
  @cmd.custom_cmd(scheduler => {
    send_extension_rpc(
      operation,
      args_json,
      generation,
      completed=(ok, status, code, detail, response_body) => {
        let result : Result[T, Error] = if ok {
          try @json.from_json(@json.parse(response_body)) catch {
            error =>
              Err(
                ExtensionRequestError(
                  status=200,
                  code="invalid_extension_response",
                  detail=error.to_string(),
                ),
              )
          } noraise {
            value => Ok(value)
          }
        } else {
          Err(ExtensionRequestError(status~, code~, detail~))
        }
        scheduler.add(msg(result))
      },
      failed=detail => {
        scheduler.add(
          msg(
            Err(
              ExtensionRequestError(
                status=0,
                code="extension_bridge_error",
                detail~,
              ),
            ),
          ),
        )
      },
    )
  })
}

///|
extern "js" fn send_extension_rpc(
  operation : String,
  args_json : String,
  generation : Int,
  completed~ : (Bool, Int, String, String, String) -> Unit,
  failed~ : (String) -> Unit,
) =
  #| (operation, argsJson, generation, completed, failed) => {
  #|   const host = globalThis.__MOONDIFF_EXTENSION_HOST__;
  #|   if (!host?.request) {
  #|     failed("Commenting is only available in the Moondiff extension.");
  #|     return;
  #|   }
  #|   let args;
  #|   try { args = JSON.parse(argsJson); } catch (error) {
  #|     failed(error?.message || String(error));
  #|     return;
  #|   }
  #|   host.request(operation, args, { generation })
  #|     .then((value) => completed(true, 200, "", "", JSON.stringify(value)))
  #|     .catch((error) => completed(
  #|       false,
  #|       Number.isInteger(error?.status) ? error.status : 0,
  #|       typeof error?.code === "string" ? error.code : "extension_error",
  #|       error?.message || String(error),
  #|       "",
  #|     ));
  #| }

///|
fn auth_status_request(emit : @rabbita.Emit[Msg]) -> @rabbita.Cmd {
  extension_rpc_json("auth.status", "{}", 0, result => {
    emit(AuthStatusLoaded(result))
  })
}

///|
fn auth_device_start_request(emit : @rabbita.Emit[Msg]) -> @rabbita.Cmd {
  extension_rpc_json("auth.device.start", "{}", 0, result => {
    emit(DeviceAuthorizationStarted(result))
  })
}

///|
fn auth_device_poll_request(
  flow_id : String,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  extension_rpc_request("auth.device.poll", DeviceFlowArgs::{ flow_id, }, 0, result => {
    emit(DeviceAuthorizationPolled(flow_id, result))
  })
}

///|
fn auth_device_cancel_request(
  flow_id : String,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  extension_rpc_request("auth.device.cancel", DeviceFlowArgs::{ flow_id, }, 0, result => {
    emit(DeviceAuthorizationCancelled(flow_id, result))
  })
}

///|
fn schedule_device_poll(
  flow_id : String,
  poll_after : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  let seconds = if poll_after < 0 {
    0
  } else if poll_after > 3_600 {
    3_600
  } else {
    poll_after
  }
  @cmd.delay(emit(PollDeviceAuthorization(flow_id)), seconds * 1_000)
}

///|
fn auth_logout_request(emit : @rabbita.Emit[Msg]) -> @rabbita.Cmd {
  extension_rpc_json("auth.logout", "{}", 0, result => {
    emit(AuthLogoutFinished(result))
  })
}

///|
fn comment_list_args(reference : CommitRef) -> CommentListArgs {
  let (kind, number, sha) = match reference.target {
    PullRequest(number) => ("pull", Some(number), None)
    Commit(sha) => ("commit", None, Some(sha))
    PullCommit(number, sha) => ("pull_commit", Some(number), Some(sha))
  }
  { owner: reference.owner, repo: reference.repo, kind, number, sha }
}

///|
fn comments_request(
  reference : CommitRef,
  generation : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  extension_rpc_request(
    "github.comments.list",
    comment_list_args(reference),
    generation,
    result => emit(CommentsLoaded(generation, result)),
  )
}

///|
fn comment_head_request(
  reference : CommitRef,
  number : String,
  anchor : ReviewAnchor,
  generation : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  gateway_json_request(
    "github.pull.get",
    reference_repository(reference),
    number,
    "",
    0,
    generation,
    result => emit(CommentHeadChecked(generation, anchor, result)),
  )
}

///|
fn create_issue_comment_request(
  reference : CommitRef,
  number : String,
  body : String,
  generation : Int,
  emit : @rabbita.Emit[Msg],
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
    result => emit(IssueCommentCreated(generation, result)),
  )
}

///|
fn create_review_comment_request(
  reference : CommitRef,
  number : String,
  commit_id : String,
  anchor : ReviewAnchor,
  body : String,
  generation : Int,
  emit : @rabbita.Emit[Msg],
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
    result => emit(ReviewCommentCreated(generation, result)),
  )
}

///|
fn create_commit_comment_request(
  reference : CommitRef,
  sha : String,
  anchor : ReviewAnchor,
  body : String,
  generation : Int,
  emit : @rabbita.Emit[Msg],
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
    result => emit(CommitCommentCreated(generation, result)),
  )
}

///|
fn create_review_reply_request(
  reference : CommitRef,
  number : String,
  comment_id : Int64,
  body : String,
  generation : Int,
  emit : @rabbita.Emit[Msg],
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
    result => emit(ReviewReplyCreated(generation, result)),
  )
}

///|
fn notify_github_page_command() -> @rabbita.Cmd {
  @cmd.custom_cmd(_scheduler => notify_github_page())
}

///|
extern "js" fn notify_github_page() -> Unit =
  #| () => globalThis.__MOONDIFF_EXTENSION_HOST__?.notifyCommentsChanged?.()

///|
fn author_label(user : ApiCommentUser?) -> String {
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
priv struct ReviewThread {
  root : ApiReviewComment
  replies : Array[ApiReviewComment]
  file_index : Int?
  outdated : Bool
}

///|
fn review_threads(
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
priv struct CommitDiscussion {
  comment : ApiCommitComment
  file_index : Int?
  outdated : Bool
}

///|
fn commit_discussions(
  view : ChangeView,
  comments : ArrayView[ApiCommitComment],
) -> Array[CommitDiscussion] {
  comments.map(comment => {
    let file_index = if comment.path is Some(path) {
      find_file_index(view, path)
    } else {
      None
    }
    { comment, file_index, outdated: commit_comment_outdated(view, comment) }
  })
}
