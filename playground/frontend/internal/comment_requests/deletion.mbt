///|
pub fn delete_comment_request(
  reference : CommitRef,
  id : CommentId,
  generation : Int,
  emit : @rabbita.Emit[Result[DeleteResult, Error]],
) -> @rabbita.Cmd {
  let comment_id = match id {
    IssueComment(id) | ReviewComment(id) | CommitComment(id) => id
  }
  let args : @protocol.CommentDelete = {
    owner: reference.owner,
    repo: reference.repo,
    comment_id,
  }
  match id {
    IssueComment(_) =>
      @github_client.delete_issue_comment(args, generation, emit)
    ReviewComment(_) =>
      @github_client.delete_review_comment(args, generation, emit)
    CommitComment(_) =>
      @github_client.delete_commit_comment(args, generation, emit)
  }
}
