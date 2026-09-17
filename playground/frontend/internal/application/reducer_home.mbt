///|
pub(all) enum HomeMsg {
  Refresh
  SelectTab(@protocol.ViewerPullKind)
  LoadPulls(@protocol.ViewerPullKind)
  ToggleCommits(@protocol.ApiPullSummary)
  LoadCommits(String)
  Open(String)
  PullsLoaded(
    Int,
    Int,
    Int,
    @protocol.ViewerPullKind,
    Result[@protocol.ApiViewerPulls, Error]
  )
  CommitsLoaded(Int, Int, Int, String, Result[@protocol.ApiPullCommits, Error])
}

///|
fn begin_home_list(
  model : Model,
  kind : @protocol.ViewerPullKind,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let page = home_list(model.home, kind)
  guard !(page.load is Loading) else { return (model, @rabbita.none) }
  let next = with_home_list(model, kind, { ..page, load: Loading, })
  (
    next,
    @github_client.get_viewer_pulls(
      { kind, cursor: home_cursor(page), },
      model.generation,
      result => {
        emit(
          Home(
            PullsLoaded(
              model.home.epoch,
              model.auth_revision,
              model.generation,
              kind,
              result,
            ),
          ),
        )
      },
    ),
  )
}

///|
fn begin_home_commits(
  model : Model,
  key : String,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  guard model.home.commits.get(key) is Some(value) &&
    !(value.page.load is Loading) else {
    return (model, @rabbita.none)
  }
  let next = with_home_commits(model, key, {
    ..value,
    page: { ..value.page, load: Loading, },
  })
  let p = value.pull
  (
    next,
    @github_client.get_pull_commits(
      {
        owner: p.owner,
        repo: p.repo,
        number: p.number,
        cursor: home_cursor(value.page),
      },
      model.generation,
      result => {
        emit(
          Home(
            CommitsLoaded(
              model.home.epoch,
              model.auth_revision,
              model.generation,
              key,
              result,
            ),
          ),
        )
      },
    ),
  )
}

///|
fn home_accepts(
  model : Model,
  epoch : Int,
  revision : Int,
  generation : Int,
) -> Bool {
  home_active(model) &&
  epoch == model.home.epoch &&
  revision == model.auth_revision &&
  generation == model.generation
}

///|
fn home_auth_error(model : Model, error : Error) -> Model {
  match error {
    @github_client.HttpRequestError(status=401, ..) =>
      with_auth(
        { ..model, auth_revision: model.auth_revision + 1, },
        AuthFailed(home_failure_message(error)),
      )
    _ => model
  }
}

///|
fn home_failure_message(error : Error) -> String {
  match error {
    @github_client.HttpRequestError(code~, detail~, ..) =>
      match code {
        "rate_limit" =>
          "GitHub is temporarily limiting requests. Please try again later."
        "permission_denied" | "not_found_or_not_installed" =>
          "GitHub denied access to these repositories. Check your repository authorization and retry."
        "authentication_required" =>
          @comment_requests.error_message(error, true)
        _ =>
          if detail.is_empty() {
            "Could not load this page. Please retry."
          } else {
            detail
          }
      }
    _ => comment_failure_message(error)
  }
}

///|
fn merge_pulls(
  old : Array[@protocol.ApiPullSummary],
  page : Array[@protocol.ApiPullSummary],
) -> Array[@protocol.ApiPullSummary] {
  let by_key : Map[String, @protocol.ApiPullSummary] = Map([])
  for item in old {
    by_key[home_pull_key(item)] = item
  }
  for item in page {
    by_key[home_pull_key(item)] = item
  }
  let items = by_key.values().collect()
  items.sort_by((a, b) => b.updated_at.compare(a.updated_at))
  items
}

