///|
pub(all) enum AuthStatus {
  AuthChecking
  Anonymous(String?)
  Authorizing(ApiDeviceFlow, String)
  DeviceCancelling(String, String)
  SignedIn(login~ : String?, user_id~ : String?, install_url~ : String?)
  AuthFailed(String)
} derive(Eq)

///|
pub fn auth_status_from_api(status : ApiAuthStatus) -> AuthStatus {
  if status.device_flow is Some(flow) && flow.phase.active() {
    Authorizing(flow, "")
  } else if status.device_flow is Some(flow) &&
    flow.phase is (Expired | Denied | Failed) {
    AuthFailed(flow.message)
  } else if status.authenticated {
    SignedIn(
      login=status.login,
      user_id=status.user_id,
      install_url=status.install_url,
    )
  } else if status.user_id is Some(_) {
    AuthFailed("Your GitHub session expired. Sign in again.")
  } else {
    Anonymous(status.install_url)
  }
}

///|
fn auth_device_id(auth : AuthStatus) -> String? {
  match auth {
    Authorizing(flow, _) => Some(flow.id)
    DeviceCancelling(id, _) => Some(id)
    _ => None
  }
}

///|
fn starting_device(id : String) -> ApiDeviceFlow {
  {
    id,
    phase: @protocol.DevicePhase::Starting,
    user_code: "",
    verification_uri: "",
    expires_at: 0,
    retry_after: 5,
    message: "",
  }
}
