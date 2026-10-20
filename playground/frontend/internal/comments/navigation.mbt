///|
// In-memory route state contains no request, renderer, or editor node.
pub struct NavigationReview {
  priv draft : DraftData?
  priv receipts : ApiCommentBundle
  priv pending : Array[PendingReviewReceipt]
  priv deleted : Array[CommentId]
} derive(Eq)

///|
pub fn Session::export_navigation(self : Session) -> NavigationReview {
  {
    draft: match self.editor {
      Editing(draft) => Some(draft)
      _ => None
    },
    receipts: copy_bundle(self.receipts),
    pending: self.pending_review_receipts.copy(),
    deleted: self.deleted.copy(),
  }
}

///|
pub fn Session::blocks_navigation(self : Session) -> Bool {
  (self.submission() is Some(phase) && !(phase is SyncingReview(_))) ||
  self.deletion is Some(Deleting(_))
}

///|
fn restore_navigation(
  session : Session,
  saved : NavigationReview,
  paths : Array[String],
) -> Session {
  let sequence = session.draft_sequence + 1
  let editor = match saved.draft {
    None => Empty
    Some(draft) => {
      let kind = match draft.kind {
        InlineDraft(_, anchor) =>
          InlineDraft(
            paths.search_by(path => path == anchor.path).unwrap_or(-1),
            anchor,
          )
        other => other
      }
      Editing({
        ..draft,
        id: { generation: session.context.generation, sequence, },
        kind,
      })
    }
  }
  let restored = {
    ..session,
    editor,
    draft_sequence: sequence,
    receipts: copy_bundle(saved.receipts),
    pending_review_receipts: saved.pending.map(receipt => {
      ..receipt,
      generation: session.context.generation,
      status: ReceiptWaiting,
    }),
    deleted: saved.deleted.copy(),
  }
  // Reuse the snapshot guard after restoring an old line anchor.
  update(restored, ContextChanged(session.context)).0
}
