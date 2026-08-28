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
/// One aligned row in a change block. The enum keeps a present blank line
/// distinct from a missing side without relying on empty-string sentinels.
pub(all) enum DiffRow {
  Paired(DiffLine, DiffLine)
  OldOnly(DiffLine)
  NewOnly(DiffLine)
} derive(Eq)

///|
/// One ordered block inside a hunk. Change-block boundaries are retained so a
/// unified renderer can emit all deletions before all insertions while a split
/// renderer consumes the aligned rows directly.
pub(all) enum DiffBlock {
  ContextBlock(ArrayView[ContextLine])
  ChangeBlock(ArrayView[DiffRow])
  /// Rows whose source text differs only in content excluded from comparison.
  /// Renderers keep their original text and line numbers without presenting
  /// them as additions or deletions.
  IgnoredBlock(ArrayView[DiffRow])
} derive(Eq)

///|
/// One grouped diff hunk. Starts are zero-based cursors and lengths are source
/// line counts. Renderers derive display headers from these numeric ranges.
/// `blocks` is a zero-copy read-only view with stable backing storage.
pub(all) struct DiffHunk {
  old_start : Int
  old_len : Int
  new_start : Int
  new_len : Int
  blocks : ArrayView[DiffBlock]
} derive(Eq)

///|
/// A fully calculated, renderer-neutral diff for one semantic fragment. Hunk
/// indexes are local to that fragment unless a consumer explicitly calls
/// `rebase`. Its recursively nested collections are zero-copy read-only views;
/// their backing storage is never mutated after publication.
pub(all) struct HunkDocument {
  hunks : ArrayView[DiffHunk]
} derive(Eq)

///|
fn DiffLine::rebase_index(self : DiffLine, offset : Int) -> DiffLine {
  { index: self.index + offset, segments: self.segments, }
}

///|
fn DiffBlock::rebase_indexes(
  self : DiffBlock,
  old_line_offset : Int,
  new_line_offset : Int,
) -> DiffBlock {
  match self {
    ContextBlock(lines) => {
      let rebased : Array[ContextLine] = []
      for line in lines {
        rebased.push({
          old_index: line.old_index + old_line_offset,
          new_index: line.new_index + new_line_offset,
          text: line.text,
        })
      }
      ContextBlock(rebased[:])
    }
    ChangeBlock(rows) | IgnoredBlock(rows) => {
      let rebased : Array[DiffRow] = []
      for row in rows {
        rebased.push(
          match row {
            Paired(old_line, new_line) =>
              Paired(
                old_line.rebase_index(old_line_offset),
                new_line.rebase_index(new_line_offset),
              )
            OldOnly(line) => OldOnly(line.rebase_index(old_line_offset))
            NewOnly(line) => NewOnly(line.rebase_index(new_line_offset))
          },
        )
      }
      if self is ChangeBlock(_) {
        ChangeBlock(rebased[:])
      } else {
        IgnoredBlock(rebased[:])
      }
    }
  }
}

///|
/// Return a new document whose zero-based source indexes are shifted by the
/// supplied offsets. Hunk ranges, context indexes, and changed-line indexes
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
    let blocks : Array[DiffBlock] = []
    for block in hunk.blocks {
      blocks.push(block.rebase_indexes(old_line_offset, new_line_offset))
    }
    hunks.push({
      old_start,
      old_len: hunk.old_len,
      new_start,
      new_len: hunk.new_len,
      blocks: blocks[:],
    })
  }
  { hunks: hunks[:], }
}
