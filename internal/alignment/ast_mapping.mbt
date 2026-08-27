///|
using @diff_ignore {type SourceView}

///|
fn unit_source_view(view : SourceView, unit : ImplUnit?) -> SourceView {
  if unit is Some(unit) {
    view.slice(unit.range.start, unit.range.len)
  } else {
    @diff_ignore.SourceView::from_lines([])
  }
}

///|
fn record_out_of_bounds_side(sides : Array[DiffSide], side : DiffSide) -> Unit {
  if !sides.contains(side) {
    sides.push(side)
  }
}

///|
fn ordered_out_of_bounds_sides(sides : ArrayView[DiffSide]) -> Array[DiffSide] {
  let ordered : Array[DiffSide] = []
  if sides.contains(Old) {
    ordered.push(Old)
  }
  if sides.contains(New) {
    ordered.push(New)
  }
  ordered
}

///|
// Structural positions keep original CST line numbers. Move both their own
// and opposite spans into the dense filtered view before hunk building. Valid
// spans touching excluded source text are deliberately omitted, while invalid
// coordinates are retained as side-specific fallback metadata.
fn map_matched_positions(
  positions : ArrayView[MatchedPos],
  own : SourceView,
  opposite : SourceView,
  own_side : DiffSide,
  opposite_side : DiffSide,
  out_of_bounds_sides : Array[DiffSide],
) -> Array[MatchedPos] {
  let mapped : Array[MatchedPos] = []
  for position in positions {
    let own_mapping = own.map_span(position.pos)
    let kind : MatchKind = match position.kind {
      Novel => Novel
      Unchanged(opposite_pos~) => {
        let mapped_opposites : Array[@span.SingleLineSpan] = []
        for span in opposite_pos {
          match opposite.map_span(span) {
            Mapped(mapped_span) => mapped_opposites.push(mapped_span)
            Filtered => ()
            OutOfBounds =>
              record_out_of_bounds_side(out_of_bounds_sides, opposite_side)
          }
        }
        Unchanged(opposite_pos=mapped_opposites)
      }
    }
    match own_mapping {
      Mapped(pos) => mapped.push({ kind, pos })
      Filtered => ()
      OutOfBounds => record_out_of_bounds_side(out_of_bounds_sides, own_side)
    }
  }
  mapped
}
