///|
pub(all) enum Phase {
  Idle
  LoadingCommit(
    reference~ : CommitRef,
    repository~ : RepositoryRef,
    page~ : Int,
    first~ : ApiCommit?,
    files~ : Array[ApiFile]
  )
  LoadingPullMetadata(reference~ : CommitRef, attempt~ : Int)
  LoadingPullCommitMetadata(reference~ : CommitRef)
  LoadingPullSnapshot(
    reference~ : CommitRef,
    attempt~ : Int,
    metadata~ : ApiPull,
    compare~ : ApiCompare?,
    page~ : Int,
    files~ : Array[ApiFile]
  )
  ValidatingPullSnapshot(
    reference~ : CommitRef,
    attempt~ : Int,
    metadata~ : ApiPull,
    compare~ : ApiCompare,
    files~ : Array[ApiFile]
  )
  LoadFailed(String)
  Showing(ChangeView)
} derive(Eq)

///|
pub(all) enum CopyStatus {
  CopyReady
  Copied
  CopyError(String)
} derive(Eq)

///|
pub(all) struct Model {
  input : String
  generation : Int
  view_mode : ViewMode
  diff_algorithm : DiffAlgorithm
  ignore_comments : Bool
  ignore_tests : Bool
  phase : Phase
  route : CommitRef?
  share_url : String?
  copy_status : CopyStatus
  file_tree : FileTreeState
  review : ReviewState
} derive(Eq)

///|
fn initial_model() -> Model {
  {
    input: "",
    generation: 0,
    view_mode: Split,
    diff_algorithm: LexicalAlgorithm,
    ignore_comments: false,
    ignore_tests: false,
    phase: Idle,
    route: None,
    share_url: None,
    copy_status: CopyReady,
    file_tree: initial_file_tree_state(),
    review: initial_review_state(),
  }
}
