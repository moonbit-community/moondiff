///|
fn ready_home_model() -> Model {
  let model = home_model()
  let model = home_step(
    model,
    home_pulls_result(model, ReviewRequested, [
      home_pull("1"),
      home_pull("2"),
      home_pull("3"),
    ]),
  )
  home_step(model, home_pulls_result(model, Authored, [home_pull("4")]))
}

///|
test "tabs retain loaded and expanded data across navigation and reset with a new session" {
  let model = ready_home_model()
  let model = home_step(model, Home(ToggleCommits(home_pull("1"))))
  let model = home_step(model, home_commit_result(model, "old"))
  let selected = home_step(model, Home(SelectTab(ReviewRequested)))
  assert_true(selected.home.tab is ReviewRequested)
  assert_true(selected.home.reviews == model.home.reviews)
  assert_true(selected.home.commits == model.home.commits)
  let away = home_step(
    selected,
    Ui(RouteChanged(@url.parse("https://playground.test/upstream/repo/pull/4"))),
  )
  let back = home_step(
    away,
    Ui(RouteChanged(@url.parse("https://playground.test/"))),
  )
  assert_true(back.home.tab is ReviewRequested)
  assert_true(back.home.commits == selected.home.commits)
  assert_true(home_model().home.tab is Authored)
  assert_true(home_step(back, Auth(Logout)).home.tab is Authored)
}

///|
test "multi-page refresh replaces each list independently and keeps old rows until completion" {
  let model = ready_home_model()
  let model = with_home_list(model, ReviewRequested, {
    ..model.home.reviews,
    updated_at: Some("old-success"),
  })
  let model = home_step(model, Home(ToggleCommits(home_pull("2"))))
  let model = home_step(model, Home(SelectTab(ReviewRequested)))
  let refresh = home_step(model, Home(Refresh))
  assert_true(refresh.home.tab is ReviewRequested)
  assert_true(refresh.home.reviews.items == model.home.reviews.items)
  assert_true(home_step(refresh, Home(Refresh)).home == refresh.home)
  let stage = home_step(
    refresh,
    home_pulls_result(
      refresh,
      ReviewRequested,
      [home_pull("1")],
      cursor="new-page2",
    ),
  )
  assert_true(stage.home.reviews.items == model.home.reviews.items)
  assert_eq(stage.home.reviews.updated_at, Some("old-success"))
  assert_eq(home_cursor(stage.home.reviews), Some("new-page2"))
  let authored = home_step(stage, home_pulls_result(stage, Authored, []))
  assert_true(authored.home.authored.items.is_empty())
  assert_true(authored.home.authored.refresh is None)
  assert_true(authored.home.reviews.load is Loading)
  let incomplete = home_step(
    authored,
    home_pulls_result(
      authored,
      ReviewRequested,
      [home_pull("5")],
      cursor="narrow-window",
      incomplete="Incomplete search",
    ),
  )
  assert_true(incomplete.home.reviews.load is Failed(_))
  assert_true(incomplete.home.reviews.items == model.home.reviews.items)
  assert_eq(incomplete.home.reviews.updated_at, Some("old-success"))
  let retry = home_step(incomplete, Home(LoadPulls(ReviewRequested)))
  assert_eq(home_cursor(retry.home.reviews), Some("narrow-window"))
  let done = home_step(
    retry,
    home_pulls_result(retry, ReviewRequested, [
      home_pull("6", date="2026-09-19T00:00:00Z"),
    ]),
  )
  assert_eq(done.home.reviews.items.map(p => p.number), ["6", "1", "5"])
  assert_true(done.home.reviews.refresh is None)
  assert_true(done.home.reviews.updated_at != Some("old-success"))
  assert_true(!done.home.commits.contains(home_pull_key(home_pull("2"))))
}