///|
fn update_home(
  model : Model,
  msg : HomeMsg,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  guard home_active(model) else { return (model, @rabbita.none) }
  match msg {
    Refresh => {
      guard !model.home.busy() else { return (model, @rabbita.none) }
      let next = {
        ..model,
        generation: model.generation + 1,
        home: refresh_home(model.home),
      }
      (next, @github_client.cancel_before(next.generation))
    }
    SelectTab(tab) =>
      ({ ..model, home: { ..model.home, tab, }, }, @rabbita.none)
    Open(path) => (model, @nav.push_url(path))
    LoadPulls(kind) => {
      let page = home_list(model.home, kind)
      if page.refresh is None && page.load is Ready && page.cursor is None {
        (model, @rabbita.none)
      } else {
        begin_home_list(model, kind, emit)
      }
    }
    ToggleCommits(pull) => {
      let key = home_pull_key(pull)
      let value = match model.home.commits.get(key) {
        Some(value) => { ..value, expanded: !value.expanded, }
        None =>
          {
            pull,
            expanded: true,
            page: empty_home_page(),
            snapshot: None,
            restarts: 0,
          }
      }
      (with_home_commits(model, key, value), @rabbita.none)
    }
    LoadCommits(key) => {
      guard model.home.commits.get(key) is Some(value) &&
        value.expanded &&
        !(value.page.refresh is None &&
        value.page.load is Ready &&
        value.page.cursor is None) else {
        return (model, @rabbita.none)
      }
      begin_home_commits(model, key, emit)
    }
    PullsLoaded(epoch, revision, generation, kind, result) => {
      guard home_accepts(model, epoch, revision, generation) else {
        return (model, @rabbita.none)
      }
      let previous = home_list(model.home, kind)
      guard previous.load is Loading else { return (model, @rabbita.none) }
      if home_cursor(previous) is Some(_) &&
        result is Err(error) &&
        error is @github_client.HttpRequestError(code="invalid_cursor", ..) {
        return (
          with_home_list(model, kind, recover_home_cursor(previous, error)),
          @rabbita.none,
        )
      }
      let next = match result {
        Err(error) =>
          home_auth_error(
            with_home_list(model, kind, {
              ..previous,
              load: Failed(home_failure_message(error)),
            }),
            error,
          )
        Ok(page) =>
          with_home_list(
            model,
            kind,
            receive_home_page(
              previous,
              merge_pulls(home_items(previous), page.items),
              page.total_count,
              page.next_cursor,
              incomplete?=page.incomplete,
            ),
          )
      }
      // Wait for both replacement lists before removing expansion state: a PR
      // can appear in the other group's new pages after this group finishes.
      let next = if previous.refresh is Some(_) &&
        next.home.reviews.refresh is None &&
        next.home.authored.refresh is None {
        prune_home_commits(next)
      } else {
        next
      }
      (next, @rabbita.none)
    }
    CommitsLoaded(epoch, revision, generation, key, result) => {
      guard home_accepts(model, epoch, revision, generation) &&
        model.home.commits.get(key) is Some(value) &&
        value.page.load is Loading else {
        return (model, @rabbita.none)
      }
      if home_cursor(value.page) is Some(_) &&
        result is Err(error) &&
        error is @github_client.HttpRequestError(code="invalid_cursor", ..) {
        return (
          with_home_commits(model, key, {
            ..value,
            page: recover_home_cursor(value.page, error),
            snapshot: None,
            restarts: 0,
          }),
          @rabbita.none,
        )
      }
      let changed = match result {
        Err(@github_client.HttpRequestError(code="pull_commits_changed", ..)) =>
          true
        Ok(page) =>
          value.snapshot is Some(snapshot) &&
          snapshot != (page.base_sha, page.head_sha)
        _ => false
      }
      if changed {
        let restart = {
          ..value,
          snapshot: None,
          restarts: value.restarts + 1,
          page: {
            ..restart_home_page(value.page),
            load: if value.restarts == 0 {
              Unloaded
            } else {
              Failed(
                "This PR keeps changing. Retry to load its latest commits.",
              )
            },
          },
        }
        return (with_home_commits(model, key, restart), @rabbita.none)
      }
      let next = match result {
        Err(error) =>
          home_auth_error(
            with_home_commits(model, key, {
              ..value,
              page: { ..value.page, load: Failed(home_failure_message(error)), },
            }),
            error,
          )
        Ok(page) => {
          let items = home_items(value.page).copy()
          let seen : Map[String, Bool] = Map([])
          for item in items {
            seen[item.sha] = true
          }
          for item in page.items {
            if !seen.contains(item.sha) {
              items.push(item)
              seen[item.sha] = true
            }
          }
          let received = receive_home_page(
            value.page,
            items,
            page.total_count,
            page.next_cursor,
          )
          with_home_commits(model, key, {
            ..value,
            snapshot: Some((page.base_sha, page.head_sha)),
            // Keep the restart budget across staging pages so a moving PR
            // cannot trap a multi-page refresh in an automatic retry loop.
            restarts: if received.refresh is Some(_) {
              value.restarts
            } else {
              0
            },
            page: received,
          })
        }
      }
      (next, @rabbita.none)
    }
  }
}
