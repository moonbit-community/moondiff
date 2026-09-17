///|
pub(all) enum ViewerPullKind {
  ReviewRequested
  Authored
} derive(Eq, FromJson(style="legacy"), ToJson(style="legacy"))

///|
pub(all) struct ViewerPullsGet {
  kind : ViewerPullKind
  cursor : String?
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct PullCommitsGet {
  owner : String
  repo : String
  number : String
  cursor : String?
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct ApiPullSummary {
  owner : String
  repo : String
  number : String
  title : String
  author : String
  updated_at : String
  draft : Bool
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct ApiViewerPulls {
  items : Array[ApiPullSummary]
  total_count : Int
  next_cursor : String?
  // A retryable search window remains; the result must not look complete.
  incomplete : String?
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct ApiCommitSummary {
  sha : String
  message : String
  author : String
  committed_at : String
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct ApiPullCommits {
  items : Array[ApiCommitSummary]
  total_count : Int
  next_cursor : String?
  base_sha : String
  head_sha : String
} derive(Eq, FromJson, ToJson)

///|
fn check_cursor(cursor : String?) -> Unit raise {
  if cursor is Some(value) {
    require(
      !value.is_empty() && value.length() <= 16384,
      "invalid_arguments",
      "Invalid pagination cursor.",
    )
  }
}
