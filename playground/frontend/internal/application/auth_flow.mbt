///|
fn apply_auth_status(
  model : Model,
  status : ApiAuthStatus,
  force_identity_boundary : Bool,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd, AuthIdentityTransition) {
  let auth = auth_status_from_api(status)
  let (next, detected) = review_state_with_auth_identity(model, auth)
  let transition = if force_identity_boundary {
    AuthIdentityBoundary
  } else {
    detected
  }
  let (next, command) = if transition is AuthIdentityBoundary {
    reload_after_auth_identity_boundary(next, emit)
  } else if next.restore_pending &&
    (next.auth is SignedIn(..) || next.auth is Anonymous(_)) {
    restore_page_requests(next, emit)
  } else {
    (next, @rabbita.none)
  }
  (next, @rabbita.batch([command, device_poll_request(next, emit)]), transition)
}

///|
fn sign_in_restarts_change_load(model : Model) -> Bool {
  if model.auth is SignedIn(..) {
    return false
  }
  match model.phase {
    Idle | Showing(_) => false
    _ => true
  }
}

///|
fn finish_sign_in(
  model : Model,
  status : ApiAuthStatus,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let restart = sign_in_restarts_change_load(model)
  let (next, command, transition) = apply_auth_status(
    model, status, false, emit,
  )
  if model.restore_pending ||
    transition is AuthIdentityBoundary ||
    next.auth is Authorizing(_, _) ||
    next.auth is AuthFailed(_) {
    return (next, command)
  }
  guard next.route is Some(reference) else { return (next, command) }
  if restart {
    return begin_sign_in_change_reload(next, reference, transition, emit)
  }
  (
    next,
    @rabbita.batch([command, comments_request(reference, next.generation, emit)]),
  )
}
