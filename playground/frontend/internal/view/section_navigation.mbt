///|
fn change_controls(model : Model, emit : @rabbita.Emit[Msg]) -> @rabbita.Html {
  let mut enabled = false
  if model.phase is Showing(view) {
    for index, _ in view.files {
      if @application.file_navigation_enabled(model, index) {
        enabled = true
        break
      }
    }
  }
  @html.span(
    class="section-change-controls",
    [
      for
        (label, text, direction) in [
          ("Previous change", "↑ prev", -1),
          ("Next change", "↓ next", 1),
        ] => {
        @html.button(
          type_="button",
          class="section-change-button",
          title=label,
          disabled=!enabled,
          attrs=@html.Attrs::build()
            .aria_label(label)
            .data_set("change-direction", direction.to_string())
            .on_click(event => {
              @application.navigate_section_change(
                event,
                model.generation,
                direction,
                emit,
              )
            }),
          text,
        )
      }
    ],
  )
}

///|
fn change_block_start_attrs(block : Int?) -> @html.Attrs {
  let attrs = @html.Attrs::build()
  if block is Some(index) {
    attrs.data_set("change-block-start", index.to_string())
  } else {
    attrs
  }
}
