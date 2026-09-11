///|
pub(all) enum ViewedMsg {
  Toggle(Int, Int)
  Refresh
  Restored(Int, Int, Result[Array[ViewedRecord], String])
  Stored(Int, Int, ViewedRecord, Bool)
  StorageFailed(Int)
  Check(Int, Int, Int)
  Loaded(Int, Int, Result[@protocol.ApiPullViewed, Error])
  Saved(Int, Int, String, Result[@protocol.ApiFileViewedResult, Error])
}

///|
fn viewed_result_matches(model : Model, base : String, head : String) -> Bool {
  model.phase is Showing({ pull_snapshot: Some(snapshot), .. }) &&
  snapshot.base.sha == base &&
  snapshot.head.sha == head
}

///|
fn update_viewed(
  model : Model,
  msg : ViewedMsg,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  // Storage completion can arrive after navigation/logout. Only remove its own
  // unsent operation; it must never send a write under the new identity.
  if msg is Stored(epoch, _, record, ok) &&
    (epoch != model.viewed.epoch || viewed_scope(model) is None) {
    return (
      model,
      if ok {
        viewed_forget(model, record, emit)
      } else {
        @rabbita.none
      },
    )
  }
  guard viewed_scope(model) is Some(_) else { return (model, @rabbita.none) }
  match msg {
    Refresh => begin_viewed_refresh(model, emit)
    Check(epoch, serial, retry) => {
      guard epoch == model.viewed.epoch &&
        serial == model.viewed.serial &&
        retry == model.viewed.retry &&
        model.viewed.poll_scheduled &&
        viewed_confirming(model.viewed) else {
        return (model, @rabbita.none)
      }
      begin_viewed_refresh(
        { ..model, viewed: { ..model.viewed, poll_scheduled: false, }, },
        emit,
        restart=false,
      )
    }
    StorageFailed(epoch) => {
      if epoch != model.viewed.epoch {
        return (model, @rabbita.none)
      }
      (
        {
          ..model,
          viewed: {
            ..model.viewed,
            storage_ready: false,
            loading: false,
            serial: model.viewed.serial + 1,
            poll_scheduled: false,
            refresh_needed: false,
            error: Some(
              "Cannot clear a completed Viewed change from session storage. Restore storage access and recheck Viewed.",
            ),
          },
        },
        @rabbita.none,
      )
    }
    Restored(epoch, serial, result) => {
      guard epoch == model.viewed.epoch &&
        serial == model.viewed.serial &&
        model.viewed.loading &&
        !model.viewed.storage_ready else {
        return (model, @rabbita.none)
      }
      let next = { ..model, viewed: { ..model.viewed, loading: false, }, }
      match result {
        Err(message) =>
          (
            { ..next, viewed: { ..next.viewed, error: Some(message), }, },
            @rabbita.none,
          )
        Ok(records) =>
          begin_viewed_refresh(restore_viewed_records(next, records), emit)
      }
    }
    Stored(epoch, index, record, ok) => {
      guard epoch == model.viewed.epoch &&
        model.viewed.files.get(index) is Some(file) &&
        file.pending is Some(pending) &&
        pending.record.id == record.id &&
        !pending.stored &&
        !pending.confirming else {
        return (model, @rabbita.none)
      }
      if !ok || model.viewed.stale || model.review.snapshot_stale {
        let (next, rollback) = rollback_viewed(
          model,
          index,
          file,
          pending,
          if ok {
            "PR updated before this Viewed change was sent. Load the latest PR."
          } else {
            "Cannot save this Viewed change in session storage. No request was sent. Restore storage access and recheck Viewed."
          },
          emit,
        )
        let (next, check) = finish_viewed_work(next, emit)
        return (
          next,
          @rabbita.batch([rollback, check, viewed_forget(next, record, emit)]),
        )
      }
      let next = with_viewed_file(model, index, {
        ..file,
        pending: Some({ ..pending, stored: true, }),
      })
      (next, viewed_write_request(next, index, record, emit))
    }
    Toggle(generation, index) => {
      guard generation == model.generation &&
        !model.viewed.stale &&
        !model.review.snapshot_stale &&
        model.viewed.ready &&
        model.viewed.storage_ready &&
        model.viewed.files.get(index) is Some(file) &&
        file.pending is None &&
        file.state is Some(before) &&
        model.phase is Showing(view) &&
        view.reference.target is PullRequest(number) &&
        view.pull_snapshot is Some(snapshot) &&
        model.auth is SignedIn(user_id=Some(user_id), ..) else {
        return (model, @rabbita.none)
      }
      let desired = before != @protocol.FileViewedState::Viewed
      let record : ViewedRecord = {
        id: new_auth_attempt_id(),
        user_id,
        owner: view.reference.owner,
        repo: view.reference.repo,
        number,
        path: view.files[index].file.filename,
        viewed: desired,
        base_sha: snapshot.base.sha,
        head_sha: snapshot.head.sha,
      }
      let next = with_viewed_file(
        {
          ..model,
          viewed: {
            ..model.viewed,
            serial: model.viewed.serial + 1,
            poll_scheduled: false,
            refresh_needed: model.viewed.refresh_needed ||
            model.viewed.loading ||
            model.viewed.poll_scheduled,
          },
        },
        index,
        {
          ..file,
          state: Some(record.target()),
          error: None,
          pending: Some({
            record,
            stored: false,
            before,
            expanded: view.files[index].expanded,
            expansion_revision: file.expansion_revision,
            confirming: false,
          }),
        },
      )
      let (next, expansion) = viewed_expansion(next, index, !desired, emit)
      (
        next,
        @rabbita.batch([
          expansion,
          viewed_persist_request(next, index, record, emit),
        ]),
      )
    }
    Loaded(epoch, serial, result) => {
      guard epoch == model.viewed.epoch &&
        serial == model.viewed.read_serial &&
        model.viewed.loading &&
        model.viewed.storage_ready else {
        return (model, @rabbita.none)
      }
      let next = { ..model, viewed: { ..model.viewed, loading: false, }, }
      if serial != model.viewed.serial || viewed_writing(model.viewed) {
        return begin_viewed_refresh(next, emit, restart=false)
      }
      match result {
        Err(error) =>
          schedule_viewed_check(
            viewed_error(
              {
                ..next,
                viewed: {
                  ..next.viewed,
                  error: Some(comment_failure_message(error)),
                  retry: if viewed_rate_limited(error) {
                    6
                  } else {
                    next.viewed.retry
                  },
                },
              },
              error,
            ),
            emit,
          )
        Ok(data) => apply_viewed_read(next, data, emit)
      }
    }
    Saved(epoch, index, id, result) => {
      guard epoch == model.viewed.epoch &&
        model.viewed.files.get(index) is Some(file) &&
        file.pending is Some(pending) &&
        pending.record.id == id &&
        pending.stored &&
        !pending.confirming else {
        return (model, @rabbita.none)
      }
      let next = {
        ..model,
        viewed: {
          ..model.viewed,
          serial: model.viewed.serial + 1,
          poll_scheduled: false,
          refresh_needed: model.viewed.refresh_needed ||
          model.viewed.loading ||
          model.viewed.poll_scheduled,
        },
      }
      let uncertain = with_viewed_file(next, index, {
        ..file,
        pending: Some({ ..pending, confirming: true, }),
      })
      let (next, command) = match result {
        Ok(data) => {
          if !viewed_result_matches(next, data.base_sha, data.head_sha) {
            return (stale_viewed(uncertain), @rabbita.none)
          }
          if data.file.path != pending.record.path ||
            data.file.state != pending.record.target() {
            return begin_viewed_refresh(uncertain, emit)
          }
          (
            with_viewed_file(next, index, { ..file, pending: None, }),
            viewed_forget(next, pending.record, emit),
          )
        }
        Err(error) => {
          if @github_client.http_error_code(error) ==
            Some("pull_snapshot_changed") {
            return (stale_viewed(uncertain), @rabbita.none)
          }
          if viewed_uncertain(error) {
            return begin_viewed_refresh(uncertain, emit)
          }
          let (rolled, expansion) = rollback_viewed(
            next,
            index,
            file,
            pending,
            comment_failure_message(error),
            emit,
          )
          (
            viewed_error(rolled, error),
            @rabbita.batch([
              expansion,
              viewed_forget(next, pending.record, emit),
            ]),
          )
        }
      }
      let (next, check) = finish_viewed_work(next, emit)
      (next, @rabbita.batch([command, check]))
    }
  }
}

