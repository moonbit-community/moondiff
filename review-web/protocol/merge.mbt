///|
pub(all) enum ApiCiState {
  Success
  Pending
  Failure
  Neutral
} derive(Eq, FromJson(style="legacy"), ToJson(style="legacy"))

///|
pub(all) enum ApiCiSource {
  CheckRun
  CommitStatus
} derive(Eq, FromJson(style="legacy"), ToJson(style="legacy"))

///|
pub(all) struct ApiCiCheck {
  name : String
  state : ApiCiState
  description : String
  details_url : String?
  source : ApiCiSource
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct PullMergeStatusGet {
  owner : String
  repo : String
  number : String
  expected_base_sha : String
  expected_head_sha : String
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct PullRebaseMerge {
  owner : String
  repo : String
  number : String
  expected_base_sha : String
  expected_head_sha : String
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct ApiPullMergeStatus {
  base_sha : String
  head_sha : String
  open : Bool
  draft : Bool
  merged : Bool
  mergeable : Bool?
  rebaseable : Bool?
  mergeable_state : String
  ci_summary : ApiCiState?
  ci_checks : Array[ApiCiCheck]
  ci_warnings : Array[String]
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct ApiPullMergeResult {
  merged : Bool
  sha : String?
  message : String
} derive(Eq, FromJson, ToJson)
