///|
fn viewed_interaction_model() -> Model {
  let model = review_reply_test_model()
  guard model.phase is Showing(view) else { panic() }
  let files = view.files.copy()
  files.push({
    ..files[0],
    file: {
      ..files[0].file,
      filename: "src/second.mbt",
      previous_filename: Some("src/old.mbt"),
    },
  })
  viewed_test_storage(
    begin_viewed_refresh(with_phase(model, Showing({ ..view, files, })), _ => {
      @rabbita.none
    }).0,
  )
}

///|
fn viewed_interaction_update(model : Model, msg : Msg) -> Model {
  let next = update(model, msg, _ => @rabbita.none).0
  match msg {
    Viewed(Toggle(_, index)) => viewed_test_stored(next, index)
    _ => next
  }
}

///|
fn viewed_interaction_loaded(model : Model) -> Model {
  let model = viewed_test_storage(model)
  guard model.phase is Showing(view) else { panic() }
  let data = viewed_test_data(Viewed)
  viewed_interaction_update(
    model,
    Viewed(
      Loaded(
        model.viewed.epoch,
        model.viewed.serial,
        Ok({
          ..data,
          files: view.files.map(file => {
            path: file.file.filename,
            state: Viewed,
          }),
        }),
      ),
    ),
  )
}

///|
fn viewed_interaction_anchor(path? : String = "src/main.mbt") -> ReviewAnchor {
  canonical_anchor(
    parse_canonical_patch(
      path,
      Some("@@ -1,3 +1,3 @@\n context\n-old\n+new\n tail"),
    ),
    Right,
    2,
  ).unwrap()
}

///|
fn assert_viewed_interaction(
  model : Model,
  expanded : Array[Bool],
) -> Unit raise {
  guard model.phase is Showing(view) else { fail("missing view") }
  assert_eq(view.files.map(file => file.expanded), expanded)
  assert_true(model.viewed.ready)
  assert_true(model.viewed.files.all(file => file.state == Some(Viewed)))
}

///|
test "first Viewed read preserves empty and edited inline and reply drafts only on their file" {
  let initial = viewed_interaction_model()
  let anchor = viewed_interaction_anchor()
  for
    open in [
      Review(OpenInlineDraft(0, anchor)),
      Review(Domain(OpenInlineDraft(0, anchor))),
      Review(OpenReplyDraft(20L)),
      Review(Domain(OpenReplyDraft(20L))),
    ] {
    let draft = viewed_interaction_update(initial, open)
    assert_true(draft.review.draft() is Some({ body: "", .. }))
    let loaded = viewed_interaction_loaded(draft)
    assert_viewed_interaction(loaded, [true, false])
    assert_true(loaded.review.draft() == draft.review.draft())
    for
      edit in [
        Review(DraftBodyChanged("keep")),
        Review(Domain(DraftBodyChanged("keep"))),
      ] {
      let edited = viewed_interaction_update(draft, edit)
      assert_eq(edited.viewed.files[0].expansion_revision, 2)
      let loaded = viewed_interaction_loaded(edited)
      assert_viewed_interaction(loaded, [true, false])
      assert_true(loaded.review.draft() == edited.review.draft())
    }
  }
  assert_viewed_interaction(viewed_interaction_loaded(initial), [false, false])
}

///|
test "Viewed draft protection resolves current paths instead of indices and excludes rejected targets" {
  let initial = viewed_interaction_model()
  // A stale index must not protect the wrong file, including renamed old paths.
  for
    (path, expected) in [
      ("src/main.mbt", [true, false]),
      ("src/second.mbt", [false, true]),
      ("src/old.mbt", [false, false]),
      ("absent.mbt", [false, false]),
    ] {
    let opened = viewed_interaction_update(
      initial,
      Review(OpenInlineDraft(99, viewed_interaction_anchor(path~))),
    )
    assert_viewed_interaction(viewed_interaction_loaded(opened), expected)
  }
  let overall = viewed_interaction_update(initial, Review(OpenOverallDraft))
  for
    msg in [
      Review(OpenInlineDraft(0, viewed_interaction_anchor())),
      Review(Domain(OpenReplyDraft(20L))),
      Review(DraftBodyChanged("overall")),
    ] {
    let rejected = viewed_interaction_update(overall, msg)
    assert_viewed_interaction(viewed_interaction_loaded(rejected), [
      false, false,
    ])
  }
  for msg in [Review(OpenReplyDraft(21L)), Review(Domain(OpenReplyDraft(999L)))] {
    assert_viewed_interaction(
      viewed_interaction_loaded(viewed_interaction_update(initial, msg)),
      [false, false],
    )
  }
  let first = viewed_interaction_update(initial, Review(OpenReplyDraft(20L)))
  let rejected = viewed_interaction_update(
    first,
    Review(
      Domain(
        OpenInlineDraft(1, viewed_interaction_anchor(path="src/second.mbt")),
      ),
    ),
  )
  assert_eq(rejected.viewed.files[0].expansion_revision, 1)
  assert_viewed_interaction(viewed_interaction_loaded(rejected), [true, false])
}

