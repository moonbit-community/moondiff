///|
pub(all) enum CommentBodyAction {
  Toggle(Double)
  Footnote(String)
}

///|
// Transient UI intent only: no DOM or geometry enters the comment session.
pub(all) struct CommentBodyRequest {
  generation : Int32
  id : @comments.CommentId
  region : Region
  action : CommentBodyAction
}

///|
priv struct PendingCommentBody {
  request : CommentBodyRequest
  source : String
}

///|
let pending_comment_body : Ref[PendingCommentBody?] = Ref(None)

///|
let comment_body_interactions : ReadOnlyArray[String] = [
  "pointerdown", "keydown", "wheel", "touchstart", "click", "input", "focusin",
]

///|
fn cancel_comment_body(event : @dom.Event) -> Unit {
  // Regional scheduler bridges dispatch non-bubbling render notifications.
  if (@browser.event_property(event, "type") : String) == "click" &&
    !(@browser.event_property(event, "bubbles") : Bool) {
    return
  }
  clear_comment_body_request()
}

///|
pub fn discard_comment_body_region(generation : Int32, region : Region) -> Unit {
  if pending_comment_body.val is Some(pending) &&
    pending.request.generation == generation &&
    pending.request.region == region {
    clear_comment_body_request()
  }
}

///|
fn clear_comment_body_request() -> Unit {
  if pending_comment_body.val is Some(_) {
    pending_comment_body.val = None
    for event in comment_body_interactions {
      @dom.window().remove_event_listener_with_options(
        event,
        cancel_comment_body,
        capture=true,
      )
    }
  }
}

///|
fn comment_body_region(element : @dom.Element) -> Region? {
  guard element.closest("[data-region]") is Some(host) &&
    host.get_attribute("data-region") is Some(region) else {
    return None
  }
  if region == "discussion" {
    Some(Discussion)
  } else if region.has_prefix("file:") {
    Some(File(region[5:].to_owned()))
  } else {
    None
  }
}

///|
pub fn toggle_comment_body(
  event : @dom.MouseEvent,
  generation : Int32,
  id : @comments.CommentId,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  guard @browser.current_element(event.current_target()) is Some(button) &&
    comment_body_region(button) is Some(region) else {
    return @rabbita.none
  }
  emit(
    Review(
      BodyActivated({
        generation,
        id,
        region,
        action: Toggle(button.get_bounding_client_rect().get_top()),
      }),
    ),
  )
}

///|
pub fn follow_comment_footnote(
  event : @dom.MouseEvent,
  generation : Int32,
  id : @comments.CommentId,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  // Enter on an anchor produces the same primary click as pointer activation.
  guard !event.get_default_prevented() &&
    event.get_button() == 0 &&
    !event.get_ctrl_key() &&
    !event.get_meta_key() &&
    !event.get_shift_key() &&
    !event.get_alt_key() &&
    event.target().to_element() is Some(element) &&
    element.closest("a[role=\"doc-noteref\"], a[role=\"doc-backlink\"]")
    is Some(link) &&
    link.closest(".github-comment-body") is Some(body) &&
    @browser.current_element(event.current_target()) is Some(container) &&
    container.contains(body.as_node()) &&
    link.get_attribute("href") is Some(href) &&
    @browser.fragment_target(href) is Some(target) &&
    body.contains(target.as_node()) &&
    target.get_attribute("id") is Some(target_id) &&
    comment_body_region(container) is Some(region) else {
    return @rabbita.none
  }
  event.prevent_default()
  emit(
    Review(
      BodyActivated({ generation, id, region, action: Footnote(target_id), }),
    ),
  )
}

///|
fn comment_body_snapshot(
  model : Model,
  request : CommentBodyRequest,
) -> (Bool, String)? {
  guard model.generation == request.generation &&
    model.review.generation() == request.generation else {
    return None
  }
  let paths = match model.phase {
    Showing(view) => view.files.map(file => file.file.filename)
    _ => []
  }
  let review = match request.region {
    File(path) if paths.contains(path) => model.review.read_view(path~)
    Discussion => model.review.read_view(paths~)
    _ => return None
  }
  let source = match request.id {
    IssueComment(id) =>
      review.group.issue_comments
      .iter()
      .find_first(c => c.id == id)
      .map(c => c.body)
    ReviewComment(id) =>
      review.group.review_comments
      .iter()
      .find_first(c => c.id == id)
      .map(c => c.body)
    CommitComment(id) =>
      review.group.commit_comments
      .iter()
      .find_first(c => c.id == id)
      .map(c => c.body)
  }
  source.map(source => (review.body_expanded(request.id), source))
}

