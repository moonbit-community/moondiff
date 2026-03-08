///|UUID(b246f889-c80e-4e31-9127-e22ba3446d93)
pub struct ElabCtx {
  line_widths : LineWidths
}

///|UUID(2e432a90-4561-4e52-a159-bf31a83a3af6)
pub fn ElabCtx::new(source : StringView) -> Self {
  { line_widths: LineWidths::from_str(source) }
}

///|UUID(41cacaa6-d761-4244-9cf4-7d798e359913)
pub fn elab_impls(source : StringView, impls : Impls) -> Array[Syntax] {
  ElabCtx::new(source).elab_impls(impls)
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

///|UUID(1c72c6ec-6539-4376-83b4-ff0c5fa12f35)
pub fn ElabCtx::elab_impls(self : Self, impls : Impls) -> Array[Syntax] {
  // TODO: `moonbitlang/parser/syntax` drops ordinary comments entirely,
  // so this elaboration can only emit comment nodes for docstrings.
  list_to_array(impls, fn(impl_) { self.elab_impl(impl_) })
}

///|UUID(7d94ce91-b74a-4662-9a82-a47a6cec9bf6)
fn ElabCtx::spans(self : Self, loc : Location) -> Array[SingleLineSpan] {
  self.line_widths.loc_to_spans(loc)
}

///|UUID(d3e671b4-102a-4415-a4c1-e4e49886edf5)
fn ElabCtx::atom(
  self : Self,
  content~ : String,
  loc~ : Location,
  kind? : AtomKind = AtomKind::Normal,
) -> Syntax {
  Syntax::atom(content~, position=self.spans(loc), kind~)
}

///|UUID(d3ac2825-6064-42ee-9f70-11d28eba4925)
fn ElabCtx::synthetic_atom(
  self : Self,
  content~ : String,
  kind? : AtomKind = AtomKind::Normal,
) -> Syntax {
  ignore(self)
  Syntax::atom(content~, position=[], kind~)
}

///|UUID(625eafc4-97f2-42d4-a432-e0f9a65b5e99)
fn ElabCtx::keyword_atom(
  self : Self,
  content~ : String,
  loc~ : Location,
) -> Syntax {
  self.atom(content~, loc~, kind=AtomKind::Keyword)
}

///|UUID(4c794947-79b8-4b46-9e25-2afc4ac08306)
fn ElabCtx::type_atom(
  self : Self,
  content~ : String,
  loc~ : Location,
) -> Syntax {
  self.atom(content~, loc~, kind=AtomKind::Type)
}

///|UUID(74eaa434-719b-4c3c-b33e-4847499dfc46)
fn ElabCtx::string_atom(
  self : Self,
  content~ : String,
  loc~ : Location,
) -> Syntax {
  self.atom(content~, loc~, kind=AtomKind::String(StringKind::StringLiteral))
}

///|UUID(06885a5b-74ef-4e51-9158-424ff94480ff)
fn ElabCtx::text_atom(
  self : Self,
  content~ : String,
  loc~ : Location,
) -> Syntax {
  self.atom(content~, loc~, kind=AtomKind::String(StringKind::Text))
}

///|UUID(6b8fa717-9cc2-478f-8d0f-b1e11214bafe)
fn ElabCtx::comment_atom(
  self : Self,
  content~ : String,
  loc~ : Location,
) -> Syntax {
  self.atom(content~, loc~, kind=AtomKind::Comment)
}

///|UUID(cd201e8a-315a-4f6a-9dab-eac66903bba0)
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

///|UUID(784d62fa-eb19-48e6-9a45-0b0c23db3d36)
fn ElabCtx::field(self : Self, tag : String, child : Syntax) -> Syntax {
  self.node(tag, [child])
}

///|UUID(5cd02d9d-1851-4b6f-8ba9-45360deff975)
fn ElabCtx::none(self : Self) -> Syntax {
  self.node("None", [])
}

///|UUID(0f9fd0b0-7845-4d0d-90cb-90f8351ade6d)
fn ElabCtx::some(self : Self, child : Syntax) -> Syntax {
  self.node("Some", [child])
}

///|UUID(66907c03-4fe5-4279-b1fe-c663aa40cec2)
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

///|UUID(d1d2c4c7-bf3d-4732-b30b-3491c3715df4)
fn[T] ElabCtx::field_option(
  self : Self,
  tag : String,
  value : T?,
  f : (T) -> Syntax,
) -> Syntax {
  self.field(tag, self.option_node(value, f))
}

///|UUID(29cb01ca-cd26-40d2-9ea5-ee67ea3f7932)
fn[T] ElabCtx::list_node(
  self : Self,
  tag : String,
  items : @list.List[T],
  f : (T) -> Syntax,
) -> Syntax {
  self.node(tag, list_to_array(items, f))
}

///|UUID(8f377ded-7325-4313-b862-662f8aa345e5)
fn ElabCtx::field_bool(self : Self, tag : String, value : Bool) -> Syntax {
  self.field(
    tag,
    self.synthetic_atom(content=show_bool(value), kind=AtomKind::Keyword),
  )
}

///|UUID(b5897953-e62e-463a-8bb0-317c0be59039)
fn show_bool(value : Bool) -> String {
  if value {
    "true"
  } else {
    "false"
  }
}

///|UUID(e8156e1d-258e-4c4a-969c-fc5ac1639fb4)
fn[T] list_to_array(items : @list.List[T], f : (T) -> Syntax) -> Array[Syntax] {
  let acc = Array::new()
  items.each(fn(item) { acc.push(f(item)) })
  acc
}

///|UUID(6a5e2556-6ad9-46b0-9395-49defaf97a0a)
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
