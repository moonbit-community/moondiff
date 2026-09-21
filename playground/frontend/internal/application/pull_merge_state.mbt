///|
pub(all) struct PullMergeState {
  epoch : Int
  serial : Int
  status : @protocol.ApiPullMergeStatus?
  loading : Bool
  submitting : Bool
  error : String?
  retry : Int
  poll_scheduled : Bool
  stale : Bool
} derive(Eq)

///|
fn empty_pull_merge_state(epoch : Int) -> PullMergeState {
  {
    epoch,
    serial: 0,
    status: None,
    loading: false,
    submitting: false,
    error: None,
    retry: 0,
    poll_scheduled: false,
    stale: false,
  }
}

///|
pub fn PullMergeState::new() -> PullMergeState {
  empty_pull_merge_state(0)
}

///|
fn pull_merge_scope(model : Model) -> (CommitRef, String, String, String)? {
  guard model.phase is Showing(view) &&
    view.reference.target is PullRequest(number) &&
    view.pull_snapshot is Some(snapshot) else {
    return None
  }
  Some((view.reference, number, snapshot.base.sha, snapshot.head.sha))
}

///|
fn pull_merge_status_pending(status : @protocol.ApiPullMergeStatus) -> Bool {
  !status.merged &&
  status.open &&
  !status.draft &&
  (
    status.mergeable is None ||
    status.rebaseable is None ||
    status.ci_summary is Some(Pending)
  )
}

///|
fn pull_merge_actionable(status : @protocol.ApiPullMergeStatus) -> Bool {
  status.open &&
  !status.draft &&
  !status.merged &&
  status.mergeable is Some(true) &&
  status.rebaseable is Some(true) &&
  status.mergeable_state != "blocked"
}

///|
fn stale_pull_merge(model : Model) -> Model {
  with_review(
    {
      ..model,
      pull_merge: {
        ..model.pull_merge,
        loading: false,
        submitting: false,
        poll_scheduled: false,
        stale: true,
      },
    },
    @comments.update(model.review, SnapshotChanged).0,
  )
}
