///|
fn begin_pull_merge_refresh(
  model : Model,
  emit : @rabbita.Emit[Msg],
  restart? : Bool = true,
) -> (Model, @rabbita.Cmd) {
  guard pull_merge_scope(model) is Some((reference, number, base, head)) &&
    model.auth is SignedIn(..) &&
    !model.pull_merge.loading &&
    !model.pull_merge.submitting &&
    !model.pull_merge.stale &&
    !model.review.snapshot_stale else {
    return (model, @rabbita.none)
  }
  let previous = if restart {
    { ..model.pull_merge, retry: 0, poll_scheduled: false, }
  } else {
    model.pull_merge
  }
  let state = {
    ..previous,
    serial: previous.serial + 1,
    loading: true,
    poll_scheduled: false,
    error: None,
  }
  let next = { ..model, pull_merge: state, }
  (
    next,
    @github_client.get_pull_merge_status(
      {
        owner: reference.owner,
        repo: reference.repo,
        number,
        expected_base_sha: base,
        expected_head_sha: head,
      },
      model.generation,
      result => emit(PullMerge(StatusLoaded(state.epoch, state.serial, result))),
    ),
  )
}

///|
fn schedule_pull_merge_refresh(
  model : Model,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let delays = [2000, 4000, 8000, 16000, 30000, 30000]
  guard pull_merge_scope(model) is Some(_) &&
    model.pull_merge.status is Some(status) &&
    pull_merge_status_pending(status) &&
    !model.pull_merge.loading &&
    !model.pull_merge.submitting &&
    !model.pull_merge.stale &&
    !model.review.snapshot_stale &&
    !model.pull_merge.poll_scheduled &&
    model.pull_merge.retry < delays.length() else {
    return (model, @rabbita.none)
  }
  let delay = delays[model.pull_merge.retry]
  let state = {
    ..model.pull_merge,
    retry: model.pull_merge.retry + 1,
    poll_scheduled: true,
  }
  (
    { ..model, pull_merge: state, },
    @rabbita.delay(
      emit(PullMerge(Poll(state.epoch, state.serial, state.retry))),
      delay,
    ),
  )
}

///|
fn pull_rebase_merge_request(
  model : Model,
  reference : CommitRef,
  number : String,
  base : String,
  head : String,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  @github_client.rebase_merge_pull(
    {
      owner: reference.owner,
      repo: reference.repo,
      number,
      expected_base_sha: base,
      expected_head_sha: head,
    },
    model.generation,
    result => {
      emit(
        PullMerge(
          MergeFinished(model.pull_merge.epoch, model.pull_merge.serial, result),
        ),
      )
    },
  )
}
