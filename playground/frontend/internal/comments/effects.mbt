///|
pub(all) enum Effect {
  CommentsRequest(
    CommitRef,
    Int32,
    (Result[ApiCommentBundle, Failure]) -> Event
  )
  CommentHeadRequest(
    CommitRef,
    String,
    Int32,
    (Result[ApiPull, Failure]) -> Event
  )
  CreateIssueCommentRequest(
    CommitRef,
    String,
    String,
    Int32,
    (Result[ApiIssueComment, Failure]) -> Event
  )
  CreateReviewCommentRequest(
    CommitRef,
    String,
    String,
    ReviewAnchor,
    String,
    Int32,
    (Result[ApiReviewComment, Failure]) -> Event
  )
  CreateCommitCommentRequest(
    CommitRef,
    String,
    ReviewAnchor,
    String,
    Int32,
    (Result[ApiCommitComment, Failure]) -> Event
  )
  CreateReviewReplyRequest(
    CommitRef,
    String,
    Int64,
    String,
    Int32,
    (Result[ApiReviewComment, Failure]) -> Event
  )
  DeleteCommentRequest(
    CommitRef,
    CommentId,
    Int32,
    (Result[DeleteResult, Failure]) -> Event
  )
  Dispatch(Event)
}

///|
fn raw_comments_request(
  reference : CommitRef,
  generation : Int32,
  respond : (Result[ApiCommentBundle, Failure]) -> Event,
) -> Effects {
  [CommentsRequest(reference, generation, respond)]
}

///|
fn raw_comment_head_request(
  reference : CommitRef,
  number : String,
  generation : Int32,
  respond : (Result[ApiPull, Failure]) -> Event,
) -> Effects {
  [CommentHeadRequest(reference, number, generation, respond)]
}

///|
fn raw_create_issue_comment_request(
  reference : CommitRef,
  number : String,
  body : String,
  generation : Int32,
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
  generation : Int32,
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
  generation : Int32,
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
  generation : Int32,
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
  generation : Int32,
  respond : (Result[DeleteResult, Failure]) -> Event,
) -> Effects {
  [DeleteCommentRequest(reference, id, generation, respond)]
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
