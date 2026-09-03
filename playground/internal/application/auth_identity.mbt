///|
priv enum AuthIdentityTransition {
  AuthIdentityUnchanged
  AuthInitialSignIn
  AuthIdentityBoundary
}

///|
fn auth_identity_transition(
  review : ReviewState,
  auth : AuthStatus,
) -> AuthIdentityTransition {
  match auth {
    SignedIn(login) =>
      match (review.last_authenticated_login, login) {
        (Some(previous), Some(current)) =>
          if previous == current {
            AuthIdentityUnchanged
          } else {
            AuthIdentityBoundary
          }
        (Some(_), None) => AuthIdentityBoundary
        (None, Some(_)) =>
          if review.auth is SignedIn(None) {
            AuthIdentityBoundary
          } else {
            AuthInitialSignIn
          }
        (None, None) =>
          if review.auth is SignedIn(_) {
            AuthIdentityBoundary
          } else {
            AuthInitialSignIn
          }
      }
    Anonymous(_) =>
      if review.last_authenticated_login is Some(_) ||
        review.auth is SignedIn(_) {
        AuthIdentityBoundary
      } else {
        AuthIdentityUnchanged
      }
    _ => AuthIdentityUnchanged
  }
}

///|
fn review_state_with_auth_identity(
  review : ReviewState,
  auth : AuthStatus,
) -> (ReviewState, AuthIdentityTransition) {
  let transition = auth_identity_transition(review, auth)
  let last_authenticated_login = match auth {
    SignedIn(login) => login
    Anonymous(_) | WebReadOnly => None
    _ => review.last_authenticated_login
  }
  (
    {
      auth,
      last_authenticated_login,
      comments: review.comments,
      draft: review.draft,
    },
    transition,
  )
}

///|
fn reload_after_auth_identity_boundary(
  model : Model,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let cleared = with_review(model, {
    auth: model.review.auth,
    last_authenticated_login: model.review.last_authenticated_login,
    comments: CommentsLoading,
    draft: None,
  })
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
  let draft = model.review.draft
  let (reloading, command) = begin_change_load(model, reference, emit)
  if identity_transition is AuthIdentityUnchanged {
    (
      with_review(reloading, review_state_with_draft(reloading.review, draft)),
      command,
    )
  } else {
    (reloading, command)
  }
}
