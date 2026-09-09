///|
test "web session maps immutable identity and expired session preserves recovery" {
  let status : ApiAuthStatus = {
    device_flow: None,
    csrf_token: "csrf-test",
    authenticated: true,
    login: Some("alice"),
    user_id: Some("123"),
    install_url: None,
  }
  assert_true(auth_status_from_api(status) is SignedIn(user_id=Some("123"), ..))
  assert_true(
    auth_status_from_api({ ..status, authenticated: false, }) is AuthFailed(_),
  )
  assert_true(
    auth_status_from_api({ ..status, authenticated: false, user_id: None, })
    is Anonymous(_),
  )
}

///|
test "same user id survives a login rename but switching accounts clears the draft" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let before = auth_identity_test_model(AuthFailed("expired"), Some("123"))
  let (same, _) = finish_sign_in(
    before,
    {
      device_flow: None,
      csrf_token: "csrf-test",
      authenticated: true,
      login: Some("renamed"),
      user_id: Some("123"),
      install_url: None,
    },
    emit,
  )
  assert_eq(same.generation, before.generation)
  assert_true(same.review.draft() == before.review.draft())
  let (other, _) = finish_sign_in(
    before,
    {
      device_flow: None,
      csrf_token: "csrf-test",
      authenticated: true,
      login: Some("alice"),
      user_id: Some("456"),
      install_url: None,
    },
    emit,
  )
  assert_eq(other.generation, before.generation + 1)
  assert_true(other.review.draft() is None)
}

///|
fn pending_api_status(id : String) -> ApiAuthStatus {
  {
    ..anonymous_api_status(),
    device_flow: Some({
      id,
      phase: @protocol.DevicePhase::Pending,
      user_code: "ABCD-EFGH",
      verification_uri: "https://github.com/login/device",
      expires_at: 2000000000,
      retry_after: 11,
      message: "",
    }),
  }
}

///|
test "session initialization restores the code and keeps drafts during pending sign-in" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let before = auth_identity_test_model(AuthFailed("expired"), Some("123"))
  let (pending, _) = update_auth(
    before,
    AuthStatusLoaded(
      before.auth_revision,
      Ok(pending_api_status("device-attempt-00001")),
    ),
    emit,
  )
  guard pending.auth is Authorizing(flow, _) else {
    fail("Expected restored device authorization")
  }
  assert_eq(flow.user_code, "ABCD-EFGH")
  assert_eq(flow.retry_after, 11)
  assert_true(pending.review.draft() == before.review.draft())
  assert_eq(pending.last_authenticated_user_id, Some("123"))
  assert_eq(pending.generation, before.generation)
}

///|
test "cancel and logout ignore late device, copy and session responses" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let status = pending_api_status("device-attempt-00001")
  let waiting = with_auth(initial_model(), auth_status_from_api(status))
  let result = Ok({
    ..signed_in_api_status("alice"),
    device_flow: status.device_flow.map(flow => {
      ..flow,
      phase: @protocol.DevicePhase::Completed,
    }),
  })
  let (cancelling, _) = update_auth(waiting, CancelSignIn, emit)
  let (logging_out, _) = update_auth(waiting, Logout, emit)
  for next in [cancelling, logging_out] {
    for
      msg in [
        DeviceUpdated(
          waiting.auth_revision,
          "device-attempt-00001",
          false,
          result.map(status => {
            (
              { request_id: "device-attempt-00001", status, } :
              @protocol.DeviceResponse)
          }),
        ),
        AuthStatusLoaded(waiting.auth_revision, result),
        ReactivationAuthStatusLoaded(
          waiting.auth_revision,
          waiting.generation,
          waiting.route,
          result,
        ),
        DeviceCodeCopied(waiting.auth_revision, "device-attempt-00001", true),
      ] {
      assert_true(update_auth(next, msg, emit).0 == next)
    }
  }
}

///|
test "responses must match both the current attempt and echoed authorization ID" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let status = pending_api_status("device-attempt-00001")
  let waiting = with_auth(initial_model(), auth_status_from_api(status))
  let completed = {
    ..signed_in_api_status("alice"),
    device_flow: status.device_flow,
  }
  assert_true(
    update_auth(
      waiting,
      DeviceUpdated(
        0,
        "device-attempt-00001",
        false,
        Ok({ request_id: "wrong-attempt-00001", status: completed, }),
      ),
      emit,
    ).0 ==
    waiting,
  )
  assert_true(
    update_auth(
      waiting,
      DeviceUpdated(
        0,
        "old-attempt-000000",
        false,
        Ok({ request_id: "wrong-attempt-00001", status: completed, }),
      ),
      emit,
    ).0 ==
    waiting,
  )
  let next = { ..waiting, auth_revision: 2, }
  assert_true(
    update_auth(
      next,
      DeviceCancelFinished(
        1,
        "device-attempt-00001",
        Ok({
          request_id: "device-attempt-00001",
          status: anonymous_api_status(),
        }),
      ),
      emit,
    ).0 ==
    next,
  )
}

///|
test "pending session errors retain recovery identity and can distinguish terminal device errors" {
  let pending = pending_api_status("device-attempt-00001")
  for phase in [@protocol.Expired, @protocol.Denied, @protocol.Failed] {
    let terminal = {
      ..pending,
      device_flow: pending.device_flow.map(flow => {
        ..flow,
        phase,
        message: "Please retry",
      }),
    }
    assert_true(auth_status_from_api(terminal) is AuthFailed("Please retry"))
  }
  let cancelled = {
    ..pending,
    device_flow: pending.device_flow.map(flow => {
      ..flow,
      phase: @protocol.DevicePhase::Cancelled,
    }),
  }
  assert_true(auth_status_from_api(cancelled) is Anonymous(_))
  assert_true(
    auth_status_from_api({ ..cancelled, user_id: Some("123"), })
    is AuthFailed(_),
  )
}
