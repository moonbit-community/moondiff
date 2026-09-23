///|
const PULL_CHANGED_ERROR : String = "This pull request changed while it was loading. Please try again."

///|
const MAX_PULL_LOAD_ATTEMPT : Int = 1

///|
fn pull_range_state(pull : ApiPull, merge_base : String) -> RangeState {
  {
    ..range_state(merge_base, pull.head.sha, Some(pull)),
    loading_page: None,
    next_page: if pull.commits == Some(0) {
      None
    } else {
      Some(1)
    },
    total_commits: pull.commits.unwrap_or(0),
    pull_merge_base: Some(merge_base),
  }
}

///|
fn auto_load_pull_commits(pull : ApiPull) -> Bool {
  match pull.commits {
    Some(count) => count > 0 && count <= 250
    None => true
  }
}

///|
fn show_pull(
  model : Model,
  reference : CommitRef,
  pull : ApiPull,
  compare : ApiCompare,
  files : Array[ApiFile],
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  match finish_pull(reference, pull, compare, files) {
    Err(message) => (with_phase(model, LoadFailed(message)), @rabbita.none)
    Ok(view) => {
      let base = view.old_revision.map(r => r.sha).unwrap_or(pull.base.sha)
      let range = pull_range_state(pull, base)
      let shown = ensure_expanded_file_documents(
        view,
        model.diff_algorithm,
        ignore_comments=model.ignore_comments,
        ignore_tests=model.ignore_tests,
      )
      let ready = with_phase({ ..model, range: Some(range), }, Showing(shown))
      let (next, commit_command) = if auto_load_pull_commits(pull) {
        update_range(ready, LoadMore, emit)
      } else {
        (ready, @rabbita.none)
      }
      (
        next,
        @rabbita.batch([
          commands_for_change(view, model.generation, emit),
          comments_request(reference, model.generation, emit),
          commit_command,
        ]),
      )
    }
  }
}

///|
fn show_pull_selector(
  model : Model,
  pull : ApiPull,
  compare : ApiCompare,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let range = pull_range_state(pull, compare.merge_base_commit.sha)
  let ready = with_phase(
    { ..model, range: Some(range), },
    ShowingPullSelector(pull),
  )
  if auto_load_pull_commits(pull) {
    update_range(ready, LoadMore, emit)
  } else {
    (ready, @rabbita.none)
  }
}

///|
fn start_pull_snapshot(
  model : Model,
  reference : CommitRef,
  attempt : Int,
  metadata : ApiPull,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  if metadata.changed_files > @github.MAX_PULL_FILES {
    return (
      with_phase(
        model,
        LoadingPullSelectorCompare(reference~, attempt~, metadata~),
      ),
      pull_compare_request(
        reference,
        metadata.base.sha,
        metadata.head.sha,
        model.generation,
        attempt,
        emit,
      ),
    )
  }
  (
    with_phase(
      model,
      LoadingPullSnapshot(
        reference~,
        attempt~,
        metadata~,
        compare=None,
        page=1,
        files=[],
      ),
    ),
    @rabbita.batch([
      pull_compare_request(
        reference,
        metadata.base.sha,
        metadata.head.sha,
        model.generation,
        attempt,
        emit,
      ),
      pull_files_request(reference, model.generation, attempt, 1, emit),
    ]),
  )
}

///|
fn continue_pull_snapshot(
  model : Model,
  reference : CommitRef,
  attempt : Int,
  metadata : ApiPull,
  compare : ApiCompare?,
  page : Int,
  files : Array[ApiFile],
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let loading = LoadingPullSnapshot(
    reference~,
    attempt~,
    metadata~,
    compare~,
    page~,
    files~,
  )
  guard compare is Some(loaded_compare) && page == 0 else {
    return (with_phase(model, loading), @rabbita.none)
  }
  (
    with_phase(
      model,
      ValidatingPullSnapshot(
        reference~,
        attempt~,
        metadata~,
        compare=loaded_compare,
        files~,
      ),
    ),
    pull_validation_request(reference, model.generation, attempt, emit),
  )
}

