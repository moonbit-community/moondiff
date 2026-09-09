///|
fn comment_list_args(reference : CommitRef) -> @protocol.CommentsList {
  let target = match reference.target {
    PullRequest(number) => @protocol.CommentTarget::Pull(number~)
    Commit(sha) => @protocol.CommentTarget::Commit(sha~)
    PullCommit(number, sha) =>
      @protocol.CommentTarget::PullCommit(number~, sha~)
  }
  { owner: reference.owner, repo: reference.repo, target, }
}

///|
pub fn comments_request(
  reference : CommitRef,
  generation : Int,
  emit : @rabbita.Emit[Result[ApiCommentBundle, Error]],
) -> @rabbita.Cmd {
  @github_client.list_comments(comment_list_args(reference), generation, emit)
}

///|
pub fn comment_head_request(
  reference : CommitRef,
  number : String,
  generation : Int,
  emit : @rabbita.Emit[Result[ApiPull, Error]],
) -> @rabbita.Cmd {
  @github_client.get_pull(
    {
      owner: reference_repository(reference).owner,
      repo: reference_repository(reference).repo,
      number,
    },
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
  @github_client.create_issue_comment(
    @protocol.IssueCommentCreate::{
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
  @github_client.create_review_comment(
    @protocol.ReviewCommentCreate::{
      owner: reference.owner,
      repo: reference.repo,
      number,
      commit_id,
      path: anchor.path,
      line: anchor.line,
      side: if anchor.side is Left {
        @protocol.CommentSide::Left
      } else {
        @protocol.CommentSide::Right
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
  @github_client.create_commit_comment(
    @protocol.CommitCommentCreate::{
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
  @github_client.create_review_reply(
    @protocol.ReviewReplyCreate::{
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
