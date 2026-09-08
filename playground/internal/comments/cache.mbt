///|
priv enum CacheChange {
  Received(ApiCommentBundle, Snapshot?)
  PublishedIssue(ApiIssueComment)
  PublishedCommit(ApiCommitComment)
  PublishedReview(String)
  Removed(CommentId)
}

///|
fn merge_cache(session : Session, change : CacheChange) -> Session {
  let current = match session.comments {
    CommentsReady(bundle) => copy_bundle(bundle)
    _ =>
      ApiCommentBundle::{
        issue_comments: [],
        review_comments: [],
        commit_comments: [],
      }
  }
  match change {
    Received(bundle, snapshot) => {
      let pending = session.receipts
      let received = copy_bundle(bundle)
      for comment in pending.issue_comments {
        if !received.issue_comments.any(c => c.id == comment.id) {
          received.issue_comments.push(comment)
        }
      }
      for comment in pending.commit_comments {
        if !received.commit_comments.any(c => c.id == comment.id) {
          received.commit_comments.push(comment)
        }
      }
      {
        ..session,
        comments: CommentsReady(without_deleted(received, session.deleted)),
        verified_snapshot: snapshot,
        refresh: RefreshIdle,
        refresh_error: None,
        receipts: {
          issue_comments: pending.issue_comments.filter(c => {
            !bundle.issue_comments.any(b => b.id == c.id)
          }),
          review_comments: [],
          commit_comments: pending.commit_comments.filter(c => {
            !bundle.commit_comments.any(b => b.id == c.id)
          }),
        },
      }
    }
    PublishedIssue(comment) => {
      let receipts = copy_bundle(session.receipts)
      if !receipts.issue_comments.any(c => c.id == comment.id) {
        receipts.issue_comments.push(comment)
      }
      if !current.issue_comments.any(c => c.id == comment.id) {
        current.issue_comments.push(comment)
      }
      {
        ..session,
        receipts,
        comments: CommentsReady(without_deleted(current, session.deleted)),
        refresh: RefreshIdle,
        refresh_id: session.refresh_id + 1,
      }
    }
    PublishedCommit(comment) => {
      let receipts = copy_bundle(session.receipts)
      if !receipts.commit_comments.any(c => c.id == comment.id) {
        receipts.commit_comments.push(comment)
      }
      if !current.commit_comments.any(c => c.id == comment.id) {
        current.commit_comments.push(comment)
      }
      {
        ..session,
        receipts,
        comments: CommentsReady(without_deleted(current, session.deleted)),
        refresh: RefreshIdle,
        refresh_id: session.refresh_id + 1,
      }
    }
    PublishedReview(url) =>
      {
        ..session,
        published_url: Some(url),
        refresh: RefreshIdle,
        refresh_id: session.refresh_id + 1,
      }
    Removed(id) => {
      let deleted = session.deleted.copy()
      if !deleted.contains(id) {
        deleted.push(id)
      }
      {
        ..session,
        deleted,
        receipts: without_deleted(session.receipts, deleted),
        comments: match session.comments {
          CommentsReady(_) => CommentsReady(without_deleted(current, deleted))
          other => other
        },
        refresh: RefreshIdle,
        refresh_id: session.refresh_id + 1,
      }
    }
  }
}
