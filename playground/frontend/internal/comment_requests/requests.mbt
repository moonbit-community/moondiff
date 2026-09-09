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
