///|
pub(all) enum RangeMsg {
  FromSelected(String)
  ToSelected(String)
  ToggleCommits
  LoadMore
  CopyLink
  RangePullLoaded(Int, Result[ApiPull, Error])
  RangePullCompareLoaded(Int, Result[ApiCompare, Error])
  RangeShaResolved(Int, Bool, Bool, Result[String, Error])
  RangePageLoaded(Int, Int, Result[ApiRangeCompare, Error])
  RangePullCommitPageLoaded(
    Int,
    Int,
    Result[Array[@protocol.ApiRangeCommit], Error]
  )
  RangePullCommitPageValidated(
    Int,
    Int,
    Array[@protocol.ApiRangeCommit],
    Result[ApiPull, Error]
  )
}

///|
fn range_resolve_request(
  repository : RepositoryRef,
  sha : String,
  is_base : Bool,
  fork_attempt : Bool,
  generation : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  @github_client.resolve_sha(
    { owner: repository.owner, repo: repository.repo, sha, },
    generation,
    result => {
      emit(Range(RangeShaResolved(generation, is_base, fork_attempt, result)))
    },
  )
}

///|
fn range_start_resolution(
  reference : CommitRef,
  state : RangeState,
  generation : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  let repository = reference_repository(reference)
  if !range_full_sha(state.base_sha) {
    return range_resolve_request(
      repository,
      state.base_sha,
      true,
      false,
      generation,
      emit,
    )
  }
  if !range_full_sha(state.head_sha) {
    return range_resolve_request(
      repository,
      state.head_sha,
      false,
      false,
      generation,
      emit,
    )
  }
  range_compare_request(
    reference,
    state.base_sha,
    state.head_sha,
    1,
    generation,
    emit,
  )
}

///|
fn range_page_failure(
  model : Model,
  state : RangeState,
  message : String,
) -> (Model, @rabbita.Cmd) {
  if model.phase is LoadingRange(_) {
    (with_phase(model, LoadFailed(message)), @rabbita.none)
  } else {
    (
      {
        ..model,
        range: Some({ ..state, loading_page: None, error: Some(message), }),
      },
      @rabbita.none,
    )
  }
}

///|
fn pull_commit_page_error(
  state : RangeState,
  page : Int,
  items : Array[@protocol.ApiRangeCommit],
  verified : ApiPull,
) -> String? {
  guard state.pull is Some(snapshot) &&
    snapshot.commits is Some(total) &&
    total >= 0 &&
    total <= 250 else {
    return Some("Pull request commit count is unavailable. Refresh this PR.")
  }
  if !same_pull_snapshot(snapshot, verified) {
    return Some(
      "This pull request changed while it was loading. Refresh this PR.",
    )
  }
  if page != state.commits.length() / 100 + 1 ||
    items.length() != Int::min(100, total - state.commits.length()) {
    return Some(
      "GitHub returned an incomplete PR commit list. Refresh this PR.",
    )
  }
  for index, item in items {
    if !range_full_sha(item.sha) ||
      state.commits
      .iter()
      .any(previous => previous.sha.to_lower() == item.sha.to_lower()) ||
      items[:index]
      .iter()
      .any(previous => previous.sha.to_lower() == item.sha.to_lower()) {
      return Some("GitHub returned an invalid PR commit list. Refresh this PR.")
    }
  }
  if state.commits.length() + items.length() == total &&
    total > 0 &&
    items[items.length() - 1].sha.to_lower() != snapshot.head.sha.to_lower() {
    return Some("GitHub returned a different PR head. Refresh this PR.")
  }
  None
}

///|
fn accept_pull_commit_page(
  state : RangeState,
  page : Int,
  items : Array[@protocol.ApiRangeCommit],
) -> RangeState {
  let commits = state.commits.copy()
  for item in items {
    commits.push(item)
  }
  let total = state.pull.unwrap().commits.unwrap()
  {
    ..state,
    commits,
    linear_commits: if commits.length() == total {
      pull_linear_chain(state.base_sha, state.head_sha, commits)
    } else {
      None
    },
    total_commits: total,
    next_page: if commits.length() < total {
      Some(page + 1)
    } else {
      None
    },
    loading_page: None,
    error: None,
  }
}

///|
fn range_compare_request(
  reference : CommitRef,
  base : String,
  head : String,
  page : Int,
  generation : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  @github_client.get_range_compare(
    { owner: reference.owner, repo: reference.repo, base, head, page, },
    generation,
    result => emit(Range(RangePageLoaded(generation, page, result))),
  )
}

