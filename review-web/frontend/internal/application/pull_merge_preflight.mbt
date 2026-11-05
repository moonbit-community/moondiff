///|
// Only a response to an explicit merge click may proceed to the write. Ordinary
// refreshes and polls can update the card, but can never submit a merge.
fn finish_pull_merge_preflight(
  model : Model,
  epoch : Int32,
  serial : Int32,
  result : Result[@protocol.ApiPullMergeStatus, Error],
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  guard epoch == model.pull_merge.epoch &&
    serial == model.pull_merge.serial &&
    model.pull_merge.submitting &&
    pull_merge_scope(model) is Some((reference, number, base, head)) else {
    return (model, @rabbita.none)
  }
  let next = {
    ..model,
    pull_merge: { ..model.pull_merge, submitting: false, },
  }
  match result {
    Err(error) => {
      if @github_client.http_error_code(error) == Some("pull_snapshot_changed") {
        return (stale_pull_merge(next), @rabbita.none)
      }
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
      let checked = {
        ..next,
        pull_merge: { ..next.pull_merge, status: Some(status), error: None, },
      }
      guard writes_allowed(checked) &&
        !checked.pull_merge.stale &&
        !checked.review.snapshot_stale &&
        pull_merge_actionable(status) else {
        return schedule_pull_merge_refresh(checked, emit)
      }
      // CI is informational here. The backend re-reads the PR before calling
      // GitHub's merge endpoint, which enforces the repository's required checks.
      // Advance the serial so a duplicate preflight response cannot write twice.
      let submitting = {
        ..checked,
        pull_merge: {
          ..checked.pull_merge,
          serial: checked.pull_merge.serial + 1,
          submitting: true,
        },
      }
      (
        submitting,
        pull_rebase_merge_request(
          submitting, reference, number, base, head, emit,
        ),
      )
    }
  }
}
