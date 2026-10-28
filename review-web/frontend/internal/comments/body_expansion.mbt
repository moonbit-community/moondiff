///|
fn bundle_contains(bundle : ApiCommentBundle, id : CommentId) -> Bool {
  match id {
    IssueComment(id) => bundle.issue_comments.any(c => c.id == id)
    ReviewComment(id) => bundle.review_comments.any(c => c.id == id)
    CommitComment(id) => bundle.commit_comments.any(c => c.id == id)
  }
}
