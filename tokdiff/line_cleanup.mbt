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

// Optional line-level semantic cleanup. The original patience equalities are
// converted to unique internal anchors; selected low-information equalities
// are reopened inside bounded windows and exact pairs found by the weighted
// aligner are promoted back to unique anchors. A final patience diff can then
// group/hunk the intended script without accidentally matching duplicate text.

///|
priv struct ComparableLine {
  text : String
  key : (Int, Int)
} derive(Eq, Hash)

///|
fn original_diff_lines(lines : ArrayView[String]) -> Array[ComparableLine] {
  let out : Array[ComparableLine] = []
  for text in lines {
    out.push({ text, key: (0, 0) })
  }
  out
}

///|
fn repeated_near(lines : ArrayView[String], index : Int, text : String) -> Bool {
  let start = if index > 32 { index - 32 } else { 0 }
  let end = if index + 33 < lines.length() {
    index + 33
  } else {
    lines.length()
  }
  for i in start..<end {
    if i != index && lines[i] == text {
      return true
    }
  }
  false
}

///|
/// Blank/comment-filler lines are always low-information. Other boilerplate
/// must contain no identifier/literal/structural marker, carry at most 13
/// units of token mass, and repeat nearby on both sides of the diff.
fn is_soft_line(
  old : ArrayView[String],
  new : ArrayView[String],
  old_index : Int,
  new_index : Int,
) -> Bool {
  let text = old[old_index]
  let toks = tokenize_line(text)
  let mut filler_only = true
  let mut significant = false
  let mut quality = 0
  for tok in toks {
    quality += alignment_weight(tok)
    match tok.kind {
      Space | Filler => ()
      _ => filler_only = false
    }
    if tok.kind is (Word | Str | Marker) {
      significant = true
    }
  }
  filler_only ||
  (
    !significant &&
    quality <= 13 &&
    repeated_near(old, old_index, text) &&
    repeated_near(new, new_index, text)
  )
}

///|
fn is_equal_edit(edit : @diff.Edit) -> Bool {
  edit is Equal(..)
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
fn soft_equal_edits(
  edits : ArrayView[@diff.Edit],
  old : ArrayView[String],
  new : ArrayView[String],
) -> Array[Bool] {
  let soft = Array::make(edits.length(), false)
  for i in 1..<(edits.length() - 1) {
    guard edits[i] is Equal(old_index~, new_index~, len~) else { continue }
    if len > 8 || is_equal_edit(edits[i - 1]) || is_equal_edit(edits[i + 1]) {
      continue
    }
    let mut eligible = true
    for offset in 0..<len {
      if !is_soft_line(old, new, old_index + offset, new_index + offset) {
        eligible = false
        break
      }
    }
    soft[i] = eligible
  }
  soft
}

///|
fn cleaned_diff_lines(
  old : ArrayView[String],
  new : ArrayView[String],
) -> (Array[ComparableLine], Array[ComparableLine]) {
  let old_lines : Array[ComparableLine] = []
  for i, text in old {
    old_lines.push({ text, key: (0, i) })
  }
  let new_lines : Array[ComparableLine] = []
  for i, text in new {
    new_lines.push({ text, key: (1, i) })
  }
  let raw = @diff.Diff(old~, new~, algorithm=Patience)
  let edits = raw.edits()
  let soft = soft_equal_edits(edits, old, new)
  let mut next_anchor = 0
  for edit in edits {
    match edit {
      Equal(old_index~, new_index~, len~) =>
        for offset in 0..<len {
          let key = (2, next_anchor)
          old_lines[old_index + offset] = { text: old[old_index + offset], key }
          new_lines[new_index + offset] = { text: new[new_index + offset], key }
          next_anchor += 1
        }
      _ => ()
    }
  }

  let mut covered_through = -1
  for i in 0..<edits.length() {
    if i <= covered_through || !soft[i] {
      continue
    }
    let mut first = i
    while first > 0 && (!is_equal_edit(edits[first - 1]) || soft[first - 1]) {
      first -= 1
    }
    let mut last = i
    while last + 1 < edits.length() &&
          (!is_equal_edit(edits[last + 1]) || soft[last + 1]) {
      last += 1
    }
    covered_through = last
    let (old_start, new_start, _, _) = edit_bounds(edits[first])
    let (_, _, old_end, new_end) = edit_bounds(edits[last])
    if alignment_tokens(
        old.view(start=old_start, end=old_end),
        new.view(start=new_start, end=new_end),
        line => line,
      )
      is Some(tokens) {
      for old_index in old_start..<old_end {
        old_lines[old_index] = { text: old[old_index], key: (0, old_index) }
      }
      for new_index in new_start..<new_end {
        new_lines[new_index] = { text: new[new_index], key: (1, new_index) }
      }
      for pair in align(tokens.olds, tokens.news) {
        match pair {
          (Some(old_offset), Some(new_offset)) => {
            let old_index = old_start + old_offset
            let new_index = new_start + new_offset
            if old[old_index] == new[new_index] {
              let key = (2, next_anchor)
              old_lines[old_index] = { text: old[old_index], key }
              new_lines[new_index] = { text: new[new_index], key }
              next_anchor += 1
            }
          }
          _ => ()
        }
      }
    }
  }
  (old_lines, new_lines)
}

///|
fn rendering_diff(
  old : ArrayView[String],
  new : ArrayView[String],
  line_cleanup : Bool,
) -> @diff.Diff[ComparableLine] {
  if line_cleanup {
    let (old_lines, new_lines) = cleaned_diff_lines(old, new)
    Diff(old=old_lines, new=new_lines, algorithm=Patience)
  } else {
    Diff(old=original_diff_lines(old), new=original_diff_lines(new))
  }
}
