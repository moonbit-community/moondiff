///|
fn home_step(model : Model, msg : Msg) -> Model {
  update(model, msg, Emit(_ => @rabbita.none)).model
}

///|
fn home_model() -> Model {
  home_step(
    initial_model(),
    Auth(AuthStatusLoaded(0, Ok(signed_in_api_status("alice")))),
  )
}

///|
fn home_pull(
  number : String,
  date? : String = "2026-09-17T00:00:00Z",
) -> @protocol.ApiPullSummary {
  {
    owner: "upstream",
    repo: "repo",
    number,
    title: "PR \{number}",
    author: "alice",
    updated_at: date,
    draft: true,
  }
}

///|
fn home_pulls_result(
  model : Model,
  kind : @protocol.ViewerPullKind,
  items : Array[@protocol.ApiPullSummary],
  cursor? : String,
  incomplete? : String,
) -> Msg {
  Home(
    PullsLoaded(
      model.home.epoch,
      model.auth_revision,
      model.generation,
      kind,
      Ok({ items, total_count: 100, next_cursor: cursor, incomplete, }),
    ),
  )
}

///|
fn home_commit_result(
  model : Model,
  sha : String,
  head? : String = "head",
  cursor? : String,
) -> Msg {
  Home(
    CommitsLoaded(
      model.home.epoch,
      model.auth_revision,
      model.generation,
      home_pull_key(home_pull("1")),
      Ok({
        items: [
          {
            sha,
            message: "Commit",
            author: "Author",
            committed_at: "2026-09-17T00:00:00Z",
          },
        ],
        total_count: 301,
        next_cursor: cursor,
        base_sha: "base",
        head_sha: head,
      }),
    ),
  )
}

///|
test "homepage starts only on the signed-in root and lists paginate independently" {
  let anonymous = home_step(
    initial_model(),
    Auth(AuthStatusLoaded(0, Ok(anonymous_api_status()))),
  )
  assert_true(anonymous.home.reviews.load is Unloaded)
  let invalid = home_step(
    home_step(anonymous, Ui(InputChanged("not a GitHub URL"))),
    Ui(Submit),
  )
  assert_true(invalid.phase is LoadFailed(_))
  let signed_root = home_step(
    invalid,
    Auth(AuthStatusLoaded(0, Ok(signed_in_api_status("alice")))),
  )
  assert_true(signed_root.phase is Idle)
  assert_true(signed_root.home.reviews.load is Loading)
  let routed = {
    ..initial_model(),
    route: Some(@github.pull_reference("upstream", "repo", "1")),
  }
  let signed_route = home_step(
    routed,
    Auth(AuthStatusLoaded(0, Ok(signed_in_api_status("alice")))),
  )
  assert_true(signed_route.home.reviews.load is Unloaded)
  let model = home_model()
  assert_true(
    model.home.reviews.load is Loading && model.home.authored.load is Loading,
  )
  let next = home_step(
    model,
    home_pulls_result(model, ReviewRequested, [home_pull("1")], cursor="page2"),
  )
  assert_true(
    next.home.reviews.load is Ready && next.home.authored.load is Loading,
  )
  let loading = home_step(next, Home(LoadPulls(ReviewRequested)))
  let failed = home_step(
    loading,
    Home(
      PullsLoaded(
        loading.home.epoch,
        loading.auth_revision,
        loading.generation,
        ReviewRequested,
        Err(GitHubRequestError::GitHubRequestError("network")),
      ),
    ),
  )
  assert_eq(failed.home.reviews.items.length(), 1)
  assert_eq(failed.home.reviews.cursor, Some("page2"))
  let retry = home_step(failed, Home(LoadPulls(ReviewRequested)))
  let done = home_step(
    retry,
    home_pulls_result(retry, ReviewRequested, [
      home_pull("1"),
      home_pull("2", date="2026-09-18T00:00:00Z"),
    ]),
  )
  assert_eq(done.home.reviews.items.map(p => p.number), ["2", "1"])
  assert_true(done.home.authored.load is Loading)
}

