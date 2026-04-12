///|UUID(b246f889-c80e-4e31-9127-e22ba3446d93)
pub struct ElabCtx {
  line_widths : LineWidths
  contents : Array[Char]
  line_ranges : Array[(Int, Int)]
}

///|UUID(9c2965f9-2f2a-4a51-b1f8-3a8fc7d4ce52)
priv struct Part {
  syntax : Syntax
  loc : Location?
}

///|UUID(2e432a90-4561-4e52-a159-bf31a83a3af6)
pub fn ElabCtx::new(source : StringView) -> Self {
  let contents = source.to_array()
  let line_ranges = Array::new()
  line_ranges.push((0, 0))
  let mut current_line_start = 0
  let mut current_column = 0
  for contents_view = contents[:] {
    match contents_view {
      [] => {
        line_ranges.push(
          (current_line_start, current_line_start + current_column),
        )
        break ElabCtx::{
          line_widths: LineWidths::from_str(source),
          contents,
          line_ranges,
        }
      }
      ['\r', '\n', .. rest] => {
        line_ranges.push(
          (current_line_start, current_line_start + current_column),
        )
        current_line_start = current_line_start + current_column + 2
        current_column = 0
        continue rest
      }
      ['\n' | '\r', .. rest] => {
        line_ranges.push(
          (current_line_start, current_line_start + current_column),
        )
        current_line_start = current_line_start + current_column + 1
        current_column = 0
        continue rest
      }
      [_, .. rest] => {
        current_column += 1
        continue rest
      }
    }
  }
}

///|UUID(73d90188-c384-4471-ab1c-29d64a14c96e)
pub fn elab_impl(source : StringView, impl_ : Impl) -> Syntax {
  ElabCtx::new(source).elab_impl(impl_)
}

///|UUID(6314eb41-c876-4775-9aa9-59b787ae6622)
pub fn elab_expr(source : StringView, expr : Expr) -> Syntax {
  ElabCtx::new(source).elab_expr(expr)
}

///|UUID(35a842d1-ad6b-4cab-8252-795416588b31)
pub fn elab_type(source : StringView, ty : Type) -> Syntax {
  ElabCtx::new(source).elab_type(ty)
}

///|UUID(72f6b63d-2830-4103-b954-d573cf0c5424)
pub fn elab_pattern(source : StringView, pat : Pattern) -> Syntax {
  ElabCtx::new(source).elab_pattern(pat)
}

///|UUID(2d57b58f-0d79-4b88-8ccf-419e37117c7e)
fn ElabCtx::spans(self : Self, loc : Location) -> Array[SingleLineSpan] {
  self.line_widths.loc_to_spans(loc)
}

///|UUID(6d773fe6-9a1b-4f4a-b912-00c7d75927b7)
fn ElabCtx::slice(self : Self, loc : Location) -> String {
  String::from_array(self.line_widths.text_of_loc(loc.start, loc.end))
}

///|UUID(9780c298-38b2-49e6-9712-430ea3be7b0f)
fn ElabCtx::slice_cnums(
  self : Self,
  start_cnum : Int,
  end_cnum : Int,
) -> String {
  String::from_array(self.contents[start_cnum:end_cnum].to_array())
}

///|UUID(a9766739-6a47-4934-b948-4c4340f9a3e3)
fn ElabCtx::find_line(self : Self, cnum : Int) -> Int {
  let mut low = 1
  let mut high = self.line_ranges.length() - 1
  let eof_line = high
  while low <= high {
    let mid = low + (high - low) / 2
    let (start, end_) = self.line_ranges[mid]
    if cnum < start {
      high = mid - 1
      continue
    }
    if cnum > end_ {
      low = mid + 1
      continue
    }
    return mid
  }
  eof_line
}

