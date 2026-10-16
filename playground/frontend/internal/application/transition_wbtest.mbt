///|
test "Viewed persistence waits for its checkbox commit and survives navigation by operation ownership" {
  let model = viewed_test_loaded(viewed_test_model(), Unviewed)
  let transition = update(model, Viewed(Toggle(model.generation, 0)), _ => {
    @rabbita.none
  })
  assert_eq(transition.after_commit.length(), 1)
  let action = transition.after_commit[0]
  guard transition.model.phase is Showing(view) else { fail("showing") }
  assert_true(action.target == File(view.files[0].file.filename))
  assert_true(action.navigation is Continue)
  assert_true(action.scope is Region)
  assert_true(transition.model.viewed.files[0].state is Some(Viewed))
  let stale = update(model, Viewed(Toggle(model.generation - 1, 0)), _ => {
    @rabbita.none
  })
  assert_true(stale.after_commit.is_empty())
}

///|
test "file navigation waits for page layout while drawer focus waits for its own region" {
  let model = viewed_test_model()
  let opened = update(model, Load(OpenFile(model.generation, 0)), _ => {
    @rabbita.none
  })
  assert_eq(opened.after_commit.length(), 1)
  assert_true(opened.after_commit[0].target is File(_))
  assert_true(opened.after_commit[0].navigation is Cancel)
  assert_true(opened.after_commit[0].scope is PageLayout)
  let drawer = update(model, Ui(ToggleFileTreeDrawer), _ => @rabbita.none)
  assert_eq(drawer.after_commit.length(), 1)
  assert_true(drawer.after_commit[0].target is FileTree)
  assert_true(drawer.after_commit[0].scope is Region)
  let from_drawer = update(drawer.model, Load(OpenFile(model.generation, 0)), _ => {
    @rabbita.none
  })
  // Scrolling and focus share one cancellable navigation action.
  assert_eq(from_drawer.after_commit.length(), 1)
  assert_true(from_drawer.after_commit[0].scope is PageLayout)
  let closed = update(drawer.model, Ui(CloseFileTreeDrawer), _ => @rabbita.none)
  assert_true(closed.after_commit[0].target is Toolbar)
}

///|
test "only valid file and change navigation requests create page layout actions" {
  let api = fixture_file("target.mbt", "modified")
  let file = ensure_file_document(
    ready_test_file(api, ["fn target() { 1 }"], ["fn target() { 2 }"]),
    LexicalAlgorithm,
  )
  let model = diff_test_model(set_file_state(diff_test_view([api]), 0, file))
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let valid = update(
    model,
    Load(NavigateChange(model.generation, 0, "target", 0, 1)),
    emit,
  )
  assert_eq(valid.after_commit.length(), 1)
  assert_true(valid.after_commit[0].scope is PageLayout)
  for
    msg in [
      OpenFile(model.generation - 1, 0),
      OpenFile(model.generation, 1),
      NavigateChange(model.generation - 1, 0, "target", 0, 1),
      NavigateChange(model.generation, 1, "target", 0, 1),
      NavigateChange(model.generation, 0, "target", -1, 1),
      NavigateChange(model.generation, 0, "target", 0, 0),
    ] {
    assert_true(update(model, Load(msg), emit).after_commit.is_empty())
  }
}

///|
test "PR sign-in dialog waits only for Discussion and preserves auth review and Viewed" {
  for
    auth in [
      AuthStatus::Anonymous(None),
      AuthChecking,
      AuthFailed("Try again"),
      Authorizing(starting_device("attempt"), ""),
      DeviceCancelling("attempt", ""),
    ] {
    for entry in [SignInEntry::Comment(0), Viewed(0)] {
      let model = review_test_model(auth)
      let transition = update(
        model,
        Ui(OpenSignIn(model.generation, entry, None)),
        _ => @rabbita.none,
      )
      assert_true(
        transition.model ==
        { ..model, sign_in_dialog: { revision: 1, entry: Some(entry), }, },
      )
      assert_eq(transition.after_commit.length(), 1)
      let action = transition.after_commit[0]
      assert_true(action.target is Discussion)
      assert_true(action.scope is Region)
      assert_true(action.navigation is Cancel)
      let closed = update(
        transition.model,
        Ui(CloseSignIn(model.generation, 1)),
        _ => @rabbita.none,
      )
      assert_true(
        closed.model ==
        { ..model, sign_in_dialog: { revision: 2, entry: None, }, },
      )
      assert_eq(closed.after_commit.length(), 1)
      assert_true(closed.after_commit[0].target is Discussion)
    }
  }
}

