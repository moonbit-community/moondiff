///|
test "comment navigation waits for its owning layout and repeated footnotes stay expanded" {
  let model = review_reply_test_model()
  let request : CommentBodyRequest = {
    generation: model.generation,
    id: ReviewComment(20L),
    region: File("src/main.mbt"),
    action: Footnote("reference"),
  }
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let opened = update(model, Review(BodyActivated(request)), emit)
  assert_true(
    opened.model.review.read_view(path="src/main.mbt").body_expanded(request.id),
  )
  assert_eq(opened.after_commit.length(), 1)
  assert_true(opened.after_commit[0].target == request.region)
  assert_true(opened.after_commit[0].scope is PageLayout)
  assert_true(opened.after_commit[0].navigation is Cancel)
  let again = update(opened.model, Review(BodyActivated(request)), emit)
  assert_true(@identity.same(opened.model.review, again.model.review))
  assert_eq(again.after_commit.length(), 1)
  let collapsed = update(
    again.model,
    Review(BodyActivated({ ..request, action: Toggle(400.0), })),
    emit,
  )
  assert_eq(collapsed.after_commit.length(), 1)
  assert_false(
    collapsed.model.review
    .read_view(path="src/main.mbt")
    .body_expanded(request.id),
  )
  let expanded = update(
    collapsed.model,
    Review(BodyActivated({ ..request, action: Toggle(400.0), })),
    emit,
  )
  assert_true(expanded.after_commit.is_empty())
  assert_true(@identity.same(model.phase, expanded.model.phase))
  assert_true(expanded.model.review.draft() == model.review.draft())
  for
    invalid in [
      { ..request, generation: model.generation - 1, },
      { ..request, id: ReviewComment(99L), },
      { ..request, region: Discussion, },
      { ..request, region: File("removed.mbt"), },
    ] {
    let ignored = update(model, Review(BodyActivated(invalid)), emit)
    assert_true(ignored.after_commit.is_empty())
    assert_true(@identity.same(model.review, ignored.model.review))
  }
}
