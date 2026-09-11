///|
pub(all) struct ViewedPending {
  record : ViewedRecord
  stored : Bool
  before : @protocol.FileViewedState
  expanded : Bool
  expansion_revision : Int
  confirming : Bool
} derive(Eq)

///|
pub(all) struct ViewedFile {
  state : @protocol.FileViewedState?
  pending : ViewedPending?
  error : String?
  touched : Bool
  expansion_revision : Int
} derive(Eq)

///|
pub(all) struct ViewedState {
  user_id : String?
  epoch : Int
  serial : Int
  read_serial : Int
  files : Array[ViewedFile]
  loading : Bool
  ready : Bool
  refresh_needed : Bool
  error : String?
  stale : Bool
  storage_ready : Bool
  retry : Int
  poll_scheduled : Bool
} derive(Eq)

///|
fn empty_viewed_state(epoch : Int) -> ViewedState {
  {
    user_id: None,
    epoch,
    serial: 0,
    read_serial: 0,
    files: [],
    loading: false,
    ready: false,
    refresh_needed: false,
    error: None,
    stale: false,
    storage_ready: false,
    retry: 0,
    poll_scheduled: false,
  }
}

///|
fn empty_viewed_file() -> ViewedFile {
  {
    state: None,
    pending: None,
    error: None,
    touched: false,
    expansion_revision: 0,
  }
}

///|
fn viewed_page(model : Model) -> (CommitRef, String, String)? {
  guard model.phase is Showing(view) &&
    view.reference.target is PullRequest(_) &&
    view.pull_snapshot is Some(snapshot) else {
    return None
  }
  Some((view.reference, snapshot.base.sha, snapshot.head.sha))
}

///|
// Resolve the accepted draft by path; its stored index may predate file ordering.
fn viewed_draft_file(model : Model) -> Int? {
  guard model.phase is Showing(view) &&
    model.review.draft() is Some(draft) &&
    draft.id.generation == model.generation &&
    draft.snapshot == comment_context(model).snapshot else {
    return None
  }
  let path = match draft.kind {
    InlineDraft(_, anchor) => anchor.path
    ReplyDraft(id) => {
      guard model.review.comments() is CommentsReady(bundle) &&
        bundle.review_comments.search_by(c => {
          c.id == id && c.in_reply_to_id is None
        })
        is Some(index) else {
        return None
      }
      bundle.review_comments[index].path
    }
    OverallDraft => return None
  }
  for index, file in view.files {
    if file.file.filename == path {
      return Some(index)
    }
  }
  None
}

///|
fn record_viewed_interaction(model : Model, index : Int) -> Model {
  guard model.phase is Showing(view) &&
    view.reference.target is PullRequest(_) &&
    view.files.get(index) is Some(_) else {
    return model
  }
  // Interaction tracking starts before authentication or the first Viewed read.
  let files = if model.viewed.files.length() == view.files.length() {
    model.viewed.files.copy()
  } else {
    view.files.map(_ => empty_viewed_file())
  }
  let file = files[index]
  files[index] = {
    ..file,
    touched: true,
    expansion_revision: file.expansion_revision + 1,
  }
  { ..model, viewed: { ..model.viewed, files, }, }
}

///|
fn viewed_scope(
  model : Model,
) -> (Int, Int, String?, String?, CommitRef, String, String)? {
  guard model.phase is Showing(view) &&
    view.reference.target is PullRequest(_) &&
    view.pull_snapshot is Some(snapshot) &&
    model.auth is SignedIn(user_id~, login~, ..) &&
    user_id is Some(id) &&
    !id.is_empty() else {
    return None
  }
  Some(
    (
      model.generation,
      model.auth_revision,
      user_id,
      login,
      view.reference,
      snapshot.base.sha,
      snapshot.head.sha,
    ),
  )
}

///|
fn viewed_writing(state : ViewedState) -> Bool {
  state.files.any(file => file.pending is Some({ confirming: false, .. }))
}

///|
fn with_viewed_file(model : Model, index : Int, file : ViewedFile) -> Model {
  let files = model.viewed.files.copy()
  files[index] = file
  { ..model, viewed: { ..model.viewed, files, }, }
}

///|
fn viewed_expansion(
  model : Model,
  index : Int,
  expanded : Bool,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  guard model.phase is Showing(view) && view.files.get(index) is Some(file) else {
    return (model, @rabbita.none)
  }
  if expanded && !file.expanded {
    expand_file(model, view, model.generation, index, file, emit)
  } else if !expanded && file.expanded {
    (
      with_phase(
        model,
        Showing(set_file_state(view, index, { ..file, expanded: false, })),
      ),
      @rabbita.none,
    )
  } else {
    (model, @rabbita.none)
  }
}

