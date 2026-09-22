///|
fn receipt_test_pull() -> @protocol.ApiPull {
  {
    title: "Pull request",
    html_url: "https://github.com/owner/repo/pull/17",
    base: {
      sha: "1111111111111111111111111111111111111111",
      repo: Some({ full_name: "owner/repo", }),
    },
    head: {
      sha: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      repo: Some({ full_name: "owner/repo", }),
    },
    additions: 1,
    deletions: 1,
    changed_files: 1,
  }
}

///|
fn receipt_test_bundle(
  comments : Array[@protocol.ApiReviewComment],
) -> @protocol.ApiCommentBundle {
  { issue_comments: [], review_comments: comments, commit_comments: [], }
}

///|
fn receipt_test_session(
  comments : Array[@protocol.ApiReviewComment],
) -> @comments.Session {
  let reference = @github.pull_reference("owner", "repo", "17")
  let pull = receipt_test_pull()
  let session = @comments.update(
      @comments.Session::new(enabled=true),
      ContextChanged({
        generation: 3,
        route: Some(reference),
        snapshot: Some({
          reference,
          sha: pull.head.sha,
          pull_snapshot: Some(pull),
        }),
        enabled: true,
      }),
    ).0
  let session = @comments.update(session, Identity(true, Some("author"))).0
  receipt_test_refresh(session, receipt_test_bundle(comments))
}

///|
fn receipt_test_refresh(
  session : @comments.Session,
  bundle : @protocol.ApiCommentBundle,
) -> @comments.Session {
  let pending = @comments.update(session, RefreshComments).0
  let id = pending.refresh_id
  let listed = @comments.update(
      pending,
      CommentsMetadataLoaded(3, id, Ok(receipt_test_pull())),
    ).0
  let validating = @comments.update(listed, CommentsLoaded(3, id, Ok(bundle))).0
  @comments.update(
    validating,
    CommentsValidated(3, id, Ok(receipt_test_pull())),
  ).0
}

///|
fn receipt_test_comment(
  id : Int,
  body : String,
  reply_to? : Int64,
) -> @protocol.ApiReviewComment {
  {
    id: Int64::from_int(id),
    body,
    html_url: "https://github.com/comment/\{id}",
    created_at: "2026-09-22T08:00:00Z",
    user: Some({ login: "author", }),
    path: "src/main.mbt",
    line: Some(2),
    side: Some(Right),
    position: Some(3),
    commit_id: receipt_test_pull().head.sha,
    in_reply_to_id: reply_to,
    original_line: None,
  }
}

///|
fn receipt_test_anchor() -> ReviewAnchor {
  { path: "src/main.mbt", side: Right, line: 2, position: Some(3), }
}

///|
fn receipt_test_publish_inline(
  session : @comments.Session,
  id : Int,
  body : String,
) -> (@comments.Session, @protocol.ApiReviewComment) {
  let anchor = receipt_test_anchor()
  let editing = @comments.update(session, OpenInlineDraft(0, anchor)).0
  let checking = @comments.update(
      @comments.update(editing, DraftBodyChanged(body)).0,
      SubmitDraft,
    ).0
  let operation = checking.submission_id
  let posting = @comments.update(
      checking,
      CommentHeadChecked(3, operation, anchor, Ok(receipt_test_pull())),
    ).0
  let comment = receipt_test_comment(id, body)
  (
    @comments.update(posting, ReviewCommentCreated(3, operation, Ok(comment))).0,
    comment,
  )
}

///|
fn receipt_test_file() -> FileState {
  let api = {
    ..fixture_file("src/main.mbt", "modified"),
    patch: Some("@@ -1,3 +1,3 @@\n context\n-old\n+new\n tail"),
  }
  ready_test_file(api, ["context", "old", "tail"], ["context", "new", "tail"])
}

