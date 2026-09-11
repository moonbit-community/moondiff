///|
fn file_change_controls(
  file : FileState,
  generation : Int,
  file_index : Int,
  algorithm : DiffAlgorithm,
  ignore_comments : Bool,
  ignore_tests : Bool,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  guard cached_file_document(file, algorithm, ignore_comments~, ignore_tests~)
    is Some(MoonBit(document=TopLevel(top), ..)) else {
    return @html.nothing
  }
  let enabled = file.expanded &&
    top.sections.any(section => {
      semantic_section_fragment(section).document.hunks.any(hunk => {
        hunk.blocks.any(block => block is ChangeBlock(rows) && !rows.is_empty())
      })
    })
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
                event, generation, file_index, direction, emit,
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
