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
fn review_hunk_header(
  hunk : @model.DiffHunk,
  old_base : Int,
  new_base : Int,
) -> String {
  "@@ -\{review_hunk_range(hunk.old_start + old_base, hunk.old_len)} +\{review_hunk_range(hunk.new_start + new_base, hunk.new_len)} @@"
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
  document : @model.HunkDocument,
  patch : CanonicalPatch,
  old_base? : Int = 0,
  new_base? : Int = 0,
) -> Array[ReviewRow] {
  let rows : Array[ReviewRow] = []
  for hunk in document.hunks {
    append_projected_review_rows(
      rows,
      file_index,
      path,
      hunk.rows,
      patch,
      old_base,
      new_base,
    )
  }
  rows
}

///|
fn append_projected_review_pair(
  rows : Array[ReviewRow],
  file_index : Int,
  path : String,
  patch : CanonicalPatch,
  pair : @model.DiffLinePair,
  kind : ReviewRowKind,
  old_base : Int,
  new_base : Int,
) -> Unit {
  match pair {
    Paired(old, new) =>
      rows.push(
        make_review_row(
          file_index,
          path,
          patch,
          Some(old_base + old.index + 1),
          Some(new_base + new.index + 1),
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
          Some(old_base + old.index + 1),
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
          Some(new_base + new.index + 1),
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

///|
fn append_projected_review_rows(
  output : Array[ReviewRow],
  file_index : Int,
  path : String,
  rows : ArrayView[@model.DiffRow],
  patch : CanonicalPatch,
  old_base : Int,
  new_base : Int,
) -> Unit {
  for row in rows {
    match row {
      Context(line) =>
        output.push(
          make_review_row(
            file_index,
            path,
            patch,
            Some(old_base + line.old_index + 1),
            Some(new_base + line.new_index + 1),
            Some(line.text),
            Some(line.text),
            Some(plain_review_segments(line.text)),
            Some(plain_review_segments(line.text)),
            ContextRow,
            true,
          ),
        )
      Changed(pair) =>
        append_projected_review_pair(
          output,
          file_index,
          path,
          patch,
          pair,
          ChangeRow,
          old_base,
          new_base,
        )
      Neutral(pair) =>
        append_projected_review_pair(
          output,
          file_index,
          path,
          patch,
          pair,
          IgnoredRow,
          old_base,
          new_base,
        )
    }
  }
}

///|
fn project_semantic_review_rows(
  file_index : Int,
  path : String,
  semantic_rows : ArrayView[@model.DiffRow],
  patch : CanonicalPatch,
  old_base? : Int = 0,
  new_base? : Int = 0,
) -> Array[ReviewRow] {
  let rows : Array[ReviewRow] = []
  append_projected_review_rows(
    rows, file_index, path, semantic_rows, patch, old_base, new_base,
  )
  rows
}

///|
fn project_review_items(
  file_index : Int,
  path : String,
  document : @model.HunkDocument,
  patch : CanonicalPatch,
  old_base? : Int = 0,
  new_base? : Int = 0,
) -> Array[ReviewItem] {
  let items : Array[ReviewItem] = []
  for hunk in document.hunks {
    items.push(ReviewHunk(review_hunk_header(hunk, old_base, new_base)))
    let one = @model.HunkDocument::{ hunks: [hunk] }
    for
      row in project_review_rows(
        file_index,
        path,
        one,
        patch,
        old_base~,
        new_base~,
      ) {
      items.push(ReviewLine(row))
    }
  }
  items
}
