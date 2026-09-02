///|
const PULL_CHANGED_ERROR : String = "This pull request changed while it was loading. Please try again."

///|
const MAX_PULL_LOAD_ATTEMPT : Int = 1

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
      let shown = ensure_expanded_file_documents(
        view,
        model.diff_algorithm,
        ignore_comments=model.ignore_comments,
        ignore_tests=model.ignore_tests,
      )
      (
        with_phase(model, Showing(shown)),
        commands_for_change(view, model.generation, emit),
      )
    }
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
      with_phase(model, LoadFailed(@github.PULL_FILE_LIMIT_ERROR)),
      @rabbita.none,
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
fn begin_change_load(
  model : Model,
  reference : CommitRef,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let generation = model.generation + 1
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
  }
  (
    {
      ..model,
      input: canonical_github_url(reference),
      generation,
      phase,
      route: Some(reference),
      share_url: Some(playground_share_url(reference)),
      copy_status: CopyReady,
      file_tree: reset_file_tree_state(model.file_tree),
      review: if extension_host_enabled() {
        { auth: model.review.auth, comments: CommentsLoading, draft: None, }
      } else {
        model.review
      },
    },
    if extension_host_enabled() {
      @rabbita.batch([command, comments_request(reference, generation, emit)])
    } else {
      command
    },
  )
}
