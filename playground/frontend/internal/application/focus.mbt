///|
fn focus_selector_after_render(selector : String) -> @rabbita.Cmd {
  @cmd.custom_cmd(kind=@cmd.after_render, _ => {
    match @dom.document().query_selector(selector).to_option() {
      None => ()
      Some(element) =>
        match element.to_html_element() {
          None => ()
          Some(target) => target.focus_with_options(prevent_scroll=true)
        }
    }
  })
}
