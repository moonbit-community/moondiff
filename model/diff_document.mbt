///|
/// Whether one source segment is unchanged or belongs to an intraline change.
/// Renderers decide how to present `Changed`; the calculation layer never
/// assigns markup, colors, or terminal styles.
pub(all) enum DiffSegmentKind {
  Unchanged
  Changed
  /// Source text excluded from comparison but retained for faithful display.
  Ignored
} derive(Eq)

///|
/// One exact source-text segment in a changed line. Concatenating a line's
/// segment texts always reconstructs that source line byte-for-byte.
pub(all) struct DiffSegment {
  kind : DiffSegmentKind
  text : String
} derive(Eq)

///|
/// One changed source line. `index` is zero-based in its original input.
/// `segments` is a zero-copy read-only view whose backing storage is never
/// mutated after the line is published.
pub(all) struct DiffLine {
  index : Int
  segments : ArrayView[DiffSegment]
} derive(Eq)

///|
/// Reconstruct the exact source text of this line.
pub fn DiffLine::text(self : DiffLine) -> String {
  let buf = StringBuilder()
  for segment in self.segments {
    buf <+ "\{segment.text}"
  }
  buf.to_string()
}

///|
/// One unchanged line shared by both inputs. Indices are zero-based.
pub(all) struct ContextLine {
  old_index : Int
  new_index : Int
  text : String
} derive(Eq)

///|
/// The source lines present on one non-context diff row. The enum keeps a
/// present blank line distinct from a missing side without empty-string
/// sentinels.
pub(all) enum DiffLinePair {
  Paired(DiffLine, DiffLine)
  OldOnly(DiffLine)
  NewOnly(DiffLine)
} derive(Eq)

///|
/// One aligned source row. `Context` is byte-for-byte equal on both sides;
/// `Changed` is recognized by the selected diff mode; `Neutral` preserves a
/// textual difference excluded by structural comparison or active filters.
pub(all) enum DiffRow {
  Context(ContextLine)
  Changed(DiffLinePair)
  Neutral(DiffLinePair)
} derive(Eq)

///|
/// One grouped diff hunk. Starts are zero-based cursors and lengths are source
/// line counts. Renderers derive display headers from these numeric ranges.
/// Consecutive `Changed` rows form the replacement runs used by unified
/// renderers. `rows` is a zero-copy read-only view with stable backing storage.
pub(all) struct DiffHunk {
  old_start : Int
  old_len : Int
  new_start : Int
  new_len : Int
  rows : ArrayView[DiffRow]
} derive(Eq)

///|
/// A traditional grouped diff used by plain-text calculation and presentation
/// renderers. Semantic `DiffFragment` values expose complete rows directly and
/// do not contain this type. Hunk indexes remain local until a consumer calls
/// `rebase`; all nested views have stable, read-only backing storage.
pub(all) struct HunkDocument {
  hunks : ArrayView[DiffHunk]
} derive(Eq)

///|
fn DiffLine::rebase_index(self : DiffLine, offset : Int) -> DiffLine {
  { index: self.index + offset, segments: self.segments }
}

///|
fn DiffLinePair::rebase_indexes(
  self : DiffLinePair,
  old_line_offset : Int,
  new_line_offset : Int,
) -> DiffLinePair {
  match self {
    Paired(old_line, new_line) =>
      Paired(
        old_line.rebase_index(old_line_offset),
        new_line.rebase_index(new_line_offset),
      )
    OldOnly(line) => OldOnly(line.rebase_index(old_line_offset))
    NewOnly(line) => NewOnly(line.rebase_index(new_line_offset))
  }
}

///|
fn DiffRow::rebase_indexes(
  self : DiffRow,
  old_line_offset : Int,
  new_line_offset : Int,
) -> DiffRow {
  match self {
    Context(line) =>
      Context({
        old_index: line.old_index + old_line_offset,
        new_index: line.new_index + new_line_offset,
        text: line.text,
      })
    Changed(lines) =>
      Changed(lines.rebase_indexes(old_line_offset, new_line_offset))
    Neutral(lines) =>
      Neutral(lines.rebase_indexes(old_line_offset, new_line_offset))
  }
}

///|
/// Return a new document whose zero-based source indexes are shifted by the
/// supplied offsets. Hunk ranges, context indexes, and non-context line indexes
/// are rebased together.
pub fn HunkDocument::rebase(
  self : HunkDocument,
  old_line_offset : Int,
  new_line_offset : Int,
) -> HunkDocument {
  let hunks : Array[DiffHunk] = []
  for hunk in self.hunks {
    let old_start = hunk.old_start + old_line_offset
    let new_start = hunk.new_start + new_line_offset
    let rows : Array[DiffRow] = []
    for row in hunk.rows {
      rows.push(row.rebase_indexes(old_line_offset, new_line_offset))
    }
    hunks.push({
      old_start,
      old_len: hunk.old_len,
      new_start,
      new_len: hunk.new_len,
      rows: rows[:],
    })
  }
  { hunks: hunks[:] }
}
