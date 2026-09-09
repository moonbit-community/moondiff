///|
fn source_load_request(
  location : SourceLocation,
  generation : Int,
  index : Int,
  side : SourceSide,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  @github_client.source_request(location, generation, result => {
    emit(Load(SourceLoaded(generation, index, side, result)))
  })
}

///|
fn commands_for_file(
  view : ChangeView,
  generation : Int,
  index : Int,
  emit : @rabbita.Emit[Msg],
) -> Array[@rabbita.Cmd] {
  source_requests_for_file(view, index).map(request => {
    let (side, location) = request
    source_load_request(location, generation, index, side, emit)
  })
}

///|
fn commands_for_change(
  view : ChangeView,
  generation : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  let commands : Array[@rabbita.Cmd] = []
  for index, file in view.files {
    if file.expanded {
      for command in commands_for_file(view, generation, index, emit) {
        commands.push(command)
      }
    }
  }
  @rabbita.batch(commands)
}

///|
fn auth_status_request(
  revision : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  @github_client.auth_status_request(result => {
    emit(Auth(AuthStatusLoaded(revision, result)))
  })
}

///|
fn reactivation_auth_status_request(
  reference : CommitRef?,
  generation : Int,
  revision : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  @github_client.auth_status_request(result => {
    emit(
      Auth(
        ReactivationAuthStatusLoaded(revision, generation, reference, result),
      ),
    )
  })
}

///|
fn auth_logout_request(
  revision : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  @github_client.auth_logout_request(result => {
    emit(Auth(AuthLogoutFinished(revision, result)))
  })
}

///|
fn comments_request(
  reference : CommitRef,
  generation : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  emit(Review(BeginCommentsRefresh(generation, reference)))
}

///|
fn device_request(
  model : Model,
  operation : @github_client.DeviceAction,
  id : String,
  delay : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  @github_client.auth_device_request(operation, id, delay, result => {
    emit(
      Auth(
        DeviceUpdated(
          model.auth_revision,
          id,
          operation is (Start | Retry),
          result,
        ),
      ),
    )
  })
}

///|
fn device_poll_request(
  model : Model,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  guard model.auth is Authorizing(flow, _) else { return @rabbita.none }
  device_request(
    model,
    if flow.phase == @protocol.DevicePhase::Starting {
      @github_client.Retry
    } else {
      @github_client.Poll
    },
    flow.id,
    flow.retry_after,
    emit,
  )
}
