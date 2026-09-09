///|
pub(all) enum Action {
  OpenDraft(DraftKind)
  Submit
  Delete(CommentId)
  LoadSnapshot
} derive(Eq)

///|
pub(all) enum Permission {
  Allowed
  Denied(String)
} derive(Eq)

///|
pub fn Permission::allowed(self : Permission) -> Bool {
  self is Allowed
}

///|
pub fn same_draft_target(left : DraftKind, right : DraftKind) -> Bool {
  match (left, right) {
    (InlineDraft(_, a), InlineDraft(_, b)) =>
      a.path == b.path && a.side == b.side && a.line == b.line
    _ => left == right
  }
}

///|
pub fn permission(review : Session, action : Action) -> Permission {
  match action {
    LoadSnapshot => {
      if !review.snapshot_stale {
        return Denied("The snapshot is current.")
      }
      if review.draft() is Some(_) || review.deletion is Some(Deleting(_)) {
        return Denied(
          "Finish the current draft or deletion before loading the latest snapshot.",
        )
      }
      Allowed
    }
    Delete(id) => {
      if !can_delete_comment(review, id) {
        return Denied("Only the author can delete this comment.")
      }
      if review.deletion is Some(Deleting(_)) {
        return Denied("A deletion is in progress.")
      }
      if draft_blocks_deletion(review, id) {
        return Denied(
          "Send or cancel the reply draft before deleting this comment.",
        )
      }
      Allowed
    }
    OpenDraft(kind) => {
      if !review_can_comment(review) {
        return Denied("Sign in with GitHub before posting a comment.")
      }
      if review.submission() is Some(_) {
        return Denied("A comment is being posted.")
      }
      if review.draft() is Some(draft) && !same_draft_target(draft.kind, kind) {
        return Denied(
          "Send or cancel your current draft before starting another comment.",
        )
      }
      target_permission(review, kind)
    }
    Submit => {
      if !review_can_comment(review) {
        return Denied("Sign in with GitHub before posting a comment.")
      }
      if review.submission() is Some(_) {
        return Denied("A comment is being posted.")
      }
      guard review.draft() is Some(draft) else {
        return Denied("Start a draft first.")
      }
      if draft.kind is InlineDraft(_, _) &&
        draft.snapshot is Some(snapshot) &&
        review.context.snapshot != Some(snapshot) {
        return Denied(
          "PR updated. Copy or cancel your draft before loading the latest snapshot.",
        )
      }
      if target_permission(review, draft.kind) is Denied(message) {
        return Denied(message)
      }
      if draft.body.trim().is_empty() {
        return Denied("Enter a comment before posting.")
      }
      Allowed
    }
  }
}

///|
fn target_permission(review : Session, kind : DraftKind) -> Permission {
  if kind is OverallDraft || kind is ReplyDraft(_) {
    if !session_is_pull(review) {
      return Denied("This operation requires a pull request.")
    }
  }
  if kind is InlineDraft(_, _) && review.context.snapshot is None {
    return Denied("Load the diff before commenting on a line.")
  }
  match kind {
    InlineDraft(_, _) if review.snapshot_stale =>
      Denied(
        "PR updated. Copy or cancel your draft before loading the latest snapshot.",
      )
    ReplyDraft(id) if !valid_reply_target(review, id) =>
      Denied("The root comment is unavailable. Copy or cancel your draft.")
    _ => Allowed
  }
}

///|
fn session_is_pull(review : Session) -> Bool {
  review.context.route is Some({ target: PullRequest(_), .. })
}
