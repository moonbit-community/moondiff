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
