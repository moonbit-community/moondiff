///|
priv enum AuthIdentityTransition {
  AuthIdentityUnchanged
  AuthInitialSignIn
  AuthIdentityBoundary
}

///|
fn auth_identity_transition(
  model : Model,
  auth : AuthStatus,
) -> AuthIdentityTransition {
  match auth {
    SignedIn(login~, ..) =>
      match (model.last_authenticated_login, login) {
        (Some(previous), Some(current)) =>
          if previous == current {
            AuthIdentityUnchanged
          } else {
            AuthIdentityBoundary
          }
        (Some(_), None) => AuthIdentityBoundary
        (None, Some(_)) =>
          if model.auth is SignedIn(login=None, ..) {
            AuthIdentityBoundary
          } else {
            AuthInitialSignIn
          }
        (None, None) =>
          if model.auth is SignedIn(..) {
            AuthIdentityBoundary
          } else {
            AuthInitialSignIn
          }
      }
    Anonymous(_) =>
      if model.last_authenticated_login is Some(_) || model.auth is SignedIn(..) {
        AuthIdentityBoundary
      } else {
        AuthIdentityUnchanged
      }
    _ => AuthIdentityUnchanged
  }
}

///|
fn review_state_with_auth_identity(
  model : Model,
  auth : AuthStatus,
) -> (Model, AuthIdentityTransition) {
  let transition = auth_identity_transition(model, auth)
  (with_auth(model, auth), transition)
}

///|
fn reload_after_auth_identity_boundary(
  model : Model,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let cleared = with_review(
    model,
    @comments.update(model.review, Reset(true, false)).0,
  )
  match cleared.route {
    Some(reference) => begin_change_load(cleared, reference, emit)
    None =>
      (
        {
          ..cleared,
          generation: cleared.generation + 1,
          phase: Idle,
          file_tree: reset_file_tree_state(cleared.file_tree),
        },
        @rabbita.none,
      )
  }
}

///|
fn begin_sign_in_change_reload(
  model : Model,
  reference : CommitRef,
  identity_transition : AuthIdentityTransition,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  begin_change_load(
    model,
    reference,
    emit,
    preserve_draft=identity_transition is AuthIdentityUnchanged,
  )
}
