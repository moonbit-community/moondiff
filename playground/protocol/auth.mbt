///|
pub(all) enum DevicePhase {
  Starting
  Pending
  Verifying
  Completed
  Cancelled
  Expired
  Denied
  Failed
} derive(Eq, FromJson(style="legacy"), ToJson(style="legacy"))

///|
pub fn DevicePhase::active(self : DevicePhase) -> Bool {
  self is (Starting | Pending | Verifying)
}

///|
pub(all) struct ApiAuthStatus {
  authenticated : Bool
  csrf_token : String
  login : String?
  user_id : String?
  install_url : String?
  device_flow : ApiDeviceFlow?
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct ApiDeviceFlow {
  id : String
  phase : DevicePhase
  user_code : String
  verification_uri : String
  expires_at : Double
  retry_after : Int
  message : String
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct DeviceResponse {
  request_id : String
  status : ApiAuthStatus
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct DeviceStart {
  attempt_id : String
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct DeviceAuthorization {
  authorization_id : String
} derive(Eq, FromJson, ToJson)