///|
test "refresh failures retain contents and retry cursors without advancing success time" {
  let model = ready_home_model()
  let model = home_step(model, Home(Refresh))
  let stage = home_step(
    model,
    home_pulls_result(model, ReviewRequested, [home_pull("7")], cursor="second"),
  )
  let failed = home_step(
    stage,
    Home(
      PullsLoaded(
        stage.home.epoch,
        stage.auth_revision,
        stage.generation,
        ReviewRequested,
        Err(
          @github_client.HttpRequestError(
            status=429,
            code="rate_limit",
            detail="Sign in",
          ),
        ),
      ),
    ),
  )
  assert_true(failed.home.reviews.items == model.home.reviews.items)
  assert_eq(failed.home.reviews.updated_at, model.home.reviews.updated_at)
  assert_true(
    failed.home.reviews.load
    is Failed(
      "GitHub is temporarily limiting requests. Please try again later."
    ),
  )
  let retry = home_step(failed, Home(LoadPulls(ReviewRequested)))
  assert_eq(home_cursor(retry.home.reviews), Some("second"))
  let done = home_step(
    retry,
    home_pulls_result(retry, ReviewRequested, [home_pull("8")]),
  )
  assert_eq(done.home.reviews.items.map(p => p.number), ["7", "8"])
  assert_true(done.home.reviews.load is Ready)
  assert_true(done.home.authored.load is Loading)
}

///|
test "commit refresh preserves depth and expansion while replacing changed snapshots" {
  let key = home_pull_key(home_pull("1"))
  let model = home_step(ready_home_model(), Home(ToggleCommits(home_pull("1"))))
  let model = home_step(
    model,
    home_commit_result(model, "old-1", cursor="old-page2"),
  )
  let model = home_step(model, Home(LoadCommits(key)))
  let model = home_step(model, home_commit_result(model, "old-2"))
  let refresh = home_step(model, Home(Refresh))
  assert_true(refresh.home.commits[key].expanded)
  let first = home_step(
    refresh,
    home_commit_result(refresh, "new-1", head="new-head", cursor="new-page2"),
  )
  assert_eq(first.home.commits[key].page.items.map(c => c.sha), [
    "old-1", "old-2",
  ])
  let failed = home_step(
    first,
    Home(
      CommitsLoaded(
        first.home.epoch,
        first.auth_revision,
        first.generation,
        key,
        Err(GitHubRequestError::GitHubRequestError("Offline")),
      ),
    ),
  )
  assert_true(failed.home.commits[key].page.load is Failed(_))
  assert_true(
    failed.home.commits[key].page.items == model.home.commits[key].page.items,
  )
  let retry = home_step(failed, Home(LoadCommits(key)))
  let changed = home_step(
    retry,
    home_commit_result(retry, "other-head-2", head="other-head"),
  )
  assert_true(changed.home.commits[key].page.load is Loading)
  assert_true(
    changed.home.commits[key].page.items == model.home.commits[key].page.items,
  )
  assert_true(home_cursor(changed.home.commits[key].page) is None)
  let first = home_step(
    changed,
    home_commit_result(changed, "latest-1", head="other-head", cursor="latest2"),
  )
  let done = home_step(
    first,
    home_commit_result(first, "latest-2", head="other-head"),
  )
  assert_eq(done.home.commits[key].page.items.map(c => c.sha), [
    "latest-1", "latest-2",
  ])
  assert_true(done.home.commits[key].page.refresh is None)
  assert_eq(done.home.commits[key].restarts, 0)
}

///|
test "repeated commit changes during refresh stop for retry and keep the usable snapshot" {
  let key = home_pull_key(home_pull("1"))
  let model = home_step(ready_home_model(), Home(ToggleCommits(home_pull("1"))))
  let model = home_step(model, home_commit_result(model, "old-1", cursor="p2"))
  let model = home_step(model, Home(LoadCommits(key)))
  let model = home_step(model, home_commit_result(model, "old-2"))
  let model = home_step(model, Home(Refresh))
  let first = home_step(
    model,
    home_commit_result(model, "a", head="head-a", cursor="p2"),
  )
  let restart = home_step(first, home_commit_result(first, "b", head="head-b"))
  let first = home_step(
    restart,
    home_commit_result(restart, "b", head="head-b", cursor="p2"),
  )
  let failed = home_step(first, home_commit_result(first, "c", head="head-c"))
  assert_true(failed.home.commits[key].page.load is Failed(_))
  assert_eq(failed.home.commits[key].page.items.map(c => c.sha), [
    "old-1", "old-2",
  ])
  assert_true(home_cursor(failed.home.commits[key].page) is None)
}

