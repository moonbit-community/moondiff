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
