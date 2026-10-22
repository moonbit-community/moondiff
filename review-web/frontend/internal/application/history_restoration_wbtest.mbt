///|
test "draft edits cancel pending restoration before layout becomes ready" {
  let original = navigation_review_model()
  let checking = {
    ..original,
    access: { ..original.access, freshness: Checking, },
    navigation: { ..original.navigation, restore_position: true, },
  }
  let pending = synchronize_history_restoration(original, checking)
  let token = pending.navigation.restoration.unwrap()
  let edited = home_step(pending, Review(OpenOverallDraft))
  assert_false(edited.navigation.restore_position)
  assert_true(token.cancelled)
  let ready = home_step(
    { ..edited, access: { ..edited.access, freshness: Confirmed, }, },
    Review(DraftBodyChanged("keep typing")),
  )
  assert_false(ready.navigation.restore_position)
  assert_true(
    ui_after_commit(edited, ready, Review(DraftBodyChanged("keep typing")), _ => {
      @rabbita.none
    }).is_empty(),
  )
}

///|
test "history cancellation and completion belong to the exact page and entry" {
  let original = navigation_review_model()
  let pending = synchronize_history_restoration(original, {
    ..original,
    navigation: { ..original.navigation, restore_position: true, },
  })
  let next = synchronize_history_restoration(pending, {
    ..pending,
    generation: pending.generation + 1,
    navigation: {
      ..pending.navigation,
      entry: { ..pending.navigation.entry, id: "next", },
    },
  })
  assert_true(pending.navigation.restoration.unwrap().cancelled)
  assert_false(next.navigation.restoration.unwrap().cancelled)
  for
    message in [
      PositionRestored(pending.generation, pending.navigation.entry.id),
      PositionRestored(next.generation, pending.navigation.entry.id),
    ] {
    assert_true(home_step(next, Ui(message)).navigation.restore_position)
  }
  let complete = home_step(next, Ui(PositionRestored(next.generation, "next")))
  assert_false(complete.navigation.restore_position)
  assert_true(next.navigation.restoration.unwrap().cancelled)
}