///|
fn stale_viewed(model : Model) -> Model {
  with_review(
    {
      ..model,
      viewed: {
        ..model.viewed,
        stale: true,
        loading: false,
        refresh_needed: false,
        poll_scheduled: false,
      },
    },
    @comments.update(model.review, SnapshotChanged).0,
  )
}

///|
fn reconcile_viewed(
  old : Model,
  model : Model,
  msg : Msg,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let same_page = old.generation == model.generation &&
    old.route == model.route &&
    viewed_page(old) == viewed_page(model) &&
    viewed_paths(old) == viewed_paths(model)
  let identity_boundary = (
      old.auth != model.auth &&
      auth_identity_transition(old, model.auth) is AuthIdentityBoundary
    ) ||
    msg is Auth(Logout)
  if !same_page ||
    viewed_scope(old) != viewed_scope(model) ||
    old.auth_revision != model.auth_revision ||
    identity_boundary {
    let preserve_expansion = same_page && !identity_boundary
    let preserve_remote = preserve_expansion &&
      old.viewed.user_id is Some(owner) &&
      (match model.auth {
        SignedIn(user_id~, ..) => user_id == Some(owner)
        Anonymous(_) => false
        _ => true
      })
    // AuthChecking temporarily hides the identity. Retain its owner and write
    // history until the account is known, but invalidate every old response.
    // Recovery only reads: it must never replay an interrupted mutation.
    let state = if preserve_remote {
      {
        ..model.viewed,
        epoch: old.viewed.epoch + 1,
        loading: false,
        ready: false,
        refresh_needed: false,
        poll_scheduled: false,
        retry: 0,
        files: model.viewed.files.map(file => {
          ..file,
          touched: file.touched || model.viewed.ready,
          // Persisting operations have not sent a mutation. Their stale Stored
          // completion will remove its own record instead of starting a write.
          state: match file.pending {
            Some({ stored: false, before, .. }) => Some(before)
            _ => file.state
          },
          pending: match file.pending {
            Some(pending) if pending.stored =>
              Some({ ..pending, confirming: true, })
            _ => None
          },
        }),
      }
    } else {
      {
        ..empty_viewed_state(old.viewed.epoch + 1),
        files: if preserve_expansion {
          model.viewed.files.map(file => {
            ..empty_viewed_file(),
            touched: file.touched || model.viewed.ready,
            expansion_revision: file.expansion_revision,
          })
        } else {
          []
        },
      }
    }
    let reset = { ..model, viewed: state, }
    return if viewed_scope(reset) is Some(_) {
      begin_viewed_refresh(reset, emit)
    } else {
      (reset, @rabbita.none)
    }
  }
  let model = match msg {
    Load(ToggleFile(generation, index))
    | Load(OpenFile(generation, index))
    | Load(ToggleSection(generation, index, _))
    | Load(NavigateChange(generation, index, _, _, _))
    | Load(RetryFile(generation, index)) if generation == model.generation =>
      record_viewed_interaction(model, index)
    Review(OpenInlineDraft(_, _) | OpenReplyDraft(_) | DraftBodyChanged(_))
    | Review(
      Domain(OpenInlineDraft(_, _) | OpenReplyDraft(_) | DraftBodyChanged(_))
    ) =>
      if old.review.draft() != model.review.draft() &&
        viewed_draft_file(model) is Some(index) {
        record_viewed_interaction(model, index)
      } else {
        model
      }
    _ => model
  }
  match msg {
    Review(RefreshComments) => begin_viewed_refresh(model, emit)
    Auth(ReactivationAuthStatusLoaded(revision, generation, reference, Ok(_))) if revision ==
      model.auth_revision &&
      generation == model.generation &&
      reference == model.route => begin_viewed_refresh(model, emit)
    _ => (model, @rabbita.none)
  }
}

///|
pub fn ViewedState::new() -> ViewedState {
  empty_viewed_state(0)
}

///|
fn viewed_paths(model : Model) -> Array[String] {
  match model.phase {
    Showing(view) => view.files.map(file => file.file.filename)
    _ => []
  }
}

///|
fn viewed_confirming(state : ViewedState) -> Bool {
  state.files.any(file => file.pending is Some({ confirming: true, .. }))
}
