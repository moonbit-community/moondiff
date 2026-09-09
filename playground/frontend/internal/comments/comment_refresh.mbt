///|
fn begin_comments_refresh(model : Model) -> (Model, Effects) {
  guard model.enabled && model.route is Some(reference) else {
    return (model, [])
  }
  // PR line anchors are meaningful only after the diff snapshot is verified.
  if reference.target is PullRequest(_) && !(model.phase is Showing(_)) {
    return (model, [])
  }
  let id = model.review.refresh_id + 1
  let generation = model.generation
  let refresh : CommentRefresh = if reference.target is PullRequest(_) {
    RefreshMetadata
  } else {
    RefreshList(None)
  }
  let next = with_review(model, {
    ..model.review,
    refresh_id: id,
    refresh,
    refresh_error: None,
  })
  let command = match reference.target {
    PullRequest(number) =>
      raw_comment_head_request(reference, number, generation, result => {
        CommentsMetadataLoaded(generation, id, result)
      })
    _ => comment_list_request(reference, generation, id)
  }
  (next, command)
}

///|
fn comment_list_request(
  reference : CommitRef,
  generation : Int,
  id : Int,
) -> Effects {
  raw_comments_request(reference, generation, result => {
    CommentsLoaded(generation, id, result)
  })
}

///|
fn matches_diff_snapshot(model : Model, pull : ApiPull) -> Bool {
  model.phase is Showing(view) &&
  view.pull_snapshot is Some(snapshot) &&
  same_pull_snapshot(snapshot, pull)
}

///|
fn mark_snapshot_stale(model : Model) -> Model {
  with_review(model, {
    ..model.review,
    snapshot_stale: true,
    refresh: RefreshIdle,
    refresh_error: None,
  })
}

///|
fn fail_comments_refresh(model : Model, error : Failure) -> Model {
  let message = comment_failure_message(error)
  model_with_comment_auth_failure(
    with_review(model, {
      ..model.review,
      refresh: RefreshIdle,
      refresh_error: Some(message),
      comments: if model.review.comments is CommentsReady(_) {
        model.review.comments
      } else {
        CommentsFailed(message)
      },
    }),
    error,
  )
}

///|
fn accept_comments(model : Model, bundle : ApiCommentBundle) -> Model {
  with_review(
    model,
    merge_cache(model.review, Received(bundle, model.review.context.snapshot)),
  )
}
