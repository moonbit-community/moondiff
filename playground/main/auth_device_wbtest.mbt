///|
fn device_api_status(
  flow_id : String,
  user_code? : String = "ABCD-EFGH",
  expires_in? : Int = 900,
  poll_after? : Int = 5,
) -> ApiAuthStatus {
  {
    authenticated: false,
    login: None,
    install_url: Some("https://github.com/apps/moondiff-test/installations/new"),
    device_flow: Some({
      flow_id,
      user_code,
      verification_uri: "https://github.com/login/device",
      expires_in,
      poll_after,
    }),
  }
}

///|
fn signed_in_api_status(login : String) -> ApiAuthStatus {
  {
    authenticated: true,
    login: Some(login),
    install_url: Some("https://github.com/apps/moondiff-test/installations/new"),
    device_flow: None,
  }
}

///|
fn anonymous_api_status() -> ApiAuthStatus {
  {
    authenticated: false,
    login: None,
    install_url: Some("https://github.com/apps/moondiff-test/installations/new"),
    device_flow: None,
  }
}

///|
fn device_auth_test_model(
  auth : AuthStatus,
  phase : Phase,
  route : CommitRef?,
) -> Model {
  {
    input: "",
    generation: 5,
    view_mode: Split,
    diff_algorithm: LexicalAlgorithm,
    ignore_comments: false,
    ignore_tests: false,
    phase,
    route,
    share_url: None,
    copy_status: CopyReady,
    review: {
      auth,
      comments: CommentsFailed("private repository"),
      draft: None,
    },
  }
}

///|
test "device authorization moves from code through pending to signed in" {
  let flow_id = "flow-current"
  let view = review_test_view()
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let anonymous = device_auth_test_model(
    Anonymous(Some("https://github.com/apps/moondiff-test/installations/new")),
    Showing(view),
    Some(view.reference),
  )
  let (started, _) = update_auth(
    anonymous,
    DeviceAuthorizationStarted(Ok(device_api_status(flow_id))),
    emit,
  )
  guard started.review.auth is DeviceAuthorizing(device) else {
    fail("expected the device code to be displayed")
  }
  assert_eq(device.flow_id, flow_id)
  assert_eq(device.user_code, "ABCD-EFGH")
  assert_true(device.copy_status is DeviceCodeCopyReady)

  let (pending, _) = update_auth(
    started,
    DeviceAuthorizationPolled(
      flow_id,
      Ok(device_api_status(flow_id, expires_in=895, poll_after=7)),
    ),
    emit,
  )
  guard pending.review.auth is DeviceAuthorizing(waiting) else {
    fail("expected authorization to remain pending")
  }
  assert_eq(waiting.expires_in, 895)
  assert_eq(waiting.poll_after, 7)

  let (signed_in, _) = update_auth(
    pending,
    DeviceAuthorizationPolled(flow_id, Ok(signed_in_api_status("octocat"))),
    emit,
  )
  assert_true(signed_in.review.auth is SignedIn(Some("octocat")))
  assert_true(signed_in.review.comments is CommentsLoading)
}

///|
test "device code copy feedback and cancellation stay scoped to the current flow" {
  let flow_id = "flow-copy"
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let model = device_auth_test_model(
    auth_status_from_api(device_api_status(flow_id)),
    Idle,
    None,
  )
  let (copying, _) = update_auth(model, CopyDeviceCode, emit)
  assert_true(copying == model)
  let (copied, _) = update_auth(model, DeviceCodeCopied(flow_id), emit)
  guard copied.review.auth is DeviceAuthorizing(done) else {
    fail("expected a device authorization")
  }
  assert_true(done.copy_status is DeviceCodeCopyDone)

  let (stale_copy, _) = update_auth(
    copied,
    DeviceCodeCopyFailed("old-flow", "no"),
    emit,
  )
  assert_true(stale_copy == copied)
  let (failed_copy, _) = update_auth(
    copied,
    DeviceCodeCopyFailed(flow_id, "clipboard denied"),
    emit,
  )
  guard failed_copy.review.auth is DeviceAuthorizing(failed) else {
    fail("expected a device authorization")
  }
  assert_true(failed.copy_status is DeviceCodeCopyError("clipboard denied"))

  let cancelling = with_review(
    failed_copy,
    review_state_with_auth(failed_copy.review, DeviceCancelling(failed)),
  )
  let (late_poll, _) = update_auth(
    cancelling,
    DeviceAuthorizationPolled(flow_id, Ok(signed_in_api_status("too-late"))),
    emit,
  )
  assert_true(late_poll == cancelling)
  let (cancelled, _) = update_auth(
    cancelling,
    DeviceAuthorizationCancelled(flow_id, Ok(anonymous_api_status())),
    emit,
  )
  assert_true(cancelled.review.auth is Anonymous(_))
}

///|
test "expired and stale device responses cannot authenticate another flow" {
  let current = "flow-new"
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let model = device_auth_test_model(
    auth_status_from_api(device_api_status(current)),
    Idle,
    None,
  )
  let (stale_poll, _) = update_auth(
    model,
    DeviceAuthorizationPolled(
      "flow-old",
      Ok(signed_in_api_status("wrong-user")),
    ),
    emit,
  )
  assert_true(stale_poll == model)
  let (stale_cancel, _) = update_auth(
    model,
    DeviceAuthorizationCancelled("flow-old", Ok(anonymous_api_status())),
    emit,
  )
  assert_true(stale_cancel == model)

  let (expired, _) = update_auth(
    model,
    DeviceAuthorizationPolled(
      current,
      Err(GitHubRequestError("The GitHub device code expired.")),
    ),
    emit,
  )
  assert_true(
    expired.review.auth is AuthFailed(message) && message.contains("expired"),
  )
}

///|
test "device sign-in retries a private repository load" {
  let reference = pull_reference("upstream", "private-project", "17")
  let flow_id = "flow-private"
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let model = device_auth_test_model(
    auth_status_from_api(device_api_status(flow_id)),
    LoadFailed("private repository"),
    Some(reference),
  )
  let (retried, _) = update_auth(
    model,
    DeviceAuthorizationPolled(flow_id, Ok(signed_in_api_status("reviewer"))),
    emit,
  )
  assert_eq(retried.generation, 6)
  assert_true(retried.phase is LoadingPullMetadata(attempt=0, ..))
  assert_true(retried.review.auth is SignedIn(Some("reviewer")))
}
