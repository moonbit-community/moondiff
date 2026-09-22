///|
priv struct DraftData {
  snapshot : Snapshot?
  id : DraftId
  kind : DraftKind
  target_path : String?
  body : String
  error : String?
} derive(Eq)

///|
priv struct Operation {
  generation : Int
  id : Int
  phase : SubmissionPhase
  body : String
} derive(Eq)

///|
priv enum EditorState {
  Empty
  Editing(DraftData)
  Submitting(DraftData, Operation)
} derive(Eq)

///|
pub fn Session::draft(self : Session) -> CommentDraft? {
  let (draft, submitting) = match self.editor {
    Empty => return None
    Editing(draft) => (draft, false)
    Submitting(draft, _) => (draft, true)
  }
  Some({
    snapshot: draft.snapshot,
    id: draft.id,
    kind: draft.kind,
    body: draft.body,
    error: match self.submission() {
      Some(SyncingReview(id)) =>
        self.pending_review_receipts
        .iter()
        .find_first(receipt => receipt.id == id)
        .map(receipt => {
          match receipt.status {
            ReceiptSyncing => None
            ReceiptWaiting =>
              Some("Waiting for GitHub to sync this comment. Refresh to retry.")
            ReceiptSyncFailed =>
              Some("Comment published, but syncing failed. Refresh to retry.")
            ReceiptPrChanged =>
              Some("Comment published. PR updated. Load latest to see it.")
          }
        })
        .unwrap_or(None)
      _ => draft.error
    },
    submitting,
  })
}

///|
pub fn Session::submission(self : Session) -> SubmissionPhase? {
  match self.editor {
    Submitting(_, operation) => Some(operation.phase)
    _ => None
  }
}

///|
fn Session::draft_target_path(self : Session) -> String? {
  match self.editor {
    Editing(draft) | Submitting(draft, _) => draft.target_path
    Empty => None
  }
}