///|UUID(647fedb0-d4d0-4ddb-bb2d-637f9445561c)
fn ElabCtx::single_span(
  self : Self,
  start_cnum : Int,
  end_cnum : Int,
) -> SingleLineSpan {
  let line = self.find_line(start_cnum)
  let (line_start, _) = self.line_ranges[line]
  SingleLineSpan::{
    line,
    start_col: start_cnum - line_start + 1,
    end_col: end_cnum - line_start + 1,
  }
}

///|UUID(14f0b1ab-a05a-480b-a570-9ae38a9bb894)
fn ElabCtx::char_loc(self : Self, cnum : Int) -> Location {
  let line = self.find_line(cnum)
  let (line_start, _) = self.line_ranges[line]
  let start = @basic.Position::{ fname: "", lnum: line, bol: line_start, cnum }
  let end_ = @basic.Position::{
    fname: "",
    lnum: line,
    bol: line_start,
    cnum: cnum + 1,
  }
  Location::{ start, end: end_ }
}

///|UUID(fcc3e2c8-c844-459d-b361-4957332bb1bb)
fn ElabCtx::empty(self : Self) -> Syntax {
  ignore(self)
  Syntax::simple_list(open_position=[], children=[], close_position=[])
}

///|UUID(e13b6090-fd40-4991-b79b-ab9e45f06ec6)
fn ElabCtx::atom_from_loc(
  self : Self,
  loc : Location,
  kind? : AtomKind = AtomKind::Normal,
) -> Syntax {
  Syntax::atom(content=self.slice(loc), position=self.spans(loc), kind~)
}

///|UUID(fea75fd6-9b40-4f42-9afe-3d7e2dbcda14)
fn ElabCtx::string_from_loc(self : Self, loc : Location) -> Syntax {
  self.atom_from_loc(loc, kind=AtomKind::String(StringKind::StringLiteral))
}

///|UUID(7aa6840c-aec1-4218-aaf8-2dfd66f51679)
fn ElabCtx::comment_from_loc(self : Self, loc : Location) -> Syntax {
  self.atom_from_loc(loc, kind=AtomKind::Comment)
}

///|UUID(4db8ad51-1d53-4c9f-9810-bb8d627b863e)
fn ElabCtx::part(self : Self, syntax : Syntax, loc : Location?) -> Part {
  ignore(self)
  Part::{ syntax, loc }
}

///|UUID(3e939bb3-cc3a-485c-ae86-af36a936ba6e)
fn ElabCtx::part_expr(self : Self, expr : Expr) -> Part {
  self.part(self.elab_expr(expr), Some(self.expr_loc(expr)))
}

///|UUID(3cfe8685-fb6d-469e-b4a3-c11bfd985854)
fn ElabCtx::part_type(self : Self, ty : Type) -> Part {
  self.part(self.elab_type(ty), Some(self.type_loc(ty)))
}

///|UUID(5c613f29-8d1d-4f0f-9589-79339fcf6a42)
fn ElabCtx::part_pattern(self : Self, pat : Pattern) -> Part {
  self.part(self.elab_pattern(pat), Some(self.pattern_loc(pat)))
}

///|UUID(8ae55f31-c4c5-4668-bf85-6aa85f1a24d8)
fn ElabCtx::part_binder(self : Self, binder : Binder) -> Part {
  self.part(self.elab_binder(binder), Some(binder.loc))
}

///|UUID(00bebdee-9de8-450f-aed3-42b2c0885ca2)
fn ElabCtx::part_label(self : Self, label : Label) -> Part {
  self.part(self.elab_label(label), Some(label.loc))
}

///|UUID(44c54a12-a9ef-4ae2-b085-9cf352fa57fa)
fn ElabCtx::part_doc(self : Self, doc : DocString) -> Part? {
  if doc.content == @list.empty() || loc_is_empty(doc.loc) {
    None
  } else {
    Some(self.part(self.elab_doc_string(doc), Some(doc.loc)))
  }
}

///|UUID(72232e36-f70c-45cb-998b-4ec487b23d2a)
fn ElabCtx::part_attribute(self : Self, attr : Attribute) -> Part {
  self.part(self.elab_attribute(attr), Some(attr.loc))
}

