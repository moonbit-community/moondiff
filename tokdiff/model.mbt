// Copyright 2026 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

///|
/// Whether one source segment is unchanged or belongs to an intraline change.
/// Renderers decide how to present `Changed`; the calculation layer never
/// assigns markup, colors, or terminal styles.
pub(all) enum DiffSegmentKind {
  Unchanged
  Changed
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
pub(all) struct DiffLine {
  index : Int
  segments : Array[DiffSegment]
} derive(Eq)

///|
/// Reconstruct the exact source text of this line.
pub fn DiffLine::text(self : DiffLine) -> String {
  let buf = StringBuilder::new()
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
  ContextBlock(Array[ContextLine])
  ChangeBlock(Array[DiffRow])
} derive(Eq)

///|
/// One grouped diff hunk. Starts are zero-based cursors and lengths are source
/// line counts. `header` preserves the canonical core-diff range spelling.
pub(all) struct DiffHunk {
  header : String
  old_start : Int
  old_len : Int
  new_start : Int
  new_len : Int
  blocks : Array[DiffBlock]
} derive(Eq)

///|
/// A fully calculated, renderer-neutral diff document.
pub(all) struct DiffDocument {
  hunks : Array[DiffHunk]
} derive(Eq)

///|
fn push_diff_segment(
  segments : Array[DiffSegment],
  kind : DiffSegmentKind,
  text : String,
) -> Unit {
  if text == "" {
    return
  }
  let last = segments.length() - 1
  if last >= 0 && segments[last].kind == kind {
    let previous = segments[last]
    segments[last] = { kind, text: previous.text + text }
  } else {
    segments.push({ kind, text })
  }
}

///|
fn push_token_range(
  segments : Array[DiffSegment],
  tokens : ArrayView[Tok],
  start : Int,
  end : Int,
  kind : DiffSegmentKind,
) -> Unit {
  let buf = StringBuilder::new()
  for index in start..<end {
    buf <+ "\{tokens[index].text}"
  }
  push_diff_segment(segments, kind, buf.to_string())
}

///|
fn diff_token_text_is_whitespace(token : Tok) -> Bool {
  if token.text == "" {
    return false
  }
  for char in token.text {
    if !char.is_whitespace() {
      return false
    }
  }
  true
}

///|
/// Append one changed token run while leaving leading and trailing whitespace
/// unchanged. Internal whitespace remains part of the changed segment.
fn flush_changed_tokens(
  segments : Array[DiffSegment],
  run : Array[Tok],
) -> Unit {
  let mut semantic_start = 0
  while semantic_start < run.length() &&
        diff_token_text_is_whitespace(run[semantic_start]) {
    semantic_start += 1
  }
  if semantic_start == run.length() {
    push_token_range(segments, run, 0, run.length(), Unchanged)
  } else {
    let mut semantic_end = run.length()
    while semantic_end > semantic_start &&
          diff_token_text_is_whitespace(run[semantic_end - 1]) {
      semantic_end -= 1
    }
    push_token_range(segments, run, 0, semantic_start, Unchanged)
    push_token_range(segments, run, semantic_start, semantic_end, Changed)
    push_token_range(segments, run, semantic_end, run.length(), Unchanged)
  }
  run.clear()
}

///|
fn plain_segments(text : String) -> Array[DiffSegment] {
  if text == "" {
    []
  } else {
    [{ kind: Unchanged, text }]
  }
}

///|
fn full_line_segments(tokens : ArrayView[Tok]) -> Array[DiffSegment] {
  let segments : Array[DiffSegment] = []
  let run = tokens.to_owned()
  flush_changed_tokens(segments, run)
  segments
}

///|
fn pair_row_segments(
  ops : ArrayView[Op],
) -> (Array[DiffSegment], Array[DiffSegment]) {
  let old_segments : Array[DiffSegment] = []
  let new_segments : Array[DiffSegment] = []
  let old_run : Array[Tok] = []
  let new_run : Array[Tok] = []
  for op in ops {
    match op {
      OEq(token) => {
        flush_changed_tokens(old_segments, old_run)
        flush_changed_tokens(new_segments, new_run)
        push_diff_segment(old_segments, Unchanged, token.text)
        push_diff_segment(new_segments, Unchanged, token.text)
      }
      OSub(old_token, new_token) => {
        old_run.push(old_token)
        new_run.push(new_token)
      }
      ODel(token) => old_run.push(token)
      OIns(token) => new_run.push(token)
    }
  }
  flush_changed_tokens(old_segments, old_run)
  flush_changed_tokens(new_segments, new_run)
  (old_segments, new_segments)
}

///|
fn projected_line_segments(
  tokens : ArrayView[Tok],
  changed : ArrayView[Bool],
) -> Array[DiffSegment] {
  let segments : Array[DiffSegment] = []
  let run : Array[Tok] = []
  for index, token in tokens {
    if changed[index] {
      run.push(token)
    } else if token.kind is Space && run.length() > 0 {
      let mut next = index + 1
      while next < tokens.length() && tokens[next].kind is Space {
        next += 1
      }
      if next < tokens.length() && changed[next] {
        run.push(token)
      } else {
        flush_changed_tokens(segments, run)
        push_diff_segment(segments, Unchanged, token.text)
      }
    } else {
      flush_changed_tokens(segments, run)
      push_diff_segment(segments, Unchanged, token.text)
    }
  }
  flush_changed_tokens(segments, run)
  segments
}

///|
fn make_diff_line(index : Int, segments : Array[DiffSegment]) -> DiffLine {
  { index, segments }
}

///|
fn make_plain_diff_line(index : Int, text : String) -> DiffLine {
  { index, segments: plain_segments(text) }
}

///|
/// Calculate semantic row pairing and intraline segments for one replacement
/// block. This is the renderer-neutral counterpart of the former HTML
/// `prepare_replacement` helper.
fn semantic_change_rows(
  old_lines : ArrayView[ComparableLine],
  new_lines : ArrayView[ComparableLine],
  old_start : Int,
  new_start : Int,
) -> Array[DiffRow] {
  let rows : Array[DiffRow] = []
  if alignment_tokens(old_lines, new_lines, line => line.text) is Some(tokens) {
    let changes = window_changes(tokens.olds, tokens.news)
    for pair in align(tokens.olds, tokens.news) {
      match pair {
        (Some(old_index), Some(new_index)) => {
          let (old_segments, new_segments) = if changes is Some(window) {
            (
              projected_line_segments(
                tokens.olds[old_index],
                window.old_changed[old_index],
              ),
              projected_line_segments(
                tokens.news[new_index],
                window.new_changed[new_index],
              ),
            )
          } else if !traceback_cells_within_limit(
              tokens.olds[old_index].length(),
              tokens.news[new_index].length(),
            ) {
            (
              plain_segments(old_lines[old_index].text),
              plain_segments(new_lines[new_index].text),
            )
          } else {
            pair_row_segments(
              pair_ops(tokens.olds[old_index], tokens.news[new_index]),
            )
          }
          rows.push(
            Paired(
              make_diff_line(old_start + old_index, old_segments),
              make_diff_line(new_start + new_index, new_segments),
            ),
          )
        }
        (Some(old_index), None) => {
          let segments = if changes is Some(window) {
            projected_line_segments(
              tokens.olds[old_index],
              window.old_changed[old_index],
            )
          } else {
            full_line_segments(tokens.olds[old_index])
          }
          rows.push(OldOnly(make_diff_line(old_start + old_index, segments)))
        }
        (None, Some(new_index)) => {
          let segments = if changes is Some(window) {
            projected_line_segments(
              tokens.news[new_index],
              window.new_changed[new_index],
            )
          } else {
            full_line_segments(tokens.news[new_index])
          }
          rows.push(NewOnly(make_diff_line(new_start + new_index, segments)))
        }
        (None, None) => ()
      }
    }
  } else {
    for offset, line in old_lines {
      rows.push(OldOnly(make_plain_diff_line(old_start + offset, line.text)))
    }
    for offset, line in new_lines {
      rows.push(NewOnly(make_plain_diff_line(new_start + offset, line.text)))
    }
  }
  rows
}

///|
fn plain_change_rows(
  old_lines : ArrayView[String],
  new_lines : ArrayView[String],
  old_start : Int,
  new_start : Int,
) -> Array[DiffRow] {
  let rows : Array[DiffRow] = []
  let row_count = if old_lines.length() > new_lines.length() {
    old_lines.length()
  } else {
    new_lines.length()
  }
  for offset in 0..<row_count {
    match (old_lines.get(offset), new_lines.get(offset)) {
      (Some(old_line), Some(new_line)) =>
        rows.push(
          Paired(
            make_plain_diff_line(old_start + offset, old_line),
            make_plain_diff_line(new_start + offset, new_line),
          ),
        )
      (Some(old_line), None) =>
        rows.push(OldOnly(make_plain_diff_line(old_start + offset, old_line)))
      (None, Some(new_line)) =>
        rows.push(NewOnly(make_plain_diff_line(new_start + offset, new_line)))
      (None, None) => ()
    }
  }
  rows
}

///|
fn hunk_range(edits : ArrayView[@diff.Edit]) -> (Int, Int, Int, Int) {
  let (old_start, new_start, _, _) = edit_bounds(edits[0])
  let (_, _, old_end, new_end) = edit_bounds(edits[edits.length() - 1])
  (old_start, old_end - old_start, new_start, new_end - new_start)
}

///|
fn semantic_hunk(hunk : @diff.Hunk[ComparableLine]) -> DiffHunk {
  let blocks : Array[DiffBlock] = []
  let edits = hunk.edits()
  let old_view = hunk.old_view()
  let new_view = hunk.new_view()
  let mut index = 0
  while index < edits.length() {
    match edits[index] {
      Delete(old_index~, old_len~, ..) if index + 1 < edits.length() &&
        edits[index + 1] is Insert(..) => {
        guard! edits[index + 1] is Insert(new_index~, new_len~, ..)
        blocks.push(
          ChangeBlock(
            semantic_change_rows(
              old_view.view(start=old_index, end=old_index + old_len),
              new_view.view(start=new_index, end=new_index + new_len),
              old_index,
              new_index,
            ),
          ),
        )
        index += 2
      }
      Equal(old_index~, new_index~, len~) => {
        let lines : Array[ContextLine] = []
        for offset in 0..<len {
          lines.push({
            old_index: old_index + offset,
            new_index: new_index + offset,
            text: old_view[old_index + offset].text,
          })
        }
        blocks.push(ContextBlock(lines))
        index += 1
      }
      Delete(old_index~, old_len~, ..) => {
        let rows : Array[DiffRow] = []
        for offset in 0..<old_len {
          let line = old_view[old_index + offset]
          rows.push(
            OldOnly(make_plain_diff_line(old_index + offset, line.text)),
          )
        }
        blocks.push(ChangeBlock(rows))
        index += 1
      }
      Insert(new_index~, new_len~, ..) => {
        let rows : Array[DiffRow] = []
        for offset in 0..<new_len {
          let line = new_view[new_index + offset]
          rows.push(
            NewOnly(make_plain_diff_line(new_index + offset, line.text)),
          )
        }
        blocks.push(ChangeBlock(rows))
        index += 1
      }
    }
  }
  let (old_start, old_len, new_start, new_len) = hunk_range(edits)
  { header: hunk.header(), old_start, old_len, new_start, new_len, blocks }
}

///|
fn plain_hunk(hunk : @diff.Hunk[String]) -> DiffHunk {
  let blocks : Array[DiffBlock] = []
  let edits = hunk.edits()
  let old_view = hunk.old_view()
  let new_view = hunk.new_view()
  let mut index = 0
  while index < edits.length() {
    match edits[index] {
      Delete(old_index~, old_len~, ..) if index + 1 < edits.length() &&
        edits[index + 1] is Insert(..) => {
        guard! edits[index + 1] is Insert(new_index~, new_len~, ..)
        blocks.push(
          ChangeBlock(
            plain_change_rows(
              old_view.view(start=old_index, end=old_index + old_len),
              new_view.view(start=new_index, end=new_index + new_len),
              old_index,
              new_index,
            ),
          ),
        )
        index += 2
      }
      Equal(old_index~, new_index~, len~) => {
        let lines : Array[ContextLine] = []
        for offset in 0..<len {
          lines.push({
            old_index: old_index + offset,
            new_index: new_index + offset,
            text: old_view[old_index + offset],
          })
        }
        blocks.push(ContextBlock(lines))
        index += 1
      }
      Delete(old_index~, old_len~, ..) => {
        let rows : Array[DiffRow] = []
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
        blocks.push(ChangeBlock(rows))
        index += 1
      }
      Insert(new_index~, new_len~, ..) => {
        let rows : Array[DiffRow] = []
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
        blocks.push(ChangeBlock(rows))
        index += 1
      }
    }
  }
  let (old_start, old_len, new_start, new_len) = hunk_range(edits)
  { header: hunk.header(), old_start, old_len, new_start, new_len, blocks }
}

///|
/// Calculate a MoonBit-aware diff and all renderer-neutral intraline changes.
pub fn diff(
  old~ : ArrayView[String],
  new~ : ArrayView[String],
  context? : Int = 3,
  line_cleanup? : Bool = false,
) -> DiffDocument {
  let hunks : Array[DiffHunk] = []
  for hunk in rendering_diff(old, new, line_cleanup).group(context~) {
    hunks.push(semantic_hunk(hunk))
  }
  { hunks, }
}

///|
/// Calculate a plain Patience line diff without lexing, semantic cleanup, or
/// intraline changes.
pub fn line_diff(
  old~ : ArrayView[String],
  new~ : ArrayView[String],
  context? : Int = 3,
) -> DiffDocument {
  let hunks : Array[DiffHunk] = []
  for hunk in @diff.Diff(old~, new~, algorithm=Patience).group(context~) {
    hunks.push(plain_hunk(hunk))
  }
  { hunks, }
}
