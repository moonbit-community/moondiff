///|
fn recovered_status(model : Model, user : String) -> Model {
  home_step(
    model,
    Auth(
      ReactivationAuthStatusLoaded(
        model.auth_revision,
        model.generation,
        model.route,
        Ok(signed_in_api_status(user)),
      ),
    ),
  )
}

///|
test "expired overall inline and reply drafts stay editable through cancellation and same-account validation" {
  let anchor : ReviewAnchor = {
    path: "src/main.mbt",
    side: Right,
    line: 2,
    position: Some(3),
  }
  for
    entry in [OpenOverallDraft, OpenInlineDraft(0, anchor), OpenReplyDraft(20L)] {
    let original = home_step(
      home_step(review_reply_test_model(), Review(entry)),
      Review(DraftBodyChanged("original")),
    )
    let original = save_route_memory(original)
    let expired = home_step(original, Auth(SessionInvalidated))
    assert_true(expired.recovering_session)
    assert_true(expired.review.draft_visible())
    assert_true(expired.navigation.routes == original.navigation.routes)
    let edited = home_step(expired, Review(DraftBodyChanged("edited offline")))
    assert_eq(edited.review.draft().unwrap().body, "edited offline")
    assert_true(
      home_step(edited, Review(SubmitDraft)).review.submission() is None,
    )
    let started = home_step(edited, Auth(StartSignIn))
    assert_eq(started.review.draft().unwrap().body, "edited offline")
    let cancelling = home_step(started, Auth(CancelSignIn))
    let id = auth_device_id(cancelling.auth).unwrap()
    let anonymous = home_step(
      cancelling,
      Auth(
        DeviceCancelFinished(
          cancelling.auth_revision,
          id,
          Ok({ request_id: id, status: anonymous_api_status(), }),
        ),
      ),
    )
    assert_true(anonymous.auth is Anonymous(_))
    assert_eq(
      anonymous.last_authenticated_user_id,
      original.last_authenticated_user_id,
    )
    assert_eq(anonymous.review.draft().unwrap().body, "edited offline")
    // Navigating while anonymous can already have confirmed the public version.
    // Recovery still validates it again with the authenticated identity.
    let restored = recovered_status(
      { ..anonymous, access: { ..anonymous.access, freshness: Confirmed, }, },
      original.last_authenticated_user_id.unwrap(),
    )
    assert_eq(restored.generation, original.generation)
    assert_true(restored.access.freshness is Checking)
    assert_false(@comments.permission(restored.review, Submit).allowed())
    guard original.phase is Showing(view) else { fail("view") }
    let confirmed = home_step(
      restored,
      Load(
        SharedSnapshotLoaded(
          restored.generation,
          Ok({
            confirmed: true,
            snapshot: {
              metadata: view.pull_snapshot.unwrap(),
              comparison: {
                merge_base_commit: { sha: view.old_revision.unwrap().sha, },
              },
              files: view.files.map(file => file.file),
              signature: "fixture",
            },
          }),
        ),
      ),
    )
    assert_true(@comments.permission(confirmed.review, Submit).allowed())
    assert_eq(confirmed.review.draft().unwrap().body, "edited offline")
    assert_true(confirmed.review.submission() is None)
  }
}

///|
test "expiry retains route drafts but logout and a different immutable user clear all drafts" {
  let editing = home_step(
    home_step(navigation_review_model(), Review(OpenOverallDraft)),
    Review(DraftBodyChanged("saved route")),
  )
  let saved = save_route_memory(editing)
  let away = home_step(saved, Ui(RouteChanged(@url.parse("http://localhost/"))))
  let expired = home_step(away, Auth(SessionInvalidated))
  let started = home_step(expired, Auth(StartSignIn))
  let returned = begin_change_load(started, editing.route.unwrap(), _ => {
      @rabbita.none
    }).0
  let returned = restore_route_memory(returned).0
  assert_eq(returned.review.draft().unwrap().body, "saved route")
  assert_true(returned.review.draft_visible())
  for
    cleared in [
      home_step(returned, Auth(Logout)),
      recovered_status(returned, "another-user"),
    ] {
    assert_true(cleared.review.draft() is None)
    assert_true(cleared.navigation.routes.is_empty())
  }
}

///|
test "expiry releases interrupted writes and rejects late auth and comment callbacks" {
  let editing = home_step(
    home_step(navigation_review_model(), Review(OpenOverallDraft)),
    Review(DraftBodyChanged("sent body")),
  )
  let posting = home_step(editing, Review(SubmitDraft))
  let expired = home_step(posting, Auth(SessionInvalidated))
  assert_true(expired.review.submission() is None)
  assert_true(expired.review.draft().unwrap().error is Some(_))
  let edited = home_step(expired, Review(DraftBodyChanged("new body")))
  let late = home_step(
    edited,
    Review(
      IssueCommentCreated(
        posting.generation,
        posting.review.submission_id,
        Ok({
          id: 91L,
          body: "sent body",
          html_url: "https://github.com/comment/91",
          created_at: "today",
          user: None,
        }),
      ),
    ),
  )
  assert_eq(late.review.draft().unwrap().body, "new body")
  assert_true(late.review.submission() is None)
  assert_true(
    home_step(
      late,
      Auth(
        AuthStatusLoaded(
          posting.auth_revision,
          Ok(signed_in_api_status("reviewer")),
        ),
      ),
    ).auth
    is AuthFailed(_),
  )
}
