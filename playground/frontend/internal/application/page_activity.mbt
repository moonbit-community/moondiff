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
  let mut restoring = false
  let listener : @dom.Listener = _ => {
    let next_active = page_is_active()
    if !active && next_active {
      if restoring {
        restoring = false
        scheduler.add(tagger(Auth(RestoreAuth)))
      } else {
        scheduler.add(tagger(Review(PageReactivated)))
      }
    }
    active = next_active
  }
  let hidden_listener : @dom.Listener = _ => {
    @github_client.dispose()
    active = false
    restoring = true
  }
  let window = @dom.window().as_event_target()
  let document = @dom.document().as_event_target()
  window
  ..add_event_listener("focus", listener)
  ..add_event_listener("blur", listener)
  ..add_event_listener("pageshow", listener)
  .add_event_listener("pagehide", hidden_listener)
  document.add_event_listener("visibilitychange", listener)
  Some({
    unload: _ => {
      @github_client.dispose()
      window
      ..remove_event_listener("focus", listener)
      ..remove_event_listener("blur", listener)
      ..remove_event_listener("pageshow", listener)
      .remove_event_listener("pagehide", hidden_listener)
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