///|
test "signed-in invalid routes keep the error while correcting input" {
  let invalid = home_step(
    home_model(),
    Ui(RouteChanged(@url.parse("https://playground.test/#/invalid"))),
  )
  assert_true(invalid.phase is LoadFailed(_))
  let mut model = invalid
  for
    input in [
      "h", "https://github.com/", "https://github.com/upstream/repo/pull/1",
    ] {
    model = home_step(model, Ui(InputChanged(input)))
    assert_eq(model.input, input)
    assert_true(model.phase is LoadFailed(_))
    assert_true(model.route is None)
    assert_true(model.home == invalid.home)
  }
  let submitted = home_step(model, Ui(Submit))
  assert_true(
    submitted.route == Some(@github.pull_reference("upstream", "repo", "1")),
  )
  assert_true(submitted.phase is LoadingPullMetadata(..))
}

///|
test "signed-in invalid URL submissions keep the error and input" {
  let model = { ..home_model(), input: "https://example.com/not-github", }
  let invalid = home_step(model, Ui(Submit))
  assert_true(invalid.phase is LoadFailed(_))
  let again = home_step(invalid, Ui(Submit))
  assert_true(again.phase is LoadFailed(_))
  assert_eq(again.input, model.input)
  assert_true(again.route is None)
}

///|
test "signed-in same-account status checks preserve input errors" {
  let invalid = home_step(
    home_model(),
    Ui(RouteChanged(@url.parse("https://playground.test/#/invalid"))),
  )
  let model = { ..invalid, input: "https://github.com/", }
  for
    msg in [
      AuthStatusLoaded(model.auth_revision, Ok(signed_in_api_status("alice"))),
      ReactivationAuthStatusLoaded(
        model.auth_revision,
        model.generation,
        None,
        Ok(signed_in_api_status("alice")),
      ),
    ] {
    let checked = home_step(model, Auth(msg))
    assert_true(checked.auth is SignedIn(..))
    assert_true(checked.phase is LoadFailed(_))
    assert_eq(checked.input, model.input)
    assert_true(checked.route is None)
    assert_true(checked.home == model.home)
  }
}

///|
test "expired homepage sessions clear all private data and reject the other list's late response" {
  let loading = home_step(home_model(), Home(ToggleCommits(home_pull("1"))))
  let expired = home_step(
    loading,
    Home(
      PullsLoaded(
        loading.home.epoch,
        loading.auth_revision,
        loading.generation,
        ReviewRequested,
        Err(authentication_required_error()),
      ),
    ),
  )
  assert_true(expired.auth is AuthFailed(_))
  assert_true(expired.home.user is None)
  assert_true(expired.home.commits.is_empty())
  let late = home_step(
    expired,
    home_pulls_result(loading, Authored, [home_pull("1")]),
  )
  assert_true(late.home.authored.items.is_empty())
}

///|
test "incomplete search keeps content and the retry cursor" {
  let model = home_model()
  let next = home_step(
    model,
    home_pulls_result(model, Authored, [home_pull("1")], cursor="next"),
  )
  let loading = home_step(next, Home(LoadPulls(Authored)))
  let failed = home_step(
    loading,
    home_pulls_result(
      loading,
      Authored,
      [],
      cursor="narrower-window",
      incomplete="Incomplete search",
    ),
  )
  assert_eq(failed.home.authored.items.length(), 1)
  assert_eq(failed.home.authored.cursor, Some("narrower-window"))
  assert_true(failed.home.authored.load is Failed("Incomplete search"))
}

///|
test "commits are lazy cached and can expand multiple PRs" {
  let model = home_model()
  assert_true(model.home.commits.is_empty())
  let loading = home_step(model, Home(ToggleCommits(home_pull("1"))))
  let key = home_pull_key(home_pull("1"))
  let loaded = home_step(
    loading,
    home_commit_result(loading, "abcdef1", cursor="page2"),
  )
  let collapsed = home_step(loaded, Home(ToggleCommits(home_pull("1"))))
  let expanded = home_step(collapsed, Home(ToggleCommits(home_pull("1"))))
  assert_true(expanded.home.commits[key].page.load is Ready)
  assert_eq(expanded.home.commits[key].page.items.length(), 1)
  let more = home_step(expanded, Home(ToggleCommits(home_pull("2"))))
  assert_eq(more.home.commits.length(), 2)
  assert_true(more.home.commits[key].expanded)
  assert_true(model.home.commits.is_empty())
}

