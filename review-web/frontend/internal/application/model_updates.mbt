///|
fn with_phase(model : Model, phase : Phase) -> Model {
  let next = {
    ..model,
    phase,
    file_tree: if phase is LoadFailed(_) {
      reset_file_tree_state(model.file_tree)
    } else {
      model.file_tree
    },
  }
  // Comments can finish before a commit diff. Publish the loaded snapshot to
  // the domain before the view asks whether line comment actions are allowed.
  {
    ..next,
    review: comment_session_context(next.review, comment_context(next)),
  }
}

///|
fn with_review(model : Model, review : Session) -> Model {
  let next = { ..model, review, }
  if review.authentication_error is Some(message) &&
    auth_device_id(model.auth) is None {
    with_auth(next, AuthFailed(message))
  } else {
    next
  }
}

///|
fn with_auth(model : Model, auth : AuthStatus) -> Model {
  let recovering_session = match auth {
    SignedIn(..) => false
    AuthFailed(_) if model.last_authenticated_user_id is Some(_) => true
    _ => model.recovering_session
  }
  let login = match auth {
    SignedIn(login~, ..) => login
    Anonymous(_) if !recovering_session => None
    _ => model.review.login
  }
  let user_id = match auth {
    SignedIn(user_id~, ..) => user_id
    Anonymous(_) if !recovering_session => None
    _ => model.last_authenticated_user_id
  }
  let (review, _) = @comments.update(
    comment_session_context(
      if recovering_session && !model.recovering_session {
        @comments.update(model.review, RecoverInterrupted).0
      } else {
        model.review
      },
      comment_context(model),
    ),
    if auth is AuthChecking {
      IdentityChecking
    } else {
      Identity(
        auth is SignedIn(..) &&
        !(model.phase is ShowingPullSelector(_)) &&
        !model.route
        .map(reference => range_reference_parts(reference) is Some(_))
        .unwrap_or(false),
        login,
      )
    },
  )
  {
    ..model,
    auth,
    access: {
      ..model.access,
      identity_checking: auth is AuthChecking,
      freshness: if recovering_session && !model.recovering_session {
        Unavailable("Your GitHub session expired. Sign in again.")
      } else {
        model.access.freshness
      },
    },
    recovering_session,
    last_authenticated_user_id: user_id,
    review,
  }
}
