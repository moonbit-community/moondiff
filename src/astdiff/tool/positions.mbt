///|UUID(0d8759b8-4c57-4578-9d9d-e6262c6ffafb)
using @syntax {type Syntax}

///|UUID(088fda98-b537-498f-8fde-63d23e0561a0)
priv enum MatchKind {
  Novel
  Unchanged(opposite_pos~ : Array[@span.SingleLineSpan])
}

///|UUID(54435d56-16ac-4c12-9185-3cb3441df57b)
priv struct MatchedPos {
  kind : MatchKind
  pos : @span.SingleLineSpan
}

///|UUID(800e3c11-f0dd-4202-8047-2c65537b4b03)
priv struct WordPart {
  text : String
  start : Int
  end_ : Int
}

///|UUID(7223d6dc-2ca6-46b2-b524-dd388be9d53f)
priv enum WordDiff {
  DeletedPart(WordPart)
  MatchedPart(self_part~ : WordPart, opposite_part~ : WordPart)
  InsertedPart(WordPart)
}

///|UUID(6a4e7b77-8452-4cfb-af4b-1d9c5169841f)
priv enum WordPartKind {
  Space
  Word
  Punct
}

///|UUID(ff5b2bac-34fa-4c10-8007-ed3e7b09a006)
fn MatchKind::is_novel(self : Self) -> Bool {
  self is Novel
}

///|UUID(75e492e5-70a3-452a-bf1c-adb398a0db09)
fn line_index(span : @span.SingleLineSpan) -> Int {
  span.line - 1
}

///|UUID(f34e40a4-d17d-485d-8d05-14d6baa98dcb)
fn is_whitespace_char(ch : Char) -> Bool {
  ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r'
}

///|UUID(c16c3f8a-c050-406d-8cc0-fac7505a9859)
fn is_word_char(ch : Char) -> Bool {
  (ch >= 'a' && ch <= 'z') ||
  (ch >= 'A' && ch <= 'Z') ||
  (ch >= '0' && ch <= '9') ||
  ch == '_'
}

///|UUID(89080742-6eb2-4a62-8caa-709dc3e53d31)
fn word_part_kind(ch : Char) -> WordPartKind {
  if is_whitespace_char(ch) {
    Space
  } else if is_word_char(ch) {
    Word
  } else {
    Punct
  }
}

///|UUID(0b201c57-7ebb-4a54-bf0c-9897814ce10f)
fn same_word_part_kind(kind : WordPartKind, ch : Char) -> Bool {
  match kind {
    Space => is_whitespace_char(ch)
    Word => is_word_char(ch)
    Punct => false
  }
}

///|UUID(23e682f0-8377-4384-a224-591ddab3bada)
fn string_slice(chars : ArrayView[Char], start : Int, end_ : Int) -> String {
  String::from_array(chars[start:end_].to_array())
}

///|UUID(45eeaf7c-0d40-4941-8f67-33a67f5ed403)
fn split_word_parts(content : String) -> Array[WordPart] {
  let chars = content.to_array()
  if chars.is_empty() {
    return []
  }
  let parts = Array::new()
  let mut start = 0
  let mut kind = word_part_kind(chars[0])
  let mut i = 1
  while i < chars.length() {
    if same_word_part_kind(kind, chars[i]) {
      i += 1
      continue
    }
    parts.push(WordPart::{ text: string_slice(chars, start, i), start, end_: i })
    start = i
    kind = word_part_kind(chars[i])
    i += 1
  }
  parts.push(WordPart::{
    text: string_slice(chars, start, chars.length()),
    start,
    end_: chars.length(),
  })
  parts
}

///|UUID(922e5dfd-d764-4b59-b9cf-44d82348922b)
fn split_content_lines(content : String) -> Array[String] {
  let lines = Array::new()
  for line in content.split("\n") {
    lines.push(line.to_string())
  } nobreak {
    lines
  }
}

