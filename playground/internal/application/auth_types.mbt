///|
pub(all) enum DeviceCodeCopyStatus {
  DeviceCodeCopyReady
  DeviceCodeCopyDone
  DeviceCodeCopyError(String)
} derive(Eq)

///|
pub(all) struct DeviceAuthorization {
  flow_id : String
  user_code : String
  verification_uri : String
  expires_in : Int
  poll_after : Int
  install_url : String?
  copy_status : DeviceCodeCopyStatus
} derive(Eq)

///|
pub(all) enum AuthStatus {
  WebReadOnly
  AuthChecking
  Anonymous(String?)
  DeviceAuthorizing(DeviceAuthorization)
  DeviceCancelling(DeviceAuthorization)
  SignedIn(login~ : String?, install_url~ : String?)
  AuthFailed(String)
} derive(Eq)

///|
pub fn auth_status_from_api(status : ApiAuthStatus) -> AuthStatus {
  if status.authenticated {
    SignedIn(login=status.login, install_url=status.install_url)
  } else if status.device_flow is Some(flow) {
    DeviceAuthorizing({
      flow_id: flow.flow_id,
      user_code: flow.user_code,
      verification_uri: flow.verification_uri,
      expires_in: flow.expires_in,
      poll_after: flow.poll_after,
      install_url: status.install_url,
      copy_status: DeviceCodeCopyReady,
    })
  } else {
    Anonymous(status.install_url)
  }
}

///|
pub fn auth_status_from_api_preserving(
  status : ApiAuthStatus,
  previous : AuthStatus,
) -> AuthStatus {
  let next = auth_status_from_api(status)
  match (next, previous) {
    (DeviceAuthorizing(device), DeviceAuthorizing(old)) if device.flow_id ==
      old.flow_id =>
      DeviceAuthorizing({ ..device, copy_status: old.copy_status, })
    (DeviceAuthorizing(device), DeviceCancelling(old)) if device.flow_id ==
      old.flow_id =>
      DeviceCancelling({ ..device, copy_status: old.copy_status, })
    _ => next
  }
}
