///|
/// Immutable comments for one path. Equality is a version/identity check.
pub struct CommentGroup {
  issue_comments : ReadOnlyArray[ApiIssueComment]
  review_comments : ReadOnlyArray[ApiReviewComment]
  commit_comments : ReadOnlyArray[ApiCommitComment]
}

///|
pub impl Eq for CommentGroup with fn equal(a, b) {
  @identity.same(a, b)
}

///|
let empty_group : CommentGroup = {
  issue_comments: [],
  review_comments: [],
  commit_comments: [],
}

///|
priv struct CommentIndex {
  version : Int
  groups : Map[String, CommentGroup]
  owners : Map[String, String]
} derive(Eq)

///|
fn CommentIndex::new() -> CommentIndex {
  { version: 0, groups: {}, owners: {}, }
}

///|
fn index_comments(before : Session, after : Session) -> Session {
  if @identity.same(before.comments, after.comments) {
    return after
  }
  let groups : Map[String, ApiCommentBundle] = Map([])
  let owners : Map[String, String] = Map([])
  fn group(path : String) -> ApiCommentBundle {
    match groups.get(path) {
      Some(group) => group
      None => {
        let group : ApiCommentBundle = {
          issue_comments: [],
          review_comments: [],
          commit_comments: [],
        }
        groups[path] = group
        group
      }
    }
  }
  if after.comments is CommentsReady(bundle) {
    for c in bundle.issue_comments {
      group("").issue_comments.push(c)
    }
    // Resolve replies through their root even if an API response has a different path.
    for c in bundle.review_comments {
      owners[ReviewComment(c.id).key()] = c.path
    }
    for c in bundle.review_comments {
      let path = match c.in_reply_to_id {
        Some(id) => owners.get(ReviewComment(id).key()).unwrap_or(c.path)
        None => c.path
      }
      group(path).review_comments.push(c)
      owners[ReviewComment(c.id).key()] = path
    }
    for c in bundle.commit_comments {
      let path = c.path.unwrap_or("")
      group(path).commit_comments.push(c)
      owners[CommitComment(c.id).key()] = path
    }
  }
  let indexed : Map[String, CommentGroup] = Map([])
  for path, bundle in groups {
    let next : CommentGroup = {
      issue_comments: ReadOnlyArray::from_array(bundle.issue_comments),
      review_comments: ReadOnlyArray::from_array(bundle.review_comments),
      commit_comments: ReadOnlyArray::from_array(bundle.commit_comments),
    }
    indexed[path] = match before.index.groups.get(path) {
      Some(old) if old.issue_comments == next.issue_comments &&
        old.review_comments == next.review_comments &&
        old.commit_comments == next.commit_comments => old
      _ => next
    }
  }
  {
    ..after,
    index: { version: before.index.version + 1, groups: indexed, owners, },
  }
}

///|
pub fn Session::comment_version(self : Session) -> Int {
  self.index.version
}

///|
pub fn Session::file_comments(self : Session, path : String) -> CommentGroup {
  self.index.groups.get(path).unwrap_or(empty_group)
}

///|
pub fn Session::draft_path(self : Session) -> String? {
  match self.draft() {
    Some({ kind: InlineDraft(_, anchor), .. }) => Some(anchor.path)
    Some({ kind: ReplyDraft(id), .. }) =>
      self.index.owners.get(ReviewComment(id).key())
    _ => None
  }
}

///|
pub(all) enum ReadStatus {
  Disabled
  Loading
  Ready
  Failed(String)
} derive(Eq)

///|
/// Permission changes are independent of the draft body and comment collection.
pub struct PermissionSummary {
  can_comment : Bool
  visible : Bool
  login : String?
  stale : Bool
  target : DraftKind?
  posting : Bool
  deleting : Bool
  has_snapshot : Bool
  is_pull : Bool
} derive(Eq)

///|
pub fn Session::permission_summary(self : Session) -> PermissionSummary {
  {
    can_comment: self.can_comment,
    visible: self.draft_visible(),
    login: self.login,
    stale: self.snapshot_stale,
    target: self.draft().map(d => d.kind),
    posting: self.submission() is Some(_),
    deleting: self.deletion is Some(Deleting(_)),
    has_snapshot: self.context.snapshot is Some(_),
    is_pull: session_is_pull(self),
  }
}

///|
/// A view cannot reach the reducer session or another file's source/comments.
pub struct ReadView {
  permissions : PermissionSummary
  group : CommentGroup
  generation : Int
  snapshot_stale : Bool
  login : String?
  deletion : CommentDeletion?
  status : ReadStatus
  refresh_busy : Bool
  refresh_error : String?
  notice : String?
  published_url : String?
  priv selected_draft : CommentDraft?
  priv can_submit : Bool
  priv can_load : Bool
} derive(Eq)

///|
pub fn Session::overall_comments(
  self : Session,
  paths : ArrayView[String],
) -> CommentGroup {
  let general = self.file_comments("")
  let missing = self.index.groups
    .iter()
    .filter(fn(entry) {
      let (path, _) = entry
      !path.is_empty() && !paths.contains(path)
    })
    .collect()
  if missing.is_empty() {
    general
  } else {
    let reviews = general.review_comments.iter().collect()
    let commits = general.commit_comments.iter().collect()
    for (_, group) in missing {
      reviews.push_iter(group.review_comments.iter())
      commits.push_iter(group.commit_comments.iter())
    }
    {
      issue_comments: general.issue_comments,
      review_comments: ReadOnlyArray::from_array(reviews),
      commit_comments: ReadOnlyArray::from_array(commits),
    }
  }
}