///|
test "Viewed active draft guard protects restored drafts without recorded interaction" {
  let initial = viewed_interaction_model()
  for
    msg in [
      OpenInlineDraft(1, viewed_interaction_anchor()),
      OpenReplyDraft(20L),
    ] {
    // Enter through the domain directly to simulate a retained editor.
    let draft = update_review(initial, msg, _ => @rabbita.none).0
    assert_false(draft.viewed.files[0].touched)
    assert_viewed_interaction(viewed_interaction_loaded(draft), [true, false])
  }
}

///|
test "Viewed resolves reply roots by current filename and ignores unavailable file paths" {
  let initial = viewed_interaction_model()
  guard initial.review.comments() is CommentsReady(bundle) else {
    fail("missing comments")
  }
  for
    (path, expected) in [
      ("src/second.mbt", [false, true]),
      ("src/old.mbt", [false, false]),
      ("absent.mbt", [false, false]),
    ] {
    let model = with_review(
      initial,
      review_fixture(
        initial.review,
        comments=CommentsReady({
          ..bundle,
          review_comments: [{ ..bundle.review_comments[0], path, }],
        }),
      ),
    )
    let draft = viewed_interaction_update(
      model,
      Review(Domain(OpenReplyDraft(20L))),
    )
    assert_true(draft.review.draft() is Some({ kind: ReplyDraft(20L), .. }))
    assert_viewed_interaction(viewed_interaction_loaded(draft), expected)
  }
}

///|
test "Viewed ignores denied draft actions and edits during submission" {
  let initial = viewed_interaction_model()
  for
    model in [
      with_review(initial, review_fixture(initial.review, snapshot_stale=true)),
      with_auth(initial, AuthChecking),
    ] {
    let rejected = viewed_interaction_update(
      model,
      Review(Domain(OpenInlineDraft(0, viewed_interaction_anchor()))),
    )
    assert_true(rejected.review.draft() is None)
    assert_false(rejected.viewed.files[0].touched)
  }
  let draft = viewed_interaction_update(initial, Review(OpenReplyDraft(20L)))
  let edited = viewed_interaction_update(
    draft,
    Review(DraftBodyChanged("post")),
  )
  let submitting = viewed_interaction_update(edited, Review(SubmitDraft))
  let rejected = viewed_interaction_update(
    submitting,
    Review(Domain(DraftBodyChanged("too late"))),
  )
  assert_true(rejected.review.draft() == submitting.review.draft())
  assert_eq(
    rejected.viewed.files[0].expansion_revision,
    submitting.viewed.files[0].expansion_revision,
  )
  // A stale async completion cannot record a new interaction either.
  let stale = viewed_interaction_update(
    edited,
    Review(
      ReviewReplyCreated(
        edited.generation - 1,
        edited.review.submission_id,
        Err(authentication_required_error()),
      ),
    ),
  )
  assert_true(stale == edited)
}

