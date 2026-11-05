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

///|
test "manual collapse waits for page layout and rejects hidden body navigation" {
  let model = review_reply_test_model()
  let request : CommentBodyRequest = {
    generation: model.generation,
    id: ReviewComment(20L),
    region: File("src/main.mbt"),
    action: SetCollapsed(true, 400.0),
  }
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let collapsed = update(model, Review(BodyActivated(request)), emit)
  assert_true(
    collapsed.model.review
    .read_view(path="src/main.mbt")
    .comment_collapsed(request.id),
  )
  assert_eq(collapsed.after_commit.length(), 1)
  assert_true(collapsed.after_commit[0].target == request.region)
  assert_true(collapsed.after_commit[0].scope is PageLayout)
  assert_true(collapsed.after_commit[0].navigation is Cancel)
  assert_true(@identity.same(model.phase, collapsed.model.phase))
  assert_true(model.review.draft() == collapsed.model.review.draft())
  for action in [CommentBodyAction::Toggle(400.0), Footnote("note")] {
    let hidden = update(
      collapsed.model,
      Review(BodyActivated({ ..request, action, })),
      emit,
    )
    assert_true(@identity.same(hidden.model.review, collapsed.model.review))
    assert_true(hidden.after_commit.is_empty())
  }
  for
    invalid in [
      { ..request, generation: model.generation - 1, },
      { ..request, region: Discussion, },
      { ..request, id: IssueComment(10L), },
      { ..request, id: ReviewComment(99L), },
    ] {
    let ignored = update(model, Review(BodyActivated(invalid)), emit)
    assert_true(@identity.same(model.review, ignored.model.review))
    assert_true(ignored.after_commit.is_empty())
  }
  let reopened = update(
    collapsed.model,
    Review(BodyActivated({ ..request, action: SetCollapsed(false, 400.0), })),
    emit,
  )
  assert_false(
    reopened.model.review
    .read_view(path="src/main.mbt")
    .comment_collapsed(request.id),
  )
  assert_eq(reopened.after_commit.length(), 1)
}
