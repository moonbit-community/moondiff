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
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct ApiCompare {
  merge_base_commit : ApiParent
} derive(Eq, FromJson, ToJson)