///|
fn range_commit_page_request(
  reference : CommitRef,
  state : RangeState,
  page : Int,
  generation : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  match (reference.target, state.pull) {
    (PullRequest(number), Some(pull)) if pull.commits is Some(count) &&
      count <= 250 =>
      @github_client.get_pull_commit_page(
        { owner: reference.owner, repo: reference.repo, number, page, },
        generation,
        result => {
          emit(Range(RangePullCommitPageLoaded(generation, page, result)))
        },
      )
    _ =>
      range_compare_request(
        reference,
        state.base_sha,
        state.head_sha,
        page,
        generation,
        emit,
      )
  }
}

///|
fn range_page_loaded(
  model : Model,
  state : RangeState,
  page : Int,
  result : Result[ApiRangeCompare, Error],
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let failure = match result {
    Err(error) => Some(error_message(error, true))
    Ok(data) => range_page_error(state, page, data)
  }
  if failure is Some(message) {
    return range_page_failure(model, state, message)
  }
  guard result is Ok(data) else { return (model, @rabbita.none) }
  let accepted = accept_range_page(state, page, data)
  guard model.route is Some(reference) else { return (model, @rabbita.none) }
  if model.phase is LoadingRange(_) {
    if accepted.next_page is Some(next_page) {
      let pending = { ..accepted, loading_page: Some(next_page), }
      return (
        { ..model, range: Some(pending), },
        range_compare_request(
          reference,
          pending.base_sha,
          pending.head_sha,
          next_page,
          model.generation,
          emit,
        ),
      )
    }
    let canonical = match reference.target {
      Range(_, _) =>
        @github.range_reference(
          reference.owner,
          reference.repo,
          accepted.base_sha,
          accepted.head_sha,
        )
      PullRange(number, _, _) =>
        @github.pull_range_reference(
          reference.owner,
          reference.repo,
          number,
          accepted.base_sha,
          accepted.head_sha,
        )
      _ => return (model, @rabbita.none)
    }
    let files = if accepted.too_many_files {
      []
    } else {
      accepted.comparison.unwrap().files.unwrap_or([])
    }
    let view = finish_range(
      canonical,
      accepted.base_sha,
      accepted.head_sha,
      accepted.pull,
      accepted.pull_merge_base,
      files,
    )
    let shown = ensure_expanded_file_documents(
      view,
      model.diff_algorithm,
      ignore_comments=model.ignore_comments,
      ignore_tests=model.ignore_tests,
    )
    let next = with_phase(
      {
        ..model,
        input: if model.input == canonical_github_url(reference) {
          canonical_github_url(canonical)
        } else {
          model.input
        },
        route: Some(canonical),
        range: Some(accepted),
      },
      Showing(shown),
    )
    let navigation = if canonical == reference {
      @rabbita.none
    } else {
      @nav.replace_url(playground_share_url(canonical))
    }
    return (
      next,
      @rabbita.batch([
        navigation,
        commands_for_change(view, model.generation, emit),
      ]),
    )
  }
  let next = { ..model, range: Some(accepted), }
  if reference.target is PullRequest(_) &&
    state.pull is Some(pull) &&
    pull.commits is None &&
    accepted.total_commits <= 250 &&
    accepted.next_page is Some(_) {
    update_range(next, LoadMore, emit)
  } else {
    (next, @rabbita.none)
  }
}

