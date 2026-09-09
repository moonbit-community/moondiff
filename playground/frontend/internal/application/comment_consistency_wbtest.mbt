///|
fn consistency_pending(
  model : Model,
  id : Int,
  refresh : @comments.CommentRefresh,
) -> Model {
  let mut review = model.review
  while review.refresh_id < id {
    review = fixture_event(review, RefreshComments)
  }
  match refresh {
    RefreshMetadata => ()
    RefreshList(Some(pull)) =>
      review = fixture_event(review, CommentsMetadataLoaded(5, id, Ok(pull)))
    RefreshValidation(pull, bundle) => {
      review = fixture_event(review, CommentsMetadataLoaded(5, id, Ok(pull)))
      review = fixture_event(review, CommentsLoaded(5, id, Ok(bundle)))
    }
    RefreshIdle =>
      review = fixture_event(
        review,
        CommentsMetadataLoaded(
          5,
          id,
          Err({ message: "cancelled", code: None, }),
        ),
      )
    _ => ()
  }
  with_review(model, review)
}

///|
test "PR refresh rejects metadata changes before and during list retrieval" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let original = review_reply_test_model()
  let (drafting, _) = update_review(original, OpenOverallDraft, emit)
  let (model, _) = update_review(drafting, DraftBodyChanged("preserved"), emit)
  let pull = review_test_pull()
  let changes = [
    { ..pull, head: { ..pull.head, sha: "new head", }, },
    { ..pull, base: { ..pull.base, sha: "new base", }, },
    {
      ..pull,
      head: { ..pull.head, repo: Some({ full_name: "other/repo", }), },
    },
    { ..pull, base: { ..pull.base, repo: None, }, },
    { ..pull, changed_files: 2, },
  ]
  guard model.review.comments() is CommentsReady(bundle) else {
    fail("fixture comments")
  }
  for changed in changes {
    for during in [false, true] {
      let pending = consistency_pending(
        model,
        3,
        if during {
          RefreshValidation(pull, { ..bundle, review_comments: [], })
        } else {
          RefreshMetadata
        },
      )
      let message : ReviewMsg = if during {
        CommentsValidated(5, 3, Ok(changed))
      } else {
        CommentsMetadataLoaded(5, 3, Ok(changed))
      }
      let (stale, _) = update_review(pending, message, emit)
      assert_true(stale.review.snapshot_stale)
      assert_true(stale.review.refresh() is RefreshIdle)
      assert_true(stale.review.comments() == model.review.comments())
      assert_true(stale.review.draft() == model.review.draft())
      assert_true(stale.phase == model.phase)
      assert_eq(stale.generation, model.generation)
    }
  }
}

///|
test "PR list waits for final metadata and accepts old commit anchors" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let model = review_reply_test_model()
  let pull = review_test_pull()
  guard model.review.comments() is CommentsReady(bundle) else {
    fail("fixture comments")
  }
  let comment = {
    ..bundle.review_comments[0],
    commit_id: "older commit",
    body: "still current",
  }
  let updated = { ..bundle, review_comments: [comment], }
  let pending = consistency_pending(model, 7, RefreshMetadata)
  let (before, _) = update_review(
    pending,
    CommentsMetadataLoaded(5, 7, Ok(pull)),
    emit,
  )
  assert_true(before.review.refresh() is RefreshList(Some(_)))
  let (listed, _) = update_review(
    before,
    CommentsLoaded(5, 7, Ok(updated)),
    emit,
  )
  assert_true(listed.review.comments() == model.review.comments())
  assert_true(listed.review.refresh() is RefreshValidation(_, _))
  let (verified, _) = update_review(
    listed,
    CommentsValidated(5, 7, Ok(pull)),
    emit,
  )
  assert_true(verified.review.comments() == CommentsReady(updated))
  let threads = @comments.review_threads(
    review_test_view(),
    updated.review_comments,
  )
  assert_false(threads[0].outdated)
  let (duplicate, _) = update_review(
    verified,
    CommentsValidated(5, 7, Ok(pull)),
    emit,
  )
  assert_true(duplicate == verified)
}

