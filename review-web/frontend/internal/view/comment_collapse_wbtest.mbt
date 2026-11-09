///|
#warnings("-alert_unstable")
#skip("browser DOM: npm run test:views")
test "manual collapse retains Markdown and deletion controls under hidden containers" {
  let comment = receipt_test_comment(20, "**Keep this body**")
  let initial = receipt_test_session([comment])
  let confirming = @comments.update(initial, AskDelete(ReviewComment(20L))).0
  let collapsed = @comments.update(
      confirming,
      SetCommentCollapsed(3, ReviewComment(20L), true),
    ).0
  fn render(session : @comments.Session) -> String {
    render_test_html(() => {
      comment_body_view(
        "author",
        "2026-09-22T08:00:00Z",
        "**Keep this body**",
        "https://github.com/comment/20",
        ReviewComment(20L),
        session.read_view(path="src/main.mbt"),
        Emit(_ => @rabbita.none),
      )
    })
  }
  let hidden = render(collapsed)
  for
    expected in [
      "data-collapsed=\"true\"", "aria-label=\"Expand comment by author\"", "aria-expanded=\"false\"",
      "aria-controls=\"comment-details-3:review:20\"", "<strong>author</strong>",
      "<div id=\"comment-details-3:review:20\" hidden=\"\">", "<div class=\"comment-actions\" hidden=\"\">",
      "<strong>Keep this body</strong>", "Confirm delete",
    ] {
    assert_true(hidden.contains(expected), msg=hidden)
  }
  let reopened = @comments.update(
      collapsed,
      SetCommentCollapsed(3, ReviewComment(20L), false),
    ).0
  assert_eq(render(reopened), render(confirming))
  assert_true(
    render(reopened).contains("aria-label=\"Collapse comment by author\""),
  )
}
