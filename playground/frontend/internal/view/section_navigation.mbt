///|
fn change_controls(
  input : NavigationInput,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
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
          disabled=!input.enabled,
          attrs=@html.Attrs::build()
            .aria_label(label)
            .data_set("change-direction", direction.to_string())
            .on_click(event => {
              @application.navigate_section_change(
                event,
                input.generation,
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