///|UUID(0c244b2b-aaee-44ee-a6ed-4221fa07f7b8)
fn relative_region_positions(
  content : String,
  positions : ArrayView[@span.SingleLineSpan],
  first_line_padding : Int,
  start : Int,
  end_ : Int,
) -> Array[@span.SingleLineSpan] {
  if start >= end_ {
    return []
  }
  let content_lines = split_content_lines(content)
  if content_lines.length() != positions.length() {
    return []
  }

  let spans = Array::new()
  let mut line_start = 0
  for i in 0..<content_lines.length() {
    let line_text = content_lines[i]
    let line_end = line_start + line_text.length()
    let overlap_start = @cmp.maximum(start, line_start)
    let overlap_end = @cmp.minimum(end_, line_end)
    if overlap_start < overlap_end {
      let base = positions[i]
      let padding = if i == 0 { first_line_padding } else { 0 }
      spans.push(@span.SingleLineSpan::{
        line: base.line,
        start_col: base.start_col + padding + (overlap_start - line_start),
        end_col: base.start_col + padding + (overlap_end - line_start),
      })
    }
    line_start = line_end + 1
  }
  spans
}

///|UUID(e6ad8aa3-0196-4422-aef1-d9b99d90c3a3)
fn token_display_width(positions : ArrayView[@span.SingleLineSpan]) -> Int {
  let width = Ref::new(0)
  for span in positions {
    width.val += span.end_col - span.start_col
  }
  width.val
}

///|UUID(ba5ffe30-8b0a-445a-9153-182546f8a9c2)
fn first_line_padding_for_content(
  node : Syntax,
  positions : ArrayView[@span.SingleLineSpan],
  content : String,
) -> Int {
  if positions.length() != 1 {
    return 0
  }
  let extra = token_display_width(positions) - content.length()
  match node {
    Syntax::Atom(
      kind=@syntax.AtomKind::String(@syntax.StringKind::StringLiteral),
      ..
    ) => if extra >= 2 { 1 } else { 0 }
    Syntax::Atom(kind=@syntax.AtomKind::Comment, ..) =>
      if extra > 0 {
        extra
      } else {
        0
      }
    _ => 0
  }
}

///|UUID(041e65f4-37ee-4a5a-b3cc-93ab908258f7)
fn whole_novel_positions(
  positions : ArrayView[@span.SingleLineSpan],
) -> Array[MatchedPos] {
  let matched = Array::new(capacity=positions.length())
  for span in positions {
    if positions.length() == 1 && span.start_col == span.end_col {
      continue
    }
    matched.push(MatchedPos::{ kind: Novel, pos: span })
  }
  matched
}

///|UUID(24eaed4e-bc15-4fbc-acd3-51c988e19d64)
fn unchanged_positions(
  positions : ArrayView[@span.SingleLineSpan],
  opposite_pos : ArrayView[@span.SingleLineSpan],
) -> Array[MatchedPos] {
  let limit = if positions.length() < opposite_pos.length() {
    positions.length()
  } else {
    opposite_pos.length()
  }
  let matched = Array::new(capacity=limit)
  let opposite = opposite_pos.to_array()
  for i in 0..<limit {
    let span = positions[i]
    if limit == 1 && span.start_col == span.end_col {
      continue
    }
    matched.push(MatchedPos::{
      kind: Unchanged(opposite_pos=opposite),
      pos: span,
    })
  }
  matched
}

///|UUID(79861160-2761-4471-adea-6797a161d108)
fn is_all_whitespace_text(text : String) -> Bool {
  for ch in text.to_array() {
    if !is_whitespace_char(ch) {
      return false
    }
  } nobreak {
    true
  }
}

