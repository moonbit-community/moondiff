///|
fn collapsed_sections(model : Model, index? : Int = 0) -> Array[String] {
  guard model.phase is Showing(view) else { panic() }
  view.files[index].collapsed_sections
}

///|
test "section toggles are immutable and scoped to a file and generation" {
  let model = diff_test_model(
    diff_test_view([
      fixture_file("first.mbt", "modified"),
      fixture_file("second.mbt", "modified"),
    ]),
  )
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let first = "section:0:1:0:1:0"
  let second = "section:0:1:0:1:1"
  let (collapsed, _) = update_load(
    model,
    ToggleSection(model.generation, 0, first),
    emit,
  )
  assert_eq(collapsed_sections(model), [])
  assert_eq(collapsed_sections(collapsed), [first])
  assert_eq(collapsed_sections(collapsed, index=1), [])
  let (both, _) = update_load(
    collapsed,
    ToggleSection(model.generation, 0, second),
    emit,
  )
  let (reopened, _) = update_load(
    both,
    ToggleSection(model.generation, 0, first),
    emit,
  )
  assert_eq(collapsed_sections(collapsed), [first])
  assert_eq(collapsed_sections(both), [first, second])
  assert_eq(collapsed_sections(reopened), [second])
  let (other_file, _) = update_load(
    reopened,
    ToggleSection(model.generation, 1, first),
    emit,
  )
  assert_eq(collapsed_sections(other_file), [second])
  assert_eq(collapsed_sections(other_file, index=1), [first])
  for
    (generation, index) in [
      (model.generation - 1, 0),
      (model.generation + 1, 0),
      (model.generation, -1),
      (model.generation, 2),
    ] {
    let (ignored, _) = update_load(
      both,
      ToggleSection(generation, index, first),
      emit,
    )
    assert_true(ignored == both)
  }
  let loading = { ..both, phase: Idle, }
  let (ignored, _) = update_load(
    loading,
    ToggleSection(loading.generation, 0, first),
    emit,
  )
  assert_true(ignored == loading)
}

///|
test "section choices survive presentation changes reopening and source updates" {
  let api = fixture_file("same_line.mbt", "modified")
  let file = ready_test_file(api, ["let first = 11; let second = 22"], [
    "let first = 33; let second = 44",
  ])
  let model = diff_test_model(set_file_state(diff_test_view([api]), 0, file))
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let key = "section:0:1:0:1:0"
  let (collapsed, _) = update_load(
    model,
    ToggleSection(model.generation, 0, key),
    emit,
  )
  let mut model = collapsed
  for
    message in [
      SelectView(Unified),
      SelectDiffAlgorithm(AstAlgorithm),
      ToggleIgnoreComments,
      ToggleIgnoreTests,
      SelectView(Split),
      SelectDiffAlgorithm(LexicalAlgorithm),
      ToggleIgnoreComments,
      ToggleIgnoreTests,
    ] {
    model = update_ui(model, message, emit).0
    assert_eq(collapsed_sections(model), [key])
  }
  for
    message in [
      ToggleFile(model.generation, 0),
      ToggleFile(model.generation, 0),
      ToggleFile(model.generation, 0),
      OpenFile(model.generation, 0),
      SourceLoaded(
        model.generation,
        0,
        Old,
        Ok(("", b"let first = 11; let second = 22")),
      ),
      SourceLoaded(
        model.generation,
        0,
        New,
        Ok(("", b"let first = 33; let second = 44")),
      ),
      RetryFile(model.generation, 0),
    ] {
    model = update_load(model, message, emit).0
    assert_eq(collapsed_sections(model), [key])
  }
  assert_eq(collapsed_sections(collapsed), [key])
}

///|
test "section toggles preserve drafts and refresh retains choices until a new snapshot" {
  let model = review_reply_test_model()
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let anchor : ReviewAnchor = {
    path: "src/main.mbt",
    side: Right,
    line: 2,
    position: Some(3),
  }
  let (model, _) = update_review(model, OpenInlineDraft(0, anchor), emit)
  let (model, _) = update_review(
    model,
    DraftBodyChanged("Keep this draft"),
    emit,
  )
  assert_true(model.review.draft() is Some(_))
  let key = "section:0:3:0:3:0"
  let (collapsed, _) = update_load(
    model,
    ToggleSection(model.generation, 0, key),
    emit,
  )
  assert_true(collapsed.review.draft() == model.review.draft())
  guard model.review.comments() is CommentsReady(bundle) else {
    fail("expected fixture comments")
  }
  let (refreshed, _) = review_test_refresh(collapsed, bundle, emit)
  assert_eq(collapsed_sections(refreshed), [key])
  assert_true(refreshed.review.draft() == model.review.draft())
  let (reopened, _) = update_load(
    refreshed,
    ToggleSection(model.generation, 0, key),
    emit,
  )
  assert_eq(collapsed_sections(reopened), [])
  assert_true(reopened.review.draft() == model.review.draft())

  let commit = decode_commit(read_fixture("testdata/github/commit_page1.json"))
  let reference = commit_reference("example", "project", commit.sha)
  let (loading, _) = begin_change_load(refreshed, reference, emit)
  let (loaded, _) = update_load(
    loading,
    CommitPageLoaded(loading.generation, 1, Ok(commit)),
    emit,
  )
  assert_eq(loaded.generation, model.generation + 1)
  assert_eq(collapsed_sections(loaded), [])
  let (stale, _) = update_load(
    loaded,
    ToggleSection(model.generation, 0, key),
    emit,
  )
  assert_true(stale == loaded)
  assert_eq(collapsed_sections(refreshed), [key])
}

///|
test "change navigation expands idempotently and rejects stale or invalid targets" {
  let model = diff_test_model(
    diff_test_view([
      fixture_file("first.mbt", "modified"),
      fixture_file("second.mbt", "modified"),
    ]),
  )
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (collapsed, _) = update_load(
    model,
    ToggleSection(model.generation, 0, "target"),
    emit,
  )
  let (collapsed, _) = update_load(
    collapsed,
    ToggleSection(model.generation, 0, "other"),
    emit,
  )
  let (opened, _) = update_load(
    collapsed,
    NavigateChange(model.generation, 0, "target", 0, 1),
    emit,
  )
  assert_eq(collapsed_sections(collapsed), ["target", "other"])
  assert_eq(collapsed_sections(opened), ["other"])
  assert_eq(collapsed_sections(opened, index=1), [])
  let (again, _) = update_load(
    opened,
    NavigateChange(model.generation, 0, "target", 1, -1),
    emit,
  )
  assert_true(again == opened)
  let (switched, _) = update_ui(opened, SelectView(Unified), emit)
  assert_eq(collapsed_sections(switched), ["other"])
  for
    (generation, index, block, direction) in [
      (model.generation - 1, 0, 0, 1),
      (model.generation + 1, 0, 0, 1),
      (model.generation, -1, 0, 1),
      (model.generation, 2, 0, 1),
      (model.generation, 0, -1, 1),
      (model.generation, 0, 0, 0),
    ] {
    let (ignored, _) = update_load(
      collapsed,
      NavigateChange(generation, index, "target", block, direction),
      emit,
    )
    assert_true(ignored == collapsed)
  }
}
