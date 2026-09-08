///|
pub(all) struct ApiDeviceFlow {
  flow_id : String
  user_code : String
  verification_uri : String
  expires_in : Int
  poll_after : Int
} derive(FromJson)

///|
pub(all) struct ApiAuthStatus {
  authenticated : Bool
  login : String?
  install_url : String?
  device_flow : ApiDeviceFlow?
} derive(FromJson)
