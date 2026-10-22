///|
fn focus_selector(selector : String) -> @rabbita.Cmd {
  @cmd.custom_cmd(_ => {
    if @dom.document().query_selector(selector).to_option() is Some(element) {
      if element.to_html_element() is Some(target) {
        target.focus_with_options(prevent_scroll=true)
      }
    }
  })
}
