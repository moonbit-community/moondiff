///|
fn apply_auth_status(
  model : Model,
  status : ApiAuthStatus,
  force_identity_boundary : Bool,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd, AuthIdentityTransition) {
  let auth = auth_status_from_api(status)
  let (next, detected) = review_state_with_auth_identity(model, auth)
  // A recovery may have visited and validated a public route while anonymous.
  // Recheck a mutable PR with the recovered identity before enabling writes.
  let next = if model.recovering_session &&
    next.auth is SignedIn(..) &&
    next.route
    .map(reference => reference.target is PullRequest(_))
    .unwrap_or(false) &&
    (next.phase is Showing(_) || next.phase is ShowingPullSelector(_)) {
    { ..next, access: { ..next.access, freshness: Checking, }, }
  } else if (next.auth is SignedIn(..) || next.auth is Anonymous(_)) &&
    next.phase is Showing(view) &&
    !(view.reference.target is PullRequest(_)) {
    // Fixed revisions only need their account identity to be confirmed again.
    { ..next, access: { ..next.access, freshness: Confirmed, }, }
  } else {
    next
  }
  let transition = if force_identity_boundary {
    AuthIdentityBoundary
  } else {
    detected
  }
  let (next, command) = if transition is AuthIdentityBoundary {
    reload_after_auth_identity_boundary(next, emit)
  } else if model.source_pause == Some(AnonymousRequests) &&
    next.auth is SignedIn(..) &&
    !(model.auth is SignedIn(..)) {
    recover_anonymous_limit(next, emit)
  } else if (
      next.restore_pending &&
      (next.auth is SignedIn(..) || next.auth is Anonymous(_))
    ) ||
    (model.recovering_session && next.auth is SignedIn(..)) {
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
    Idle | Showing(_) | ShowingPullSelector(_) => false
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
  if model.source_pause == Some(AnonymousRequests) &&
    next.auth is SignedIn(..) &&
    (model.phase is Showing(_) || model.phase is ShowingPullSelector(_)) {
    return (next, command)
  }
  if model.restore_pending ||
    (model.recovering_session && next.auth is SignedIn(..)) ||
    transition is AuthIdentityBoundary ||
    next.auth is Authorizing(_, _) ||
    next.auth is AuthFailed(_) {
    return (next, command)
  }
  guard next.route is Some(reference) else { return (next, command) }
  if restart {
    let (loading, load_command) = begin_sign_in_change_reload(
      next, reference, transition, emit,
    )
    return (loading, @rabbita.batch([command, load_command]))
  }
  if (next.phase is Showing(_) || next.phase is ShowingPullSelector(_)) &&
    (
      model.access.freshness is Unavailable(_) ||
      (
        reference.target is PullRequest(_) &&
        model.access.freshness is Checking &&
        !(model.auth is SignedIn(..)) &&
        next.auth is SignedIn(..)
      )
    ) {
    let (ready, resume_command) = restore_page_requests(next, emit)
    return (ready, @rabbita.batch([command, resume_command]))
  }
  if next.phase is ShowingPullSelector(_) {
    return (next, command)
  }
  (
    next,
    @rabbita.batch([command, comments_request(reference, next.generation, emit)]),
  )
}
