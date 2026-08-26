///|
using @diff_ignore {type SourceView}

///|
fn unit_source_view(view : SourceView, unit : ImplUnit?) -> SourceView {
  if unit is Some(unit) {
    let source_len = if unit.source == "" {
      0
    } else {
      @source_text.split_lines(unit.source).length()
    }
    view.slice(unit.start_line - 1, source_len)
  } else {
    @diff_ignore.SourceView::from_lines([])
  }
}

///|
// Structural positions keep original CST line numbers. Move both their own
// and opposite spans into the dense filtered view before hunk building.
// Any syntax span touching excluded source text is deliberately omitted.
fn map_matched_positions(
  positions : ArrayView[MatchedPos],
  own : SourceView,
  opposite : SourceView,
) -> Array[MatchedPos] {
  let mapped : Array[MatchedPos] = []
  for position in positions {
    guard own.map_span(position.pos) is Some(pos) else { continue }
    let kind = match position.kind {
      Novel => MatchKind::Novel
      Unchanged(opposite_pos~) => {
        let mapped : Array[@span.SingleLineSpan] = []
        for span in opposite_pos {
          if opposite.map_span(span) is Some(mapped_span) {
            mapped.push(mapped_span)
          }
        }
        Unchanged(opposite_pos=mapped)
      }
    }
    mapped.push({ kind, pos })
  }
  mapped
}
