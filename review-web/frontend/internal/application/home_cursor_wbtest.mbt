///|
fn invalid_home_cursor() -> Error {
  @github_client.HttpRequestError(
    status=400,
    code="invalid_cursor",
    detail="This pagination cursor is no longer valid.",
  )
}

///|
fn home_pulls_cursor_error(
  model : Model,
  kind : @protocol.ViewerPullKind,
) -> Msg {
  Home(
    PullsLoaded(
      model.home.epoch,
      model.auth_revision,
      model.generation,
      kind,
      Err(invalid_home_cursor()),
    ),
  )
}

///|
fn home_commits_cursor_error(model : Model, key : String) -> Msg {
  Home(
    CommitsLoaded(
      model.home.epoch,
      model.auth_revision,
      model.generation,
      key,
      Err(invalid_home_cursor()),
    ),
  )
}

///|
test "both PR lists recover invalid cursors independently without discarding commit caches" {
  for kind in [@protocol.ReviewRequested, Authored] {
    let other = if kind == Authored {
      @protocol.ReviewRequested
    } else {
      Authored
    }
    let model = home_model()
    let loaded = home_step(
      model,
      home_pulls_result(model, kind, [home_pull("1")], cursor="expired"),
    )
    let loaded = home_step(
      loaded,
      home_pulls_result(loaded, other, [home_pull("2")], cursor="other-page"),
    )
    let expanded = home_step(loaded, Home(ToggleCommits(home_pull("1"))))
    let cached = home_step(expanded, home_commit_result(expanded, "abcdef1"))
    let loading = home_step(cached, Home(LoadPulls(kind)))
    let recovered = home_step(loading, home_pulls_cursor_error(loading, kind))
    let page = home_list(recovered.home, kind)
    assert_true(page.load is Loading)
    assert_true(page.items.is_empty())
    assert_true(page.total is None && page.cursor is None)
    assert_true(
      home_list(recovered.home, other) == home_list(cached.home, other),
    )
    assert_true(recovered.home.commits == cached.home.commits)
    assert_eq(recovered.generation, cached.generation)
    assert_eq(recovered.auth_revision, cached.auth_revision)
    assert_eq(recovered.home.epoch, cached.home.epoch)
    let done = home_step(
      recovered,
      home_pulls_result(recovered, kind, [home_pull("3")]),
    )
    assert_eq(home_list(done.home, kind).items.map(p => p.number), ["3"])
  }
}

///|
test "PR invalid cursor on first page or recovery stops at Retry without a request loop" {
  for kind in [@protocol.ReviewRequested, Authored] {
    let model = home_model()
    let failed = home_step(model, home_pulls_cursor_error(model, kind))
    assert_true(home_list(failed.home, kind).load is Failed(_))
    let idle = home_step(failed, Home(ToggleCommits(home_pull("2"))))
    assert_true(home_list(idle.home, kind).load is Failed(_))
    let retry = home_step(idle, Home(LoadPulls(kind)))
    assert_true(home_list(retry.home, kind).load is Loading)
    assert_true(home_list(retry.home, kind).cursor is None)
    let loaded = home_step(
      retry,
      home_pulls_result(retry, kind, [home_pull("1")], cursor="expired"),
    )
    let loading = home_step(loaded, Home(LoadPulls(kind)))
    let recovered = home_step(loading, home_pulls_cursor_error(loading, kind))
    let failed = home_step(recovered, home_pulls_cursor_error(recovered, kind))
    assert_true(home_list(failed.home, kind).load is Failed(_))
    assert_true(home_list(failed.home, kind).cursor is None)
    assert_true(home_list(failed.home, kind).items.is_empty())
  }
}

