///|
pub(all) enum FileViewedState {
  Viewed
  Unviewed
  Dismissed
} derive(Eq, FromJson(style="legacy"), ToJson(style="legacy"))

///|
pub(all) struct PullViewedGet {
  owner : String
  repo : String
  number : String
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct PullFileViewedSet {
  owner : String
  repo : String
  number : String
  path : String
  viewed : Bool
  base_sha : String
  head_sha : String
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct ApiFileViewed {
  path : String
  state : FileViewedState
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct ApiPullViewed {
  base_sha : String
  head_sha : String
  files : Array[ApiFileViewed]
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct ApiFileViewedResult {
  base_sha : String
  head_sha : String
  file : ApiFileViewed
} derive(Eq, FromJson, ToJson)
