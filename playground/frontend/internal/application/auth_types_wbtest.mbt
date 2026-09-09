///|
test "authentication DTOs map to review auth state and preserve device copy feedback" {
  guard auth_status_from_api({
      authenticated: true,
      login: Some("octocat"),
      install_url: Some("https://github.com/apps/moondiff/installations/new"),
      device_flow: None,
    })
    is SignedIn(login~, install_url~) else {
    fail("expected an authenticated status")
  }
  assert_eq(login, Some("octocat"))
  assert_eq(
    install_url,
    Some("https://github.com/apps/moondiff/installations/new"),
  )
  let pending : ApiAuthStatus = {
    authenticated: false,
    login: None,
    install_url: Some("https://github.com/apps/moondiff/installations/new"),
    device_flow: Some({
      flow_id: "flow-1",
      user_code: "ABCD-EFGH",
      verification_uri: "https://github.com/login/device",
      expires_in: 900,
      poll_after: 5,
    }),
  }
  guard auth_status_from_api(pending) is DeviceAuthorizing(device) else {
    fail("expected a pending device authorization")
  }
  assert_eq(device.flow_id, "flow-1")
  assert_true(device.copy_status is DeviceCodeCopyReady)
  guard auth_status_from_api_preserving(
      pending,
      DeviceAuthorizing({ ..device, copy_status: DeviceCodeCopyDone, }),
    )
    is DeviceAuthorizing(preserved) else {
    fail("expected the same device flow to remain active")
  }
  assert_true(preserved.copy_status is DeviceCodeCopyDone)
  guard auth_status_from_api_preserving(
      pending,
      DeviceCancelling({ ..device, copy_status: DeviceCodeCopyDone, }),
    )
    is DeviceCancelling(cancelling) else {
    fail("expected cancellation of the same device flow to be preserved")
  }
  assert_eq(cancelling.flow_id, "flow-1")
  assert_true(cancelling.copy_status is DeviceCodeCopyDone)
}
