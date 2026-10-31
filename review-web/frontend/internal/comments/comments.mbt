///|
pub(all) enum CommentsStatus {
  CommentsDisabled
  CommentsLoading
  CommentsReady(ApiCommentBundle)
  CommentsFailed(String)
} derive(Eq)

///|
pub(all) enum DraftKind {
  OverallDraft
  InlineDraft(Int32, ReviewAnchor)
  ReplyDraft(Int64)
} derive(Eq)

///|
pub(all) struct CommentDraft {
  snapshot : Snapshot?
  id : DraftId
  kind : DraftKind
  body : String
  // Read-only projection of EditorState; never stored as an independent flag.
  submitting : Bool
  error : String?
} derive(Eq)

///|
pub(all) enum CommentRefresh {
  RefreshIdle
  RefreshMetadata
  RefreshList(@protocol.ApiPull?)
  RefreshValidation(@protocol.ApiPull, ApiCommentBundle)
} derive(Eq)

///|
pub(all) enum SubmissionPhase {
  CheckingHead
  PostingIssue
  PostingReview
  PostingCommit
  PostingReply
  SyncingReview(Int64)
} derive(Eq)

///|
pub struct Session {
  priv index : CommentIndex
  priv draft_sequence : Int32
  priv receipts : ApiCommentBundle
  // Track published review IDs until a verified list can replace the editor.
  priv pending_review_receipts : Array[PendingReviewReceipt]
  priv context : Context
  verified_snapshot : Snapshot?
  refresh_id : Int32
  priv refresh : CommentRefresh
  refresh_error : String?
  snapshot_confirmed : Bool
  snapshot_stale : Bool
  submission_id : Int32
  notice : String?
  published_url : String?
  can_comment : Bool
  priv identity_checking : Bool
  login : String?
  authentication_error : String?
  priv comments : CommentsStatus
  priv editor : EditorState
  deletion_id : Int32
  deletion : CommentDeletion?
  // Successful deletions remain excluded from refreshes until the route generation changes.
  priv deleted : Array[CommentId]
  // Reading choices belong to this page and are not exported with navigation state.
  priv expanded_bodies : Array[CommentId]
} derive(Eq)

///|
pub fn Session::new(enabled~ : Bool = false) -> Session {
  {
    index: CommentIndex::new(),
    draft_sequence: 0,
    receipts: { issue_comments: [], review_comments: [], commit_comments: [], },
    pending_review_receipts: [],
    context: { generation: 0, route: None, snapshot: None, enabled, },
    verified_snapshot: None,
    refresh_id: 0,
    refresh: RefreshIdle,
    refresh_error: None,
    snapshot_confirmed: true,
    snapshot_stale: false,
    submission_id: 0,
    notice: None,
    published_url: None,
    can_comment: false,
    identity_checking: false,
    login: None,
    authentication_error: None,
    deletion_id: 0,
    deletion: None,
    deleted: [],
    expanded_bodies: [],
    comments: if enabled {
      CommentsLoading
    } else {
      CommentsDisabled
    },
    editor: Empty,
  }
}

///|
pub fn review_can_comment(review : Session) -> Bool {
  review.can_comment
}

///|
pub fn author_label(user : ApiCommentUser?) -> String {
  user.map(user => user.login).unwrap_or("ghost")
}

///|
fn review_side_from_api(side : @protocol.CommentSide?) -> ReviewSide? {
  match side {
    Some(Left) => Some(Left)
    Some(Right) => Some(Right)
    _ => None
  }
}

///|
pub(all) struct ReviewThread {
  id : CommentId
  root : ApiReviewComment
  replies : Array[ApiReviewComment]
  file_index : Int32?
  outdated : Bool
}

///|
pub(all) struct CommitDiscussion {
  comment : ApiCommitComment
  file_index : Int32?
  outdated : Bool
}

///|
pub(all) struct DraftId {
  generation : Int32
  sequence : Int32
} derive(Eq)

///|
pub fn DraftId::key(self : DraftId) -> String {
  "draft:\{self.generation}:\{self.sequence}"
}

///|
// Local drafts remain editable while account access is unavailable. The
// application clears them at an explicit logout or confirmed identity boundary.
pub fn Session::draft_visible(self : Session) -> Bool {
  self.can_comment || self.identity_checking || self.draft() is Some(_)
}
