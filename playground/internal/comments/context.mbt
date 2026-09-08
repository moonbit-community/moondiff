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
  generation : Int
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
pub(all) struct Context {
  generation : Int
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
      snapshot != current {
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
  (next.review, effects)
}
