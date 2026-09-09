///|
pub(all) enum Effect {
  CommentsRequest(CommitRef, Int, (Result[ApiCommentBundle, Failure]) -> Event)
  CommentHeadRequest(
    CommitRef,
    String,
    Int,
    (Result[ApiPull, Failure]) -> Event
  )
  CreateIssueCommentRequest(
    CommitRef,
    String,
    String,
    Int,
    (Result[ApiIssueComment, Failure]) -> Event
  )
  CreateReviewCommentRequest(
    CommitRef,
    String,
    String,
    ReviewAnchor,
    String,
    Int,
    (Result[ApiReviewComment, Failure]) -> Event
  )
  CreateCommitCommentRequest(
    CommitRef,
    String,
    ReviewAnchor,
    String,
    Int,
    (Result[ApiCommitComment, Failure]) -> Event
  )
  CreateReviewReplyRequest(
    CommitRef,
    String,
    Int64,
    String,
    Int,
    (Result[ApiReviewComment, Failure]) -> Event
  )
  DeleteCommentRequest(
    CommitRef,
    CommentId,
    Int,
    (Result[DeleteResult, Failure]) -> Event
  )
  Notify
  Dispatch(Event)
}

///|
fn raw_comments_request(
  reference : CommitRef,
  generation : Int,
  respond : (Result[ApiCommentBundle, Failure]) -> Event,
) -> Effects {
  [CommentsRequest(reference, generation, respond)]
}

///|
fn raw_comment_head_request(
  reference : CommitRef,
  number : String,
  generation : Int,
  respond : (Result[ApiPull, Failure]) -> Event,
) -> Effects {
  [CommentHeadRequest(reference, number, generation, respond)]
}

///|
fn raw_create_issue_comment_request(
  reference : CommitRef,
  number : String,
  body : String,
  generation : Int,
  respond : (Result[ApiIssueComment, Failure]) -> Event,
) -> Effects {
  [CreateIssueCommentRequest(reference, number, body, generation, respond)]
}

///|
fn raw_create_review_comment_request(
  reference : CommitRef,
  number : String,
  commit_id : String,
  anchor : ReviewAnchor,
  body : String,
  generation : Int,
  respond : (Result[ApiReviewComment, Failure]) -> Event,
) -> Effects {
  [
    CreateReviewCommentRequest(
      reference, number, commit_id, anchor, body, generation, respond,
    ),
  ]
}

///|
fn raw_create_commit_comment_request(
  reference : CommitRef,
  sha : String,
  anchor : ReviewAnchor,
  body : String,
  generation : Int,
  respond : (Result[ApiCommitComment, Failure]) -> Event,
) -> Effects {
  [
    CreateCommitCommentRequest(
      reference, sha, anchor, body, generation, respond,
    ),
  ]
}

///|
fn raw_create_review_reply_request(
  reference : CommitRef,
  number : String,
  comment_id : Int64,
  body : String,
  generation : Int,
  respond : (Result[ApiReviewComment, Failure]) -> Event,
) -> Effects {
  [
    CreateReviewReplyRequest(
      reference, number, comment_id, body, generation, respond,
    ),
  ]
}

///|
fn delete_comment_request(
  reference : CommitRef,
  id : CommentId,
  generation : Int,
  respond : (Result[DeleteResult, Failure]) -> Event,
) -> Effects {
  [DeleteCommentRequest(reference, id, generation, respond)]
}

///|
fn notify_github_page_command() -> Effects {
  [Notify]
}

///|
type Effects = Array[Effect]

///|
fn batch(groups : Array[Effects]) -> Effects {
  let effects : Effects = []
  for group in groups {
    effects.push_iter(group.iter())
  }
  effects
}
