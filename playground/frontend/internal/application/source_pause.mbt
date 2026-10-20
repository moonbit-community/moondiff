///|
fn pause_waiting_sources(model : Model) -> Model {
  guard model.source_pause is Some(_) &&
    model.phase is Showing(view) &&
    view.files.any(file => file.old_side is Loading || file.new_side is Loading) else {
    return model
  }
  with_phase(
    model,
    Showing({
      ..view,
      files: view.files.map(file => {
        if file.old_side is Loading || file.new_side is Loading {
          {
            ..file,
            old_side: if file.old_side is Loading {
              Paused
            } else {
              file.old_side
            },
            new_side: if file.new_side is Loading {
              Paused
            } else {
              file.new_side
            },
          }
        } else {
          file
        }
      }),
    }),
  )
}

///|
fn pause_source_loading(
  model : Model,
  reason : @github_client.RateLimitReason,
) -> Model {
  if reason is AnonymousRequests && model.auth is SignedIn(..) {
    return model
  }
  pause_waiting_sources({ ..model, source_pause: Some(reason), })
}

///|
fn load_failure(model : Model, error : Error) -> Model {
  let next = match @github_client.rate_limit_reason(error) {
    Some(reason) => pause_source_loading(model, reason)
    None => model
  }
  with_phase(next, LoadFailed(error_message(error, true)))
}

///|
fn resume_source_loading(
  model : Model,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  guard model.source_pause == Some(AnonymousRequests) &&
    model.auth is SignedIn(..) else {
    return (model, @rabbita.none)
  }
  let mut next = { ..model, source_pause: None, }
  if next.phase is Showing(view) {
    let urgent = []
    let files = view.files.mapi((index, file) => {
      if file.old_side is Paused || file.new_side is Paused {
        urgent.push(index)
        {
          ..file,
          old_side: if file.old_side is Paused {
            Loading
          } else {
            file.old_side
          },
          new_side: if file.new_side is Paused {
            Loading
          } else {
            file.new_side
          },
        }
      } else {
        file
      }
    })
    next = with_phase(
      {
        ..next,
        pull_sources: if view.reference.target is PullRequest(_) {
          let state = match next.pull_sources {
            Some(state) if state.generation == next.generation => state
            _ => PullSourceState::new(next.generation)
          }
          Some({
            ..state,
            urgent: state.urgent +
            urgent.filter(index => !state.urgent.contains(index)),
          })
        } else {
          None
        },
      },
      Showing({ ..view, files, }),
    )
    if !(view.reference.target is PullRequest(_)) {
      let (restored, command) = restore_page_requests(next, emit)
      return (
        restored,
        @rabbita.batch([
          @github_client.resume_anonymous_sources(model.generation),
          command,
        ]),
      )
    }
  }
  (next, @github_client.resume_anonymous_sources(model.generation))
}

///|
fn recover_anonymous_limit(
  model : Model,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  if model.route is Some(reference) &&
    reference.target is PullRequest(_) &&
    (model.phase is Showing(_) || model.phase is ShowingPullSelector(_)) {
    // Keep both schedulers paused until an independent version check succeeds.
    return (
      { ..model, access: { ..model.access, freshness: Checking, }, },
      shared_snapshot_request(
        reference,
        model.generation,
        emit,
        revalidate=true,
      ),
    )
  }
  resume_source_loading(model, emit)
}
