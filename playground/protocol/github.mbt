///|
pub(all) struct ApiStats {
  additions : Int
  deletions : Int
  total : Int
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct ApiCommitInfo {
  message : String
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct ApiParent {
  sha : String
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct ApiFile {
  filename : String
  previous_filename : String?
  status : String
  additions : Int
  deletions : Int
  changes : Int
  patch : String?
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct ApiCommit {
  sha : String
  html_url : String
  commit : ApiCommitInfo
  parents : Array[ApiParent]
  stats : ApiStats
  files : Array[ApiFile]
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct ApiRepository {
  full_name : String
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct ApiPullBranch {
  sha : String
  repo : ApiRepository?
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct ApiPull {
  title : String
  html_url : String
  base : ApiPullBranch
  head : ApiPullBranch
  additions : Int
  deletions : Int
  changed_files : Int
  commits : Int?
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct ApiCompare {
  merge_base_commit : ApiParent
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct ApiRangeCommit {
  sha : String
  commit : ApiCommitInfo
  parents : Array[ApiParent]
} derive(Eq, FromJson, ToJson)

///|
/// GitHub returns files only on the first page of a paginated comparison.
pub(all) struct ApiRangeCompare {
  base_commit : ApiRangeCommit
  merge_base_commit : ApiParent
  total_commits : Int
  commits : Array[ApiRangeCommit]
  files : Array[ApiFile]?
} derive(Eq, FromJson, ToJson)

///|
pub fn resolved_sha(requested : String, response : String) -> String raise {
  let sha = response.trim().to_owned()
  guard (sha.length() == 40 || sha.length() == 64) &&
    valid_sha(sha) &&
    sha.to_lower().has_prefix(requested.to_lower()) else {
    raise ProtocolError(
      "invalid_github_response", "GitHub returned an invalid commit SHA.",
    )
  }
  sha.to_lower()
}