///|
fn comment_body_expected(request : CommentBodyRequest) -> Bool {
  request.action is Footnote(_)
}

///|
// Called at every central event boundary, including deletions and route changes.
pub fn prepare_comment_body(model : Model, msg : Msg) -> Unit {
  if pending_comment_body.val is Some(pending) &&
    (
      msg is Review(BodyActivated(_)) ||
      comment_body_snapshot(model, pending.request) !=
      Some((comment_body_expected(pending.request), pending.source))
    ) {
    clear_comment_body_request()
  }
  if msg is Review(BodyActivated(request)) &&
    comment_body_snapshot(model, request) is Some((expanded, source)) &&
    expanded == comment_body_expected(request) {
    pending_comment_body.val = Some({ request, source, })
    for event in comment_body_interactions {
      @dom.window().add_event_listener_with_options(
        event,
        cancel_comment_body,
        capture=true,
        passive=true,
      )
    }
  }
}

///|
fn comment_body_after_commit(model : Model, msg : Msg) -> AfterCommit? {
  guard msg is Review(BodyActivated(request)) &&
    comment_body_snapshot(model, request) is Some((expanded, _)) &&
    expanded == comment_body_expected(request) else {
    return None
  }
  Some({
    target: request.region,
    scope: PageLayout,
    navigation: Cancel,
    command: @cmd.custom_cmd(_ => commit_comment_body(request)),
  })
}

///|
fn comment_body_inset(element : @dom.Element) -> Double {
  let mut inset = 8.0
  if @dom.document().query_selector(".hero-workspace").to_option()
    is Some(toolbar) {
    inset += toolbar.get_bounding_client_rect().get_height()
  }
  if element.closest(".change-main") is Some(main) &&
    main.query_selector(".change-titlebar") is Some(title) {
    inset += title.get_bounding_client_rect().get_height()
  }
  if element.closest(".file-card") is Some(file) &&
    file.query_selector(".file-heading") is Some(heading) {
    inset += heading.get_bounding_client_rect().get_height()
  }
  if element.closest(".semantic-section") is Some(section) &&
    section.query_selector(".semantic-section-title") is Some(title) {
    inset += title.get_bounding_client_rect().get_height()
  }
  inset
}

///|
fn commit_comment_body(request : CommentBodyRequest) -> Unit {
  guard pending_comment_body.val is Some(pending) &&
    @identity.same(pending.request, request) else {
    return
  }
  clear_comment_body_request()
  guard @browser.element(
      "comment-body-\{request.generation}:\{request.id.key()}",
    )
    is Some(clip) &&
    clip.get_is_connected() &&
    comment_body_region(clip) == Some(request.region) &&
    clip.get_attribute("data-expanded") ==
    Some(comment_body_expected(request).to_string()) &&
    clip.closest(".github-comment-content") is Some(container) &&
    container.query_selector(".comment-body-toggle") is Some(button) else {
    return
  }
  let (target, top) = match request.action {
    Toggle(previous_top) => {
      let rect = button.get_bounding_client_rect()
      let bottom = @dom.window().inner_height() - rect.get_height() - 8.0
      (button, previous_top.min(bottom).max(comment_body_inset(button)))
    }
    Footnote(id) => {
      guard @browser.element(id) is Some(target) &&
        clip.contains(target.as_node()) else {
        return
      }
      @browser.navigate_fragment(id)
      (target, comment_body_inset(target))
    }
  }
  let rect = target.get_bounding_client_rect()
  @dom.window().scroll_to(
    @browser.scroll_x(),
    @dom.window().scroll_y() + rect.get_top() - top,
    behavior="instant",
  )
  let temporary = request.action is Footnote(_) &&
    target.get_attribute("tabindex") is None &&
    (@browser.property(target, "tabIndex") : Int32) < 0
  if temporary {
    target.set_attribute("tabindex", "-1")
    target.set_attribute("data-comment-footnote-focus", "")
    target.add_event_listener_with_options(
      "blur",
      _ => {
        target.remove_attribute("data-comment-footnote-focus")
        if target.get_attribute("tabindex") == Some("-1") {
          target.remove_attribute("tabindex")
        }
      },
      once=true,
    )
  }
  @browser.focus(target)
}