///|UUID(2669e5b6-c5b1-4e58-a6fd-d0f5d7992550)
fn ElabCtx::append_part(self : Self, parts : Array[Part], part : Part?) -> Unit {
  ignore(self)
  match part {
    Some(part) => parts.push(part)
    None => ()
  }
}

///|UUID(aa31f8c6-8bd1-43b6-823e-0bd5d1177ba2)
fn[T] ElabCtx::parts_from_list(
  self : Self,
  items : @list.List[T],
  f : (T) -> Part,
) -> Array[Part] {
  ignore(self)
  let parts = Array::new()
  items.each(fn(item) { parts.push(f(item)) })
  parts
}

///|UUID(8854f655-3610-4e2f-87f4-3aaf6d50d828)
fn ElabCtx::tokenize_loc(
  self : Self,
  loc : Location,
  word_kind? : AtomKind = AtomKind::Normal,
  classify_keywords? : Bool = false,
) -> Syntax {
  let children = Array::new()
  self.append_tokens(
    children,
    loc.start.cnum,
    loc.end.cnum,
    word_kind,
    classify_keywords,
  )
  Syntax::simple_list(open_position=[], children~, close_position=[])
}

///|UUID(fa2ddde6-e1de-4e50-b0c4-ee98dbe410fb)
fn ElabCtx::append_gap(
  self : Self,
  children : Array[Syntax],
  start_cnum : Int,
  end_cnum : Int,
) -> Unit {
  self.append_tokens(children, start_cnum, end_cnum, AtomKind::Normal, true)
}

///|UUID(12b20e44-f226-4d87-b75f-66d6f6266d48)
fn ElabCtx::append_tokens(
  self : Self,
  children : Array[Syntax],
  start_cnum : Int,
  end_cnum : Int,
  word_kind : AtomKind,
  classify_keywords : Bool,
) -> Unit {
  let mut i = start_cnum
  while i < end_cnum {
    let ch = self.contents[i]
    if is_whitespace(ch) {
      i += 1
      continue
    }
    let start = i
    let is_word = is_word_char(ch)
    i += 1
    while i < end_cnum {
      let next = self.contents[i]
      if is_whitespace(next) || is_word_char(next) != is_word {
        break
      }
      i += 1
    }
    let content = self.slice_cnums(start, i)
    let kind = classify_token(content, is_word, word_kind, classify_keywords)
    children.push(
      Syntax::atom(content~, position=[self.single_span(start, i)], kind~),
    )
  }
}

///|UUID(45825b1b-0189-45f0-9a8d-6c68bd91965d)
fn ElabCtx::region(self : Self, loc : Location, parts : Array[Part]) -> Syntax {
  sort_parts_in_place(parts)
  let children = Array::new()
  let mut cursor = loc.start.cnum
  for part in parts {
    match part.loc {
      Some(part_loc) => {
        if part_loc.start.cnum > cursor {
          self.append_gap(children, cursor, part_loc.start.cnum)
        }
        children.push(part.syntax)
        if part_loc.end.cnum > cursor {
          cursor = part_loc.end.cnum
        }
      }
      None => children.push(part.syntax)
    }
  }
  if loc.end.cnum > cursor {
    self.append_gap(children, cursor, loc.end.cnum)
  }
  Syntax::simple_list(open_position=[], children~, close_position=[])
}

///|UUID(04165233-d830-40df-b49f-ef393cf17d41)
fn ElabCtx::delimited(
  self : Self,
  open_loc : Location,
  parts : Array[Part],
  close_loc : Location,
) -> Syntax {
  sort_parts_in_place(parts)
  let children = Array::new()
  let mut cursor = open_loc.end.cnum
  for part in parts {
    match part.loc {
      Some(part_loc) => {
        if part_loc.start.cnum > cursor {
          self.append_gap(children, cursor, part_loc.start.cnum)
        }
        children.push(part.syntax)
        if part_loc.end.cnum > cursor {
          cursor = part_loc.end.cnum
        }
      }
      None => children.push(part.syntax)
    }
  }
  if close_loc.start.cnum > cursor {
    self.append_gap(children, cursor, close_loc.start.cnum)
  }
  Syntax::list(
    open_content=self.slice(open_loc),
    open_position=self.spans(open_loc),
    children~,
    close_content=self.slice(close_loc),
    close_position=self.spans(close_loc),
  )
}