///|
test "sign-in dialog rejects stale events and entries outside anonymous PR files" {
  let model = review_test_model(Anonymous(None))
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  for
    target in [
      ChangeTarget::Commit("head"),
      PullCommit("17", "head"),
      Range("base", "head"),
      PullRange("17", "base", "head"),
    ] {
    let view = review_test_view(target~)
    let next = { ..model, phase: Showing(view), route: Some(view.reference), }
    let rejected = update(
      next,
      Ui(OpenSignIn(next.generation, Comment(0), None)),
      emit,
    )
    assert_true(rejected.model.sign_in_dialog.entry is None)
    assert_true(rejected.after_commit.is_empty())
  }
  for
    next in [
      review_test_model(
        SignedIn(login=Some("alice"), user_id=Some("1"), install_url=None),
      ),
      initial_model(),
    ] {
    assert_true(
      update(next, Ui(OpenSignIn(next.generation, Comment(0), None)), emit).after_commit.is_empty(),
    )
  }
  for
    msg in [
      OpenSignIn(model.generation - 1, Comment(0), None),
      OpenSignIn(model.generation, Viewed(-1), None),
      OpenSignIn(model.generation, Comment(100), None),
      CloseSignIn(model.generation, 0),
    ] {
    let rejected = update(model, Ui(msg), emit)
    assert_true(rejected.model == model)
    assert_true(rejected.after_commit.is_empty())
  }
  let opened = update(
      model,
      Ui(OpenSignIn(model.generation, Comment(0), None)),
      emit,
    ).model
  let reopened = update(
      opened,
      Ui(OpenSignIn(model.generation, Viewed(0), None)),
      emit,
    ).model
  for
    msg in [
      CloseSignIn(model.generation, 1),
      CloseSignIn(model.generation - 1, 2),
    ] {
    let rejected = update(reopened, Ui(msg), emit)
    assert_true(rejected.model == reopened)
    assert_true(rejected.after_commit.is_empty())
  }
}

///|
test "sign-in success closes without a draft or Viewed write and navigation drops old focus" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let model = review_test_model(Anonymous(None))
  let opened = update(
      model,
      Ui(OpenSignIn(model.generation, Comment(0), None)),
      emit,
    ).model
  let signed_in = update(
    opened,
    Auth(
      AuthStatusLoaded(
        opened.auth_revision,
        Ok({
          authenticated: true,
          login: Some("alice"),
          user_id: Some("1"),
          install_url: None,
          device_flow: None,
          csrf_token: None,
        }),
      ),
    ),
    emit,
  )
  assert_true(signed_in.model.sign_in_dialog.entry is None)
  assert_true(signed_in.model.review.draft() is None)
  assert_false(
    signed_in.model.viewed.files.any(file => {
      file.state is Some(Viewed) || file.pending is Some(_)
    }),
  )
  assert_eq(signed_in.after_commit.length(), 1)
  assert_true(signed_in.after_commit[0].target is Discussion)
  assert_true(signed_in.after_commit[0].scope is Region)
  let changed = update(
    opened,
    Ui(RouteChanged(@url.parse("http://localhost/upstream/project/pull/18"))),
    emit,
  )
  assert_true(changed.model.generation != opened.generation)
  assert_true(changed.model.sign_in_dialog.entry is None)
  assert_true(changed.after_commit.is_empty())
}
