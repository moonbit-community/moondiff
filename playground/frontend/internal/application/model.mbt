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
pub(all) struct Model {
  input : String
  generation : Int
  view_mode : ViewMode
  diff_algorithm : DiffAlgorithm
  ignore_comments : Bool
  ignore_tests : Bool
  phase : Phase
  route : CommitRef?
  file_tree : FileTreeState
  auth : AuthStatus
  auth_revision : Int
  restore_pending : Bool
  last_authenticated_user_id : String?
  review : Session
} derive(Eq)

///|
fn initial_model() -> Model {
  {
    input: "",
    generation: 0,
    view_mode: Split,
    diff_algorithm: LexicalAlgorithm,
    ignore_comments: true,
    ignore_tests: true,
    phase: Idle,
    route: None,
    file_tree: initial_file_tree_state(),
    auth: AuthChecking,
    auth_revision: 0,
    restore_pending: false,
    last_authenticated_user_id: None,
    review: initial_review_state(),
  }
}

///|
fn initial_review_state() -> Session {
  @comments.Session::new(enabled=true)
}