///|UUID(029e9c86-1619-4e08-8d27-58373b0f5e3e)
fn ElabCtx::delimited_or_region(
  self : Self,
  loc : Location,
  open_loc : Location?,
  parts : Array[Part],
  close_loc : Location?,
) -> Syntax {
  match (open_loc, close_loc) {
    (Some(open_loc), Some(close_loc)) =>
      self.delimited(open_loc, parts, close_loc)
    _ => self.region(loc, parts)
  }
}

///|UUID(f790053a-3cf3-41dc-a053-2e1fc4ad6910)
fn ElabCtx::part_delimited_or_region(
  self : Self,
  loc : Location,
  open_loc : Location?,
  parts : Array[Part],
  close_loc : Location?,
) -> Part {
  self.part(
    self.delimited_or_region(loc, open_loc, parts, close_loc),
    Some(loc),
  )
}

///|UUID(41a8966c-2dda-4ed5-a8ea-915f2eeb08db)
fn ElabCtx::outer_delim_locs(
  self : Self,
  loc : Location,
  open_char : Char,
  close_char : Char,
) -> (Location, Location)? {
  let mut start = loc.start.cnum
  while start < loc.end.cnum && is_whitespace(self.contents[start]) {
    start += 1
  }
  if start >= loc.end.cnum || self.contents[start] != open_char {
    return None
  }
  let mut end_ = loc.end.cnum - 1
  while end_ >= start && is_whitespace(self.contents[end_]) {
    end_ -= 1
  }
  if end_ <= start || self.contents[end_] != close_char {
    return None
  }
  Some((self.char_loc(start), self.char_loc(end_)))
}

///|UUID(48f490e8-7617-4fe6-b7d3-a462d9d4a367)
fn ElabCtx::outer_delimited_or_region(
  self : Self,
  loc : Location,
  open_char : Char,
  close_char : Char,
  parts : Array[Part],
) -> Syntax {
  match self.outer_delim_locs(loc, open_char, close_char) {
    Some((open_loc, close_loc)) => self.delimited(open_loc, parts, close_loc)
    None => self.region(loc, parts)
  }
}

///|UUID(3e90e36e-e6d8-4aa8-a47d-58de70a65961)
fn ElabCtx::find_char_forward(
  self : Self,
  start_cnum : Int,
  end_cnum : Int,
  target : Char,
) -> Location? {
  let mut i = start_cnum
  while i < end_cnum {
    if self.contents[i] == target {
      return Some(self.char_loc(i))
    }
    i += 1
  }
  None
}

///|UUID(4c60fb89-c579-4d01-b6ff-818c8d4c5b0c)
fn ElabCtx::find_char_backward(
  self : Self,
  start_cnum : Int,
  end_cnum : Int,
  target : Char,
) -> Location? {
  let mut i = end_cnum - 1
  while i >= start_cnum {
    if self.contents[i] == target {
      return Some(self.char_loc(i))
    }
    i -= 1
  }
  None
}

///|UUID(a9f792ab-41f7-4ef2-9b38-aa0beac6a596)
fn ElabCtx::part_bracketed_range(
  self : Self,
  loc : Location,
  search_start : Int,
  search_end : Int,
  parts : Array[Part],
) -> Part {
  let open_loc = self.find_char_forward(search_start, search_end, '[')
  let close_loc = self.find_char_backward(search_start, search_end, ']')
  self.part(
    self.delimited_or_region(loc, open_loc, parts, close_loc),
    Some(loc),
  )
}