///|
test "invalid commit cursor resets its snapshot and restart budget and respects collapse" {
  for collapse in [false, true] {
    let expanded = home_step(home_model(), Home(ToggleCommits(home_pull("1"))))
    let cached = home_step(
      expanded,
      home_commit_result(expanded, "abcdef1", cursor="expired"),
    )
    let key = home_pull_key(home_pull("1"))
    let cached = with_home_commits(cached, key, {
      ..cached.home.commits[key],
      restarts: 2,
    })
    let cached = home_step(cached, Home(ToggleCommits(home_pull("2"))))
    let loading = home_step(cached, Home(LoadCommits(key)))
    let loading = if collapse {
      home_step(loading, Home(ToggleCommits(home_pull("1"))))
    } else {
      loading
    }
    let recovered = home_step(loading, home_commits_cursor_error(loading, key))
    let value = recovered.home.commits[key]
    assert_true(value.page.items.is_empty())
    assert_true(value.page.total is None && value.page.cursor is None)
    assert_true(value.snapshot is None)
    assert_eq(value.restarts, 0)
    assert_eq(value.expanded, !collapse)
    assert_true(value.page.load == (if collapse { Unloaded } else { Loading }))
    assert_true(recovered.home.reviews == cached.home.reviews)
    assert_true(recovered.home.authored == cached.home.authored)
    let other = home_pull_key(home_pull("2"))
    assert_true(recovered.home.commits[other] == cached.home.commits[other])
    let loading = if collapse {
      home_step(recovered, Home(ToggleCommits(home_pull("1"))))
    } else {
      recovered
    }
    assert_true(loading.home.commits[key].page.load is Loading)
    let done = home_step(
      loading,
      home_commit_result(loading, "abcdef2", head="new"),
    )
    assert_eq(done.home.commits[key].page.items.map(c => c.sha), ["abcdef2"])
    assert_eq(done.home.commits[key].snapshot, Some(("base", "new")))
  }
}

///|
test "commit invalid cursor on first page or recovery stops until explicit Retry" {
  let key = home_pull_key(home_pull("1"))
  let loading = home_step(home_model(), Home(ToggleCommits(home_pull("1"))))
  let failed = home_step(loading, home_commits_cursor_error(loading, key))
  assert_true(failed.home.commits[key].page.load is Failed(_))
  let collapsed = home_step(failed, Home(ToggleCommits(home_pull("1"))))
  let expanded = home_step(collapsed, Home(ToggleCommits(home_pull("1"))))
  assert_true(expanded.home.commits[key].page.load is Failed(_))
  let retry = home_step(expanded, Home(LoadCommits(key)))
  assert_true(retry.home.commits[key].page.load is Loading)
  assert_true(retry.home.commits[key].page.cursor is None)
  let loaded = home_step(
    retry,
    home_commit_result(retry, "abcdef1", cursor="expired"),
  )
  let loading = home_step(loaded, Home(LoadCommits(key)))
  let recovered = home_step(loading, home_commits_cursor_error(loading, key))
  let failed = home_step(recovered, home_commits_cursor_error(recovered, key))
  assert_true(failed.home.commits[key].page.load is Failed(_))
  assert_true(failed.home.commits[key].page.cursor is None)
}

///|
test "late invalid cursors and successful pages cannot contaminate refreshed or restored lists" {
  let model = home_model()
  let loaded = home_step(
    model,
    home_pulls_result(model, Authored, [home_pull("1")], cursor="expired"),
  )
  let loaded = home_step(loaded, Home(ToggleCommits(home_pull("1"))))
  let loaded = home_step(
    loaded,
    home_commit_result(loaded, "abcdef1", cursor="expired"),
  )
  let key = home_pull_key(home_pull("1"))
  let loading = home_step(
    home_step(loaded, Home(LoadPulls(Authored))),
    Home(LoadCommits(key)),
  )
  let recovering = home_step(
    loading,
    home_pulls_cursor_error(loading, Authored),
  )
  let recovering = home_step(
    recovering,
    home_commits_cursor_error(recovering, key),
  )
  let late = [
    home_pulls_cursor_error(loading, Authored),
    home_commits_cursor_error(loading, key),
    home_pulls_result(recovering, Authored, [home_pull("9")]),
    home_commit_result(recovering, "abcdef9"),
  ]
  let ready = home_step(
    recovering,
    home_pulls_result(recovering, Authored, [home_pull("1")]),
  )
  let ready = home_step(ready, home_pulls_result(ready, ReviewRequested, []))
  let refreshed = home_step(ready, Home(Refresh))
  for msg in late {
    assert_true(home_step(refreshed, msg).home == refreshed.home)
  }
  let restoring = home_step(recovering, Auth(RestoreAuth))
  let restored = home_step(
    restoring,
    Auth(
      ReactivationAuthStatusLoaded(
        restoring.auth_revision,
        restoring.generation,
        None,
        Ok(signed_in_api_status("alice")),
      ),
    ),
  )
  for msg in late {
    assert_true(home_step(restored, msg).home == restored.home)
  }
}
