///|
pub struct ElabCtx {
  line_widths : LineWidths
}

///|
pub fn ElabCtx::new(source : StringView) -> Self {
  { line_widths: LineWidths::from_str(source) }
}

///|
pub fn elab_impls(source : StringView, impls : Impls) -> Array[Syntax] {
  ElabCtx::new(source).elab_impls(impls)
}

///|
pub fn elab_impl(source : StringView, impl_ : Impl) -> Syntax {
  ElabCtx::new(source).elab_impl(impl_)
}

///|
pub fn elab_expr(source : StringView, expr : Expr) -> Syntax {
  ElabCtx::new(source).elab_expr(expr)
}

///|
pub fn elab_type(source : StringView, ty : Type) -> Syntax {
  ElabCtx::new(source).elab_type(ty)
}

///|
pub fn elab_pattern(source : StringView, pat : Pattern) -> Syntax {
  ElabCtx::new(source).elab_pattern(pat)
}

///|
pub fn ElabCtx::elab_impls(self : Self, impls : Impls) -> Array[Syntax] {
  // TODO: `moonbitlang/parser/syntax` drops ordinary comments entirely,
  // so this elaboration can only emit comment nodes for docstrings.
  list_to_array(impls, fn(impl_) { self.elab_impl(impl_) })
}

///|
fn ElabCtx::spans(self : Self, loc : Location) -> Array[SingleLineSpan] {
  self.line_widths.loc_to_spans(loc)
}

///|
fn ElabCtx::atom(
  self : Self,
  content~ : String,
  loc~ : Location,
  kind? : AtomKind = AtomKind::Normal,
) -> Syntax {
  Syntax::atom(content~, position=self.spans(loc), kind~)
}

///|
fn ElabCtx::synthetic_atom(
  self : Self,
  content~ : String,
  kind? : AtomKind = AtomKind::Normal,
) -> Syntax {
  ignore(self)
  Syntax::atom(content~, position=[], kind~)
}

///|
fn ElabCtx::keyword_atom(
  self : Self,
  content~ : String,
  loc~ : Location,
) -> Syntax {
  self.atom(content~, loc~, kind=AtomKind::Keyword)
}

///|
fn ElabCtx::type_atom(
  self : Self,
  content~ : String,
  loc~ : Location,
) -> Syntax {
  self.atom(content~, loc~, kind=AtomKind::Type)
}

///|
fn ElabCtx::string_atom(
  self : Self,
  content~ : String,
  loc~ : Location,
) -> Syntax {
  self.atom(content~, loc~, kind=AtomKind::String(StringKind::StringLiteral))
}

///|
fn ElabCtx::text_atom(
  self : Self,
  content~ : String,
  loc~ : Location,
) -> Syntax {
  self.atom(content~, loc~, kind=AtomKind::String(StringKind::Text))
}

///|
fn ElabCtx::comment_atom(
  self : Self,
  content~ : String,
  loc~ : Location,
) -> Syntax {
  self.atom(content~, loc~, kind=AtomKind::Comment)
}

///|
fn ElabCtx::node(self : Self, tag : String, children : Array[Syntax]) -> Syntax {
  ignore(self)
  Syntax::list(
    open_content=tag,
    open_position=[],
    children~,
    close_content="",
    close_position=[],
  )
}

///|
fn ElabCtx::field(self : Self, tag : String, child : Syntax) -> Syntax {
  self.node(tag, [child])
}

///|
fn ElabCtx::none(self : Self) -> Syntax {
  self.node("None", [])
}

///|
fn ElabCtx::some(self : Self, child : Syntax) -> Syntax {
  self.node("Some", [child])
}

///|
fn[T] ElabCtx::option_node(
  self : Self,
  value : T?,
  f : (T) -> Syntax,
) -> Syntax {
  match value {
    Some(value) => self.some(f(value))
    None => self.none()
  }
}

///|
fn[T] ElabCtx::field_option(
  self : Self,
  tag : String,
  value : T?,
  f : (T) -> Syntax,
) -> Syntax {
  self.field(tag, self.option_node(value, f))
}

///|
fn[T] ElabCtx::list_node(
  self : Self,
  tag : String,
  items : @list.List[T],
  f : (T) -> Syntax,
) -> Syntax {
  self.node(tag, list_to_array(items, f))
}

///|
fn ElabCtx::field_bool(self : Self, tag : String, value : Bool) -> Syntax {
  self.field(
    tag,
    self.synthetic_atom(content=show_bool(value), kind=AtomKind::Keyword),
  )
}

///|
fn show_bool(value : Bool) -> String {
  if value {
    "true"
  } else {
    "false"
  }
}

///|
fn[T] list_to_array(items : @list.List[T], f : (T) -> Syntax) -> Array[Syntax] {
  let acc = Array::new()
  items.each(fn(item) { acc.push(f(item)) })
  acc
}

///|
fn join_lines(lines : @list.List[String]) -> String {
  let buf = StringBuilder::new()
  let mut first = true
  lines.each(fn(line) {
    if first {
      first = false
    } else {
      buf.write_string("\n")
    }
    buf.write_string(line)
  })
  buf.to_string()
}