///|
test "invalid refresh cursors restart staging with a bounded retry and preserve the visible list" {
  let model = home_step(ready_home_model(), Home(Refresh))
  let first = home_step(
    model,
    home_pulls_result(
      model,
      ReviewRequested,
      [home_pull("8")],
      cursor="expired",
    ),
  )
  let restart = home_step(
    first,
    home_pulls_cursor_error(first, ReviewRequested),
  )
  assert_true(home_cursor(restart.home.reviews) is None)
  assert_true(restart.home.reviews.items == model.home.reviews.items)
  let first = home_step(
    restart,
    home_pulls_result(
      restart,
      ReviewRequested,
      [home_pull("9")],
      cursor="expired-again",
    ),
  )
  let failed = home_step(first, home_pulls_cursor_error(first, ReviewRequested))
  assert_true(failed.home.reviews.load is Failed(_))
  assert_true(failed.home.reviews.items == model.home.reviews.items)
  let retry = home_step(failed, Home(LoadPulls(ReviewRequested)))
  let done = home_step(
    retry,
    home_pulls_result(retry, ReviewRequested, [home_pull("10")]),
  )
  assert_eq(done.home.reviews.items.map(p => p.number), ["10"])
}

///|
test "refresh resumes staging after page restoration and rejects late responses and expired sessions" {
  let model = home_step(ready_home_model(), Home(Refresh))
  let stage = home_step(
    model,
    home_pulls_result(model, ReviewRequested, [home_pull("8")], cursor="second"),
  )
  let away = home_step(stage, Auth(RestoreAuth))
  assert_true(away.home.reviews.items == stage.home.reviews.items)
  let back = home_step(
    away,
    Auth(
      ReactivationAuthStatusLoaded(
        away.auth_revision,
        away.generation,
        None,
        Ok(signed_in_api_status("alice")),
      ),
    ),
  )
  assert_eq(home_cursor(back.home.reviews), Some("second"))
  assert_true(
    home_step(
      back,
      home_pulls_result(stage, ReviewRequested, [home_pull("99")]),
    ).home ==
    back.home,
  )
  let expired = home_step(
    back,
    Home(
      PullsLoaded(
        back.home.epoch,
        back.auth_revision,
        back.generation,
        ReviewRequested,
        Err(authentication_required_error()),
      ),
    ),
  )
  assert_true(expired.home.user is None)
  assert_true(expired.home.reviews.items.is_empty())
  assert_true(expired.home.reviews.refresh is None)
  assert_true(expired.home.reviews.updated_at is None)
  assert_true(
    home_step(expired, home_pulls_result(back, Authored, [home_pull("99")])).home.authored.items.is_empty(),
  )
}

///|
test "loading more leaves the last successful initial load or refresh time unchanged" {
  let model = ready_home_model()
  let model = with_home_list(model, ReviewRequested, {
    ..model.home.reviews,
    cursor: Some("next"),
    updated_at: Some("initial-success"),
  })
  let loading = home_step(model, Home(LoadPulls(ReviewRequested)))
  let done = home_step(
    loading,
    home_pulls_result(loading, ReviewRequested, [home_pull("5")]),
  )
  assert_eq(done.home.reviews.updated_at, Some("initial-success"))
  let recovered = home_step(
    loading,
    home_pulls_cursor_error(loading, ReviewRequested),
  )
  let done = home_step(
    recovered,
    home_pulls_result(recovered, ReviewRequested, [home_pull("6")]),
  )
  assert_eq(done.home.reviews.updated_at, Some("initial-success"))
}

///|
test "independent list completion preserves expansion for PRs appearing in the other refreshed group" {
  let key = home_pull_key(home_pull("1"))
  let model = home_step(ready_home_model(), Home(ToggleCommits(home_pull("1"))))
  let model = home_step(model, home_commit_result(model, "cached"))
  let model = home_step(model, Home(Refresh))
  let reviews = home_step(model, home_pulls_result(model, ReviewRequested, []))
  assert_true(reviews.home.commits[key].expanded)
  let both = home_step(
    reviews,
    home_pulls_result(reviews, Authored, [home_pull("1")]),
  )
  assert_true(both.home.commits[key].expanded)
  assert_eq(both.home.commits[key].page.items.map(c => c.sha), ["cached"])
}
