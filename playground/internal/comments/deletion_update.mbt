///|
fn update_deletion(
  model : Model,
  id : CommentId,
  confirm : Bool,
) -> (Model, Effects) {
  guard permission(model.review, Delete(id)).allowed() else {
    return (model, [])
  }
  if !confirm {
    return (
      with_review(model, { ..model.review, deletion: Some(ConfirmDelete(id)), }),
      [],
    )
  }
  guard model.route is Some(reference) && model.review.deletion is Some(state) else {
    return (model, [])
  }
  let selected = match state {
    ConfirmDelete(selected) | DeleteFailed(selected, _) => selected == id
    _ => false
  }
  guard selected else { return (model, []) }
  let generation = model.generation
  let operation = model.review.deletion_id + 1
  (
    with_review(model, {
      ..model.review,
      deletion_id: operation,
      deletion: Some(Deleting(id)),
    }),
    delete_comment_request(reference, id, generation, result => {
      CommentDeleted(generation, operation, id, result)
    }),
  )
}

///|
fn finish_deletion(
  model : Model,
  generation : Int,
  operation : Int,
  id : CommentId,
  result : Result[DeleteResult, Failure],
) -> (Model, Effects) {
  guard owns_response(
      model.review,
      generation,
      operation,
      model.review.deletion_id,
    ) &&
    model.review.deletion == Some(Deleting(id)) else {
    return (model, [])
  }
  match result {
    Ok(result) if result.deleted => {
      let merged = merge_cache(model.review, Removed(id))
      let next = with_review(model, { ..merged, deletion: None, })
      (
        next,
        batch([
          if model.route is Some(reference) {
            comments_request(reference, generation)
          } else {
            []
          },
          notify_github_page_command(),
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
        [],
      )
    }
  }
}
