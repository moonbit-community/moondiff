///|
priv enum ReviewSide {
  Left
  Right
} derive(Debug, Eq)

///|
#warnings("-unused_value")
priv struct ReviewAnchor {
  path : String
  line : Int
  side : ReviewSide
  position : Int?
} derive(Debug, Eq)

///|
priv enum CanonicalPatch {
  Commentable(Array[ReviewAnchor])
  NotCommentable
}

///|
priv struct PatchRange {
  start : Int
  count : Int
}

///|
priv struct PatchHeader {
  old : PatchRange
  new : PatchRange
}

///|
fn parse_patch_decimal(value : String) -> Int? {
  if value.is_empty() {
    return None
  }
  let mut parsed = 0
  for char in value {
    if !char.is_ascii_digit() {
      return None
    }
    let digit = char.to_int() - '0'.to_int()
    if parsed > (2_147_483_647 - digit) / 10 {
      return None
    }
    parsed = parsed * 10 + digit
  }
  Some(parsed)
}

///|
fn parse_patch_range(token : String, prefix : Char) -> PatchRange? {
  guard token.get_char(0) == Some(prefix) else { return None }
  let rest = token.view(start_offset=1).to_owned()
  let parts : Array[String] = rest
    .split(",")
    .map(StringView::to_owned)
    .collect()
  match parts {
    [start] => parse_patch_decimal(start).map(start => { start, count: 1, })
    [start, count] =>
      match (parse_patch_decimal(start), parse_patch_decimal(count)) {
        (Some(start), Some(count)) => Some({ start, count, })
        _ => None
      }
    _ => None
  }
}

///|
fn parse_patch_header(line : String) -> PatchHeader? {
  let parts : Array[String] = line
    .split(" ")
    .filter(part => !part.is_empty())
    .map(StringView::to_owned)
    .collect()
  if parts.length() < 4 || parts[0] != "@@" || parts[3] != "@@" {
    return None
  }
  match (parse_patch_range(parts[1], '-'), parse_patch_range(parts[2], '+')) {
    (Some(old), Some(new)) => Some({ old, new, })
    _ => None
  }
}

///|
fn canonical_patch_error() -> CanonicalPatch {
  NotCommentable
}

///|
fn parse_canonical_patch(path : String, patch : String?) -> CanonicalPatch {
  guard patch is Some(value) && !value.is_empty() && !value.contains("\r") else {
    return canonical_patch_error()
  }
  let lines : Array[String] = value
    .split("\n")
    .map(StringView::to_owned)
    .collect()
  let anchors : Array[ReviewAnchor] = []
  let mut index = 0
  let mut position = 0
  let mut saw_hunk = false
  let mut old_line = 0
  let mut new_line = 0
  let mut old_remaining = 0
  let mut new_remaining = 0
  let mut saw_source_line = false
  while index < lines.length() {
    let line = lines[index]
    if index == lines.length() - 1 && line.is_empty() {
      index += 1
      continue
    }
    if line.has_prefix("@@") {
      if saw_hunk && (old_remaining != 0 || new_remaining != 0) {
        return canonical_patch_error()
      }
      guard parse_patch_header(line) is Some(header) else {
        return canonical_patch_error()
      }
      if saw_hunk {
        position += 1
      }
      saw_hunk = true
      old_line = header.old.start
      new_line = header.new.start
      old_remaining = header.old.count
      new_remaining = header.new.count
      saw_source_line = false
      index += 1
      continue
    }
    if !saw_hunk {
      return canonical_patch_error()
    }
    if line == "\\ No newline at end of file" {
      if !saw_source_line {
        return canonical_patch_error()
      }
      position += 1
      index += 1
      continue
    }
    guard line.get_char(0) is Some(prefix) else {
      return canonical_patch_error()
    }
    position += 1
    saw_source_line = true
    match prefix {
      ' ' => {
        if old_remaining <= 0 || new_remaining <= 0 {
          return canonical_patch_error()
        }
        anchors.push({
          path,
          line: new_line,
          side: Right,
          position: Some(position),
        })
        old_line += 1
        new_line += 1
        old_remaining -= 1
        new_remaining -= 1
      }
      '-' => {
        if old_remaining <= 0 {
          return canonical_patch_error()
        }
        anchors.push({
          path,
          line: old_line,
          side: Left,
          position: Some(position),
        })
        old_line += 1
        old_remaining -= 1
      }
      '+' => {
        if new_remaining <= 0 {
          return canonical_patch_error()
        }
        anchors.push({
          path,
          line: new_line,
          side: Right,
          position: Some(position),
        })
        new_line += 1
        new_remaining -= 1
      }
      _ => return canonical_patch_error()
    }
    index += 1
  }
  if !saw_hunk || old_remaining != 0 || new_remaining != 0 {
    canonical_patch_error()
  } else {
    Commentable(anchors)
  }
}

///|
fn canonical_anchor(
  patch : CanonicalPatch,
  side : ReviewSide,
  line : Int,
) -> ReviewAnchor? {
  guard patch is Commentable(anchors) else { return None }
  for anchor in anchors {
    if anchor.side == side && anchor.line == line {
      return Some(anchor)
    }
  }
  None
}

///|
#warnings("-unused_value")
fn patch_is_commentable(patch : CanonicalPatch) -> Bool {
  patch is Commentable(_)
}
