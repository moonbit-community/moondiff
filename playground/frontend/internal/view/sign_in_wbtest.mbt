///|
test "PR Viewed offers sign-in throughout session checks and authorization" {
  let model = pull_region_model()
  for
    auth in [
      @application.AuthStatus::Anonymous(None),
      AuthChecking,
      AuthFailed("Try again"),
      Authorizing(
        {
          id: "attempt",
          phase: Starting,
          user_code: "",
          verification_uri: "",
          expires_at: 0,
          retry_after: 5,
          message: "",
        },
        "",
      ),
      DeviceCancelling("attempt", ""),
    ] {
    let input = viewed_control(true, { ..model, auth, }, 0, "a.mbt")
    assert_true(input.requires_sign_in)
    assert_false(input.disabled)
    assert_false(
      viewed_control(false, { ..model, auth, }, 0, "a.mbt").requires_sign_in,
    )
  }
  let model = {
    ..model,
    auth: SignedIn(login=Some("me"), user_id=Some("1"), install_url=None),
  }
  assert_false(viewed_control(true, model, 0, "a.mbt").requires_sign_in)
  assert_true(viewed_control(true, model, 0, "a.mbt").disabled)
}

///|
#warnings("-alert_unstable")
#skip("browser DOM: npm run test:views")
test "anonymous PR gutters offer sign-in only on anchored lines" {
  let anchor : ReviewAnchor = {
    path: "a.mbt",
    side: Right,
    line: 1,
    position: Some(1),
  }
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  for is_pull in [true, false] {
    let reference = if is_pull {
      @github.pull_reference("owner", "repo", "17")
    } else {
      @github.commit_reference("owner", "repo", "head")
    }
    let session = @comments.update(
        @comments.Session::new(),
        ContextChanged({
          generation: 1,
          route: Some(reference),
          snapshot: None,
          enabled: true,
        }),
      ).0
    for can_comment in [false, true] {
      let review = @comments.update(session, Identity(can_comment, None)).0.read_view()
      for selected in [Some(anchor), None] {
        let html = render_test_html(() => {
          @html.table([
            @html.tbody([
              @html.tr([
                review_gutter(
                  0,
                  Some(1),
                  selected,
                  "new-line-number",
                  review,
                  emit,
                ),
              ]),
            ]),
          ])
        })
        assert_eq(
          html.contains("line-comment-button"),
          selected is Some(_) && (is_pull || can_comment),
        )
        assert_eq(
          html.contains("Sign in to comment"),
          selected is Some(_) && is_pull && !can_comment,
        )
      }
    }
  }
}
