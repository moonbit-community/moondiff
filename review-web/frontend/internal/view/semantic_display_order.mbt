///|
// Preserve new-side order, attaching each deletion run to its preceding old-side
// match (or the following match for leading deletions). Use every identity here:
// visibility and collapse filtering must not change a deletion's anchor.
fn semantic_display_order(top : @mbtdiff.TopLevelDiff) -> Array[Int32] {
  let positions = Array::make(top.sections.length(), 0)
  for position, index in top.new_order {
    positions[index] = position
  }
  // A slot precedes the new-side declaration at that position (or follows the
  // last one). Filling slots in old order also resolves shared anchors stably.
  let before : Array[Array[Int32]] = Array::makei(top.new_order.length() + 1, _ => {
    []
  })
  let leading : Array[Int32] = []
  let mut previous : Int32? = None
  for index in top.old_order {
    match top.sections[index] {
      Matched(..) => {
        if previous is None {
          before[positions[index]].append(leading)
          leading.clear()
        }
        previous = Some(index)
      }
      Deleted(..) =>
        match previous {
          Some(anchor) => before[positions[anchor] + 1].push(index)
          None => leading.push(index)
        }
      Inserted(..) => ()
    }
  }
  // With no matched declarations, all old declarations precede the new ones.
  before[0].append(leading)
  let result = []
  for position, index in top.new_order {
    result.append(before[position])
    result.push(index)
  }
  result.append(before[top.new_order.length()])
  result
}
