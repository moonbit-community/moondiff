///|
pub(all) struct ApiCommentUser {
  login : String
} derive(Eq, FromJson)

///|
pub(all) struct ApiIssueComment {
  id : Int64
  body : String
  html_url : String
  created_at : String
  user : ApiCommentUser?
} derive(Eq, FromJson)

///|
pub(all) struct ApiReviewComment {
  id : Int64
  body : String
  html_url : String
  created_at : String
  user : ApiCommentUser?
  path : String
  line : Int?
  original_line : Int?
  side : String?
  position : Int?
  commit_id : String
  in_reply_to_id : Int64?
} derive(Eq, FromJson)

///|
pub(all) struct ApiCommitComment {
  id : Int64
  body : String
  html_url : String
  created_at : String
  user : ApiCommentUser?
  path : String?
  position : Int?
  line : Int?
} derive(Eq, FromJson)

///|
pub(all) struct ApiCommentBundle {
  issue_comments : Array[ApiIssueComment]
  review_comments : Array[ApiReviewComment]
  commit_comments : Array[ApiCommitComment]
} derive(Eq, FromJson)

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
  InlineDraft(Int, ReviewAnchor)
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
  RefreshList(@github.ApiPull?)
  RefreshValidation(@github.ApiPull, ApiCommentBundle)
} derive(Eq)

///|
pub(all) enum SubmissionPhase {
  CheckingHead
  PostingIssue
  PostingReview
  PostingCommit
  PostingReply
} derive(Eq)

///|
pub struct Session {
  priv draft_sequence : Int
  priv receipts : ApiCommentBundle
  priv context : Context
  verified_snapshot : Snapshot?
  refresh_id : Int
  priv refresh : CommentRefresh
  refresh_error : String?
  snapshot_stale : Bool
  submission_id : Int
  notice : String?
  published_url : String?
  can_comment : Bool
  login : String?
  authentication_error : String?
  priv comments : CommentsStatus
  priv editor : EditorState
  deletion_id : Int
  deletion : CommentDeletion?
  // Successful deletions remain excluded from refreshes until the route generation changes.
  priv deleted : Array[CommentId]
} derive(Eq)

///|
pub fn Session::new(enabled? : Bool = false) -> Session {
  {
    draft_sequence: 0,
    receipts: { issue_comments: [], review_comments: [], commit_comments: [], },
    context: { generation: 0, route: None, snapshot: None, enabled, },
    verified_snapshot: None,
    refresh_id: 0,
    refresh: RefreshIdle,
    refresh_error: None,
    snapshot_stale: false,
    submission_id: 0,
    notice: None,
    published_url: None,
    can_comment: false,
    login: None,
    authentication_error: None,
    deletion_id: 0,
    deletion: None,
    deleted: [],
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
fn review_side_from_api(side : String?) -> ReviewSide? {
  match side {
    Some("LEFT") => Some(Left)
    Some("RIGHT") => Some(Right)
    _ => None
  }
}

///|
fn find_file_index(view : ChangeView, path : String) -> Int? {
  for index, file in view.files {
    if file.file.filename == path {
      return Some(index)
    }
  }
  None
}

///|
fn review_comment_outdated(
  view : ChangeView,
  comment : ApiReviewComment,
) -> Bool {
  if comment.position is None || comment.line is None {
    return true
  }
  guard comment.line is Some(line) &&
    review_side_from_api(comment.side) is Some(side) &&
    find_file_index(view, comment.path) is Some(index) else {
    return true
  }
  let file = view.files[index].file
  canonical_anchor(parse_canonical_patch(file.filename, file.patch), side, line)
  is None
}

///|
fn commit_comment_outdated(
  view : ChangeView,
  comment : ApiCommitComment,
) -> Bool {
  guard comment.path is Some(path) &&
    comment.position is Some(position) &&
    find_file_index(view, path) is Some(index) else {
    return true
  }
  guard parse_canonical_patch(path, view.files[index].file.patch)
    is Commentable(anchors) else {
    return true
  }
  !anchors.any(anchor => anchor.position == Some(position))
}

///|
pub(all) struct ReviewThread {
  id : CommentId
  root : ApiReviewComment
  replies : Array[ApiReviewComment]
  file_index : Int?
  outdated : Bool
}

///|
pub fn review_threads(
  view : ChangeView,
  comments : ArrayView[ApiReviewComment],
) -> Array[ReviewThread] {
  let threads : Array[ReviewThread] = []
  for root in comments {
    // GitHub can retain replies after deleting their root. Promote the oldest
    // remaining reply so the rest of the thread stays visible.
    if root.in_reply_to_id is Some(parent) {
      if comments.any(comment => comment.id == parent) ||
        comments.any(comment => {
          comment.in_reply_to_id == Some(parent) && comment.id < root.id
        }) {
        continue
      }
    }
    let replies : Array[ApiReviewComment] = []
    for reply in comments {
      if reply.id != root.id &&
        (
          reply.in_reply_to_id == Some(root.id) ||
          (
            root.in_reply_to_id is Some(parent) &&
            reply.in_reply_to_id == Some(parent)
          )
        ) {
        replies.push(reply)
      }
    }
    threads.push({
      id: ReviewComment(root.in_reply_to_id.unwrap_or(root.id)),
      root,
      replies,
      file_index: find_file_index(view, root.path),
      outdated: review_comment_outdated(view, root),
    })
  }
  threads
}

///|
pub(all) struct CommitDiscussion {
  comment : ApiCommitComment
  file_index : Int?
  outdated : Bool
}

///|
pub fn commit_discussions(
  view : ChangeView,
  comments : ArrayView[ApiCommitComment],
) -> Array[CommitDiscussion] {
  comments.map(comment => {
    let file_index = if comment.path is Some(path) {
      find_file_index(view, path)
    } else {
      None
    }
    { comment, file_index, outdated: commit_comment_outdated(view, comment), }
  })
}

///|
pub(all) struct DraftId {
  generation : Int
  sequence : Int
} derive(Eq)

///|
pub fn DraftId::key(self : DraftId) -> String {
  "draft:\{self.generation}:\{self.sequence}"
}
