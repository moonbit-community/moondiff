///|
#derive(Eq)
pub(all) struct Failure {
  message : String
  code : String?
}

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
#derive(Eq)
pub(all) struct Snapshot {
  reference : CommitRef
  sha : String
  pull_snapshot : ApiPull?
}

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
#derive(Eq)
pub(all) struct Context {
  generation : Int32
  route : CommitRef?
  snapshot : Snapshot?
  enabled : Bool
}

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
    return (
      {
        ..session,
        context,
        snapshot_stale: stale,
        overview_collapsed: session.overview_collapsed &&
        context.generation == session.context.generation &&
        context.route == session.context.route,
        collapsed_comments: if context.generation == session.context.generation &&
          context.route == session.context.route &&
          (match (context.snapshot, session.context.snapshot) {
            (Some(next), Some(previous)) => next.same_version(previous)
            (None, None) => true
            _ => false
          }) {
          session.collapsed_comments
        } else {
          []
        },
        expanded_bodies: if context.generation == session.context.generation {
          session.expanded_bodies
        } else {
          []
        },
      },
      [],
    )
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
