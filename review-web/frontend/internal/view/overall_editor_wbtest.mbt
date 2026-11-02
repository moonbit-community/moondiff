///|
fn overall_editor_test_html(session : @comments.Session) -> String {
  render_test_html(() => {
    comments_overview(
      {
        generation: 3,
        is_pull: true,
        review: session.read_view(paths=["src/main.mbt"]),
        auth: SignedIn(
          user_id=Some("author"),
          login=Some("author"),
          install_url=None,
        ),
        sign_in_dialog: @application.SignInDialog::new(),
        markdown: None,
      },
      Emit(_ => @rabbita.none),
    )
  })
}

///|
#warnings("-alert_unstable")
#skip("browser DOM: npm run test:views")
test "overall composer renders empty without a draft and returns after cancellation" {
  let session = receipt_test_session([])
  let html = overall_editor_test_html(session)
  assert_true(html.contains("overall-comment-editor"))
  assert_true(html.contains("Add a comment"))
  assert_true(html.contains("https://github.com/author.png?size=64"))
  assert_true(html.contains("Post comment"))
  assert_false(html.contains("data-draft-id"))
  assert_false(html.contains("comment-cancel"))
  assert_false(html.contains("Add overall comment"))
  assert_true(session.draft() is None)
  let editing = @comments.update(
      session,
      OverallDraftBodyChanged("first input"),
    ).0
  let html = overall_editor_test_html(editing)
  assert_true(html.contains("first input"))
  assert_true(html.contains("data-draft-id"))
  assert_true(html.contains("comment-cancel"))
  let cancelled = @comments.update(editing, CancelDraft).0
  assert_eq(
    overall_editor_test_html(cancelled),
    overall_editor_test_html(session),
  )
}

///|
#warnings("-alert_unstable")
#skip("browser DOM: npm run test:views")
test "overall composer remains visible and blocked by drafts in other regions" {
  let session = receipt_test_session([receipt_test_comment(20, "root")])
  for
    event in [
      @comments.OpenInlineDraft(0, receipt_test_anchor()),
      OpenReplyDraft(20L),
    ] {
    let editing = @comments.update(session, event).0
    let html = overall_editor_test_html(editing)
    assert_true(html.contains("overall-comment-editor"))
    let root = @dom.document().create_element("div")
    @browser.set_property(root, "innerHTML", html)
    assert_true(
      root.query_selector(".overall-comment-editor textarea:disabled")
      is Some(_),
    )
    assert_true(html.contains("Post or cancel your current draft"))
    assert_true(html.contains("aria-describedby=\"overall-comment-notice\""))
    assert_false(html.contains("data-draft-id"))
    assert_false(html.contains("comment-cancel"))
  }
  let anonymous = @comments.update(session, Identity(false, None)).0
  assert_false(
    overall_editor_test_html(anonymous).contains("overall-comment-editor"),
  )
}
