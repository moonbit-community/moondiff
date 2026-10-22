///|
fn copy_bundle(bundle : ApiCommentBundle) -> ApiCommentBundle {
  {
    issue_comments: bundle.issue_comments.copy(),
    review_comments: bundle.review_comments.copy(),
    commit_comments: bundle.commit_comments.copy(),
  }
}

///|
pub fn Session::comments(self : Session) -> CommentsStatus {
  match self.comments {
    CommentsReady(bundle) => CommentsReady(copy_bundle(bundle))
    other => other
  }
}

///|
pub fn Session::generation(self : Session) -> Int32 {
  self.context.generation
}
