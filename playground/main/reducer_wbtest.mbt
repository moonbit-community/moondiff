///|
test "top-level reducer routes every message domain" {
  let model = initial_model()
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)

  let auth_msg = DeviceCodeCopied("stale-flow")
  let (auth_routed, _) = update(model, Auth(auth_msg), emit)
  let (auth_direct, _) = update_auth(model, auth_msg, emit)
  assert_true(auth_routed == auth_direct)

  let review_msg = VisibilityChanged(true)
  let (review_routed, _) = update(model, Review(review_msg), emit)
  let (review_direct, _) = update_review(model, review_msg, emit)
  assert_true(review_routed == review_direct)

  let load_msg = PullMetadataLoaded(
    model.generation + 1,
    0,
    Err(GitHubRequestError("ignored stale response")),
  )
  let (load_routed, _) = update(model, Load(load_msg), emit)
  let (load_direct, _) = update_load(model, load_msg, emit)
  assert_true(load_routed == load_direct)

  let ui_msg = InputChanged("https://github.com/example/repo/commit/abcdef1")
  let (ui_routed, _) = update(model, Ui(ui_msg), emit)
  let (ui_direct, _) = update_ui(model, ui_msg, emit)
  assert_true(ui_routed == ui_direct)
}
