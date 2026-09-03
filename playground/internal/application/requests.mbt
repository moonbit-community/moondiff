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
fn auth_status_request(emit : @rabbita.Emit[Msg]) -> @rabbita.Cmd {
  @comments.auth_status_request(result => emit(Auth(AuthStatusLoaded(result))))
}

///|
fn reactivation_auth_status_request(
  reference : CommitRef,
  generation : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  @comments.auth_status_request(result => {
    emit(Auth(ReactivationAuthStatusLoaded(generation, reference, result)))
  })
}

///|
fn auth_device_start_request(emit : @rabbita.Emit[Msg]) -> @rabbita.Cmd {
  @comments.auth_device_start_request(result => {
    emit(Auth(DeviceAuthorizationStarted(result)))
  })
}

///|
fn auth_device_poll_request(
  flow_id : String,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  @comments.auth_device_poll_request(flow_id, result => {
    emit(Auth(DeviceAuthorizationPolled(flow_id, result)))
  })
}

///|
fn auth_device_cancel_request(
  flow_id : String,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  @comments.auth_device_cancel_request(flow_id, result => {
    emit(Auth(DeviceAuthorizationCancelled(flow_id, result)))
  })
}

///|
fn schedule_device_poll(
  flow_id : String,
  poll_after : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  let seconds = if poll_after < 0 {
    0
  } else if poll_after > 3_600 {
    3_600
  } else {
    poll_after
  }
  @cmd.delay(emit(Auth(PollDeviceAuthorization(flow_id))), seconds * 1_000)
}

///|
fn auth_logout_request(emit : @rabbita.Emit[Msg]) -> @rabbita.Cmd {
  @comments.auth_logout_request(result => emit(Auth(AuthLogoutFinished(result))))
}

///|
fn comments_request(
  reference : CommitRef,
  generation : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  @comments.comments_request(reference, generation, result => {
    emit(Review(CommentsLoaded(generation, result)))
  })
}

///|
fn comment_head_request(
  reference : CommitRef,
  number : String,
  anchor : ReviewAnchor,
  generation : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  @comments.comment_head_request(reference, number, generation, result => {
    emit(Review(CommentHeadChecked(generation, anchor, result)))
  })
}

///|
fn create_issue_comment_request(
  reference : CommitRef,
  number : String,
  body : String,
  generation : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  @comments.create_issue_comment_request(reference, number, body, generation, result => {
    emit(Review(IssueCommentCreated(generation, result)))
  })
}

///|
fn create_review_comment_request(
  reference : CommitRef,
  number : String,
  commit_id : String,
  anchor : ReviewAnchor,
  body : String,
  generation : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  @comments.create_review_comment_request(
    reference,
    number,
    commit_id,
    anchor,
    body,
    generation,
    result => emit(Review(ReviewCommentCreated(generation, result))),
  )
}

///|
fn create_commit_comment_request(
  reference : CommitRef,
  sha : String,
  anchor : ReviewAnchor,
  body : String,
  generation : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  @comments.create_commit_comment_request(
    reference,
    sha,
    anchor,
    body,
    generation,
    result => emit(Review(CommitCommentCreated(generation, result))),
  )
}

///|
fn create_review_reply_request(
  reference : CommitRef,
  number : String,
  comment_id : Int64,
  body : String,
  generation : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  @comments.create_review_reply_request(
    reference,
    number,
    comment_id,
    body,
    generation,
    result => emit(Review(ReviewReplyCreated(generation, result))),
  )
}
