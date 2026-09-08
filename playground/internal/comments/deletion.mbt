///|
pub(all) enum CommentId {
  IssueComment(Int64)
  ReviewComment(Int64)
  CommitComment(Int64)
} derive(Eq)

///|
pub(all) enum CommentDeletion {
  ConfirmDelete(CommentId)
  Deleting(CommentId)
  DeleteFailed(CommentId, String)
} derive(Eq)

///|
pub(all) struct DeleteResult {
  deleted : Bool
} derive(FromJson)

///|
pub fn without_deleted(
  bundle : ApiCommentBundle,
  deleted : Array[CommentId],
) -> ApiCommentBundle {
  {
    issue_comments: bundle.issue_comments.filter(c => {
      !deleted.contains(IssueComment(c.id))
    }),
    review_comments: bundle.review_comments.filter(c => {
      !deleted.contains(ReviewComment(c.id))
    }),
    commit_comments: bundle.commit_comments.filter(c => {
      !deleted.contains(CommitComment(c.id))
    }),
  }
}

///|
pub fn can_delete_comment(review : Session, id : CommentId) -> Bool {
  guard review.can_comment &&
    review.login is Some(login) &&
    !login.is_empty() &&
    review.comments is CommentsReady(bundle) else {
    return false
  }
  match id {
    IssueComment(id) =>
      bundle.issue_comments.any(c => {
        c.id == id && c.user.map(u => u.login) == Some(login)
      })
    ReviewComment(id) =>
      bundle.review_comments.any(c => {
        c.id == id && c.user.map(u => u.login) == Some(login)
      })
    CommitComment(id) =>
      bundle.commit_comments.any(c => {
        c.id == id && c.user.map(u => u.login) == Some(login)
      })
  }
}

///|
/// Only a live top-level review comment can receive replies.
pub fn valid_reply_target(review : Session, id : Int64) -> Bool {
  guard review.comments is CommentsReady(bundle) else { return false }
  !review.deleted.contains(ReviewComment(id)) &&
  review.deletion != Some(Deleting(ReviewComment(id))) &&
  bundle.review_comments.any(c => c.id == id && c.in_reply_to_id is None)
}

///|
/// Even an empty or submitting reply draft protects its target from deletion.
pub fn draft_blocks_deletion(review : Session, id : CommentId) -> Bool {
  review.draft() is Some({ kind: ReplyDraft(target), .. }) &&
  id == ReviewComment(target)
}

///|
pub fn CommentId::key(self : CommentId) -> String {
  match self {
    IssueComment(id) => "issue:\{id}"
    ReviewComment(id) => "review:\{id}"
    CommitComment(id) => "commit:\{id}"
  }
}