///|
test "refresh sequence generation and stage reject late lists and errors" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let model = review_reply_test_model()
  let pull = review_test_pull()
  guard model.review.comments() is CommentsReady(bundle) else {
    fail("fixture comments")
  }
  let stages : Array[@comments.CommentRefresh] = [
    RefreshMetadata,
    RefreshList(Some(pull)),
    RefreshValidation(pull, bundle),
    RefreshIdle,
  ]
  for refresh in stages {
    let pending = consistency_pending(model, 9, refresh)
    for generation in [4, 5] {
      let id = if generation == 5 { 8 } else { 9 }
      let messages : Array[ReviewMsg] = [
        CommentsMetadataLoaded(generation, id, Ok(pull)),
        CommentsMetadataLoaded(
          generation,
          id,
          Err(authentication_required_error()),
        ),
        CommentsLoaded(generation, id, Ok(bundle)),
        CommentsLoaded(generation, id, Err(authentication_required_error())),
        CommentsValidated(generation, id, Ok(pull)),
        CommentsValidated(generation, id, Err(authentication_required_error())),
      ]
      for message in messages {
        let (ignored, _) = update_review(pending, message, emit)
        assert_true(ignored == pending)
      }
    }
  }
  let idle = consistency_pending(model, 9, RefreshIdle)
  let (ignored, _) = update_review(idle, CommentsLoaded(5, 9, Ok(bundle)), emit)
  assert_true(ignored == idle)
}

///|
test "network failures at all refresh stages preserve verified comments and draft" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (model, _) = update_review(
    review_reply_test_model(),
    OpenReplyDraft(20L),
    emit,
  )
  let pull = review_test_pull()
  guard model.review.comments() is CommentsReady(bundle) else {
    fail("fixture comments")
  }
  let error = GitHubRequestError::GitHubRequestError("offline")
  let stages : Array[(@comments.CommentRefresh, ReviewMsg)] = [
    (RefreshMetadata, CommentsMetadataLoaded(5, 10, Err(error))),
    (RefreshList(Some(pull)), CommentsLoaded(5, 10, Err(error))),
    (RefreshValidation(pull, bundle), CommentsValidated(5, 10, Err(error))),
  ]
  for (stage, message) in stages {
    let (failed, _) = update_review(
      consistency_pending(model, 10, stage),
      message,
      emit,
    )
    assert_true(failed.review.comments() == model.review.comments())
    assert_true(failed.review.draft() == model.review.draft())
    assert_true(failed.auth == model.auth)
    assert_true(failed.review.refresh_error is Some(_))
    assert_true(failed.review.refresh() is RefreshIdle)
    let (recovered, _) = review_test_refresh(failed, bundle, emit)
    assert_true(recovered.review.refresh_error is None)
  }
}

///|
test "all draft entry pairs preserve empty and edited drafts including errors" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let model = review_reply_test_model()
  let anchor = canonical_anchor(
    parse_canonical_patch(
      "src/main.mbt",
      review_test_view().files[0].file.patch,
    ),
    Right,
    2,
  ).unwrap()
  let entries : Array[ReviewMsg] = [
    OpenOverallDraft,
    OpenInlineDraft(0, anchor),
    OpenReplyDraft(20L),
  ]
  for entry in entries {
    let (empty, _) = update_review(model, entry, emit)
    for body in ["", "keep all state"] {
      let editing = update_draft(empty, body~, error=Some("retry error"))
      for other in entries {
        let (again, _) = update_review(editing, other, emit)
        assert_true(again.review.draft() == editing.review.draft())
      }
    }
    let filled = update_draft(empty, body="posting")
    let (pending, _) = update_review(filled, SubmitDraft, emit)
    for other in entries {
      let (blocked, _) = update_review(pending, other, emit)
      assert_true(blocked == pending)
    }
  }
}

