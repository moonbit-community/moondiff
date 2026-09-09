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
pub fn Session::deleted(self : Session) -> Array[CommentId] {
  self.deleted.copy()
}

///|
pub fn Session::refresh(self : Session) -> CommentRefresh {
  match self.refresh {
    RefreshValidation(pull, bundle) =>
      RefreshValidation(pull, copy_bundle(bundle))
    other => other
  }
}

///|
pub fn Session::generation(self : Session) -> Int {
  self.context.generation
}

///|
pub fn Session::comment_key(self : Session, id : CommentId) -> String {
  "\{self.context.generation}:\{id.key()}"
}
