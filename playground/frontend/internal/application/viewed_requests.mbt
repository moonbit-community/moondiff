///|
fn begin_viewed_refresh(
  model : Model,
  emit : @rabbita.Emit[Msg],
  restart? : Bool = true,
) -> (Model, @rabbita.Cmd) {
  guard viewed_scope(model) is Some(_) &&
    !model.viewed.stale &&
    !model.review.snapshot_stale &&
    model.phase is Showing(view) &&
    view.reference.target is PullRequest(number) else {
    return (model, @rabbita.none)
  }
  // One read per round, including repeated manual checks while a read runs.
  if model.viewed.loading {
    return (model, @rabbita.none)
  }
  let model = if restart {
    { ..model, viewed: { ..model.viewed, retry: 0, poll_scheduled: false, }, }
  } else {
    model
  }
  if viewed_writing(model.viewed) {
    return (
      { ..model, viewed: { ..model.viewed, refresh_needed: true, }, },
      @rabbita.none,
    )
  }
  let state = {
    ..model.viewed,
    user_id: match model.auth {
      SignedIn(user_id~, ..) => user_id
      _ => None
    },
    serial: model.viewed.serial + 1,
    read_serial: model.viewed.serial + 1,
    loading: true,
    poll_scheduled: false,
    refresh_needed: false,
    error: None,
    files: if model.viewed.files.length() == view.files.length() {
      model.viewed.files
    } else {
      view.files.map(_ => empty_viewed_file())
    },
  }
  let next = { ..model, viewed: state, }
  let reference = view.reference
  (
    next,
    if !state.storage_ready {
      viewed_restore_request(next, emit)
    } else {
      @github_client.get_pull_viewed(
        { owner: reference.owner, repo: reference.repo, number, },
        model.generation,
        result => emit(Viewed(Loaded(state.epoch, state.serial, result))),
      )
    },
  )
}

///|
fn schedule_viewed_check(
  model : Model,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let delays = [2000, 4000, 8000, 16000, 30000, 30000]
  guard viewed_scope(model) is Some(_) &&
    viewed_confirming(model.viewed) &&
    !model.viewed.stale &&
    !model.review.snapshot_stale &&
    !model.viewed.loading &&
    !model.viewed.poll_scheduled &&
    model.viewed.retry < delays.length() else {
    return (model, @rabbita.none)
  }
  let delay = delays[model.viewed.retry]
  let state = {
    ..model.viewed,
    retry: model.viewed.retry + 1,
    poll_scheduled: true,
  }
  (
    { ..model, viewed: state, },
    @rabbita.delay(
      emit(Viewed(Check(state.epoch, state.serial, state.retry))),
      delay,
    ),
  )
}

///|
fn viewed_write_request(
  model : Model,
  index : Int,
  record : ViewedRecord,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  @github_client.set_file_viewed(
    {
      owner: record.owner,
      repo: record.repo,
      number: record.number,
      path: record.path,
      viewed: record.viewed,
      base_sha: record.base_sha,
      head_sha: record.head_sha,
    },
    model.generation,
    result => emit(Viewed(Saved(model.viewed.epoch, index, record.id, result))),
  )
}

///|
fn viewed_uncertain(error : Error) -> Bool {
  match error {
    @github_client.HttpRequestError(status~, code~, ..) =>
      status >= 500 ||
      status == 0 ||
      code == "network_error" ||
      code == "invalid_server_response"
    _ => true
  }
}

///|
fn viewed_rate_limited(error : Error) -> Bool {
  match error {
    @github_client.HttpRequestError(status~, code~, ..) =>
      status == 429 || code == "rate_limit"
    _ => false
  }
}

///|
fn viewed_error(model : Model, error : Error) -> Model {
  if @github_client.http_error_code(error) == Some("pull_snapshot_changed") {
    stale_viewed(model)
  } else if @github_client.http_error_code(error) ==
    Some("authentication_required") {
    with_auth(model, AuthFailed(comment_failure_message(error)))
  } else {
    model
  }
}
