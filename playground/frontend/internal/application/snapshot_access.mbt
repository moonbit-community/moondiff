///|
pub(all) enum SnapshotFreshness {
  Confirmed
  Checking
  Unavailable(String)
} derive(Eq)

///|
pub(all) struct SnapshotAccess {
  freshness : SnapshotFreshness
  identity_checking : Bool
  preparing : PreparedSnapshot?
  reload_requested : Bool
  waiting_for_viewed : Bool
} derive(Eq)

///|
pub(all) struct PreparedSnapshot {
  snapshot : @github_client.PullSnapshot
  view : ChangeView
} derive(Eq)

///|
pub fn SnapshotAccess::new() -> SnapshotAccess {
  {
    freshness: Confirmed,
    identity_checking: false,
    preparing: None,
    reload_requested: false,
    waiting_for_viewed: false,
  }
}

///|
pub fn snapshot_confirmed(model : Model) -> Bool {
  model.access.freshness is Confirmed &&
  !model.access.identity_checking &&
  model.access.preparing is None
}

///|
pub fn writes_allowed(model : Model) -> Bool {
  snapshot_confirmed(model) && model.auth is SignedIn(..)
}

///|
fn synchronize_snapshot_permission(model : Model) -> Model {
  let review = @comments.update(
      model.review,
      SnapshotFreshnessChanged(snapshot_confirmed(model)),
    ).0
  if @identity.same(review, model.review) {
    model
  } else {
    with_review(model, review)
  }
}

///|
fn shared_snapshot_request(
  reference : CommitRef,
  generation : Int32,
  emit : @rabbita.Emit[Msg],
  revalidate~ : Bool = false,
) -> @rabbita.Cmd {
  guard reference.target is PullRequest(number) else { return @rabbita.none }
  @github_client.load_pull_snapshot(
    { owner: reference.owner, repo: reference.repo, number, },
    generation,
    result => emit(Load(SharedSnapshotLoaded(generation, result))),
    revalidate~,
  )
}

///|
fn request_latest_snapshot(
  model : Model,
  reference : CommitRef,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  (
    {
      ..model,
      access: {
        ..model.access,
        freshness: Checking,
        preparing: None,
        reload_requested: true,
        waiting_for_viewed: false,
      },
    },
    shared_snapshot_request(reference, model.generation, emit, revalidate=true),
  )
}

///|
fn resume_waiting_snapshot(
  model : Model,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  guard model.access.waiting_for_viewed &&
    !snapshot_replacement_blocked(model) &&
    @comments.permission(model.review, LoadSnapshot).allowed() &&
    model.route is Some(reference) &&
    reference.target is PullRequest(_) &&
    model.phase is Showing(_) else {
    return (model, @rabbita.none)
  }
  // Consume the intent before issuing the request, so later reads cannot
  // start another replacement while this one is being prepared.
  request_latest_snapshot(model, reference, emit)
}