///|
#warnings("-alert_unstable")
test "published inline reviews retain the Posting editor until verified, including fallback placements" {
  let (published, comment) = receipt_test_publish_inline(
    receipt_test_session([]),
    91,
    "submitted body stays visible",
  )
  let file = receipt_test_file()
  let read = published.read_view(path="src/main.mbt")
  let draft = read.draft().unwrap()
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  for columns in [4, 3] {
    let (key, editor) = inline_editor_row(
      read,
      Some(receipt_test_anchor()),
      columns,
      emit,
    )
    assert_eq(key, draft.id.key())
    let rendered = @rabbita.render_to_string(() => {
      @rabbita.Val::constant(editor)
    })
    assert_true(rendered.contains("inline-right"), msg=rendered)
    assert_true(rendered.contains("colspan=\"\{columns}\""), msg=rendered)
    assert_true(rendered.contains("Posting…"), msg=rendered)
    assert_true(rendered.contains(comment.body), msg=rendered)
    assert_false(rendered.contains("pending-review-receipt"), msg=rendered)
  }
  // Collapsed/filtered files and missing paths keep the same draft in fallback.
  for file_index in [Some(0), None] {
    let fallback = prepare_discussions(
      file_index.map(_ => file.file),
      file_index,
      if file_index is Some(_) {
        read
      } else {
        published.read_view(paths=[])
      },
      emit,
    )
    let rendered = @rabbita.render_to_string(() => {
      @rabbita.Val::constant(fallback_discussions(fallback, file_index))
    })
    assert_true(rendered.contains("file-discussions"), msg=rendered)
    assert_true(rendered.contains("Not shown in current view"), msg=rendered)
    assert_true(rendered.contains("Posting…"), msg=rendered)
    assert_true(rendered.contains(comment.body), msg=rendered)
    assert_eq(rendered.split("class=\"comment-editor\"").count() - 1, 1)
  }
  let confirmed = receipt_test_refresh(
    published,
    receipt_test_bundle([comment]),
  )
  let formal = prepare_discussions(
    Some(file.file),
    Some(0),
    confirmed.read_view(path="src/main.mbt"),
    emit,
  )
  let rendered = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(fallback_discussions(formal, Some(0)))
  })
  assert_true(rendered.contains(comment.body), msg=rendered)
  assert_false(rendered.contains("comment-editor"), msg=rendered)
  assert_false(rendered.contains("Posting…"), msg=rendered)
}

///|
#warnings("-alert_unstable")
test "published replies retain the thread editor and fall back if the root disappears" {
  let root = receipt_test_comment(20, "root")
  let existing = receipt_test_comment(21, "existing reply", reply_to=root.id)
  let initial = receipt_test_session([root, existing])
  let editing = @comments.update(initial, OpenReplyDraft(root.id)).0
  let posting = @comments.update(
      @comments.update(editing, DraftBodyChanged("pending reply body")).0,
      SubmitDraft,
    ).0
  let operation = posting.submission_id
  let created = receipt_test_comment(22, "pending reply body", reply_to=root.id)
  let published = @comments.update(
      posting,
      ReviewReplyCreated(3, operation, Ok(created)),
    ).0
  let file = receipt_test_file()
  let patch = parse_canonical_patch(file.file.filename, file.file.patch)
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let confirmed = receipt_test_refresh(
    published,
    receipt_test_bundle([root, existing, created]),
  )
  for (session, formal) in [(published, false), (confirmed, true)] {
    let read = session.read_view(path="src/main.mbt")
    let thread = @comments.file_threads(read.group, Some(0), patch)[0]
    let rendered = @rabbita.render_to_string(() => {
      @rabbita.Val::constant(review_thread_view(thread, read, emit))
    })
    assert_true(
      rendered.find(existing.body).unwrap() <
      rendered.find(created.body).unwrap(),
    )
    assert_eq(rendered.contains("Posting…"), !formal, msg=rendered)
    assert_eq(rendered.contains("comment-reply-entry"), formal, msg=rendered)
    assert_eq(rendered.split(created.body).count() - 1, 1)
  }
  let without_root = receipt_test_refresh(posting, receipt_test_bundle([]))
  let fallback_session = @comments.update(
      without_root,
      ReviewReplyCreated(3, operation, Ok(created)),
    ).0
  for file_index in [Some(0), None] {
    let read = if file_index is Some(_) {
      fallback_session.read_view(path="src/main.mbt")
    } else {
      fallback_session.read_view(paths=[])
    }
    let discussions = prepare_discussions(
      file_index.map(_ => file.file),
      file_index,
      read,
      emit,
    )
    let rendered = @rabbita.render_to_string(() => {
      @rabbita.Val::constant(fallback_discussions(discussions, file_index))
    })
    assert_true(rendered.contains("Thread unavailable"), msg=rendered)
    assert_true(rendered.contains("Posting…"), msg=rendered)
    assert_true(rendered.contains(created.body), msg=rendered)
    assert_eq(rendered.split("class=\"comment-editor\"").count() - 1, 1)
  }
}
