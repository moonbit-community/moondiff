///|
fn apply_auth_status(
  model : Model,
  status : ApiAuthStatus,
  preserve_device_copy : Bool,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let auth = if preserve_device_copy {
    auth_status_from_api_preserving(status, model.review.auth)
  } else {
    auth_status_from_api(status)
  }
  let next = with_review(model, review_state_with_auth(model.review, auth))
  match auth {
    DeviceAuthorizing(device) =>
      (next, schedule_device_poll(device.flow_id, device.poll_after, emit))
    _ => (next, @rabbita.none)
  }
}

///|
fn finish_device_sign_in(
  model : Model,
  status : ApiAuthStatus,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let next = with_review(
    model,
    review_state_with_auth(model.review, auth_status_from_api(status)),
  )
  guard model.route is Some(reference) else { return (next, @rabbita.none) }
  if model.phase is LoadFailed(_) {
    return begin_change_load(next, reference, emit)
  }
  (
    with_review(next, review_state_with_comments(next.review, CommentsLoading)),
    comments_request(reference, model.generation, emit),
  )
}

///|
fn device_flow_is_current(model : Model, flow_id : String) -> Bool {
  match model.review.auth {
    DeviceAuthorizing(device) | DeviceCancelling(device) =>
      device.flow_id == flow_id
    _ => false
  }
}

///|
fn device_flow_is_cancelling(model : Model, flow_id : String) -> Bool {
  model.review.auth is DeviceCancelling(device) && device.flow_id == flow_id
}

///|
fn device_flow_is_authorizing(model : Model, flow_id : String) -> Bool {
  model.review.auth is DeviceAuthorizing(device) && device.flow_id == flow_id
}