///|
fn update_range(
  model : Model,
  msg : RangeMsg,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  guard model.range is Some(state) && model.route is Some(reference) else {
    return (model, @rabbita.none)
  }
  match msg {
    FromSelected(value) => {
      guard reference.target is PullRequest(_) &&
        range_pull_selector_ready(state) &&
        range_commit_after(state, value, state.to_sha) else {
        return (model, @rabbita.none)
      }
      (
        { ..model, range: Some({ ..state, from_sha: value, error: None, }), },
        @rabbita.none,
      )
    }
    ToSelected(value) => {
      guard reference.target is PullRequest(_) &&
        range_pull_selector_ready(state) &&
        range_commit_after(state, state.from_sha, value) else {
        return (model, @rabbita.none)
      }
      (
        { ..model, range: Some({ ..state, to_sha: value, error: None, }), },
        @rabbita.none,
      )
    }
    ToggleCommits =>
      (
        { ..model, range: Some({ ..state, expanded: !state.expanded, }), },
        @rabbita.none,
      )
    LoadMore => {
      guard state.next_page is Some(page) && state.loading_page is None else {
        return (model, @rabbita.none)
      }
      let command = range_commit_page_request(
        reference,
        state,
        page,
        model.generation,
        emit,
      )
      (
        {
          ..model,
          range: Some({ ..state, loading_page: Some(page), error: None, }),
        },
        command,
      )
    }
    CopyLink =>
      (
        model,
        @cmd.custom_cmd(_ => copy_range_link(playground_share_url(reference))),
      )
    RangePullLoaded(generation, result) => {
      guard generation == model.generation &&
        model.phase is LoadingRangePullMetadata(_) else {
        return (model, @rabbita.none)
      }
      match result {
        Err(error) =>
          (
            with_phase(model, LoadFailed(error_message(error, true))),
            @rabbita.none,
          )
        Ok(pull) => {
          let next = with_phase(
            { ..model, range: Some({ ..state, pull: Some(pull), }), },
            LoadingRangePullCompare(reference~),
          )
          (
            next,
            @github_client.get_compare(
              {
                owner: reference.owner,
                repo: reference.repo,
                base: pull.base.sha,
                head: pull.head.sha,
              },
              generation,
              result => emit(Range(RangePullCompareLoaded(generation, result))),
            ),
          )
        }
      }
    }
    RangePullCompareLoaded(generation, result) => {
      guard generation == model.generation &&
        model.phase is LoadingRangePullCompare(_) else {
        return (model, @rabbita.none)
      }
      match result {
        Err(error) =>
          (
            with_phase(model, LoadFailed(error_message(error, true))),
            @rabbita.none,
          )
        Ok(compare) => {
          let next = with_phase(
            {
              ..model,
              range: Some({
                ..state,
                pull_merge_base: Some(compare.merge_base_commit.sha),
              }),
            },
            LoadingRange(reference~),
          )
          (next, range_start_resolution(reference, state, generation, emit))
        }
      }
    }
    RangeShaResolved(generation, is_base, fork_attempt, result) => {
      guard generation == model.generation && model.phase is LoadingRange(_) else {
        return (model, @rabbita.none)
      }
      match result {
        Err(
          @github_client.HttpRequestError(code="not_found_or_not_installed", ..) as error
        ) => {
          if !fork_attempt && state.pull is Some(pull) {
            let repository = branch_repository(
              pull.head,
              reference_repository(reference),
            )
            if repository != reference_repository(reference) {
              return (
                model,
                range_resolve_request(
                  repository,
                  if is_base {
                    state.base_sha
                  } else {
                    state.head_sha
                  },
                  is_base,
                  true,
                  generation,
                  emit,
                ),
              )
            }
          }
          (
            with_phase(model, LoadFailed(error_message(error, true))),
            @rabbita.none,
          )
        }
        Err(error) =>
          (
            with_phase(model, LoadFailed(error_message(error, true))),
            @rabbita.none,
          )
        Ok(sha) => {
          let updated = if is_base {
            { ..state, base_sha: sha, }
          } else {
            { ..state, head_sha: sha, }
          }
          (
            { ..model, range: Some(updated), },
            range_start_resolution(reference, updated, generation, emit),
          )
        }
      }
    }
    RangePullCommitPageLoaded(generation, page, result) => {
      guard generation == model.generation &&
        state.loading_page == Some(page) &&
        reference.target is PullRequest(number) &&
        (model.phase is Showing(_) || model.phase is ShowingPullSelector(_)) else {
        return (model, @rabbita.none)
      }
      match result {
        Err(error) =>
          range_page_failure(model, state, error_message(error, true))
        Ok(items) =>
          (
            model,
            @github_client.get_pull(
              { owner: reference.owner, repo: reference.repo, number, },
              generation,
              verified => {
                emit(
                  Range(
                    RangePullCommitPageValidated(
                      generation, page, items, verified,
                    ),
                  ),
                )
              },
            ),
          )
      }
    }
    RangePullCommitPageValidated(generation, page, items, result) => {
      guard generation == model.generation &&
        state.loading_page == Some(page) &&
        reference.target is PullRequest(_) &&
        (model.phase is Showing(_) || model.phase is ShowingPullSelector(_)) else {
        return (model, @rabbita.none)
      }
      let failure = match result {
        Err(error) => Some(error_message(error, true))
        Ok(verified) => pull_commit_page_error(state, page, items, verified)
      }
      if failure is Some(message) {
        range_page_failure(model, state, message)
      } else {
        let accepted = accept_pull_commit_page(state, page, items)
        let next = { ..model, range: Some(accepted), }
        if accepted.next_page is Some(_) {
          update_range(next, LoadMore, emit)
        } else {
          (next, @rabbita.none)
        }
      }
    }
    RangePageLoaded(generation, page, result) => {
      guard generation == model.generation &&
        state.loading_page == Some(page) &&
        (
          model.phase is LoadingRange(_) ||
          model.phase is Showing(_) ||
          model.phase is ShowingPullSelector(_)
        ) else {
        return (model, @rabbita.none)
      }
      range_page_loaded(model, state, page, result, emit)
    }
  }
}

///|
extern "js" fn copy_range_link(url : String) -> Unit =
  #| url => { navigator.clipboard?.writeText?.(new URL(url, location.href).href)?.catch(() => {}); }