///|UUID(1020e47f-950a-4f0b-8447-3f899f416b20)
fn word_diffs(
  lhs_parts : ArrayView[WordPart],
  rhs_parts : ArrayView[WordPart],
) -> Array[WordDiff] {
  let width = rhs_parts.length() + 1
  let dp = Array::make((lhs_parts.length() + 1) * width, 0)
  let index = fn(i : Int, j : Int) { i * width + j }

  let mut i = lhs_parts.length() - 1
  while i >= 0 {
    let mut j = rhs_parts.length() - 1
    while j >= 0 {
      dp[index(i, j)] = if lhs_parts[i].text == rhs_parts[j].text {
        dp[index(i + 1, j + 1)] + 1
      } else {
        @cmp.maximum(dp[index(i + 1, j)], dp[index(i, j + 1)])
      }
      j -= 1
    }
    i -= 1
  }

  let diffs = Array::new()
  let lhs_i = Ref::new(0)
  let rhs_i = Ref::new(0)
  while lhs_i.val < lhs_parts.length() && rhs_i.val < rhs_parts.length() {
    let lhs_part = lhs_parts[lhs_i.val]
    let rhs_part = rhs_parts[rhs_i.val]
    if lhs_part.text == rhs_part.text {
      diffs.push(MatchedPart(self_part=lhs_part, opposite_part=rhs_part))
      lhs_i.val += 1
      rhs_i.val += 1
    } else if dp[index(lhs_i.val + 1, rhs_i.val)] >=
      dp[index(lhs_i.val, rhs_i.val + 1)] {
      diffs.push(DeletedPart(lhs_part))
      lhs_i.val += 1
    } else {
      diffs.push(InsertedPart(rhs_part))
      rhs_i.val += 1
    }
  }
  while lhs_i.val < lhs_parts.length() {
    diffs.push(DeletedPart(lhs_parts[lhs_i.val]))
    lhs_i.val += 1
  }
  while rhs_i.val < rhs_parts.length() {
    diffs.push(InsertedPart(rhs_parts[rhs_i.val]))
    rhs_i.val += 1
  }
  diffs
}

///|UUID(7d30871c-c26e-4f07-bbc9-87e8b24959b7)
fn has_common_words(diffs : ArrayView[WordDiff]) -> Bool {
  let unchanged_count = Ref::new(0)
  let novel_count = Ref::new(0)
  for diff in diffs {
    match diff {
      MatchedPart(self_part~, ..) =>
        if !is_all_whitespace_text(self_part.text) {
          unchanged_count.val += 1
        }
      DeletedPart(part) | InsertedPart(part) =>
        if !is_all_whitespace_text(part.text) {
          novel_count.val += 1
        }
    }
  }
  unchanged_count.val > 1 && unchanged_count.val * 2 >= novel_count.val
}

///|UUID(ae703ce3-9408-43ab-8e5c-65c6f4d49510)
fn split_replaced_atom_positions(
  change : @diff.ChangeKind,
  positions : ArrayView[@span.SingleLineSpan],
) -> Array[MatchedPos] {
  let (self_node, opposite_node) = match change {
    @diff.ChangeKind::ReplacedComment(lhs~, rhs~) => (lhs, rhs)
    @diff.ChangeKind::ReplacedString(lhs~, rhs~) => (lhs, rhs)
    _ => panic()
  }

  let (self_content, self_pos) = match self_node {
    Syntax::Atom(content~, position~, ..) =>
      (content, filter_empty_ends(position))
    _ => return whole_novel_positions(positions)
  }
  let (opposite_content, opposite_pos) = match opposite_node {
    Syntax::Atom(content~, position~, ..) =>
      (content, filter_empty_ends(position))
    _ => return whole_novel_positions(positions)
  }
  if self_pos.length() == 0 || opposite_pos.length() == 0 {
    return whole_novel_positions(positions)
  }
  let self_padding = first_line_padding_for_content(
    self_node, self_pos, self_content,
  )
  let opposite_padding = first_line_padding_for_content(
    opposite_node, opposite_pos, opposite_content,
  )

  let self_parts = split_word_parts(self_content)
  let opposite_parts = split_word_parts(opposite_content)
  if self_parts.is_empty() || opposite_parts.is_empty() {
    return whole_novel_positions(positions)
  }

  let diffs = word_diffs(self_parts, opposite_parts)
  if !has_common_words(diffs) {
    return whole_novel_positions(positions)
  }

  let matched = Array::new()
  for diff in diffs {
    match diff {
      DeletedPart(part) => {
        if is_all_whitespace_text(part.text) {
          continue
        }
        let spans = relative_region_positions(
          self_content,
          self_pos,
          self_padding,
          part.start,
          part.end_,
        )
        if spans.is_empty() {
          return whole_novel_positions(positions)
        }
        matched.push_iter(whole_novel_positions(spans).iter())
      }
      InsertedPart(_) => ()
      MatchedPart(self_part~, opposite_part~) => {
        let self_spans = relative_region_positions(
          self_content,
          self_pos,
          self_padding,
          self_part.start,
          self_part.end_,
        )
        let opposite_spans = relative_region_positions(
          opposite_content,
          opposite_pos,
          opposite_padding,
          opposite_part.start,
          opposite_part.end_,
        )
        if self_spans.is_empty() || opposite_spans.is_empty() {
          return whole_novel_positions(positions)
        }
        matched.push_iter(
          unchanged_positions(self_spans, opposite_spans).iter(),
        )
      }
    }
  }
  if matched.is_empty() {
    whole_novel_positions(positions)
  } else {
    matched
  }
}