///|
test "commit pagination discards old snapshots and retries from the first page" {
  let loading = home_step(home_model(), Home(ToggleCommits(home_pull("1"))))
  let loaded = home_step(
    loading,
    home_commit_result(loading, "abcdef1", cursor="page2"),
  )
  let key = home_pull_key(home_pull("1"))
  let next = home_step(loaded, Home(LoadCommits(key)))
  let changed = home_step(
    next,
    home_commit_result(next, "abcdef2", head="new-head"),
  )
  assert_true(changed.home.commits[key].page.load is Loading)
  assert_true(changed.home.commits[key].page.items.is_empty())
  assert_true(changed.home.commits[key].page.cursor is None)
  let latest = home_step(
    changed,
    home_commit_result(changed, "abcdef3", head="new-head"),
  )
  assert_eq(latest.home.commits[key].page.items.map(c => c.sha), ["abcdef3"])
}

///|
test "refresh logout and account changes ignore late private responses" {
  let loading = home_step(home_model(), Home(ToggleCommits(home_pull("1"))))
  let late_pulls = home_pulls_result(loading, Authored, [home_pull("1")])
  let late_commits = home_commit_result(loading, "abcdef1")
  assert_true(home_step(loading, Home(Refresh)).home == loading.home)
  let ready = home_step(
    loading,
    home_pulls_result(loading, ReviewRequested, [home_pull("1")]),
  )
  let ready = home_step(ready, home_pulls_result(ready, Authored, []))
  let refreshed = home_step(ready, Home(Refresh))
  assert_true(
    refreshed.home.commits[home_pull_key(home_pull("1"))].page.refresh
    is Some(_),
  )
  assert_true(home_step(refreshed, late_pulls).home.authored.items.is_empty())
  assert_true(home_step(refreshed, late_commits).home == refreshed.home)
  let logout = home_step(loading, Auth(Logout))
  assert_true(logout.home.commits.is_empty())
  assert_true(home_step(logout, late_commits).home.commits.is_empty())
  let switched = home_step(
    loading,
    Auth(
      ReactivationAuthStatusLoaded(
        loading.auth_revision,
        loading.generation,
        None,
        Ok(signed_in_api_status("bob")),
      ),
    ),
  )
  assert_eq(switched.home.user, Some("id:bob"))
  assert_true(home_step(switched, late_pulls).home.authored.items.is_empty())
}

///|
test "history and page restoration resume interrupted pages while retaining cached rows" {
  let model = home_model()
  let loaded = home_step(
    model,
    home_pulls_result(model, ReviewRequested, [home_pull("1")], cursor="page2"),
  )
  let loading = home_step(loaded, Home(LoadPulls(ReviewRequested)))
  let loading = home_step(loading, Home(ToggleCommits(home_pull("1"))))
  let late = home_pulls_result(loading, ReviewRequested, [home_pull("2")])
  let away = home_step(
    loading,
    Ui(RouteChanged(@url.parse("https://playground.test/upstream/repo/pull/1"))),
  )
  assert_true(away.home.reviews.load is Paused)
  assert_eq(home_step(away, late).home.reviews.items.length(), 1)
  let back = home_step(
    away,
    Ui(RouteChanged(@url.parse("https://playground.test/"))),
  )
  assert_true(back.home.reviews.load is Loading)
  assert_eq(back.home.reviews.cursor, Some("page2"))
  let key = home_pull_key(home_pull("1"))
  assert_true(back.home.commits[key].expanded)
  assert_true(back.home.commits[key].page.load is Loading)
  let hidden = home_step(back, Auth(RestoreAuth))
  assert_true(hidden.home.reviews.load is Paused)
  let restored = home_step(
    hidden,
    Auth(
      ReactivationAuthStatusLoaded(
        hidden.auth_revision,
        hidden.generation,
        None,
        Ok(signed_in_api_status("alice")),
      ),
    ),
  )
  assert_true(restored.home.reviews.load is Loading)
  assert_eq(restored.home.reviews.items.length(), 1)
  assert_true(restored.home.commits[key].page.load is Loading)
}
