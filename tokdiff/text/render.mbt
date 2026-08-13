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
fn append_diff_line(
  buf : StringBuilder,
  prefix : String,
  line : @tokdiff.DiffLine,
) -> Unit {
  buf <+ "\{prefix}"
  for segment in line.segments {
    buf <+ "\{segment.text}"
  }
  buf <+ "\n"
}

///|
fn render_hunk(hunk : @tokdiff.DiffHunk) -> String {
  let buf = StringBuilder::new()
  buf <+ "\{hunk.header}\n"
  for block in hunk.blocks {
    match block {
      ContextBlock(lines) =>
        for line in lines {
          buf <+ " \{line.text}\n"
        }
      ChangeBlock(rows) => {
        for row in rows {
          match row {
            Paired(old_line, _) | OldOnly(old_line) =>
              append_diff_line(buf, "-", old_line)
            NewOnly(_) => ()
          }
        }
        for row in rows {
          match row {
            Paired(_, new_line) | NewOnly(new_line) =>
              append_diff_line(buf, "+", new_line)
            OldOnly(_) => ()
          }
        }
      }
    }
  }
  buf.to_string()
}

///|
/// Render every hunk in a calculated diff as unified patch text.
pub fn render_unified_hunks(document : @tokdiff.DiffDocument) -> Array[String] {
  document.hunks.map(render_hunk)
}

///|
/// Return unified patch hunks for a MoonBit-aware diff.
pub fn unified_hunks(
  old~ : ArrayView[String],
  new~ : ArrayView[String],
  context? : Int = 3,
  line_cleanup? : Bool = false,
) -> Array[String] {
  render_unified_hunks(@tokdiff.diff(old~, new~, context~, line_cleanup~))
}

///|
/// Return unified patch hunks for a plain Patience line diff.
pub fn unified_line_hunks(
  old~ : ArrayView[String],
  new~ : ArrayView[String],
  context? : Int = 3,
) -> Array[String] {
  render_unified_hunks(@tokdiff.line_diff(old~, new~, context~))
}
