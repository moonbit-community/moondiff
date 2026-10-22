///|
fn snapshot_viewed_waiting() -> Model {
  let writing = viewed_test_toggle(
    viewed_test_loaded(viewed_test_model(), Unviewed),
  )
  let confirming = viewed_test_timeout(mark_snapshot_stale(writing))
  home_step(confirming, Review(LoadLatestSnapshot))
}

///|
fn snapshot_viewed_read(
  model : Model,
  result : Result[@protocol.ApiPullViewed, Error],
) -> Model {
  home_step(
    model,
    Viewed(Loaded(model.viewed.epoch, model.viewed.read_serial, result)),
  )
}

///|
test "early Load latest consumes its intent once after a coordinated Viewed response" {
  for response in 0..<3 {
    let waiting = snapshot_viewed_waiting()
    assert_true(waiting.review.snapshot_stale)
    assert_false(waiting.viewed.stale)
    assert_true(waiting.viewed.loading)
    assert_true(waiting.access.waiting_for_viewed)
    assert_false(waiting.access.reload_requested)
    assert_false(waiting.access.freshness is Checking)
    assert_true(home_step(waiting, Review(LoadLatestSnapshot)) == waiting)
    assert_true(home_step(waiting, Viewed(Refresh)) == waiting)
    let data = viewed_test_data(Viewed)
    let result : Result[@protocol.ApiPullViewed, Error] = match response {
      0 => Ok(data)
      1 => Ok({ ..data, head_sha: "b".repeat(40), })
      _ =>
        Err(
          @github_client.HttpRequestError(
            status=409,
            code="pull_snapshot_changed",
            detail="PR updated",
          ),
        )
    }
    let checking = snapshot_viewed_read(waiting, result)
    assert_false(checking.access.waiting_for_viewed)
    assert_true(checking.access.reload_requested)
    assert_true(checking.access.freshness is Checking)
    assert_eq(checking.generation, waiting.generation)
    assert_true(checking.phase == waiting.phase)
    assert_eq(checking.viewed.stale, response != 0)
    assert_eq(checking.viewed.files[0].pending is Some(_), response != 0)
    assert_true(home_step(checking, Review(LoadLatestSnapshot)) == checking)
    // A duplicate confirmation cannot issue another snapshot request.
    assert_true(snapshot_viewed_read(checking, Ok(data)) == checking)
  }
}

///|
test "stale review keeps Viewed retries and manual recovery without releasing old pending values" {
  let waiting = snapshot_viewed_waiting()
  let pending = waiting.viewed.files[0].pending
  let old = snapshot_viewed_read(waiting, Ok(viewed_test_data(Unviewed)))
  assert_true(old.access.waiting_for_viewed)
  assert_true(old.viewed.poll_scheduled)
  assert_eq(old.viewed.retry, 1)
  assert_true(old.viewed.files[0].pending == pending)
  assert_true(old.phase == waiting.phase)
  assert_true(viewed_test_toggle(old) == old)
  let retry = viewed_test_tick(old)
  assert_true(retry.viewed.loading)
  let failed = snapshot_viewed_read(
    retry,
    Err(
      @github_client.HttpRequestError(
        status=503,
        code="unavailable",
        detail="Try again",
      ),
    ),
  )
  assert_true(failed.access.waiting_for_viewed)
  assert_true(failed.viewed.poll_scheduled)
  assert_eq(failed.viewed.retry, 2)
  assert_true(failed.viewed.files[0].pending == pending)
  let limited = snapshot_viewed_read(
    viewed_test_tick(failed),
    Err(
      @github_client.HttpRequestError(
        status=429,
        code="rate_limit",
        detail="Try later",
      ),
    ),
  )
  assert_true(limited.access.waiting_for_viewed)
  assert_false(limited.viewed.poll_scheduled)
  assert_eq(limited.viewed.retry, 6)
  assert_true(viewed_test_tick(limited) == limited)
  let manual = home_step(limited, Viewed(Refresh))
  assert_eq(manual.viewed.retry, 0)
  assert_true(manual.viewed.loading)
  assert_true(manual.viewed.error is None)
  let ready = snapshot_viewed_read(manual, Ok(viewed_test_data(Viewed)))
  assert_false(ready.access.waiting_for_viewed)
  assert_true(ready.access.reload_requested)
  assert_false(snapshot_replacement_blocked(ready))
}

///|
test "Load latest starts a new confirmation round when the previous read has paused" {
  let confirming = viewed_test_loaded(
    viewed_test_timeout(
      mark_snapshot_stale(
        viewed_test_toggle(viewed_test_loaded(viewed_test_model(), Unviewed)),
      ),
    ),
    Unviewed,
  )
  assert_false(confirming.viewed.loading)
  assert_true(confirming.viewed.poll_scheduled)
  let waiting = home_step(confirming, Review(LoadLatestSnapshot))
  assert_true(waiting.access.waiting_for_viewed)
  assert_false(waiting.access.reload_requested)
  assert_true(waiting.viewed.loading)
  assert_false(waiting.viewed.poll_scheduled)
  assert_eq(waiting.viewed.retry, 0)
}

///|
test "waiting Load latest still respects replacement blockers added during confirmation" {
  let waiting = snapshot_viewed_waiting()
  let blocked = {
    ..waiting,
    pull_merge: { ..waiting.pull_merge, submitting: true, },
  }
  let confirmed = snapshot_viewed_read(blocked, Ok(viewed_test_data(Viewed)))
  assert_true(confirmed.viewed.files[0].pending is None)
  assert_true(confirmed.access.waiting_for_viewed)
  assert_false(confirmed.access.reload_requested)
  assert_true(confirmed.phase == waiting.phase)
  assert_true(snapshot_replacement_blocked(confirmed))
}

///|
test "navigation logout and account switches discard waiting Load latest and ignore old reads" {
  let waiting = snapshot_viewed_waiting()
  let old_read : Msg = Viewed(
    Loaded(
      waiting.viewed.epoch,
      waiting.viewed.read_serial,
      Ok({ ..viewed_test_data(Viewed), head_sha: "b".repeat(40), }),
    ),
  )
  let switched = home_step(
    waiting,
    Auth(
      ReactivationAuthStatusLoaded(
        waiting.auth_revision,
        waiting.generation,
        waiting.route,
        Ok({ ..signed_in_api_status("bob"), user_id: Some("2"), }),
      ),
    ),
  )
  let left = home_step(
    waiting,
    Ui(RouteChanged(@url.parse("http://localhost/"))),
  )
  let logged_out = home_step(waiting, Auth(Logout))
  for next in [switched, left, logged_out] {
    assert_false(next.access.waiting_for_viewed)
    assert_false(next.access.reload_requested)
    let late = home_step(next, old_read)
    assert_true(late == next)
  }
}
