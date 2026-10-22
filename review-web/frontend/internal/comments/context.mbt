///|
pub(all) struct Failure {
  message : String
  code : String?
} derive(Eq)

///|
priv enum Phase {
  Idle
  Showing(Snapshot)
}

///|
priv struct Model {
  review : Session
  generation : Int32
  route : CommitRef?
  phase : Phase
  enabled : Bool
}

///|
fn with_review(model : Model, review : Session) -> Model {
  { ..model, review, }
}

///|
fn comment_failure_message(error : Failure) -> String {
  error.message
}

///|
pub(all) struct Snapshot {
  reference : CommitRef
  sha : String
  pull_snapshot : ApiPull?
} derive(Eq)

///|
/// Compare code and anchor identity while allowing display metadata to change.
pub fn Snapshot::same_version(self : Snapshot, other : Snapshot) -> Bool {
  self.reference == other.reference &&
  self.sha == other.sha &&
  (match (self.pull_snapshot, other.pull_snapshot) {
    (Some(left), Some(right)) => same_pull_snapshot(left, right)
    (None, None) => true
    _ => false
  })
}

///|
pub(all) struct Context {
  generation : Int32
  route : CommitRef?
  snapshot : Snapshot?
  enabled : Bool
} derive(Eq)

///|
pub fn update(session : Session, event : Event) -> (Session, Array[Effect]) {
  if event is ContextChanged(context) {
    let stale = if session.draft()
      is Some({ kind: InlineDraft(_, _), snapshot: Some(snapshot), .. }) &&
      context.snapshot is Some(current) &&
      !snapshot.same_version(current) {
      true
    } else {
      session.snapshot_stale
    }
    return ({ ..session, context, snapshot_stale: stale, }, [])
  }
  let context = session.context
  let model = Model::{
    review: session,
    generation: context.generation,
    route: context.route,
    phase: context.snapshot.map(view => Showing(view)).unwrap_or(Idle),
    enabled: context.enabled,
  }
  let (next, effects) = update_review(model, event)
  (index_comments(session, next.review), effects)
}
