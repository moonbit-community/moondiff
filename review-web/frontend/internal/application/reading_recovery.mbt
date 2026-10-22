///|
// Request bookkeeping only. The renderer owns all nodes, geometry and listeners.
// A cancelled token remains invalid even if a retained request callback uses it.
pub(all) struct ReadingRecovery {
  id : Int32
  generation : Int32
  entry : String
  mut cancelled : Bool
  mut finished : Bool
  mut auth_serial : Int32
  auth_requests : Map[Int32, Int32]
  mut snapshot : Bool
  mut comments_queued : Int32
  mut comments_refresh : Int32?
  mut viewed : (Int32, Int32)?
  mut merge : (Int32, Int32)?
} derive(Eq)

///|
#deprecated
#doc(hidden)
pub extend ReadingRecovery with Eq::{not_equal, equal}

///|
pub fn ReadingRecovery::pending(self : ReadingRecovery) -> Bool {
  !self.auth_requests.is_empty() ||
  self.snapshot ||
  self.comments_queued > 0 ||
  self.comments_refresh is Some(_) ||
  self.viewed is Some(_) ||
  self.merge is Some(_)
}

///|
fn new_reading_recovery(model : Model) -> Model {
  {
    ..model,
    reading_recovery_serial: model.reading_recovery_serial + 1,
    reading_recovery_blocked: false,
    reading_recovery: Some({
      id: model.reading_recovery_serial + 1,
      generation: model.generation,
      entry: model.navigation.entry.id,
      cancelled: false,
      finished: false,
      auth_serial: 0,
      auth_requests: {},
      snapshot: false,
      comments_queued: 0,
      comments_refresh: None,
      viewed: None,
      merge: None,
    }),
  }
}

///|
fn recovery_auth_request(
  recovery : ReadingRecovery?,
  revision : Int32,
  emit : @rabbita.Emit[Msg],
) -> () -> @rabbita.Cmd {
  guard recovery is Some(token) && !token.cancelled && !token.finished else {
    return () => @rabbita.none
  }
  token.auth_serial += 1
  let request = token.auth_serial
  let recovery = token.id
  token.auth_requests[request] = revision
  () => emit(Ui(ReadingAuthRequestFinished(recovery, revision, request)))
}

///|
fn prepare_reading_recovery(model : Model, msg : Msg) -> Model {
  let starts = msg is Auth(StartSignIn | RestoreAuth | SessionInvalidated) ||
    msg is Review(PageReactivated | RefreshComments)
  let explicit = msg is Auth(StartSignIn | RestoreAuth) ||
    msg is Review(RefreshComments)
  let model = if starts &&
    model.phase is Showing(_) &&
    !model.navigation.restore_position &&
    (explicit || !model.reading_recovery_blocked) &&
    (
      model.reading_recovery is None ||
      model.reading_recovery
      .map(t => t.finished && !t.cancelled)
      .unwrap_or(false) ||
      (
        explicit &&
        model.reading_recovery.map(t => t.cancelled).unwrap_or(false)
      )
    ) {
    new_reading_recovery(model)
  } else {
    model
  }
  if model.reading_recovery is Some(token) {
    if msg is Ui(ReadingAuthRequestFinished(id, revision, request)) &&
      token.id == id &&
      token.auth_requests.get(request) == Some(revision) {
      token.auth_requests.remove(request)
    }
    if msg is Ui(Navigate(_) | RouteChanged(_) | Submit | RetryRoute) ||
      msg is Auth(Logout | CancelSignIn) {
      token.cancelled = true
    }
  }
  model
}

///|
fn reconcile_reading_recovery(before : Model, next : Model, msg : Msg) -> Model {
  let next = if before.generation != next.generation ||
    before.navigation.entry.id != next.navigation.entry.id {
    { ..next, reading_recovery_blocked: false, }
  } else {
    next
  }
  let next = if before.generation == next.generation &&
    before.phase is Showing(_) &&
    next.phase is Showing(_) &&
    before.source_pause != next.source_pause &&
    next.source_pause is Some(_) &&
    (
      next.reading_recovery is None ||
      next.reading_recovery
      .map(t => t.finished && !t.cancelled)
      .unwrap_or(false)
    ) &&
    !next.reading_recovery_blocked &&
    !next.navigation.restore_position {
    new_reading_recovery(next)
  } else {
    next
  }
  guard next.reading_recovery is Some(token) else { return next }
  if token.generation != next.generation ||
    token.entry != next.navigation.entry.id ||
    !(next.phase is Showing(_)) ||
    next.navigation.restore_position {
    token.cancelled = true
    return { ..next, reading_recovery: None, reading_recovery_blocked: false, }
  }
  for (request, revision) in token.auth_requests.iter().collect() {
    if revision != next.auth_revision {
      token.auth_requests.remove(request)
    }
  }
  if msg is Review(BeginCommentsRefresh(generation, _)) &&
    generation == token.generation &&
    token.comments_queued > 0 {
    token.comments_queued -= 1
    token.comments_refresh = Some(next.review.refresh_id)
  }
  if msg is Review(RefreshComments) &&
    next.review.refresh_id != before.review.refresh_id &&
    next.review.read_view().refresh_busy {
    token.comments_refresh = Some(next.review.refresh_id)
  }
  if token.comments_refresh is Some(id) &&
    (next.review.refresh_id != id || !next.review.read_view().refresh_busy) {
    token.comments_refresh = None
  }
  if token.viewed is Some((epoch, serial)) &&
    (
      !next.viewed.loading ||
      epoch != next.viewed.epoch ||
      serial != next.viewed.read_serial
    ) {
    token.viewed = None
  }
  if token.merge is Some((epoch, serial)) &&
    (
      !next.pull_merge.loading ||
      epoch != next.pull_merge.epoch ||
      serial != next.pull_merge.serial
    ) {
    token.merge = None
  }
  if !(next.access.freshness is Checking) {
    token.snapshot = false
  }
  next
}
