///|
const LINE_DIFF_CUTOFF : Int = 4_096

///|
fn make_diff_line(
  index : Int,
  segments : Array[@model.DiffSegment],
) -> @model.DiffLine {
  { index, segments: segments[:] }
}

///|
fn make_plain_diff_line(index : Int, text : String) -> @model.DiffLine {
  let segments : Array[@model.DiffSegment] = if text == "" {
    []
  } else {
    [{ kind: Unchanged, text }]
  }
  make_diff_line(index, segments)
}

///|
fn plain_change_rows(
  old_lines : ArrayView[String],
  new_lines : ArrayView[String],
  old_start : Int,
  new_start : Int,
  budget : @worddiff.RefinementBudget,
) -> ArrayView[@model.DiffRow] {
  let rows : Array[@model.DiffRow] = []
  let row_count = if old_lines.length() > new_lines.length() {
    old_lines.length()
  } else {
    new_lines.length()
  }
  let refine_words = old_lines.length() == new_lines.length()
  for offset in 0..<row_count {
    match (old_lines.get(offset), new_lines.get(offset)) {
      (Some(old_line), Some(new_line)) => {
        let row : @model.DiffRow = if refine_words {
          match @worddiff.refine_line(old_line, new_line, budget~) {
            Some((old_segments, new_segments)) =>
              Paired(
                make_diff_line(old_start + offset, old_segments),
                make_diff_line(new_start + offset, new_segments),
              )
            None =>
              Paired(
                make_plain_diff_line(old_start + offset, old_line),
                make_plain_diff_line(new_start + offset, new_line),
              )
          }
        } else {
          Paired(
            make_plain_diff_line(old_start + offset, old_line),
            make_plain_diff_line(new_start + offset, new_line),
          )
        }
        rows.push(row)
      }
      (Some(old_line), None) =>
        rows.push(OldOnly(make_plain_diff_line(old_start + offset, old_line)))
      (None, Some(new_line)) =>
        rows.push(NewOnly(make_plain_diff_line(new_start + offset, new_line)))
      (None, None) => ()
    }
  }
  rows[:]
}

///|
fn edit_bounds(edit : @diff.Edit) -> (Int, Int, Int, Int) {
  match edit {
    Delete(old_index~, old_len~, new_index~) =>
      (old_index, new_index, old_index + old_len, new_index)
    Equal(old_index~, new_index~, len~) =>
      (old_index, new_index, old_index + len, new_index + len)
    Insert(old_index~, new_index~, new_len~) =>
      (old_index, new_index, old_index, new_index + new_len)
  }
}

///|
fn hunk_range(edits : ArrayView[@diff.Edit]) -> (Int, Int, Int, Int) {
  let (old_start, new_start, _, _) = edit_bounds(edits[0])
  let (_, _, old_end, new_end) = edit_bounds(edits[edits.length() - 1])
  (old_start, old_end - old_start, new_start, new_end - new_start)
}

///|
fn plain_hunk(
  hunk : @diff.Hunk[String],
  budget : @worddiff.RefinementBudget,
) -> @model.DiffHunk {
  let blocks : Array[@model.DiffBlock] = []
  let edits = hunk.edits()
  let old_view = hunk.old_view()
  let new_view = hunk.new_view()
  let mut index = 0
  while index < edits.length() {
    let replacement = if index + 1 < edits.length() {
      @worddiff.replacement_ranges(edits[index], edits[index + 1])
    } else {
      None
    }
    match replacement {
      Some(((old_start, old_end), (new_start, new_end))) => {
        blocks.push(
          ChangeBlock(
            plain_change_rows(
              old_view.view(start=old_start, end=old_end),
              new_view.view(start=new_start, end=new_end),
              old_start,
              new_start,
              budget,
            ),
          ),
        )
        index += 2
      }
      None =>
        match edits[index] {
          Equal(old_index~, new_index~, len~) => {
            let lines : Array[@model.ContextLine] = []
            for offset in 0..<len {
              lines.push({
                old_index: old_index + offset,
                new_index: new_index + offset,
                text: old_view[old_index + offset],
              })
            }
            blocks.push(ContextBlock(lines[:]))
            index += 1
          }
          Delete(old_index~, old_len~, ..) => {
            let rows : Array[@model.DiffRow] = []
            for offset in 0..<old_len {
              rows.push(
                OldOnly(
                  make_plain_diff_line(
                    old_index + offset,
                    old_view[old_index + offset],
                  ),
                ),
              )
            }
            blocks.push(ChangeBlock(rows[:]))
            index += 1
          }
          Insert(new_index~, new_len~, ..) => {
            let rows : Array[@model.DiffRow] = []
            for offset in 0..<new_len {
              rows.push(
                NewOnly(
                  make_plain_diff_line(
                    new_index + offset,
                    new_view[new_index + offset],
                  ),
                ),
              )
            }
            blocks.push(ChangeBlock(rows[:]))
            index += 1
          }
        }
    }
  }
  let (old_start, old_len, new_start, new_len) = hunk_range(edits)
  { old_start, old_len, new_start, new_len, blocks: blocks[:] }
}

///|
fn line_diff_with_budget(
  old : ArrayView[String],
  new : ArrayView[String],
  context : Int,
  budget : @worddiff.RefinementBudget,
) -> @model.HunkDocument {
  let context = if context < 0 { 0 } else { context }
  let hunks : Array[@model.DiffHunk] = []
  for
    hunk in @diff.Diff(old~, new~, cutoff=LINE_DIFF_CUTOFF, algorithm=Patience).group(
      context~,
    ) {
    hunks.push(plain_hunk(hunk, budget))
  }
  { hunks: hunks[:] }
}

///|
/// Calculate a Patience line diff without lexing or semantic cleanup. Equal-
/// width replacement blocks receive bounded whitespace-word refinement under
/// a limit of 16,384 UTF-16 code units per side and shared document limits of
/// 1,048,576 attempted code units and 65,536 diff tokens. Rejected refinements
/// keep their plain line structure. A negative `context` is treated as zero.
pub fn line_diff(
  old~ : ArrayView[String],
  new~ : ArrayView[String],
  context? : Int = 3,
) -> @model.HunkDocument {
  line_diff_with_budget(old, new, context, @worddiff.RefinementBudget::new())
}
