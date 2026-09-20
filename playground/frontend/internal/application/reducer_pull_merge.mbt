///|
pub(all) enum PullMergeMsg {
  Refresh
  Poll(Int, Int, Int)
  StatusLoaded(Int, Int, Result[@protocol.ApiPullMergeStatus, Error])
  Submit
  MergeFinished(Int, Int, Result[@protocol.ApiPullMergeResult, Error])
}

///|
fn pull_merge_failure_message(error : Error) -> String {
  match @github_client.http_error_code(error) {
    Some("authentication_required") =>
      "Your GitHub session expired. Sign in again before merging."
    Some("merge_permission_denied") =>
      "GitHub denied permission to merge this pull request."
    Some("merge_blocked") =>
      "Repository rules currently block this rebase merge."
    Some("merge_conflict") =>
      "This pull request has conflicts and cannot be rebased automatically."
    Some("mergeability_unknown") =>
      "GitHub is still calculating whether this pull request can be rebased."
    Some("pull_is_draft") =>
      "Mark this pull request ready for review before merging."
    Some("pull_closed") => "This pull request is closed."
    Some("pull_already_merged") => "This pull request is already merged."
    Some("merge_rejected") =>
      "GitHub rejected this rebase merge. Check repository rules and try again."
    Some("merge_upstream_failure") =>
      "GitHub could not complete the rebase merge. Try again."
    _ => comment_failure_message(error)
  }
}

///|
fn update_pull_merge(
  model : Model,
  msg : PullMergeMsg,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  guard pull_merge_scope(model) is Some((reference, number, base, head)) else {
    return (model, @rabbita.none)
  }
  match msg {
    Refresh => begin_pull_merge_refresh(model, emit)
    Poll(epoch, serial, retry) => {
      guard epoch == model.pull_merge.epoch &&
        serial == model.pull_merge.serial &&
        retry == model.pull_merge.retry &&
        model.pull_merge.poll_scheduled else {
        return (model, @rabbita.none)
      }
      begin_pull_merge_refresh(
        { ..model, pull_merge: { ..model.pull_merge, poll_scheduled: false, }, },
        emit,
        restart=false,
      )
    }
    StatusLoaded(epoch, serial, result) => {
      guard epoch == model.pull_merge.epoch &&
        serial == model.pull_merge.serial &&
        model.pull_merge.loading else {
        return (model, @rabbita.none)
      }
      let next = {
        ..model,
        pull_merge: { ..model.pull_merge, loading: false, },
      }
      match result {
        Err(error) =>
          if @github_client.http_error_code(error) ==
            Some("pull_snapshot_changed") {
            (stale_pull_merge(next), @rabbita.none)
          } else {
            let message = pull_merge_failure_message(error)
            let failed = {
              ..next,
              pull_merge: { ..next.pull_merge, error: Some(message), },
            }
            (
              if @github_client.http_error_code(error) ==
                Some("authentication_required") {
                with_auth(failed, AuthFailed(message))
              } else {
                failed
              },
              @rabbita.none,
            )
          }
        Ok(status) => {
          if status.base_sha != base || status.head_sha != head {
            return (stale_pull_merge(next), @rabbita.none)
          }
          schedule_pull_merge_refresh(
            {
              ..next,
              pull_merge: {
                ..next.pull_merge,
                status: Some(status),
                error: None,
              },
            },
            emit,
          )
        }
      }
    }
    Submit => {
      guard !model.pull_merge.loading &&
        !model.pull_merge.submitting &&
        !model.pull_merge.stale &&
        !model.review.snapshot_stale &&
        model.pull_merge.status is Some(status) &&
        status.base_sha == base &&
        status.head_sha == head &&
        pull_merge_actionable(status) &&
        model.auth is SignedIn(..) else {
        return (model, @rabbita.none)
      }
      let state = {
        ..model.pull_merge,
        serial: model.pull_merge.serial + 1,
        submitting: true,
        loading: false,
        poll_scheduled: false,
        error: None,
      }
      let next = { ..model, pull_merge: state, }
      (
        next,
        pull_rebase_merge_request(next, reference, number, base, head, emit),
      )
    }
    MergeFinished(epoch, serial, result) => {
      guard epoch == model.pull_merge.epoch &&
        serial == model.pull_merge.serial &&
        model.pull_merge.submitting else {
        return (model, @rabbita.none)
      }
      let next = {
        ..model,
        pull_merge: { ..model.pull_merge, submitting: false, },
      }
      match result {
        Ok({ merged: true, .. }) => {
          guard next.pull_merge.status is Some(status) else {
            return (next, @rabbita.none)
          }
          (
            {
              ..next,
              pull_merge: {
                ..next.pull_merge,
                status: Some({ ..status, open: false, merged: true, }),
                error: None,
                poll_scheduled: false,
              },
            },
            @rabbita.none,
          )
        }
        Ok(result) =>
          (
            {
              ..next,
              pull_merge: {
                ..next.pull_merge,
                error: Some(
                  if result.message.is_empty() {
                    "GitHub did not merge this pull request. Try again."
                  } else {
                    result.message
                  },
                ),
              },
            },
            @rabbita.none,
          )
        Err(error) => {
          let code = @github_client.http_error_code(error)
          if code == Some("pull_snapshot_changed") {
            return (stale_pull_merge(next), @rabbita.none)
          }
          let status = next.pull_merge.status.map(status => {
            match code {
              Some("merge_conflict") =>
                { ..status, mergeable: Some(false), rebaseable: Some(false), }
              Some("merge_blocked") => { ..status, mergeable_state: "blocked", }
              Some("mergeability_unknown") =>
                { ..status, mergeable: None, rebaseable: None, }
              Some("pull_is_draft") => { ..status, draft: true, }
              Some("pull_closed") => { ..status, open: false, }
              Some("pull_already_merged") =>
                { ..status, open: false, merged: true, }
              _ => status
            }
          })
          let failed = {
            ..next,
            pull_merge: {
              ..next.pull_merge,
              status,
              error: Some(pull_merge_failure_message(error)),
            },
          }
          let failed = if code == Some("authentication_required") {
            with_auth(failed, AuthFailed(pull_merge_failure_message(error)))
          } else {
            failed
          }
          if code == Some("mergeability_unknown") {
            schedule_pull_merge_refresh(failed, emit)
          } else {
            (failed, @rabbita.none)
          }
        }
      }
    }
  }
}

///|
fn reconcile_pull_merge(
  old : Model,
  model : Model,
  msg : Msg,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let old_scope = pull_merge_scope(old)
  let scope = pull_merge_scope(model)
  if old_scope != scope {
    let reset = {
      ..model,
      pull_merge: empty_pull_merge_state(old.pull_merge.epoch + 1),
    }
    return if scope is Some(_) {
      begin_pull_merge_refresh(reset, emit)
    } else {
      (reset, @rabbita.none)
    }
  }
  if model.review.snapshot_stale && !model.pull_merge.stale {
    return (
      {
        ..model,
        pull_merge: {
          ..model.pull_merge,
          loading: false,
          submitting: false,
          poll_scheduled: false,
          stale: true,
        },
      },
      @rabbita.none,
    )
  }
  if old.auth != model.auth {
    if model.auth is SignedIn(..) {
      return begin_pull_merge_refresh(model, emit)
    }
    if old.auth is SignedIn(..) {
      return (
        {
          ..model,
          pull_merge: empty_pull_merge_state(model.pull_merge.epoch + 1),
        },
        @rabbita.none,
      )
    }
  }
  if msg is Review(PageReactivated) {
    return begin_pull_merge_refresh(model, emit)
  }
  (model, @rabbita.none)
}
