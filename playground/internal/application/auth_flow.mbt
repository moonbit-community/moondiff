///|
fn apply_auth_status(
  model : Model,
  status : ApiAuthStatus,
  preserve_device_copy : Bool,
  continue_device_poll : Bool,
  force_identity_boundary : Bool,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd, AuthIdentityTransition) {
  let auth = if preserve_device_copy {
    auth_status_from_api_preserving(status, model.review.auth)
  } else {
    auth_status_from_api(status)
  }
  let (review, detected_transition) = review_state_with_auth_identity(
    model.review,
    auth,
  )
  let transition = if force_identity_boundary {
    AuthIdentityBoundary
  } else {
    detected_transition
  }
  let next = with_review(model, review)
  let (transitioned, transition_command) = if transition is AuthIdentityBoundary {
    reload_after_auth_identity_boundary(next, emit)
  } else {
    (next, @rabbita.none)
  }
  let poll_command = match auth {
    DeviceAuthorizing(device) =>
      if continue_device_poll ||
        auth_snapshot_starts_device_poll(model.review.auth, device.flow_id) {
        schedule_device_poll(device.flow_id, device.poll_after, emit)
      } else {
        @rabbita.none
      }
    _ => @rabbita.none
  }
  (transitioned, @rabbita.batch([transition_command, poll_command]), transition)
}

///|
fn auth_snapshot_starts_device_poll(
  previous : AuthStatus,
  flow_id : String,
) -> Bool {
  match previous {
    DeviceAuthorizing(device) | DeviceCancelling(device) =>
      device.flow_id != flow_id
    _ => true
  }
}

///|
fn sign_in_restarts_change_load(model : Model) -> Bool {
  if model.review.auth is SignedIn(_) {
    return false
  }
  match model.phase {
    Idle | Showing(_) => false
    _ => true
  }
}

///|
fn finish_device_sign_in(
  model : Model,
  status : ApiAuthStatus,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let restart_change = sign_in_restarts_change_load(model)
  let (next, auth_command, identity_transition) = apply_auth_status(
    model, status, false, false, false, emit,
  )
  if identity_transition is AuthIdentityBoundary {
    return (next, auth_command)
  }
  guard next.route is Some(reference) else { return (next, auth_command) }
  if restart_change {
    let (reloading, load_command) = begin_sign_in_change_reload(
      next, reference, identity_transition, emit,
    )
    return (reloading, @rabbita.batch([auth_command, load_command]))
  }
  (
    with_review(next, review_state_with_comments(next.review, CommentsLoading)),
    @rabbita.batch([
      auth_command,
      comments_request(reference, next.generation, emit),
    ]),
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
