///|
pub(all) enum ViewMode {
  Split
  Unified
} derive(Eq)

///|
pub(all) enum DiffAlgorithm {
  LexicalAlgorithm
  AstAlgorithm
} derive(Eq, Hash)

///|
pub(all) enum SourceSide {
  Old
  New
} derive(Eq)

///|
pub(all) enum SideLoad {
  NotRequested
  Loading
  Ready(Array[String])
  CannotRender(String, Bool)
  LoadFailed(String)
} derive(Eq)

///|
pub(all) enum CachedDiffResult {
  Line(@mbtdiff.HunkDocument)
  MoonBit(document~ : @mbtdiff.DiffDocument, status~ : @mbtdiff.DiffStatus)
} derive(Eq)

///|
pub(all) enum CacheKey {
  Line
  MoonBit(DiffAlgorithm, Bool, Bool)
} derive(Eq, Hash)

///|
pub(all) struct DiffCache {
  entries : @immut_hashmap.HashMap[CacheKey, CachedDiffResult]
} derive(Eq)

///|
pub fn DiffCache::empty() -> DiffCache {
  { entries: @immut_hashmap.new(), }
}

///|
pub fn DiffCache::get(self : DiffCache, key : CacheKey) -> CachedDiffResult? {
  self.entries.get(key)
}

///|
pub fn DiffCache::put(
  self : DiffCache,
  key : CacheKey,
  value : CachedDiffResult,
) -> DiffCache {
  { entries: self.entries.add(key, value), }
}

///|
pub(all) struct FileState {
  file : ApiFile
  diff_mode : FileDiffMode
  expanded : Bool
  old_side : SideLoad
  new_side : SideLoad
  diff_cache : DiffCache
} derive(Eq)

///|
pub(all) struct ChangeView {
  reference : CommitRef
  sha : String
  parent_sha : String?
  old_revision : Revision?
  new_revision : Revision
  message : String
  html_url : String
  stats : ApiStats
  total_files : Int
  files : Array[FileState]
} derive(Eq)
