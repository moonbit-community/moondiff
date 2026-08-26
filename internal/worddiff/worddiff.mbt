///|
const WORD_TOKEN_LIMIT : Int = 4_096

///|
const WORD_DIFF_CUTOFF : Int = 4_096

///|
const DEFAULT_LINE_CHARACTER_LIMIT : UInt = 16_384

///|
const DEFAULT_DOCUMENT_CHARACTER_LIMIT : UInt = 1_048_576

///|
const DEFAULT_DOCUMENT_TOKEN_LIMIT : UInt = 65_536

///|
/// A shared, monotonically-decreasing budget for optional intraline word
/// refinement. Character limits count MoonBit `String.length()` UTF-16 code
/// units. The line limit applies independently to each side; the document
/// limits combine the old and new sides of every attempted refinement.
pub struct RefinementBudget {
  line_character_limit : UInt
  remaining_characters : Ref[UInt]
  remaining_tokens : Ref[UInt]
}

///|
/// Construct a word-refinement budget. Callers normally use the defaults;
/// smaller limits are accepted so internal tests can exercise exact budget
/// boundaries without building large documents.
pub fn RefinementBudget::new(
  line_character_limit? : UInt = DEFAULT_LINE_CHARACTER_LIMIT,
  character_limit? : UInt = DEFAULT_DOCUMENT_CHARACTER_LIMIT,
  token_limit? : UInt = DEFAULT_DOCUMENT_TOKEN_LIMIT,
) -> RefinementBudget {
  {
    line_character_limit,
    remaining_characters: Ref(character_limit),
    remaining_tokens: Ref(token_limit),
  }
}

///|
// Charge both sides as one operation. No state changes unless both amounts fit.
fn charge_pair(
  remaining : Ref[UInt],
  old_units : UInt,
  new_units : UInt,
) -> Bool {
  let available = remaining.val
  if old_units > available {
    return false
  }
  let after_old = available - old_units
  if new_units > after_old {
    return false
  }
  remaining.val = after_old - new_units
  true
}

///|
fn RefinementBudget::charge_characters(
  self : RefinementBudget,
  old_length : Int,
  new_length : Int,
) -> Bool {
  charge_pair(
    self.remaining_characters,
    old_length.reinterpret_as_uint(),
    new_length.reinterpret_as_uint(),
  )
}

///|
fn RefinementBudget::line_lengths_within_limit(
  self : RefinementBudget,
  old_length : Int,
  new_length : Int,
) -> Bool {
  old_length.reinterpret_as_uint() <= self.line_character_limit &&
  new_length.reinterpret_as_uint() <= self.line_character_limit
}

///|
fn RefinementBudget::charge_tokens(
  self : RefinementBudget,
  old_count : Int,
  new_count : Int,
) -> Bool {
  charge_pair(
    self.remaining_tokens,
    old_count.reinterpret_as_uint(),
    new_count.reinterpret_as_uint(),
  )
}

///|
fn flush_token(tokens : Array[String], run : StringBuilder) -> Bool {
  if run.is_empty() {
    return true
  }
  tokens.push(run.to_string())
  run.reset()
  tokens.length() <= WORD_TOKEN_LIMIT
}

///|
/// Split one line into alternating runs of Unicode whitespace and
/// non-whitespace. Punctuation deliberately remains inside its surrounding
/// non-whitespace run.
fn tokenize_line(line : String) -> Array[String]? {
  let tokens : Array[String] = []
  let run = StringBuilder()
  let mut previous_class = -1
  for char in line {
    let current_class = if char.is_whitespace() { 1 } else { 0 }
    if previous_class >= 0 && previous_class != current_class {
      if !flush_token(tokens, run) {
        return None
      }
    }
    run.write_char(char)
    previous_class = current_class
  }
  if !flush_token(tokens, run) {
    return None
  }
  Some(tokens)
}

///|
fn push_segment(
  segments : Array[@model.DiffSegment],
  kind : @model.DiffSegmentKind,
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
  segments : Array[@model.DiffSegment],
  tokens : ArrayView[String],
  start : Int,
  end : Int,
  kind : @model.DiffSegmentKind,
) -> Unit {
  let text = StringBuilder()
  for index in start..<end {
    text.write_string(tokens[index])
  }
  push_segment(segments, kind, text.to_string())
}

///|
/// Refine one positional replacement line with a bounded Myers diff over
/// whitespace/non-whitespace runs. When supplied, `budget` is shared by every
/// attempted line in one document. Without one, a fresh default budget keeps
/// existing one-off calls compatible. `None` means a character, token, or
/// per-line bound rejected the optional refinement; callers must retain the
/// plain line representation.
pub fn refine_line(
  old : String,
  new : String,
  budget? : RefinementBudget,
) -> (Array[@model.DiffSegment], Array[@model.DiffSegment])? {
  let budget = match budget {
    Some(budget) => budget
    None => RefinementBudget::new()
  }
  let old_length = old.length()
  let new_length = new.length()
  if !budget.charge_characters(old_length, new_length) {
    return None
  }
  if !budget.line_lengths_within_limit(old_length, new_length) {
    return None
  }
  guard tokenize_line(old) is Some(old_tokens) else { return None }
  guard tokenize_line(new) is Some(new_tokens) else { return None }
  if !budget.charge_tokens(old_tokens.length(), new_tokens.length()) {
    return None
  }
  let old_segments : Array[@model.DiffSegment] = []
  let new_segments : Array[@model.DiffSegment] = []
  for
    edit in @diff.Diff(
      old=old_tokens,
      new=new_tokens,
      cutoff=WORD_DIFF_CUTOFF,
      algorithm=Myers,
    ).edits() {
    match edit {
      Equal(old_index~, new_index~, len~) => {
        push_token_range(
          old_segments,
          old_tokens,
          old_index,
          old_index + len,
          Unchanged,
        )
        push_token_range(
          new_segments,
          new_tokens,
          new_index,
          new_index + len,
          Unchanged,
        )
      }
      Delete(old_index~, old_len~, ..) =>
        push_token_range(
          old_segments,
          old_tokens,
          old_index,
          old_index + old_len,
          Changed,
        )
      Insert(new_index~, new_len~, ..) =>
        push_token_range(
          new_segments,
          new_tokens,
          new_index,
          new_index + new_len,
          Changed,
        )
    }
  }
  Some((old_segments, new_segments))
}

///|
/// Return the half-open old/new ranges of an adjacent replacement. Core diffs
/// currently emit `Delete` then `Insert`; the reverse ordering is accepted as
/// well so callers do not depend on that incidental ordering.
pub fn replacement_ranges(
  first : @diff.Edit,
  second : @diff.Edit,
) -> ((Int, Int), (Int, Int))? {
  match (first, second) {
    (
      Delete(old_index=old_start, old_len~, ..),
      Insert(new_index=new_start, new_len~, ..),
    ) =>
      Some(((old_start, old_start + old_len), (new_start, new_start + new_len)))
    (
      Insert(new_index=new_start, new_len~, ..),
      Delete(old_index=old_start, old_len~, ..),
    ) =>
      Some(((old_start, old_start + old_len), (new_start, new_start + new_len)))
    _ => None
  }
}