///|
test "Viewed keeps interaction after cancelling or submitting drafts and retrying its first read" {
  let initial = viewed_interaction_model()
  for
    msg in [
      Review(OpenInlineDraft(0, viewed_interaction_anchor())),
      Review(Domain(OpenReplyDraft(20L))),
    ] {
    let opened = viewed_interaction_update(initial, msg)
    let cancelled = viewed_interaction_update(opened, Review(CancelDraft))
    assert_true(cancelled.review.draft() is None)
    assert_viewed_interaction(viewed_interaction_loaded(cancelled), [
      true, false,
    ])
    let edited = viewed_interaction_update(
      opened,
      Review(DraftBodyChanged("post")),
    )
    let submitted = viewed_interaction_update(edited, Review(SubmitDraft))
    assert_true(submitted.review.draft() is Some({ submitting: true, .. }))
    assert_viewed_interaction(viewed_interaction_loaded(submitted), [
      true, false,
    ])
    let failed = viewed_interaction_update(
      cancelled,
      Viewed(
        Loaded(
          cancelled.viewed.epoch,
          cancelled.viewed.serial,
          Err(
            @github_client.HttpRequestError(
              status=429,
              code="rate_limit",
              detail="later",
            ),
          ),
        ),
      ),
    )
    assert_false(failed.viewed.ready)
    let retry = viewed_interaction_update(failed, Viewed(Refresh))
    assert_viewed_interaction(viewed_interaction_loaded(retry), [true, false])
  }
}

///|
test "Viewed tracks section toggles and retries before loading but ignores stale file messages" {
  let initial = viewed_interaction_model()
  for
    msg in [
      Load(OpenFile(initial.generation, 0)),
      Load(ToggleSection(initial.generation, 0, "section")),
      Load(NavigateChange(initial.generation, 0, "section", 0, 1)),
      Load(RetryFile(initial.generation, 0)),
    ] {
    let changed = viewed_interaction_update(initial, msg)
    assert_viewed_interaction(viewed_interaction_loaded(changed), [true, false])
    assert_false(initial.viewed.files[0].touched)
  }
  for
    (generation, index) in [
      (initial.generation - 1, 0),
      (initial.generation, -1),
      (initial.generation, 2),
    ] {
    for
      msg in [
        Load(ToggleFile(generation, index)),
        Load(OpenFile(generation, index)),
        Load(ToggleSection(generation, index, "section")),
        Load(NavigateChange(generation, index, "section", 0, 1)),
        Load(RetryFile(generation, index)),
      ] {
      let ignored = viewed_interaction_update(initial, msg)
      assert_true(ignored == initial)
      assert_viewed_interaction(viewed_interaction_loaded(ignored), [
        false, false,
      ])
    }
  }
}

///|
test "Viewed failure rollback and uncertain confirmation preserve interactions after unmark" {
  let loaded = viewed_interaction_loaded(viewed_interaction_model())
  let unmarked = viewed_interaction_update(
    loaded,
    Viewed(Toggle(loaded.generation, 0)),
  )
  for
    msg in [
      Review(OpenInlineDraft(0, viewed_interaction_anchor())),
      Review(Domain(OpenReplyDraft(20L))),
      Load(ToggleSection(unmarked.generation, 0, "section")),
      Load(RetryFile(unmarked.generation, 0)),
    ] {
    let changed = viewed_interaction_update(unmarked, msg)
    for status in [403, 504] {
      let failed = viewed_test_saved(
        changed,
        Err(
          @github_client.HttpRequestError(
            status~,
            code="failure",
            detail="failed",
          ),
        ),
      )
      let settled = if status == 504 {
        viewed_interaction_loaded(failed)
      } else {
        failed
      }
      assert_true(viewed_test_expanded(settled))
      if status == 504 {
        assert_true(settled.viewed.files[0].pending is Some(_))
        assert_true(settled.viewed.files[0].state == Some(Unviewed))
      } else {
        assert_viewed_interaction(settled, [true, false])
        assert_true(settled.viewed.files[0].pending is None)
        assert_true(settled.viewed.files[0].error is Some(_))
      }
      assert_true(settled.review.draft() == changed.review.draft())
    }
  }
  // With no later interaction the old collapsed state is restored.
  let failed = viewed_test_saved(
    unmarked,
    Err(
      @github_client.HttpRequestError(
        status=403,
        code="failure",
        detail="failed",
      ),
    ),
  )
  assert_viewed_interaction(failed, [false, false])
  // An interaction before the write does not suppress rollback either.
  let draft = viewed_interaction_update(loaded, Review(OpenReplyDraft(20L)))
  let unmarked = viewed_interaction_update(
    draft,
    Viewed(Toggle(draft.generation, 0)),
  )
  let failed = viewed_test_saved(
    unmarked,
    Err(
      @github_client.HttpRequestError(
        status=403,
        code="failure",
        detail="failed",
      ),
    ),
  )
  assert_viewed_interaction(failed, [false, false])
  let edited = viewed_interaction_update(
    unmarked,
    Review(Domain(DraftBodyChanged("after write"))),
  )
  let uncertain = viewed_test_saved(
    edited,
    Err(
      @github_client.HttpRequestError(
        status=504,
        code="timeout",
        detail="failed",
      ),
    ),
  )
  let waiting = viewed_interaction_loaded(uncertain)
  assert_true(viewed_test_expanded(waiting))
  assert_true(waiting.viewed.files[0].pending is Some(_))
}

