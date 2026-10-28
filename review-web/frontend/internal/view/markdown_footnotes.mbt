///|
fn markdown_id_component(value : String) -> String {
  let result = StringBuilder()
  let hex = b"0123456789abcdef"
  for byte in @utf8.encode(value) {
    let n = byte.to_int()
    result.write_char(hex[n >> 4].to_int().unsafe_to_char())
    result.write_char(hex[n & 15].to_int().unsafe_to_char())
  }
  result.to_string()
}

///|
fn markdown_scope_footnotes(doc : @cmark.Doc, scope : String) -> @cmark.Doc {
  if !doc.defs.values().any(definition => definition is FootnoteDef(_)) {
    return doc
  }
  let prefix = "^md-\{markdown_id_component(scope)}-"
  fn rename(label : @cmark.Label) -> @cmark.Label {
    // Encode the full normalized key: Unicode, spaces and dashes stay distinct
    // even though cmark normally converts whitespace in footnote IDs to dashes.
    { ..label, key: prefix + markdown_id_component(label.key), }
  }
  let mapper = @cmark.Mapper::new(
    inline=fn(mapper, inline) {
      let link = match inline {
        Link(link) | Image(link) => link
        _ => return Default
      }
      guard link.v.reference is Ref(layout, label, defined) &&
        doc.defs.get(defined.key) is Some(FootnoteDef(_)) else {
        return Default
      }
      let link : @cmark.Node[@cmark.InlineLink] = link.map(value => {
        reference: Ref(layout, rename(label), rename(defined)),
        text: mapper.map_inline(value.text).unwrap_or(@cmark.Inline::empty()),
      })
      @cmark.Mapper::ret(
        if inline is Image(_) {
          Image(link)
        } else {
          Link(link)
        },
      )
    },
    block=fn(mapper, block) {
      guard block is ExtFootnoteDefinition(footnote) else { return Default }
      @cmark.Mapper::ret(
        ExtFootnoteDefinition(
          footnote.map(value => {
            ..value,
            label: rename(value.label),
            defined_label: value.defined_label.map(rename),
            block: mapper
            .map_block(value.block)
            .unwrap_or(@cmark.Block::empty()),
          }),
        ),
      )
    },
  )
  let mapped = mapper.map_doc(doc)
  let defs : Map[String, @cmark.LabelDef] = Map([])
  // Preserve the parser's complete definition table, including ordinary link
  // definitions nested inside footnotes. map_doc maps their bodies, not labels.
  for key, definition in mapped.defs {
    match definition {
      FootnoteDef(footnote) =>
        defs[prefix + markdown_id_component(key)] = FootnoteDef(
          footnote.map(value => {
            ..value,
            label: rename(value.label),
            defined_label: value.defined_label.map(rename),
          }),
        )
      _ => defs[key] = definition
    }
  }
  { ..mapped, defs, }
}