///|
fn receive_shared_snapshot(
  model : Model,
  generation : Int32,
  result : Result[@github_client.SnapshotResult, Error],
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  guard generation == model.generation &&
    model.route is Some(reference) &&
    reference.target is PullRequest(_) else {
    return (model, @rabbita.none)
  }
  match result {
    Err(error) => {
      let model = match @github_client.rate_limit_reason(error) {
        Some(reason) => pause_source_loading(model, reason)
        None => model
      }
      let message = error_message(error, true)
      if model.phase is Showing(_) || model.phase is ShowingPullSelector(_) {
        (
          {
            ..model,
            access: {
              ..model.access,
              freshness: Unavailable(message),
              preparing: None,
            },
          },
          @rabbita.none,
        )
      } else {
        (with_phase(model, LoadFailed(message)), @rabbita.none)
      }
    }
    Ok(result) => {
      let snapshot = result.snapshot
      let next = {
        ..model,
        access: {
          ..model.access,
          preparing: None,
          freshness: if result.confirmed {
            Confirmed
          } else {
            Checking
          },
        },
      }
      if model.phase is Showing(view) &&
        comment_context(model).snapshot is Some(current) &&
        current.same_version({
          reference,
          sha: snapshot.metadata.head.sha,
          pull_snapshot: Some(snapshot.metadata),
        }) &&
        view.old_revision.map(old => old.sha) ==
        Some(snapshot.comparison.merge_base_commit.sha) {
        if result.confirmed && model.access.reload_requested {
          if snapshot_replacement_blocked(model) {
            return retain_previous_snapshot(model)
          }
          return install_snapshot(
            next,
            snapshot,
            Some({
              ..view,
              message: snapshot.metadata.title,
              html_url: snapshot.metadata.html_url,
              stats: @github.pull_stats(snapshot.metadata),
              pull_snapshot: Some(snapshot.metadata),
            }),
            emit,
          )
        }
        let shown = with_phase(
          {
            ..next,
            range: next.range.map(state => {
              ..state,
              pull: Some(snapshot.metadata),
            }),
          },
          Showing({
            ..view,
            message: snapshot.metadata.title,
            html_url: snapshot.metadata.html_url,
            stats: @github.pull_stats(snapshot.metadata),
            pull_snapshot: Some(snapshot.metadata),
          }),
        )
        return if result.confirmed {
          resume_source_loading(shown, emit)
        } else {
          (shown, @rabbita.none)
        }
      }
      // Keep the generation that owns validation and the current commit choices.
      if model.phase is ShowingPullSelector(pull) &&
        @github.same_pull_snapshot(pull, snapshot.metadata) &&
        model.range is Some(state) &&
        state.pull_merge_base == Some(snapshot.comparison.merge_base_commit.sha) {
        if result.confirmed && model.access.reload_requested {
          if snapshot_replacement_blocked(model) {
            return retain_previous_snapshot(model)
          }
          return install_snapshot(next, snapshot, None, emit)
        }
        let shown = with_phase(
          { ..next, range: Some({ ..state, pull: Some(snapshot.metadata), }), },
          ShowingPullSelector(snapshot.metadata),
        )
        return if result.confirmed {
          resume_source_loading(shown, emit)
        } else {
          (shown, @rabbita.none)
        }
      }
      let replacing = model.phase is Showing(_) ||
        model.phase is ShowingPullSelector(_)
      if replacing {
        // A retained version can paint, but cannot replace a different shown
        // version until its independent metadata confirmation has completed.
        if !result.confirmed {
          return (model, @rabbita.none)
        }
        return prepare_snapshot_replacement(model, snapshot, emit)
      }
      install_snapshot(next, snapshot, None, emit)
    }
  }
}

///|
fn install_snapshot(
  model : Model,
  snapshot : @github_client.PullSnapshot,
  prepared : ChangeView?,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  guard model.route is Some(reference) else { return (model, @rabbita.none) }
  let replacing = model.phase is Showing(_) ||
    model.phase is ShowingPullSelector(_)
  let next = {
    ..model,
    source_pause: if replacing &&
      model.auth is SignedIn(..) &&
      model.source_pause == Some(AnonymousRequests) {
      None
    } else {
      model.source_pause
    },
    access: {
      ..model.access,
      freshness: if replacing {
        Confirmed
      } else {
        model.access.freshness
      },
      preparing: None,
      reload_requested: false,
      waiting_for_viewed: false,
    },
  }
  let next = if replacing {
    let saved = save_route_memory(next)
    let generation = saved.generation + 1
    let reset = comment_session_context(initial_review_state(), {
      generation,
      route: Some(reference),
      snapshot: None,
      enabled: true,
    })
    let login = match saved.auth {
      SignedIn(login~, ..) => login
      _ => None
    }
    let review = @comments.update(
        reset,
        if saved.access.identity_checking {
          IdentityChecking
        } else {
          Identity(saved.auth is SignedIn(..), login)
        },
      ).0
    {
      ..saved,
      generation,
      review,
      range: None,
      file_tree: reset_file_tree_state(saved.file_tree),
      navigation: {
        ..saved.navigation,
        restore_data: true,
        restore_position: true,
      },
    }
  } else {
    next
  }
  let (shown, command) = if snapshot.metadata.changed_files >
    @github.MAX_PULL_FILES {
    show_pull_selector(next, snapshot.metadata, snapshot.comparison, emit)
  } else {
    match prepared {
      Some(view) => show_pull_view(next, view, snapshot.metadata, emit)
      None =>
        show_pull(
          next,
          reference,
          snapshot.metadata,
          snapshot.comparison,
          snapshot.files,
          emit,
        )
    }
  }
  (
    shown,
    if replacing {
      @rabbita.batch([
        @github_client.cancel_before(shown.generation),
        @github_client.resume_anonymous_sources(shown.generation),
        command,
      ])
    } else {
      command
    },
  )
}