///|
fn validate_or_retry_pull_snapshot(
  model : Model,
  reference : CommitRef,
  attempt : Int,
  metadata : ApiPull,
  compare : ApiCompare,
  files : Array[ApiFile],
  verified : ApiPull,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  if !same_pull_snapshot(metadata, verified) {
    if attempt < MAX_PULL_LOAD_ATTEMPT {
      return start_pull_snapshot(model, reference, attempt + 1, verified, emit)
    }
    return (with_phase(model, LoadFailed(PULL_CHANGED_ERROR)), @rabbita.none)
  }
  match validate_pull_files(verified, files) {
    Err(message) =>
      if attempt < MAX_PULL_LOAD_ATTEMPT {
        start_pull_snapshot(model, reference, attempt + 1, verified, emit)
      } else {
        (with_phase(model, LoadFailed(message)), @rabbita.none)
      }
    Ok(_) => show_pull(model, reference, verified, compare, files, emit)
  }
}

///|
fn validate_or_retry_pull_selector(
  model : Model,
  reference : CommitRef,
  attempt : Int,
  metadata : ApiPull,
  compare : ApiCompare,
  verified : ApiPull,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  if !same_pull_snapshot(metadata, verified) {
    if attempt < MAX_PULL_LOAD_ATTEMPT {
      return start_pull_snapshot(model, reference, attempt + 1, verified, emit)
    }
    return (with_phase(model, LoadFailed(PULL_CHANGED_ERROR)), @rabbita.none)
  }
  show_pull_selector(model, verified, compare, emit)
}

///|
fn begin_change_load(
  model : Model,
  reference : CommitRef,
  emit : @rabbita.Emit[Msg],
  preserve_draft? : Bool = false,
) -> (Model, @rabbita.Cmd) {
  let generation = model.generation + 1
  let range = range_reference_parts(reference).map(pair => {
    let (base, head) = pair
    range_state(base, head, None)
  })
  let (phase, command) = match reference.target {
    Commit(_) => {
      let repository = reference_repository(reference)
      (
        LoadingCommit(reference~, repository~, page=1, first=None, files=[]),
        commit_request(reference, repository, generation, 1, emit),
      )
    }
    PullRequest(_) =>
      (
        LoadingPullMetadata(reference~, attempt=0),
        pull_metadata_request(reference, generation, 0, emit),
      )
    PullCommit(_, _) =>
      (
        LoadingPullCommitMetadata(reference~),
        pull_commit_metadata_request(reference, generation, emit),
      )
    Range(base, head) =>
      (
        LoadingRange(reference~),
        range_start_resolution(
          reference,
          range_state(base, head, None),
          generation,
          emit,
        ),
      )
    PullRange(number, _, _) =>
      (
        LoadingRangePullMetadata(reference~),
        @github_client.get_pull(
          { owner: reference.owner, repo: reference.repo, number, },
          generation,
          result => emit(Range(RangePullLoaded(generation, result))),
        ),
      )
  }
  let reset_review = @comments.update(
      comment_session_context(model.review, {
        generation,
        route: Some(reference),
        snapshot: None,
        enabled: range is None,
      }),
      Reset(range is None, preserve_draft),
    ).0
  let login = match model.auth {
    SignedIn(login~, ..) => login
    _ => None
  }
  let review = @comments.update(
      reset_review,
      if model.auth is AuthChecking {
        IdentityChecking
      } else {
        Identity(model.auth is SignedIn(..) && range is None, login)
      },
    ).0
  (
    {
      ..model,
      input: canonical_github_url(reference),
      generation,
      restore_pending: false,
      phase,
      route: Some(reference),
      range,
      file_tree: reset_file_tree_state(model.file_tree),
      review,
    },
    if range is Some(_) {
      @rabbita.batch([@github_client.cancel_before(generation), command])
    } else if !(reference.target is PullRequest(_)) {
      @rabbita.batch([
        @github_client.cancel_before(generation),
        command,
        comments_request(reference, generation, emit),
      ])
    } else {
      @rabbita.batch([@github_client.cancel_before(generation), command])
    },
  )
}