///|
fn rollback_viewed(
  model : Model,
  index : Int,
  file : ViewedFile,
  pending : ViewedPending,
  message : String,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let next = with_viewed_file(model, index, {
    ..file,
    state: Some(pending.before),
    pending: None,
    error: Some(message),
  })
  if file.expansion_revision == pending.expansion_revision {
    viewed_expansion(next, index, pending.expanded, emit)
  } else {
    (next, @rabbita.none)
  }
}

///|
fn apply_viewed_read(
  model : Model,
  data : @protocol.ApiPullViewed,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  if !viewed_result_matches(model, data.base_sha, data.head_sha) {
    return (stale_viewed(model), @rabbita.none)
  }
  guard model.phase is Showing(view) else { return (model, @rabbita.none) }
  let states : Map[String, @protocol.FileViewedState] = Map([])
  for file in data.files {
    states[file.path] = file.state
  }
  guard states.length() == data.files.length() &&
    states.length() == view.files.length() &&
    view.files.all(file => states.contains(file.file.filename)) else {
    return schedule_viewed_check(
      {
        ..model,
        viewed: {
          ..model.viewed,
          error: Some(
            "GitHub returned an incomplete Viewed file list. Retry syncing Viewed.",
          ),
        },
      },
      emit,
    )
  }
  let mut next = model
  let commands = []
  let draft_file = viewed_draft_file(next)
  for index, file in view.files {
    let old = next.viewed.files[index]
    let state = states[file.file.filename]
    if old.pending is Some(pending) {
      // An old value is not evidence of rejection: GitHub can finish a timed-out
      // mutation later. Keep the target, expansion and draft until it matches.
      if state == pending.record.target() {
        commands.push(viewed_forget(next, pending.record, emit))
        next = with_viewed_file(next, index, {
          ..old,
          state: Some(state),
          pending: None,
          error: None,
        })
      }
      continue
    }
    if !model.viewed.ready &&
      !old.touched &&
      draft_file != Some(index) &&
      state is Viewed {
      let (collapsed, command) = viewed_expansion(next, index, false, emit)
      next = collapsed
      commands.push(command)
    }
    next = with_viewed_file(next, index, {
      ..old,
      state: Some(state),
      error: None,
    })
  }
  let (next, check) = schedule_viewed_check(
    { ..next, viewed: { ..next.viewed, ready: true, error: None, }, },
    emit,
  )
  commands.push(check)
  (next, @rabbita.batch(commands))
}

///|
fn finish_viewed_work(
  model : Model,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  if model.viewed.refresh_needed {
    begin_viewed_refresh(model, emit, restart=false)
  } else {
    schedule_viewed_check(model, emit)
  }
}
