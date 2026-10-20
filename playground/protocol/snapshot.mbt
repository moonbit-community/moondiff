///|
pub(all) struct ApiPullSnapshot {
  metadata : ApiPull
  comparison : ApiCompare
  files : Array[ApiFile]
  signature : String
} derive(Eq, FromJson, ToJson)

///|
pub(all) enum ApiPullSnapshotResult {
  Complete(ApiPullSnapshot)
  MetadataOnly(ApiPull)
} derive(Eq, FromJson(style="legacy"), ToJson(style="legacy"))

///|
pub const SNAPSHOT_FILE_LIMIT : Int32 = 300

///|
pub const SNAPSHOT_BYTE_LIMIT : Int32 = 8 * 1048576

///|
pub fn same_pull_snapshot(initial : ApiPull, verified : ApiPull) -> Bool {
  initial.base == verified.base &&
  initial.head == verified.head &&
  initial.changed_files == verified.changed_files &&
  initial.commits == verified.commits
}

///|
pub fn snapshot_signature(pull : ApiPull, comparison : ApiCompare) -> String {
  Json::array([
    ToJson::to_json(pull.base),
    ToJson::to_json(pull.head),
    Json(pull.changed_files),
    ToJson::to_json(pull.commits),
    Json(comparison.merge_base_commit.sha),
  ]).stringify()
}
