///|
test "navigation restores body and original snapshot with a new generation and path index" {
  let original = session_fixture()
  let anchor = ReviewAnchor::{
    path: "src/test.mbt",
    side: Right,
    line: 1,
    position: Some(1),
  }
  let edited = update(
      update(original, OpenInlineDraft(0, anchor)).0,
      DraftBodyChanged("Keep text"),
    ).0
  let saved = edited.export_navigation()
  let context = { ..original.context, generation: 12, }
  let fresh = update(Session::new(enabled=true), ContextChanged(context)).0
  let restored = update(
      fresh,
      RestoreNavigation(saved, ["other.mbt", "src/test.mbt"]),
    ).0
  guard restored.draft() is Some(draft) else { fail("draft") }
  assert_eq(draft.id.generation, 12)
  assert_eq(draft.body, "Keep text")
  assert_true(draft.kind is InlineDraft(1, _))
  assert_true(draft.snapshot == edited.draft().unwrap().snapshot)
  assert_true(!restored.blocks_navigation())
}

///|
test "published review receipts restore without an editor or a second submission" {
  let (published, _, _) = publish_inline_receipt(
    pending_review_session(pending_empty_bundle()),
    72,
    "Published exactly once",
  )
  assert_true(published.submission() is Some(SyncingReview(_)))
  assert_false(published.blocks_navigation())
  let saved = published.export_navigation()
  let fresh = update(
      Session::new(enabled=true),
      ContextChanged({ ..published.context, generation: 18, }),
    ).0
  let restored = update(fresh, RestoreNavigation(saved, ["src/main.mbt"])).0
  assert_true(restored.draft() is None)
  assert_true(restored.submission() is None)
  assert_eq(restored.pending_review_receipts.length(), 1)
  assert_eq(restored.pending_review_receipts[0].generation, 18)
  let (ignored, effects) = update(restored, SubmitDraft)
  assert_true(ignored == restored)
  assert_true(effects.is_empty())
}