///|
test "submission identity and phase protect retries and subsequent drafts" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (empty, _) = update_review(
    review_reply_test_model(),
    OpenOverallDraft,
    emit,
  )
  let filled = update_draft(empty, body="first")
  let (pending, _) = update_review(filled, SubmitDraft, emit)
  let id = pending.review.submission_id
  let (failed, _) = update_review(
    pending,
    IssueCommentCreated(5, id, Err(authentication_required_error())),
    emit,
  )
  assert_eq(failed.review.draft().unwrap().body, "first")
  assert_true(failed.review.submission() is None)
  let restored = with_auth(failed, filled.auth)
  let (retry, _) = update_review(restored, SubmitDraft, emit)
  assert_true(retry.review.submission_id > id)
  let created = ApiIssueComment::{
    id: 90L,
    body: "first",
    html_url: "https://github.com/comment/90",
    created_at: "today",
    user: None,
  }
  for
    message in [
      IssueCommentCreated(5, id, Ok(created)),
      IssueCommentCreated(5, id, Err(authentication_required_error())),
    ] {
    let (ignored, _) = update_review(retry, message, emit)
    assert_true(ignored == retry)
  }
  let (done, _) = update_review(
    retry,
    IssueCommentCreated(5, retry.review.submission_id, Ok(created)),
    emit,
  )
  let (next, _) = update_review(done, OpenReplyDraft(20L), emit)
  for
    message in [
      IssueCommentCreated(5, retry.review.submission_id, Ok(created)),
      IssueCommentCreated(
        5,
        retry.review.submission_id,
        Err(authentication_required_error()),
      ),
    ] {
    let (ignored, _) = update_review(next, message, emit)
    assert_true(ignored == next)
  }
  let anchor = canonical_anchor(
    parse_canonical_patch(
      "src/main.mbt",
      review_test_view().files[0].file.patch,
    ),
    Right,
    2,
  ).unwrap()
  let (line, _) = update_review(
    review_reply_test_model(),
    OpenInlineDraft(0, anchor),
    emit,
  )
  let (checking, _) = update_review(
    update_draft(line, body="line"),
    SubmitDraft,
    emit,
  )
  let msg = CommentHeadChecked(
    5,
    checking.review.submission_id,
    anchor,
    Ok(review_test_pull()),
  )
  let (posting, _) = update_review(checking, msg, emit)
  assert_true(posting.review.submission() == Some(PostingReview))
  let (duplicate, _) = update_review(posting, msg, emit)
  assert_true(duplicate == posting)
  let (wrong_stage, _) = update_review(
    posting,
    IssueCommentCreated(5, posting.review.submission_id, Ok(created)),
    emit,
  )
  assert_true(wrong_stage == posting)
}

///|
test "stale snapshot blocks only line authoring and manual load waits for drafts and writes" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let model = mark_snapshot_stale(review_reply_test_model())
  let anchor = canonical_anchor(
    parse_canonical_patch(
      "src/main.mbt",
      review_test_view().files[0].file.patch,
    ),
    Right,
    2,
  ).unwrap()
  let (blocked, _) = update_review(model, OpenInlineDraft(0, anchor), emit)
  assert_true(blocked.review.draft() is None)
  for entry in [OpenOverallDraft, OpenReplyDraft(20L)] {
    let (drafting, _) = update_review(model, entry, emit)
    let (blocked, _) = update_review(drafting, LoadLatestSnapshot, emit)
    assert_true(blocked == drafting)
    let (posting, _) = update_review(
      update_draft(drafting, body="allowed"),
      SubmitDraft,
      emit,
    )
    assert_true(posting.review.draft().unwrap().submitting)
  }
  let deleting = with_review(
    model,
    review_fixture(model.review, deletion=Some(Deleting(ReviewComment(20L)))),
  )
  let (blocked, _) = update_review(deleting, LoadLatestSnapshot, emit)
  assert_true(blocked == deleting)
  let (loaded, _) = update_review(model, LoadLatestSnapshot, emit)
  assert_eq(loaded.generation, model.generation + 1)
  assert_true(loaded.phase is LoadingPullMetadata(..))
}