///|UUID(89a5c9d2-9f3d-4dd4-af71-cf95af4a8d5b)
fn filter_empty_ends(
  positions : ArrayView[@span.SingleLineSpan],
) -> Array[@span.SingleLineSpan] {
  let filtered = Array::new(capacity=positions.length())
  for i in 0..<positions.length() {
    let span = positions[i]
    if (i == 0 || i == positions.length() - 1) && span.start_col == span.end_col {
      continue
    }
    filtered.push(span)
  }
  filtered
}

///|UUID(0ec2b85f-3d8b-4b49-b522-612388afcf2e)
fn opposite_positions_for(
  change : @diff.ChangeKind,
  is_close_delim : Bool,
) -> Array[@span.SingleLineSpan] {
  match change {
    @diff.ChangeKind::Unchanged(opposite) =>
      match opposite {
        Syntax::Atom(position~, ..) => filter_empty_ends(position)
        Syntax::List(open_position~, close_position~, ..) =>
          if is_close_delim {
            filter_empty_ends(close_position)
          } else {
            filter_empty_ends(open_position)
          }
      }
    _ => []
  }
}

///|UUID(90c893dc-5add-480c-a20e-c92b10cfcd20)
fn matched_positions_for(
  change : @diff.ChangeKind,
  positions : ArrayView[@span.SingleLineSpan],
  is_close_delim : Bool,
) -> Array[MatchedPos] {
  let positions = filter_empty_ends(positions)
  match change {
    @diff.ChangeKind::Novel => whole_novel_positions(positions)
    @diff.ChangeKind::ReplacedComment(..)
    | @diff.ChangeKind::ReplacedString(..) =>
      split_replaced_atom_positions(change, positions)
    @diff.ChangeKind::Unchanged(_) => {
      let opposite_pos = opposite_positions_for(change, is_close_delim)
      unchanged_positions(positions, opposite_pos)
    }
  }
}

///|UUID(b48e6514-1f58-46da-a6cb-783370a7f41c)
fn change_positions(
  nodes : ArrayView[Syntax],
  change_map : @diff.ChangeMap,
) -> Array[MatchedPos] {
  let positions = Array::new()
  fn walk(node : Syntax) -> Unit {
    let change = change_map.get(node).unwrap_or_else(() => panic())
    match node {
      Syntax::Atom(position~, ..) =>
        positions.push_iter(
          matched_positions_for(change, position, false).iter(),
        )
      Syntax::List(open_position~, children~, close_position~, ..) => {
        positions.push_iter(
          matched_positions_for(change, open_position, false).iter(),
        )
        for child in children {
          walk(child)
        }
        positions.push_iter(
          matched_positions_for(change, close_position, true).iter(),
        )
      }
    }
  }
  for node in nodes {
    walk(node)
  } nobreak {
    positions
  }
}
