///|
// Shared by the state, its interaction listener and any queued render command.
// Cancellation is synchronous so even a command ahead of the next reducer event
// cannot steal focus or scroll after the user has taken control.
pub(all) struct HistoryRestoration {
  generation : Int32
  entry : String
  mut cancelled : Bool
} derive(Eq)

///|
#deprecated
#doc(hidden)
pub extend HistoryRestoration with Eq::{not_equal, equal}

///|
fn cancel_history_for_edit(model : Model, msg : Msg) -> Model {
  guard model.navigation.restore_position &&
    (
      msg
      is Review(
        DraftBodyChanged(_)
        | OpenOverallDraft
        | OpenInlineDraft(_, _)
        | OpenReplyDraft(_)
      ) ||
      msg is Ui(InputChanged(_) | FileTreeSearchChanged(_))
    ) else {
    return model
  }
  if model.navigation.restoration is Some(restoration) {
    restoration.cancelled = true
  }
  { ..model, navigation: { ..model.navigation, restore_position: false, }, }
}

///|
fn synchronize_history_restoration(before : Model, next : Model) -> Model {
  if before.navigation.restoration is Some(restoration) &&
    (
      !next.navigation.restore_position ||
      restoration.generation != next.generation ||
      restoration.entry != next.navigation.entry.id
    ) {
    restoration.cancelled = true
  }
  if !next.navigation.restore_position {
    return next
  }
  if next.navigation.restoration is Some(restoration) &&
    restoration.generation == next.generation &&
    restoration.entry == next.navigation.entry.id {
    return if restoration.cancelled {
      { ..next, navigation: { ..next.navigation, restore_position: false, }, }
    } else {
      next
    }
  }
  {
    ..next,
    navigation: {
      ..next.navigation,
      restoration: Some({
        generation: next.generation,
        entry: next.navigation.entry.id,
        cancelled: false,
      }),
    },
  }
}

///|
priv suberror HistoryInteractionSubscription {
  HistoryInteractionSubscription(HistoryRestoration, @rabbita.Emit[Msg])
}

///|
fn history_interaction_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  guard payload is HistoryInteractionSubscription(initial, initial_tagger) else {
    return None
  }
  let mut restoration = initial
  let mut tagger = initial_tagger
  let listener : @dom.Listener = event => {
    guard !restoration.cancelled else { return }
    // Regional mounts use a private, non-bubbling click to acquire their paint
    // scheduler. It is a render notification, not an interaction.
    let kind : String = @browser.event_property(event, "type")
    let bubbles : Bool = @browser.event_property(event, "bubbles")
    if kind == "click" && !bubbles {
      return
    }
    restoration.cancelled = true
    scheduler.add(
      tagger(Ui(PositionRestored(restoration.generation, restoration.entry))),
    )
  }
  // Scroll notifications also come from layout and our own focus restoration.
  // Observe scrolling intent instead, including keyboard and scrollbar input.
  let events = [
    "pointerdown", "click", "keydown", "input", "wheel", "touchstart", "touchmove",
  ]
  let window = @dom.window()
  for event in events {
    window.add_event_listener_with_options(
      event,
      listener,
      capture=true,
      passive=true,
    )
  }
  Some({
    unload: _ => {
      for event in events {
        window.remove_event_listener_with_options(event, listener, capture=true)
      }
    },
    update_tagger: payload => {
      if payload is HistoryInteractionSubscription(next, next_tagger) {
        restoration = next
        tagger = next_tagger
      }
    },
  })
}

///|
fn history_interaction_subscription(
  model : Model,
  emit : @rabbita.Emit[Msg],
) -> @sub.Sub {
  guard model.navigation.restore_position &&
    model.navigation.restoration is Some(restoration) &&
    !restoration.cancelled else {
    return @sub.none
  }
  @sub.custom_sub(
    "history_interaction",
    Local,
    HistoryInteractionSubscription(restoration, emit),
    SubLoader(history_interaction_loader),
  )
}