///|
test "all four late creation responses preserve a subsequent draft" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (model, _) = update_review(
    review_reply_test_model(),
    OpenOverallDraft,
    emit,
  )
  guard model.review.comments() is CommentsReady(bundle) else {
    fail("fixture comments")
  }
  let issue : ApiIssueComment = {
    id: 90L,
    body: "late",
    html_url: "https://github.com/comment/90",
    created_at: "today",
    user: None,
  }
  let review = bundle.review_comments[0]
  let commit : ApiCommitComment = {
    id: 91L,
    body: "late",
    html_url: "https://github.com/comment/91",
    created_at: "today",
    user: None,
    path: Some("src/main.mbt"),
    position: Some(3),
    line: Some(2),
  }
  let messages : Array[ReviewMsg] = [
    IssueCommentCreated(5, 0, Ok(issue)),
    ReviewCommentCreated(5, 0, Ok(review)),
    CommitCommentCreated(5, 0, Ok(commit)),
    ReviewReplyCreated(5, 0, Ok(review)),
    IssueCommentCreated(5, 0, Err(authentication_required_error())),
    ReviewCommentCreated(5, 0, Err(authentication_required_error())),
    CommitCommentCreated(5, 0, Err(authentication_required_error())),
    ReviewReplyCreated(5, 0, Err(authentication_required_error())),
  ]
  for message in messages {
    let (unchanged, _) = update_review(model, message, emit)
    assert_true(unchanged == model)
  }
}

///|
fn update_draft(model : Model, body? : String, error? : String?) -> Model {
  guard model.review.draft() is Some(draft) else { return model }
  with_review(
    model,
    review_fixture(
      model.review,
      draft=Some({
        ..draft,
        body: body.unwrap_or(draft.body),
        error: error.unwrap_or(draft.error),
      }),
      stage=model.review.submission(),
    ),
  )
}

///|
fn mark_snapshot_stale(model : Model) -> Model {
  with_review(model, review_fixture(model.review, snapshot_stale=true))
}

///|
test "a commit snapshot arriving after its comments enables line authoring" {
  let view = review_test_view()
  let reference = @github.pull_commit_reference(
    "upstream",
    "project",
    "17",
    view.sha,
  )
  let model = review_test_model(
    SignedIn(login=Some("reviewer"), install_url=None),
  )
  let loading = {
    ..model,
    route: Some(reference),
    phase: LoadingPullCommitMetadata(reference~),
  }
  let session = comment_session_context(@comments.Session::new(enabled=true), {
    generation: loading.generation,
    route: Some(reference),
    snapshot: None,
    enabled: true,
  })
  let session = @comments.update(session, Identity(true, Some("reviewer"))).0
  let pending = @comments.update(session, RefreshComments).0
  let session = @comments.update(
      pending,
      CommentsLoaded(
        loading.generation,
        pending.refresh_id,
        Ok({ issue_comments: [], review_comments: [], commit_comments: [], }),
      ),
    ).0
  let loading = { ..loading, review: session, }
  let anchor = ReviewAnchor::{
    path: "src/main.mbt",
    side: Right,
    line: 2,
    position: Some(3),
  }
  assert_false(
    @comments.permission(loading.review, OpenDraft(InlineDraft(0, anchor))).allowed(),
  )
  let ready = with_phase(loading, Showing({ ..view, reference, }))
  assert_true(
    @comments.permission(ready.review, OpenDraft(InlineDraft(0, anchor))).allowed(),
  )
  assert_true(ready.review.comments() == loading.review.comments())
}
