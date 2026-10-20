///|
test "ready page restoration reuses parsed sources diff and highlights before metadata returns" {
  let model = navigation_review_model()
  guard model.phase is Showing(view) else { fail("view") }
  let view = ensure_expanded_file_documents(
    view,
    model.diff_algorithm,
    ignore_comments=model.ignore_comments,
    ignore_tests=model.ignore_tests,
  )
  let model = with_phase(model, Showing(view))
  let home = home_step(
    save_route_memory(model),
    Ui(RouteChanged(@url.parse("http://localhost/"))),
  )
  let restored = home_step(
    home,
    Ui(RouteChanged(@url.parse("http://localhost/upstream/project/pull/17"))),
  )
  guard restored.phase is Showing(ready) else {
    fail("ready before validation")
  }
  assert_true(
    @identity.same(ready.files[0].diff_cache, view.files[0].diff_cache),
  )
  assert_true(restored.access.freshness is Checking)
  assert_false(writes_allowed(restored))
  let verified = home_step(
    restored,
    Load(
      SharedSnapshotLoaded(
        restored.generation,
        Ok({ snapshot: shown_snapshot(model), confirmed: true, }),
      ),
    ),
  )
  guard verified.phase is Showing(ready) else { fail("verified") }
  assert_true(
    @identity.same(ready.files[0].diff_cache, view.files[0].diff_cache),
  )
  assert_true(writes_allowed(verified))
}

///|
test "ready page cache limits non-current pages and falls back above four MiB of source" {
  let original = navigation_review_model()
  let mut saved = original
  for number in ["18", "19", "20"] {
    saved = save_route_memory(saved)
    guard saved.phase is Showing(view) else { fail("view") }
    let reference = @github.pull_reference("upstream", "project", number)
    saved = with_phase(
      { ..saved, route: Some(reference), },
      Showing({ ..view, reference, }),
    )
  }
  let destination = @github.pull_reference("upstream", "project", "19")
  let restored = begin_change_load(saved, destination, _ => @rabbita.none).0
  assert_eq(restored.navigation.pages.length(), 2)
  assert_true(restored.phase is Showing(_))
  assert_true(ready_page(restored, original.route.unwrap()) is None)
  guard original.phase is Showing(view) else { fail("view") }
  let huge = {
    ..view,
    files: [
      { ..view.files[0], old_side: Ready(["x".repeat(4 * 1048576 + 1)]), },
    ],
  }
  let saved = save_route_memory(with_phase(original, Showing(huge)))
  assert_true(saved.navigation.pages.is_empty())
  assert_true(
    saved.navigation.routes.contains(route_key(original.route.unwrap())),
  )
  let other_user = {
    ..saved,
    navigation: original.navigation,
    last_authenticated_user_id: Some("other"),
  }
  assert_true(ready_page(other_user, original.route.unwrap()) is None)
}

///|
test "the parsed-page source budget includes separators and permits exactly four MiB" {
  guard navigation_review_model().phase is Showing(view) else { fail("view") }
  let exact = {
    ..view,
    files: [
      {
        ..view.files[0],
        old_side: Ready(["x".repeat(4 * 1048576)]),
        new_side: Ready([]),
      },
    ],
  }
  assert_true(retain_page(exact))
  let over = {
    ..exact,
    files: [{ ..exact.files[0], new_side: Ready(["x"]), }],
  }
  assert_false(retain_page(over))
}
