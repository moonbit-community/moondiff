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
priv struct DeleteArgs {
  owner : String
  repo : String
  comment_id : Int64
} derive(ToJson)

///|
pub fn delete_comment_request(
  reference : CommitRef,
  id : CommentId,
  generation : Int,
  emit : @rabbita.Emit[Result[DeleteResult, Error]],
) -> @rabbita.Cmd {
  let (operation, comment_id) = match id {
    IssueComment(id) => ("github.issue.comment.delete", id)
    ReviewComment(id) => ("github.review.comment.delete", id)
    CommitComment(id) => ("github.commit.comment.delete", id)
  }
  extension_rpc_request(
    operation,
    DeleteArgs::{ owner: reference.owner, repo: reference.repo, comment_id, },
    generation,
    emit,
  )
}

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
pub fn can_delete_comment(review : ReviewState, id : CommentId) -> Bool {
  guard review.auth is SignedIn(login=Some(login), ..) &&
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