///|
pub fn Session::read_view(
  self : Session,
  path? : String,
  paths? : ArrayView[String] = [],
  group? : CommentGroup,
) -> ReadView {
  let group = match group {
    Some(group) => group
    None =>
      match path {
        Some(path) => self.file_comments(path)
        None => self.overall_comments(paths)
      }
  }
  let draft_path = self.draft_path()
  let own_draft = match path {
    Some(path) => draft_path == Some(path)
    None => draft_path is None || !paths.contains(draft_path.unwrap_or(""))
  }
  let selected_draft = if own_draft { self.draft() } else { None }
  let deletion = self.deletion.filter(deletion => {
    let id = match deletion {
      ConfirmDelete(id) | Deleting(id) | DeleteFailed(id, _) => id
    }
    match id {
      IssueComment(_) => path is None
      _ =>
        match path {
          Some(path) => self.index.owners.get(id.key()) == Some(path)
          None => !paths.contains(self.index.owners.get(id.key()).unwrap_or(""))
        }
    }
  })
  {
    permissions: self.permission_summary(),
    group,
    generation: self.generation(),
    snapshot_stale: self.snapshot_stale,
    login: self.login,
    deletion,
    selected_draft,
    can_submit: own_draft && permission(self, Submit).allowed(),
    can_load: path is None && permission(self, LoadSnapshot).allowed(),
    status: if path is Some(_) {
      Ready
    } else {
      match self.comments {
        CommentsDisabled => Disabled
        CommentsLoading => Loading
        CommentsReady(_) => Ready
        CommentsFailed(e) => Failed(e)
      }
    },
    refresh_busy: path is None && !(self.refresh is RefreshIdle),
    refresh_error: if path is None {
      self.refresh_error
    } else {
      None
    },
    notice: if path is None {
      self.notice
    } else {
      None
    },
    published_url: if path is None {
      self.published_url
    } else {
      None
    },
  }
}

///|
pub fn ReadView::draft(self : ReadView) -> CommentDraft? {
  self.selected_draft
}

///|
pub fn ReadView::draft_visible(self : ReadView) -> Bool {
  self.permissions.visible
}

///|
pub fn ReadView::comment_key(self : ReadView, id : CommentId) -> String {
  "\{self.generation}:\{id.key()}"
}

///|
pub fn ReadView::can_delete(self : ReadView, id : CommentId) -> Bool {
  guard self.permissions.can_comment && self.login is Some(login) else {
    return false
  }
  match id {
    IssueComment(id) =>
      self.group.issue_comments.any(c => {
        c.id == id && c.user.map(u => u.login) == Some(login)
      })
    ReviewComment(id) =>
      self.group.review_comments.any(c => {
        c.id == id && c.user.map(u => u.login) == Some(login)
      })
    CommitComment(id) =>
      self.group.commit_comments.any(c => {
        c.id == id && c.user.map(u => u.login) == Some(login)
      })
  }
}

///|
pub fn ReadView::draft_blocks_deletion(self : ReadView, id : CommentId) -> Bool {
  self.permissions.target is Some(ReplyDraft(target)) &&
  id == ReviewComment(target)
}

///|
pub fn ReadView::valid_reply_target(self : ReadView, id : Int64) -> Bool {
  self.deletion != Some(Deleting(ReviewComment(id))) &&
  self.group.review_comments.any(c => c.id == id && c.in_reply_to_id is None)
}

///|
pub fn ReadView::allowed(self : ReadView, action : Action) -> Bool {
  match action {
    Submit => self.can_submit
    LoadSnapshot => self.can_load
    Delete(id) =>
      self.can_delete(id) &&
      !self.permissions.deleting &&
      !self.draft_blocks_deletion(id)
    OpenDraft(kind) => {
      let p = self.permissions
      p.can_comment &&
      !p.posting &&
      (p.target is None || same_draft_target(p.target.unwrap(), kind)) &&
      (match kind {
        OverallDraft => p.is_pull
        ReplyDraft(id) => p.is_pull && self.valid_reply_target(id)
        InlineDraft(_, _) => p.has_snapshot && !p.stale
      })
    }
  }
}

///|
pub fn file_threads(
  group : CommentGroup,
  file_index : Int?,
  patch : @review.CanonicalPatch,
) -> Array[ReviewThread] {
  let comments = group.review_comments
  let threads : Array[ReviewThread] = []
  for root in comments {
    if root.in_reply_to_id is Some(parent) {
      if comments.any(c => c.id == parent) ||
        comments.any(c => c.in_reply_to_id == Some(parent) && c.id < root.id) {
        continue
      }
    }
    let replies = comments.filter(c => {
      c.id != root.id &&
      (
        c.in_reply_to_id == Some(root.id) ||
        (
          root.in_reply_to_id is Some(parent) &&
          c.in_reply_to_id == Some(parent)
        )
      )
    })
    let outdated = root.position is None ||
      root.line is None ||
      file_index is None ||
      !(root.line is Some(line) &&
      review_side_from_api(root.side) is Some(side) &&
      canonical_anchor(patch, side, line) is Some(_))
    threads.push({
      id: ReviewComment(root.in_reply_to_id.unwrap_or(root.id)),
      root,
      replies: replies.iter().collect(),
      file_index,
      outdated,
    })
  }
  threads
}

///|
pub fn file_commit_discussions(
  group : CommentGroup,
  file_index : Int?,
  patch : @review.CanonicalPatch,
) -> Array[CommitDiscussion] {
  group.commit_comments
  .iter()
  .map(comment => {
    let outdated = !(file_index is Some(_) &&
      comment.position is Some(position) &&
      patch is Commentable(anchors) &&
      anchors.any(a => a.position == Some(position)))
    { comment, file_index, outdated, }
  })
  .collect()
}
