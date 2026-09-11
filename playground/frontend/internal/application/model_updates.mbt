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
  {
    ..model,
    review,
    auth: if review.authentication_error is Some(message) &&
      auth_device_id(model.auth) is None {
      AuthFailed(message)
    } else {
      model.auth
    },
  }
}

///|
fn with_auth(model : Model, auth : AuthStatus) -> Model {
  let login = match auth {
    SignedIn(login~, ..) => login
    Anonymous(_) => None
    _ => model.review.login
  }
  let user_id = match auth {
    SignedIn(user_id~, ..) => user_id
    Anonymous(_) => None
    _ => model.last_authenticated_user_id
  }
  let (review, _) = @comments.update(
    comment_session_context(model.review, comment_context(model)),
    if auth is AuthChecking {
      IdentityChecking
    } else {
      Identity(auth is SignedIn(..), login)
    },
  )
  { ..model, auth, last_authenticated_user_id: user_id, review, }
}