///|
test "Viewed records anonymous interactions and retains them through initial sign in and same account restore" {
  let initial = viewed_interaction_model()
  let anonymous = with_auth(
    { ..initial, viewed: ViewedState::new(), },
    Anonymous(None),
  )
  let touched = viewed_interaction_update(
    anonymous,
    Load(ToggleSection(anonymous.generation, 0, "section")),
  )
  assert_false(touched.viewed.ready)
  assert_true(touched.viewed.files[0].touched)
  let signed_in = viewed_interaction_update(
    touched,
    Auth(
      ReactivationAuthStatusLoaded(
        touched.auth_revision,
        touched.generation,
        touched.route,
        Ok(signed_in_api_status("reviewer")),
      ),
    ),
  )
  assert_viewed_interaction(viewed_interaction_loaded(signed_in), [true, false])
  let draft = viewed_interaction_update(signed_in, Review(OpenReplyDraft(20L)))
  let restoring = viewed_interaction_update(draft, Auth(RestoreAuth))
  let restored = viewed_interaction_update(
    restoring,
    Auth(
      ReactivationAuthStatusLoaded(
        restoring.auth_revision,
        restoring.generation,
        restoring.route,
        Ok(signed_in_api_status("reviewer")),
      ),
    ),
  )
  assert_viewed_interaction(viewed_interaction_loaded(restored), [true, false])
  assert_true(restored.review.draft() == draft.review.draft())
  assert_true(
    update_viewed(
      restored,
      Loaded(
        draft.viewed.epoch,
        draft.viewed.serial,
        Ok(viewed_test_data(Viewed)),
      ),
      _ => @rabbita.none,
    ).0 ==
    restored,
  )
}

///|
test "Viewed clears interaction across accounts pages and snapshots even while anonymous" {
  let initial = viewed_interaction_model()
  let touched = viewed_interaction_update(
    initial,
    Load(OpenFile(initial.generation, 0)),
  )
  guard touched.phase is Showing(view) && view.pull_snapshot is Some(snapshot) else {
    fail("missing view")
  }
  for
    next in [
      with_auth(
        touched,
        SignedIn(user_id=Some("bob"), login=Some("bob"), install_url=None),
      ),
      { ..touched, generation: touched.generation + 1, },
      {
        ..touched,
        route: Some({ ..view.reference, target: PullRequest("18"), }),
      },
      with_phase(
        touched,
        Showing({
          ..view,
          pull_snapshot: Some({
            ..snapshot,
            head: { ..snapshot.head, sha: "changed", },
          }),
        }),
      ),
    ] {
    let reset = reconcile_viewed(touched, next, Viewed(Refresh), _ => {
        @rabbita.none
      }).0
    assert_true(
      reset.viewed.files.all(file => {
        !file.touched && file.expansion_revision == 0
      }),
    )
    assert_true(reset.viewed.epoch > touched.viewed.epoch)
    assert_true(
      update_viewed(
        reset,
        Loaded(
          touched.viewed.epoch,
          touched.viewed.serial,
          Ok(viewed_test_data(Viewed)),
        ),
        _ => @rabbita.none,
      ).0 ==
      reset,
    )
  }
  let anonymous = with_auth(touched, Anonymous(None))
  let reset = reconcile_viewed(
      anonymous,
      { ..anonymous, generation: anonymous.generation + 1, },
      Viewed(Refresh),
      _ => @rabbita.none,
    ).0
  assert_true(reset.viewed.files.is_empty())
}