///|UUID(10a17d6d-b946-4103-a227-22716f157c79)
fn merge_loc_option(lhs : Location?, rhs : Location?) -> Location? {
  match (lhs, rhs) {
    (Some(lhs), Some(rhs)) => Some(lhs.merge(rhs))
    (Some(lhs), None) => Some(lhs)
    (None, Some(rhs)) => Some(rhs)
    (None, None) => None
  }
}

///|UUID(2dc8715d-7af9-4d24-8e33-450cb5ad67d5)
fn merge_loc_list(items : @list.List[Location]) -> Location? {
  let mut acc = None
  items.each(fn(item) { acc = merge_loc_option(acc, Some(item)) })
  acc
}

///|UUID(2dc77c66-f073-4dfc-a326-a9e18af83509)
fn merge_part_locs(parts : Array[Part]) -> Location? {
  let mut acc = None
  for part in parts {
    acc = merge_loc_option(acc, part.loc)
  }
  acc
}

///|UUID(5fd8d650-6d1f-4f99-a886-769278e41b5b)
fn sort_parts_in_place(parts : Array[Part]) -> Unit {
  let mut i = 1
  while i < parts.length() {
    let current = parts[i]
    let mut j = i
    while j > 0 && part_starts_after(parts[j - 1], current) {
      parts[j] = parts[j - 1]
      j -= 1
    }
    parts[j] = current
    i += 1
  }
}

///|UUID(16790d4a-c2c7-42b7-b6f0-884e8bb23b27)
fn part_starts_after(lhs : Part, rhs : Part) -> Bool {
  match (lhs.loc, rhs.loc) {
    (Some(lhs), Some(rhs)) => lhs.start.cnum > rhs.start.cnum
    _ => false
  }
}

///|UUID(f8aee96a-5d4f-40c0-ae46-f2d21adbac73)
fn loc_is_empty(loc : Location) -> Bool {
  loc.start.cnum == loc.end.cnum
}

///|UUID(a2107ac4-bdbd-4dc0-8b67-6e99605f1911)
fn is_whitespace(ch : Char) -> Bool {
  ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r'
}

///|UUID(0f2d6113-c818-42dc-9715-6d4ad8b0c33b)
fn is_word_char(ch : Char) -> Bool {
  match ch {
    '_' | '0'..='9' | 'a'..='z' | 'A'..='Z' => true
    _ => false
  }
}

///|UUID(f32255e1-afd4-41e0-8614-771e5e95fbc5)
fn classify_token(
  content : String,
  is_word : Bool,
  word_kind : AtomKind,
  classify_keywords : Bool,
) -> AtomKind {
  if !is_word {
    AtomKind::Normal
  } else if classify_keywords && looks_like_keyword(content) {
    AtomKind::Keyword
  } else {
    word_kind
  }
}

///|UUID(dafd8fdb-d9f6-4aaa-af82-23ed4c63af66)
fn looks_like_keyword(content : String) -> Bool {
  content == "and" ||
  content == "as" ||
  content == "async" ||
  content == "break" ||
  content == "catch" ||
  content == "const" ||
  content == "continue" ||
  content == "declare" ||
  content == "default" ||
  content == "defer" ||
  content == "derive" ||
  content == "else" ||
  content == "enum" ||
  content == "enumview" ||
  content == "extern" ||
  content == "false" ||
  content == "fn" ||
  content == "for" ||
  content == "guard" ||
  content == "if" ||
  content == "impl" ||
  content == "in" ||
  content == "is" ||
  content == "lexmatch" ||
  content == "let" ||
  content == "loop" ||
  content == "main" ||
  content == "match" ||
  content == "mut" ||
  content == "noraise" ||
  content == "priv" ||
  content == "pub" ||
  content == "raise" ||
  content == "return" ||
  content == "struct" ||
  content == "suberror" ||
  content == "test" ||
  content == "trait" ||
  content == "true" ||
  content == "try" ||
  content == "type" ||
  content == "using" ||
  content == "where" ||
  content == "while" ||
  content == "with"
}
