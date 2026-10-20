///|
fn snapshot_replacement_blocked(model : Model) -> Bool {
  (
    model.review.draft() is Some(_) &&
    !(model.review.submission() is Some(SyncingReview(_)))
  ) ||
  navigation_blocked(model) ||
  // A stale Viewed response has already passed the backend write coordinator.
  // Its retained confirmation record must survive restoration, but cannot keep
  // Load latest blocked after the upstream mutation has finished.
  viewed_writing(model.viewed) ||
  (viewed_confirming(model.viewed) && !model.viewed.stale) ||
  model.access.identity_checking ||
  model.auth is AuthFailed(_)
}

///|
fn retain_previous_snapshot(model : Model) -> (Model, @rabbita.Cmd) {
  (
    {
      ..model,
      access: {
        ..model.access,
        preparing: None,
        freshness: Unavailable(
          "This PR has a newer version. Finish the current write or close your draft, then retry to load it. Your draft stays with the displayed version.",
        ),
      },
    },
    @rabbita.none,
  )
}

///|
fn prepare_snapshot_replacement(
  model : Model,
  snapshot : @github_client.PullSnapshot,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  if snapshot_replacement_blocked(model) {
    return retain_previous_snapshot(model)
  }
  guard model.route is Some(reference) else { return (model, @rabbita.none) }
  if snapshot.metadata.changed_files > @github.MAX_PULL_FILES {
    return install_snapshot(model, snapshot, None, emit)
  }
  let view = match
    finish_pull(
      reference,
      snapshot.metadata,
      snapshot.comparison,
      snapshot.files,
    ) {
    Ok(view) => view
    Err(message) =>
      return (
        {
          ..model,
          access: {
            ..model.access,
            freshness: Unavailable(message),
            preparing: None,
          },
        },
        @rabbita.none,
      )
  }
  let selected = match model.phase {
    Showing(old) =>
      model.file_tree.selected_file_index
      .bind(index => old.files.get(index))
      .bind(file => {
        view.files.search_by(next => next.file.filename == file.file.filename)
      })
    _ => None
  }
  let target = match selected {
    Some(_) => selected
    None => view.files.search_by(file => file.expanded)
  }
  guard target is Some(index) else {
    return install_snapshot(model, snapshot, Some(view), emit)
  }
  let file = view.files[index]
  let file = {
    ..file,
    expanded: true,
    old_side: if file.old_side is NotRequested {
      Loading
    } else {
      file.old_side
    },
    new_side: if file.new_side is NotRequested {
      Loading
    } else {
      file.new_side
    },
  }
  let view = set_file_state(view, index, file)
  let next = {
    ..model,
    access: {
      ..model.access,
      freshness: Checking,
      preparing: Some({ snapshot, view, }),
    },
  }
  let requests = source_requests_for_file(view, index)
  if requests.is_empty() {
    return complete_snapshot_replacement(next, emit)
  }
  (
    next,
    @rabbita.batch(
      requests.map(request => {
        let (side, location) = request
        @github_client.source_request(
          location,
          model.generation,
          result => {
            emit(
              Load(
                ReplacementSourceLoaded(
                  model.generation,
                  snapshot.signature,
                  index,
                  side,
                  result,
                ),
              ),
            )
          },
          priority=true,
        )
      }),
    ),
  )
}

///|
fn receive_replacement_source(
  model : Model,
  generation : Int32,
  signature : String,
  index : Int32,
  side : SourceSide,
  result : Result[(String, Bytes), Error],
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  guard generation == model.generation &&
    model.access.preparing is Some(prepared) &&
    prepared.snapshot.signature == signature &&
    prepared.view.files.get(index) is Some(file) else {
    return (model, @rabbita.none)
  }
  if result is Err(error) &&
    @github_client.http_error_code(error) != Some("source_too_large") {
    return (
      {
        ..model,
        access: {
          ..model.access,
          preparing: None,
          freshness: Unavailable(error_message(error, false)),
        },
      },
      @rabbita.none,
    )
  }
  let loaded : SideLoad = match result {
    Err(error) => CannotRender(error_message(error, false), false)
    _ => side_from_result(result)
  }
  let changed = match side {
    Old => { ..file, old_side: loaded, }
    New => { ..file, new_side: loaded, }
  }
  let view = set_file_state(
    prepared.view,
    index,
    ensure_file_document(
      changed,
      model.diff_algorithm,
      ignore_comments=model.ignore_comments,
      ignore_tests=model.ignore_tests,
    ),
  )
  let next = {
    ..model,
    access: { ..model.access, preparing: Some({ ..prepared, view, }), },
  }
  if changed.old_side is Loading || changed.new_side is Loading {
    (next, @rabbita.none)
  } else {
    complete_snapshot_replacement(next, emit)
  }
}

///|
fn complete_snapshot_replacement(
  model : Model,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  guard model.access.preparing is Some(prepared) else {
    return (model, @rabbita.none)
  }
  // This check must run after source preparation: a draft or write may have
  // appeared while the new version was being fetched.
  if snapshot_replacement_blocked(model) {
    return retain_previous_snapshot(model)
  }
  install_snapshot(model, prepared.snapshot, Some(prepared.view), emit)
}
