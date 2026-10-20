///|
fn[C : @html.IsChildren] internal_link(
  path : String,
  label : C,
  emit : @rabbita.Emit[Msg],
  class~ : String = "",
  prefetch~ : @protocol.PullGet? = None,
  activate? : Msg,
) -> @rabbita.Html {
  @html.a(
    escape=true,
    href=path,
    class~,
    attrs=@html.Attrs::build()
      .on_mouseenter(_ => {
        if prefetch is Some(_) {
          emit(Home(PrefetchIntent(prefetch, true)))
        } else {
          @rabbita.none
        }
      })
      .on_focus(_ => {
        if prefetch is Some(_) {
          emit(Home(PrefetchIntent(prefetch, true)))
        } else {
          @rabbita.none
        }
      })
      .on_mouseleave(_ => {
        if prefetch is Some(_) {
          emit(Home(PrefetchIntent(prefetch, false)))
        } else {
          @rabbita.none
        }
      })
      .on_blur(_ => {
        if prefetch is Some(_) {
          emit(Home(PrefetchIntent(prefetch, false)))
        } else {
          @rabbita.none
        }
      })
      .on_click(event => {
        let button : Int32 = @browser.event_property(event.as_event(), "button")
        let ctrl : Bool = @browser.event_property(event.as_event(), "ctrlKey")
        let meta : Bool = @browser.event_property(event.as_event(), "metaKey")
        let shift : Bool = @browser.event_property(event.as_event(), "shiftKey")
        let alt : Bool = @browser.event_property(event.as_event(), "altKey")
        if button == 0 && !ctrl && !meta && !shift && !alt {
          event.prevent_default()
          emit(activate.unwrap_or(Ui(Navigate(path))))
        } else {
          @rabbita.none
        }
      }),
    label,
  )
}
