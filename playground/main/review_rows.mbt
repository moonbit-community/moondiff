///|
priv enum ReviewRowKind {
  ContextRow
  ChangeRow
  IgnoredRow
}

///|
priv struct ReviewRow {
  file_index : Int
  old_line : Int?
  new_line : Int?
  old_text : String?
  new_text : String?
  old_segments : ArrayView[@model.DiffSegment]?
  new_segments : ArrayView[@model.DiffSegment]?
  kind : ReviewRowKind
  old_anchor : ReviewAnchor?
  new_anchor : ReviewAnchor?
}

///|
priv enum ReviewItem {
  ReviewHunk(String)
  ReviewLine(ReviewRow)
}

///|
fn review_hunk_range(start : Int, len : Int) -> String {
  if len == 1 {
    (start + 1).to_string()
  } else {
    "\{start + 1},\{len}"
  }
}

///|
fn review_hunk_header(hunk : @model.DiffHunk) -> String {
  "@@ -\{review_hunk_range(hunk.old_start, hunk.old_len)} +\{review_hunk_range(hunk.new_start, hunk.new_len)} @@"
}

///|
fn plain_review_segments(text : String) -> ArrayView[@model.DiffSegment] {
  if text.is_empty() {
    []
  } else {
    [{ kind: Unchanged, text }]
  }
}

///|
fn make_review_row(
  file_index : Int,
  _path : String,
  patch : CanonicalPatch,
  old_line : Int?,
  new_line : Int?,
  old_text : String?,
  new_text : String?,
  old_segments : ArrayView[@model.DiffSegment]?,
  new_segments : ArrayView[@model.DiffSegment]?,
  kind : ReviewRowKind,
  context : Bool,
) -> ReviewRow {
  let old_anchor = match (context, old_line) {
    (false, Some(line)) => canonical_anchor(patch, Left, line)
    _ => None
  }
  let new_anchor = if new_line is Some(line) {
    canonical_anchor(patch, Right, line)
  } else {
    None
  }
  {
    file_index,
    old_line,
    new_line,
    old_text,
    new_text,
    old_segments,
    new_segments,
    kind,
    old_anchor,
    new_anchor,
  }
}

///|
fn project_review_rows(
  file_index : Int,
  path : String,
  document : @model.DiffDocument,
  patch : CanonicalPatch,
) -> Array[ReviewRow] {
  let rows : Array[ReviewRow] = []
  for hunk in document.hunks {
    for block in hunk.blocks {
      match block {
        ContextBlock(lines) =>
          for line in lines {
            rows.push(
              make_review_row(
                file_index,
                path,
                patch,
                Some(line.old_index + 1),
                Some(line.new_index + 1),
                Some(line.text),
                Some(line.text),
                Some(plain_review_segments(line.text)),
                Some(plain_review_segments(line.text)),
                ContextRow,
                true,
              ),
            )
          }
        ChangeBlock(changes) | IgnoredBlock(changes) => {
          let kind = if block is IgnoredBlock(_) {
            IgnoredRow
          } else {
            ChangeRow
          }
          for row in changes {
            match row {
              Paired(old, new) =>
                rows.push(
                  make_review_row(
                    file_index,
                    path,
                    patch,
                    Some(old.index + 1),
                    Some(new.index + 1),
                    Some(old.text()),
                    Some(new.text()),
                    Some(old.segments),
                    Some(new.segments),
                    kind,
                    false,
                  ),
                )
              OldOnly(old) =>
                rows.push(
                  make_review_row(
                    file_index,
                    path,
                    patch,
                    Some(old.index + 1),
                    None,
                    Some(old.text()),
                    None,
                    Some(old.segments),
                    None,
                    kind,
                    false,
                  ),
                )
              NewOnly(new) =>
                rows.push(
                  make_review_row(
                    file_index,
                    path,
                    patch,
                    None,
                    Some(new.index + 1),
                    None,
                    Some(new.text()),
                    None,
                    Some(new.segments),
                    kind,
                    false,
                  ),
                )
            }
          }
        }
      }
    }
  }
  rows
}

///|
fn project_review_items(
  file_index : Int,
  path : String,
  document : @model.DiffDocument,
  patch : CanonicalPatch,
) -> Array[ReviewItem] {
  let items : Array[ReviewItem] = []
  for hunk in document.hunks {
    items.push(ReviewHunk(review_hunk_header(hunk)))
    let one = @model.DiffDocument::{ hunks: [hunk] }
    for row in project_review_rows(file_index, path, one, patch) {
      items.push(ReviewLine(row))
    }
  }
  items
}
