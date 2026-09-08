///|
fn comments_request(reference : CommitRef, generation : Int) -> Effects {
  [Dispatch(BeginCommentsRefresh(generation, reference))]
}

///|
fn comment_head_request(
  reference : CommitRef,
  number : String,
  anchor : ReviewAnchor,
  generation : Int,
  submission_id : Int,
) -> Effects {
  raw_comment_head_request(reference, number, generation, result => {
    CommentHeadChecked(generation, submission_id, anchor, result)
  })
}

///|
fn create_issue_comment_request(
  reference : CommitRef,
  number : String,
  body : String,
  generation : Int,
  submission_id : Int,
) -> Effects {
  raw_create_issue_comment_request(reference, number, body, generation, result => {
    IssueCommentCreated(generation, submission_id, result)
  })
}

///|
fn create_review_comment_request(
  reference : CommitRef,
  number : String,
  commit_id : String,
  anchor : ReviewAnchor,
  body : String,
  generation : Int,
  submission_id : Int,
) -> Effects {
  raw_create_review_comment_request(
    reference,
    number,
    commit_id,
    anchor,
    body,
    generation,
    result => ReviewCommentCreated(generation, submission_id, result),
  )
}

///|
fn create_commit_comment_request(
  reference : CommitRef,
  sha : String,
  anchor : ReviewAnchor,
  body : String,
  generation : Int,
  submission_id : Int,
) -> Effects {
  raw_create_commit_comment_request(reference, sha, anchor, body, generation, result => {
    CommitCommentCreated(generation, submission_id, result)
  })
}

///|
fn create_review_reply_request(
  reference : CommitRef,
  number : String,
  comment_id : Int64,
  body : String,
  generation : Int,
  submission_id : Int,
) -> Effects {
  raw_create_review_reply_request(
    reference,
    number,
    comment_id,
    body,
    generation,
    result => ReviewReplyCreated(generation, submission_id, result),
  )
}
