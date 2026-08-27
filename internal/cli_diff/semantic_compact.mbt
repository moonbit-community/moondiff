///|
fn semantic_row_consumption(row : @model.DiffRow) -> (Int, Int) {
  match row {
    Context(_) => (1, 1)
    Changed(pair) | Neutral(pair) =>
      match pair {
        Paired(_, _) => (1, 1)
        OldOnly(_) => (1, 0)
        NewOnly(_) => (0, 1)
      }
  }
}

///|
fn semantic_row_cursors(
  rows : ArrayView[@model.DiffRow],
) -> (Array[Int], Array[Int]) {
  let old : Array[Int] = [0]
  let new : Array[Int] = [0]
  for row in rows {
    let consumed = semantic_row_consumption(row)
    old.push(old[old.length() - 1] + consumed.0)
    new.push(new[new.length() - 1] + consumed.1)
  }
  (old, new)
}

///|
fn push_semantic_window(
  windows : Array[(Int, Int)],
  start : Int,
  end_ : Int,
) -> Unit {
  guard windows.last() is Some(previous) else {
    windows.push((start, end_))
    return
  }
  if start <= previous.1 {
    windows[windows.length() - 1] = (previous.0, @cmp.maximum(previous.1, end_))
  } else {
    windows.push((start, end_))
  }
}

///|
fn semantic_pair_has_ignored_segment(pair : @model.DiffLinePair) -> Bool {
  fn line_has_ignored(line : @model.DiffLine) -> Bool {
    line.segments.any(segment => segment.kind is Ignored)
  }

  match pair {
    Paired(old_line, new_line) =>
      line_has_ignored(old_line) || line_has_ignored(new_line)
    OldOnly(line) | NewOnly(line) => line_has_ignored(line)
  }
}

///|
// The former AST hunk projector placed non-novel formatting rows in change
// blocks, while filtered source gaps used ignored blocks. Preserve that CLI
// styling distinction without making either kind a hunk core.
fn semantic_cli_row(row : @model.DiffRow) -> @model.DiffRow {
  match row {
    Neutral(pair) if !semantic_pair_has_ignored_segment(pair) => Changed(pair)
    _ => row
  }
}

///|
/// Convert a complete semantic row stream into traditional CLI hunks. Only
/// `Changed` rows form hunk cores; `Neutral` rows are presentation context and
/// never make a fragment visible on their own.
fn compact_semantic_rows(
  rows : ArrayView[@model.DiffRow],
  context_lines : Int,
) -> @model.HunkDocument {
  let radius = @cmp.maximum(context_lines, 0)
  let windows : Array[(Int, Int)] = []
  for index, row in rows {
    if row is Changed(_) {
      push_semantic_window(
        windows,
        @cmp.maximum(index - radius, 0),
        @cmp.minimum(index + radius + 1, rows.length()),
      )
    }
  }
  let (old_cursors, new_cursors) = semantic_row_cursors(rows)
  let hunks : Array[@model.DiffHunk] = []
  for window in windows {
    let (start, end_) = window
    let display_rows : Array[@model.DiffRow] = []
    for row in rows[start:end_] {
      display_rows.push(semantic_cli_row(row))
    }
    hunks.push({
      old_start: old_cursors[start],
      old_len: old_cursors[end_] - old_cursors[start],
      new_start: new_cursors[start],
      new_len: new_cursors[end_] - new_cursors[start],
      rows: display_rows[:],
    })
  }
  { hunks: hunks[:] }
}
