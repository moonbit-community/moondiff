///|
fn update_deletion(
  model : Model,
  id : @comments.CommentId,
  confirm : Bool,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  guard @comments.can_delete_comment(model.review, id) &&
    !(model.review.deletion is Some(Deleting(_))) else {
    return (model, @rabbita.none)
  }
  if !confirm {
    return (
      with_review(model, { ..model.review, deletion: Some(ConfirmDelete(id)), }),
      @rabbita.none,
    )
  }
  guard model.route is Some(reference) && model.review.deletion is Some(state) else {
    return (model, @rabbita.none)
  }
  let selected = match state {
    ConfirmDelete(selected) | DeleteFailed(selected, _) => selected == id
    _ => false
  }
  guard selected else { return (model, @rabbita.none) }
  let generation = model.generation
  (
    with_review(model, { ..model.review, deletion: Some(Deleting(id)), }),
    @comments.delete_comment_request(reference, id, generation, result => {
      emit(Review(CommentDeleted(generation, id, result)))
    }),
  )
}

///|
fn finish_deletion(
  model : Model,
  generation : Int,
  id : @comments.CommentId,
  result : Result[@comments.DeleteResult, Error],
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  guard generation == model.generation &&
    model.review.deletion == Some(Deleting(id)) else {
    return (model, @rabbita.none)
  }
  match result {
    Ok(result) if result.deleted => {
      let deleted = model.review.deleted.copy()
      deleted.push(id)
      let comments : @comments.CommentsStatus = match model.review.comments {
        CommentsReady(bundle) =>
          CommentsReady(@comments.without_deleted(bundle, deleted))
        other => other
      }
      let next = with_review(model, {
        ..model.review,
        comments,
        deleted,
        deletion: None,
      })
      (
        next,
        @rabbita.batch([
          if model.route is Some(reference) {
            comments_request(reference, generation, emit)
          } else {
            @rabbita.none
          },
          @comments.notify_github_page_command(),
        ]),
      )
    }
    _ => {
      let message = match result {
        Err(error) => comment_failure_message(error)
        _ => "GitHub did not confirm deletion. Try again."
      }
      let failed = with_review(model, {
        ..model.review,
        deletion: Some(DeleteFailed(id, message)),
      })
      (
        match result {
          Err(error) => model_with_comment_auth_failure(failed, error)
          _ => failed
        },
        @rabbita.none,
      )
    }
  }
}
