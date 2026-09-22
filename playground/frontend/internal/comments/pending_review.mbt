///|
/// A published review keeps its editor in Posting until a verified GitHub list
/// observes the comment ID. Receipts track synchronization independently from
/// the frozen body in the editor.
pub(all) enum PendingReviewStatus {
  ReceiptSyncing
  ReceiptWaiting
  ReceiptSyncFailed
  ReceiptPrChanged
} derive(Eq)

///|
pub(all) struct PendingReviewReceipt {
  id : Int64
  url : String
  kind : DraftKind
  path : String
  generation : Int
  status : PendingReviewStatus
} derive(Eq)

///|
pub fn PendingReviewReceipt::key(self : PendingReviewReceipt) -> String {
  "\{self.generation}:\{ReviewComment(self.id).key()}"
}

///|
fn pending_review_status(session : Session) -> PendingReviewStatus {
  if session.snapshot_stale {
    ReceiptPrChanged
  } else {
    ReceiptSyncing
  }
}

///|
fn pending_review_receipts_with_status(
  session : Session,
  status : PendingReviewStatus,
) -> Array[PendingReviewReceipt] {
  session.pending_review_receipts.map(receipt => { ..receipt, status, })
}

///|
fn pending_review_receipts_for_refresh(
  session : Session,
) -> Array[PendingReviewReceipt] {
  pending_review_receipts_with_status(session, pending_review_status(session))
}

///|
fn recover_pending_review_receipts(
  session : Session,
) -> Array[PendingReviewReceipt] {
  session.pending_review_receipts.map(receipt => {
    if receipt.status is ReceiptSyncing {
      {
        ..receipt,
        status: if session.snapshot_stale {
          ReceiptPrChanged
        } else {
          ReceiptSyncFailed
        },
      }
    } else {
      receipt
    }
  })
}

///|
fn reconcile_pending_review_receipts(
  session : Session,
  bundle : ApiCommentBundle,
) -> Array[PendingReviewReceipt] {
  let remaining : Array[PendingReviewReceipt] = []
  for receipt in session.pending_review_receipts {
    if !bundle.review_comments.any(comment => comment.id == receipt.id) {
      remaining.push({
        ..receipt,
        status: if session.snapshot_stale {
          ReceiptPrChanged
        } else {
          ReceiptWaiting
        },
      })
    }
  }
  remaining
}

///|
fn review_receipt(
  model : Model,
  comment : ApiReviewComment,
) -> PendingReviewReceipt? {
  guard model.review.draft() is Some(draft) else { return None }
  let path = match draft.kind {
    InlineDraft(_, anchor) => anchor.path
    ReplyDraft(_) => model.review.draft_target_path().unwrap_or(comment.path)
    OverallDraft => return None
  }
  Some({
    id: comment.id,
    url: comment.html_url,
    kind: draft.kind,
    path,
    generation: model.generation,
    status: pending_review_status(model.review),
  })
}
