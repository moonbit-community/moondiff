///|
priv suberror PageActivitySubscription {
  PageActivitySubscription(@rabbita.Emit[Msg])
}

///|
extern "js" fn page_is_active() -> Bool = "() => !document.hidden && document.hasFocus()"

///|
fn page_activity_sub_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  guard payload is PageActivitySubscription(next_tagger) else { return None }
  let mut tagger = next_tagger
  let mut active = page_is_active()
  let listener : @dom.Listener = _ => {
    let next_active = page_is_active()
    if !active && next_active {
      scheduler.add(tagger(Review(PageReactivated)))
    }
    active = next_active
  }
  let window = @dom.window().as_event_target()
  let document = @dom.document().as_event_target()
  window
  ..add_event_listener("focus", listener)
  .add_event_listener("blur", listener)
  document.add_event_listener("visibilitychange", listener)
  Some({
    unload: _ => {
      window
      ..remove_event_listener("focus", listener)
      .remove_event_listener("blur", listener)
      document.remove_event_listener("visibilitychange", listener)
    },
    update_tagger: next_payload => {
      guard next_payload is PageActivitySubscription(next_tagger) else {
        return
      }
      tagger = next_tagger
    },
  })
}

///|
fn page_reactivation_subscription(emit : @rabbita.Emit[Msg]) -> @sub.Sub {
  @sub.custom_sub(
    "page_activity",
    Local,
    PageActivitySubscription(emit),
    SubLoader(page_activity_sub_loader),
  )
}
