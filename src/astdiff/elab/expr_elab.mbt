///|
fn ElabCtx::elab_argument(self : Self, argument : Argument) -> Syntax {
  // TODO: `Argument` itself has no location. Positional arguments also lose
  // comma and parenthesis spans, so only the contained value/kind are precise.
  self.node("Argument", [
    self.field("value", self.elab_expr(argument.value)),
    self.field("kind", self.elab_argument_kind(argument.kind)),
  ])
}

///|
fn ElabCtx::elab_parameter(self : Self, parameter : Parameter) -> Syntax {
  // TODO: `Parameter` does not preserve punctuation spans such as `~`, `?`,
  // `:`, or `=`. Only binder/type/default child locations are available.
  match parameter {
    DiscardPositional(ty~, loc~) =>
      self.node("Parameter::DiscardPositional", [
        self.field("binder", self.keyword_atom(content="_", loc~)),
        self.field_option("ty", ty, fn(value) { self.elab_type(value) }),
      ])
    Positional(binder~, ty~) =>
      self.node("Parameter::Positional", [
        self.field("binder", self.elab_binder(binder)),
        self.field_option("ty", ty, fn(value) { self.elab_type(value) }),
      ])
    Labelled(binder~, ty~) =>
      self.node("Parameter::Labelled", [
        self.field("binder", self.elab_binder(binder)),
        self.field_option("ty", ty, fn(value) { self.elab_type(value) }),
      ])
    Optional(binder~, default~, ty~) =>
      self.node("Parameter::Optional", [
        self.field("binder", self.elab_binder(binder)),
        self.field_option("ty", ty, fn(value) { self.elab_type(value) }),
        self.field("default", self.elab_expr(default)),
      ])
    QuestionOptional(binder~, ty~) =>
      self.node("Parameter::QuestionOptional", [
        self.field("binder", self.elab_binder(binder)),
        self.field_option("ty", ty, fn(value) { self.elab_type(value) }),
      ])
  }
}

///|
fn ElabCtx::elab_case(self : Self, case_ : Case) -> Syntax {
  // TODO: `Case` does not expose a standalone location for the `=>` token
  // or the optional guard keyword.
  self.node("Case", [
    self.field("pattern", self.elab_pattern(case_.pattern)),
    self.field_option("guard", case_.guard_, fn(value) { self.elab_expr(value) }),
    self.field("body", self.elab_expr(case_.body)),
  ])
}

///|
fn ElabCtx::elab_lex_case(self : Self, case_ : LexCase) -> Syntax {
  self.node("LexCase", [
    self.field(
      "pat",
      self.list_node("LexCase::Patterns", case_.pat, fn(value) {
        self.elab_lex_top_pattern(value)
      }),
    ),
    self.field_option("guard", case_.guard_, fn(value) { self.elab_expr(value) }),
    self.field("body", self.elab_expr(case_.body)),
  ])
}

///|
fn ElabCtx::elab_lex_top_pattern(self : Self, pat : LexTopPattern) -> Syntax {
  match pat {
    Pattern(pat) =>
      self.node("LexTopPattern::Pattern", [
        self.field("pat", self.elab_lex_pattern(pat)),
      ])
    Binder(binder) =>
      self.node("LexTopPattern::Binder", [
        self.field("binder", self.elab_binder(binder)),
      ])
    Wildcard(loc~) =>
      self.node("LexTopPattern::Wildcard", [
        self.keyword_atom(content="_", loc~),
      ])
  }
}

///|
fn ElabCtx::elab_lex_pattern(self : Self, pat : LexPattern) -> Syntax {
  match pat {
    Regex(lit~, loc~) =>
      self.node("LexPattern::Regex", [self.text_atom(content=lit, loc~)])
    RegexInterp(elems~, loc=_) =>
      self.node("LexPattern::RegexInterp", [
        self.list_node("LexPattern::RegexInterp::Elems", elems, fn(value) {
          self.elab_interp_elem(value)
        }),
      ])
    Alias(pat~, binder~, loc=_) =>
      self.node("LexPattern::Alias", [
        self.field("pat", self.elab_lex_pattern(pat)),
        self.field("binder", self.elab_binder(binder)),
      ])
    Sequence(pats~, loc=_) =>
      self.node("LexPattern::Sequence", [
        self.list_node("LexPattern::Sequence::Items", pats, fn(value) {
          self.elab_lex_pattern(value)
        }),
      ])
  }
}

///|
fn ElabCtx::elab_spreadable_elem(self : Self, elem : SpreadableElem) -> Syntax {
  match elem {
    Regular(expr) =>
      self.node("SpreadableElem::Regular", [
        self.field("expr", self.elab_expr(expr)),
      ])
    Spread(expr~, loc~) =>
      self.node("SpreadableElem::Spread", [
        self.field("spread", self.keyword_atom(content="..", loc~)),
        self.field("expr", self.elab_expr(expr)),
      ])
  }
}

///|
fn ElabCtx::elab_map_expr_elem(self : Self, elem : MapExprElem) -> Syntax {
  self.node("MapExprElem", [
    self.field("key", self.elab_constant(elem.key, elem.key_loc)),
    self.field("expr", self.elab_expr(elem.expr)),
  ])
}

///|
fn ElabCtx::elab_static_assertion(
  self : Self,
  assertion : StaticAssertion,
) -> Syntax {
  self.node("StaticAssertion", [
    self.field("ty", self.elab_type(assertion.ty)),
    self.field(
      "trait",
      self.elab_long_ident(assertion.trait_, assertion.loc, AtomKind::Type),
    ),
    self.field("msg", self.atom(content=assertion.msg, loc=assertion.loc)),
  ])
}

///|
fn ElabCtx::elab_func(self : Self, func : Func) -> Syntax {
  self.node("Func", [
    self.field(
      "parameters",
      self.list_node("Func::Parameters", func.parameters, fn(value) {
        self.elab_parameter(value)
      }),
    ),
    self.field("body", self.elab_expr(func.body)),
    self.field_option("return_type", func.return_type, fn(value) {
      self.elab_type(value)
    }),
    self.field("error_type", self.elab_error_type(func.error_type)),
    self.field("kind", self.elab_fn_kind(func.kind)),
    self.field_option("has_error", func.has_error, fn(loc) {
      self.keyword_atom(content="raise", loc~)
    }),
    self.field_option("is_async", func.is_async, fn(loc) {
      self.keyword_atom(content="async", loc~)
    }),
  ])
}

///|
fn ElabCtx::elab_field_def(self : Self, field : FieldDef) -> Syntax {
  self.node("FieldDef", [
    self.field("label", self.elab_label(field.label)),
    self.field("expr", self.elab_expr(field.expr)),
    self.field_bool("is_pun", field.is_pun),
  ])
}

///|
fn ElabCtx::elab_interp_elem(self : Self, elem : InterpElem) -> Syntax {
  match elem {
    Literal(repr~, loc~) =>
      self.node("InterpElem::Literal", [self.text_atom(content=repr, loc~)])
    InterpElem::Expr(expr~, loc=_) =>
      self.node("InterpElem::Expr", [self.field("expr", self.elab_expr(expr))])
    Source(source) =>
      self.node("InterpElem::Source", [
        self.text_atom(content=source.source, loc=source.loc),
      ])
  }
}

///|
fn ElabCtx::elab_multiline_string_elem(
  self : Self,
  elem : MultilineStringElem,
) -> Syntax {
  match elem {
    MultilineStringElem::String(value) =>
      // TODO: plain multiline string chunks lose their individual locations.
      self.node("MultilineStringElem::String", [
        self.synthetic_atom(
          content=value,
          kind=AtomKind::String(StringKind::Text),
        ),
      ])
    Interp(elems) =>
      self.node("MultilineStringElem::Interp", [
        self.list_node("MultilineStringElem::Interp::Elems", elems, fn(value) {
          self.elab_interp_elem(value)
        }),
      ])
  }
}

///|
fn ElabCtx::elab_try_operator_kind(
  self : Self,
  kind : TryOperatorKind,
) -> Syntax {
  ignore(self)
  match kind {
    Question => self.node("TryOperatorKind::Question", [])
    Exclamation => self.node("TryOperatorKind::Exclamation", [])
  }
}

///|
fn ElabCtx::elab_dotdot_binder(self : Self, binder : DotDotBinder) -> Syntax {
  // TODO: `DotDotBinder::Underscore` and `DotDotBinder::NoBinder` do not
  // carry the source span of the `..` pattern segment.
  match binder {
    Underscore => self.node("DotDotBinder::Underscore", [])
    NoBinder => self.node("DotDotBinder::NoBinder", [])
    BinderAs(binder) =>
      self.node("DotDotBinder::BinderAs", [
        self.field("binder", self.elab_binder(binder)),
      ])
    DotDotBinder::Binder(binder) =>
      self.node("DotDotBinder::Binder", [
        self.field("binder", self.elab_binder(binder)),
      ])
  }
}

///|
fn ElabCtx::elab_array_pattern(self : Self, pat : ArrayPattern) -> Syntax {
  match pat {
    ArrayPattern::Pattern(pat) =>
      self.node("ArrayPattern::Pattern", [
        self.field("pat", self.elab_pattern(pat)),
      ])
    StringSpread(str~, loc~) =>
      self.node("ArrayPattern::StringSpread", [
        self.string_atom(content=str, loc~),
      ])
    BytesSpread(bytes~, loc~) =>
      self.node("ArrayPattern::BytesSpread", [
        self.string_atom(content=bytes, loc~),
      ])
    ConstSpread(binder~, pkg~, loc=_) =>
      self.node("ArrayPattern::ConstSpread", [
        self.field("binder", self.elab_binder(binder)),
        self.field(
          "pkg",
          self.option_node(pkg, fn(pkg) {
            self.synthetic_atom(content=pkg, kind=AtomKind::Type)
          }),
        ),
      ])
  }
}

///|
fn ElabCtx::elab_array_patterns(
  self : Self,
  patterns : ArrayPatterns,
) -> Syntax {
  match patterns {
    Closed(items) =>
      self.node("ArrayPatterns::Closed", [
        self.list_node("ArrayPatterns::Closed::Items", items, fn(value) {
          self.elab_array_pattern(value)
        }),
      ])
    Open(prefix, suffix, binder) =>
      self.node("ArrayPatterns::Open", [
        self.field(
          "prefix",
          self.list_node("ArrayPatterns::Open::Prefix", prefix, fn(value) {
            self.elab_array_pattern(value)
          }),
        ),
        self.field(
          "suffix",
          self.list_node("ArrayPatterns::Open::Suffix", suffix, fn(value) {
            self.elab_array_pattern(value)
          }),
        ),
        self.field("binder", self.elab_dotdot_binder(binder)),
      ])
  }
}

///|
fn ElabCtx::elab_where_clause(
  self : Self,
  where_clause : WhereClause,
) -> Syntax {
  self.node("WhereClause", [
    self.field(
      "fields",
      self.list_node("WhereClause::Fields", where_clause.fields, fn(value) {
        self.elab_field_def(value)
      }),
    ),
  ])
}

///|
fn ElabCtx::elab_field_pat(self : Self, field : FieldPat) -> Syntax {
  self.node("FieldPat", [
    self.field("label", self.elab_label(field.label)),
    self.field("pattern", self.elab_pattern(field.pattern)),
    self.field_bool("is_pun", field.is_pun),
  ])
}

///|
fn ElabCtx::elab_constr_pat_arg(self : Self, arg : ConstrPatArg) -> Syntax {
  // TODO: `ConstrPatArg` does not store a separate location, so delimiter
  // and label punctuation spans are unavailable here.
  self.node("ConstrPatArg", [
    self.field("pat", self.elab_pattern(arg.pat)),
    self.field("kind", self.elab_argument_kind(arg.kind)),
  ])
}

///|
fn ElabCtx::elab_map_pat_elem(self : Self, elem : MapPatElem) -> Syntax {
  self.node("MapPatElem", [
    self.field("key", self.elab_constant(elem.key, elem.key_loc)),
    self.field("pat", self.elab_pattern(elem.pat)),
    self.field_bool("match_absent", elem.match_absent),
  ])
}

///|
fn ElabCtx::elab_range_kind(self : Self, kind : RangeKind) -> Syntax {
  ignore(self)
  match kind {
    Inclusive => self.node("RangeKind::Inclusive", [])
    Exclusive => self.node("RangeKind::Exclusive", [])
    InclusiveMissingEqual => self.node("RangeKind::InclusiveMissingEqual", [])
  }
}

///|
pub fn ElabCtx::elab_pattern(self : Self, pat : Pattern) -> Syntax {
  // TODO: `Pattern` nodes do not expose delimiter positions for tuple,
  // record, map, or array punctuation.
  match pat {
    Alias(pat~, alias_~, loc=_) =>
      self.node("Pattern::Alias", [
        self.field("pat", self.elab_pattern(pat)),
        self.field("alias", self.elab_binder(alias_)),
      ])
    Any(loc~) =>
      self.node("Pattern::Any", [self.keyword_atom(content="_", loc~)])
    Pattern::Array(pats~, loc=_) =>
      self.node("Pattern::Array", [
        self.field("pats", self.elab_array_patterns(pats)),
      ])
    Constant(c~, loc~) =>
      self.node("Pattern::Constant", [
        self.field("value", self.elab_constant(c, loc)),
      ])
    Constraint(pat~, ty~, loc=_) =>
      self.node("Pattern::Constraint", [
        self.field("pat", self.elab_pattern(pat)),
        self.field("ty", self.elab_type(ty)),
      ])
    Constr(constr~, args~, is_open~, loc=_) =>
      self.node("Pattern::Constr", [
        self.field("constr", self.elab_constructor(constr)),
        self.field(
          "args",
          self.option_node(args, fn(args) {
            self.list_node("Pattern::Constr::Args", args, fn(value) {
              self.elab_constr_pat_arg(value)
            })
          }),
        ),
        self.field_bool("is_open", is_open),
      ])
    Or(pat1~, pat2~, loc=_) =>
      self.node("Pattern::Or", [
        self.field("pat1", self.elab_pattern(pat1)),
        self.field("pat2", self.elab_pattern(pat2)),
      ])
    Tuple(pats~, loc=_) =>
      self.node("Pattern::Tuple", [
        self.list_node("Pattern::Tuple::Items", pats, fn(value) {
          self.elab_pattern(value)
        }),
      ])
    Pattern::Var(binder) =>
      self.node("Pattern::Var", [self.field("binder", self.elab_binder(binder))])
    Record(fields~, is_closed~, loc=_) =>
      self.node("Pattern::Record", [
        self.field(
          "fields",
          self.list_node("Pattern::Record::Fields", fields, fn(value) {
            self.elab_field_pat(value)
          }),
        ),
        self.field_bool("is_closed", is_closed),
      ])
    Map(elems~, is_closed~, loc=_) =>
      self.node("Pattern::Map", [
        self.field(
          "elems",
          self.list_node("Pattern::Map::Elems", elems, fn(value) {
            self.elab_map_pat_elem(value)
          }),
        ),
        self.field_bool("is_closed", is_closed),
      ])
    Range(lhs~, rhs~, kind~, loc=_) =>
      self.node("Pattern::Range", [
        self.field("lhs", self.elab_pattern(lhs)),
        self.field("rhs", self.elab_pattern(rhs)),
        self.field("kind", self.elab_range_kind(kind)),
      ])
    SpecialConstr(binder~, args~, loc=_) =>
      self.node("Pattern::SpecialConstr", [
        self.field("binder", self.elab_binder(binder)),
        self.field(
          "args",
          self.list_node("Pattern::SpecialConstr::Args", args, fn(value) {
            self.elab_constr_pat_arg(value)
          }),
        ),
      ])
  }
}

///|
fn ElabCtx::elab_binder_expr_pair(self : Self, pair : (Binder, Expr)) -> Syntax {
  let (binder, expr) = pair
  self.node("BinderExprPair", [
    self.field("binder", self.elab_binder(binder)),
    self.field("expr", self.elab_expr(expr)),
  ])
}

///|
fn ElabCtx::elab_binder_func_pair(self : Self, pair : (Binder, Func)) -> Syntax {
  let (binder, func) = pair
  self.node("BinderFuncPair", [
    self.field("binder", self.elab_binder(binder)),
    self.field("func", self.elab_func(func)),
  ])
}

///|
fn ElabCtx::elab_binder_type_func_triple(
  self : Self,
  triple : (Binder, Type?, Func),
) -> Syntax {
  let (binder, ty, func) = triple
  self.node("BinderTypeFuncTriple", [
    self.field("binder", self.elab_binder(binder)),
    self.field_option("ty", ty, fn(value) { self.elab_type(value) }),
    self.field("func", self.elab_func(func)),
  ])
}

///|
fn ElabCtx::elab_optional_binder(self : Self, binder : Binder?) -> Syntax {
  self.option_node(binder, fn(value) { self.elab_binder(value) })
}

///|
pub fn ElabCtx::elab_expr(self : Self, expr : Expr) -> Syntax {
  match expr {
    Apply(func~, args~, attr~, loc=_) =>
      self.node("Expr::Apply", [
        self.field("func", self.elab_expr(func)),
        self.field(
          "args",
          self.list_node("Expr::Apply::Args", args, fn(value) {
            self.elab_argument(value)
          }),
        ),
        self.field("attr", self.elab_apply_attr(attr)),
      ])
    Infix(op~, lhs~, rhs~, loc=_) =>
      self.node("Expr::Infix", [
        self.field("op", self.elab_var(op)),
        self.field("lhs", self.elab_expr(lhs)),
        self.field("rhs", self.elab_expr(rhs)),
      ])
    Unary(op~, expr~, loc=_) =>
      self.node("Expr::Unary", [
        self.field("op", self.elab_var(op)),
        self.field("expr", self.elab_expr(expr)),
      ])
    Expr::Array(exprs~, loc=_) =>
      self.node("Expr::Array", [
        self.list_node("Expr::Array::Items", exprs, fn(value) {
          self.elab_expr(value)
        }),
      ])
    ArraySpread(elems~, loc=_) =>
      self.node("Expr::ArraySpread", [
        self.list_node("Expr::ArraySpread::Elems", elems, fn(value) {
          self.elab_spreadable_elem(value)
        }),
      ])
    ArrayGet(array~, index~, loc=_) =>
      self.node("Expr::ArrayGet", [
        self.field("array", self.elab_expr(array)),
        self.field("index", self.elab_expr(index)),
      ])
    ArrayGetSlice(array~, start_index~, end_index~, index_loc~, loc=_) =>
      self.node("Expr::ArrayGetSlice", [
        self.field("array", self.elab_expr(array)),
        self.field_option("start_index", start_index, fn(value) {
          self.elab_expr(value)
        }),
        self.field_option("end_index", end_index, fn(value) {
          self.elab_expr(value)
        }),
        self.field("index_loc", self.atom(content="slice", loc=index_loc)),
      ])
    ArraySet(array~, index~, value~, loc=_) =>
      self.node("Expr::ArraySet", [
        self.field("array", self.elab_expr(array)),
        self.field("index", self.elab_expr(index)),
        self.field("value", self.elab_expr(value)),
      ])
    ArrayAugmentedSet(op~, array~, index~, value~, loc=_) =>
      self.node("Expr::ArrayAugmentedSet", [
        self.field("op", self.elab_var(op)),
        self.field("array", self.elab_expr(array)),
        self.field("index", self.elab_expr(index)),
        self.field("value", self.elab_expr(value)),
      ])
    Expr::Constant(c~, loc~) =>
      self.node("Expr::Constant", [
        self.field("value", self.elab_constant(c, loc)),
      ])
    MultilineString(elems~, loc=_) =>
      self.node("Expr::MultilineString", [
        self.list_node("Expr::MultilineString::Elems", elems, fn(value) {
          self.elab_multiline_string_elem(value)
        }),
      ])
    Interp(elems~, loc=_) =>
      self.node("Expr::Interp", [
        self.list_node("Expr::Interp::Elems", elems, fn(value) {
          self.elab_interp_elem(value)
        }),
      ])
    Constraint(expr~, ty~, loc=_) =>
      self.node("Expr::Constraint", [
        self.field("expr", self.elab_expr(expr)),
        self.field("ty", self.elab_type(ty)),
      ])
    Expr::Constr(constr~, loc=_) =>
      self.node("Expr::Constr", [
        self.field("constr", self.elab_constructor(constr)),
      ])
    While(loop_cond~, loop_body~, while_else~, label~, loc=_) =>
      self.node("Expr::While", [
        self.field("loop_cond", self.elab_expr(loop_cond)),
        self.field("loop_body", self.elab_expr(loop_body)),
        self.field_option("while_else", while_else, fn(value) {
          self.elab_expr(value)
        }),
        self.field_option("label", label, fn(value) { self.elab_label(value) }),
      ])
    Function(func~, loc=_) =>
      self.node("Expr::Function", [self.field("func", self.elab_func(func))])
    Ident(id~, loc=_) =>
      self.node("Expr::Ident", [self.field("id", self.elab_var(id))])
    If(cond~, ifso~, ifnot~, loc=_) =>
      self.node("Expr::If", [
        self.field("cond", self.elab_expr(cond)),
        self.field("ifso", self.elab_expr(ifso)),
        self.field_option("ifnot", ifnot, fn(value) { self.elab_expr(value) }),
      ])
    Guard(cond~, otherwise~, body~, loc=_) =>
      self.node("Expr::Guard", [
        self.field("cond", self.elab_expr(cond)),
        self.field_option("otherwise", otherwise, fn(value) {
          self.elab_expr(value)
        }),
        self.field("body", self.elab_expr(body)),
      ])
    Is(expr~, pat~, loc=_) =>
      self.node("Expr::Is", [
        self.field("expr", self.elab_expr(expr)),
        self.field("pat", self.elab_pattern(pat)),
      ])
    IsLexMatch(expr~, strategy~, pat~, pat_loc~, loc=_) =>
      self.node("Expr::IsLexMatch", [
        self.field("expr", self.elab_expr(expr)),
        self.field_option("strategy", strategy, fn(value) {
          self.elab_label(value)
        }),
        self.field("pat_loc", self.atom(content="pat", loc=pat_loc)),
        self.field(
          "pat",
          self.list_node("Expr::IsLexMatch::Patterns", pat, fn(value) {
            self.elab_lex_top_pattern(value)
          }),
        ),
      ])
    Defer(expr~, body~, loc=_) =>
      self.node("Expr::Defer", [
        self.field("expr", self.elab_expr(expr)),
        self.field("body", self.elab_expr(body)),
      ])
    LetFn(name~, func~, body~, loc=_) =>
      self.node("Expr::LetFn", [
        self.field("name", self.elab_binder(name)),
        self.field("func", self.elab_func(func)),
        self.field("body", self.elab_expr(body)),
      ])
    LetRec(bindings~, body~, loc=_) =>
      self.node("Expr::LetRec", [
        self.field(
          "bindings",
          self.list_node("Expr::LetRec::Bindings", bindings, fn(value) {
            self.elab_binder_func_pair(value)
          }),
        ),
        self.field("body", self.elab_expr(body)),
      ])
    LetAnd(bindings~, body~, loc=_) =>
      self.node("Expr::LetAnd", [
        self.field(
          "bindings",
          self.list_node("Expr::LetAnd::Bindings", bindings, fn(value) {
            self.elab_binder_type_func_triple(value)
          }),
        ),
        self.field("body", self.elab_expr(body)),
      ])
    Let(pattern~, expr~, body~, loc=_) =>
      self.node("Expr::Let", [
        self.field("pattern", self.elab_pattern(pattern)),
        self.field("expr", self.elab_expr(expr)),
        self.field("body", self.elab_expr(body)),
      ])
    Sequence(exprs~, last_expr~, loc=_) =>
      self.node("Expr::Sequence", [
        self.field(
          "exprs",
          self.list_node("Expr::Sequence::Exprs", exprs, fn(value) {
            self.elab_expr(value)
          }),
        ),
        self.field("last_expr", self.elab_expr(last_expr)),
      ])
    Tuple(exprs~, loc=_) =>
      self.node("Expr::Tuple", [
        self.list_node("Expr::Tuple::Items", exprs, fn(value) {
          self.elab_expr(value)
        }),
      ])
    Record(type_name~, fields~, trailing~, loc=_) =>
      self.node("Expr::Record", [
        self.field_option("type_name", type_name, fn(value) {
          self.elab_type_name(value)
        }),
        self.field(
          "fields",
          self.list_node("Expr::Record::Fields", fields, fn(value) {
            self.elab_field_def(value)
          }),
        ),
        self.field("trailing", self.elab_trailing_mark(trailing)),
      ])
    RecordUpdate(type_name~, record~, fields~, loc=_) =>
      self.node("Expr::RecordUpdate", [
        self.field_option("type_name", type_name, fn(value) {
          self.elab_type_name(value)
        }),
        self.field("record", self.elab_expr(record)),
        self.field(
          "fields",
          self.list_node("Expr::RecordUpdate::Fields", fields, fn(value) {
            self.elab_field_def(value)
          }),
        ),
      ])
    Field(record~, accessor~, loc=_) =>
      self.node("Expr::Field", [
        self.field("record", self.elab_expr(record)),
        self.field("accessor", self.elab_accessor(accessor)),
      ])
    Method(type_name~, method_name~, loc=_) =>
      self.node("Expr::Method", [
        self.field("type_name", self.elab_type_name(type_name)),
        self.field("method_name", self.elab_label(method_name)),
      ])
    DotApply(self=receiver, method_name~, args~, return_self~, attr~, loc=_) =>
      self.node("Expr::DotApply", [
        self.field("self", self.elab_expr(receiver)),
        self.field("method_name", self.elab_label(method_name)),
        self.field(
          "args",
          self.list_node("Expr::DotApply::Args", args, fn(value) {
            self.elab_argument(value)
          }),
        ),
        self.field_bool("return_self", return_self),
        self.field("attr", self.elab_apply_attr(attr)),
      ])
    As(expr~, trait_~, loc=_) =>
      self.node("Expr::As", [
        self.field("expr", self.elab_expr(expr)),
        self.field("trait", self.elab_type_name(trait_)),
      ])
    Mutate(record~, accessor~, field~, augmented_by~, loc=_) =>
      self.node("Expr::Mutate", [
        self.field("record", self.elab_expr(record)),
        self.field("accessor", self.elab_accessor(accessor)),
        self.field("field", self.elab_expr(field)),
        self.field_option("augmented_by", augmented_by, fn(value) {
          self.elab_var(value)
        }),
      ])
    Match(expr~, cases~, match_loc~, loc=_) =>
      self.node("Expr::Match", [
        self.field("match", self.keyword_atom(content="match", loc=match_loc)),
        self.field("expr", self.elab_expr(expr)),
        self.field(
          "cases",
          self.list_node("Expr::Match::Cases", cases, fn(value) {
            self.elab_case(value)
          }),
        ),
      ])
    LexMatch(strategy~, expr~, match_loc~, cases~, loc=_) =>
      self.node("Expr::LexMatch", [
        self.field(
          "match",
          self.keyword_atom(content="lexmatch", loc=match_loc),
        ),
        self.field_option("strategy", strategy, fn(value) {
          self.elab_label(value)
        }),
        self.field("expr", self.elab_expr(expr)),
        self.field(
          "cases",
          self.list_node("Expr::LexMatch::Cases", cases, fn(value) {
            self.elab_lex_case(value)
          }),
        ),
      ])
    LetMut(binder~, ty~, expr~, body~, loc=_) =>
      self.node("Expr::LetMut", [
        self.field("binder", self.elab_binder(binder)),
        self.field_option("ty", ty, fn(value) { self.elab_type(value) }),
        self.field("expr", self.elab_expr(expr)),
        self.field("body", self.elab_expr(body)),
      ])
    Pipe(lhs~, rhs~, loc=_) =>
      self.node("Expr::Pipe", [
        self.field("lhs", self.elab_expr(lhs)),
        self.field("rhs", self.elab_expr(rhs)),
      ])
    Assign(var_~, expr~, augmented_by~, loc=_) =>
      self.node("Expr::Assign", [
        self.field("var", self.elab_var(var_)),
        self.field("expr", self.elab_expr(expr)),
        self.field_option("augmented_by", augmented_by, fn(value) {
          self.elab_var(value)
        }),
      ])
    Expr::Hole(loc~, kind~) =>
      self.node("Expr::Hole", [self.field("kind", self.elab_hole(kind, loc))])
    Return(return_value~, loc~) =>
      self.node("Expr::Return", [
        self.field("return", self.keyword_atom(content="return", loc~)),
        self.field_option("return_value", return_value, fn(value) {
          self.elab_expr(value)
        }),
      ])
    Raise(err_value~, loc~) =>
      self.node("Expr::Raise", [
        self.field("raise", self.keyword_atom(content="raise", loc~)),
        self.field("err_value", self.elab_expr(err_value)),
      ])
    Unit(loc~, faked~) => {
      let token = if faked {
        self.node("Expr::Unit::Synthetic", [])
      } else {
        self.atom(content="()", loc~)
      }
      self.node("Expr::Unit", [
        self.field("token", token),
        self.field_bool("faked", faked),
      ])
    }
    Break(arg~, label~, loc~) =>
      self.node("Expr::Break", [
        self.field("break", self.keyword_atom(content="break", loc~)),
        self.field_option("arg", arg, fn(value) { self.elab_expr(value) }),
        self.field_option("label", label, fn(value) { self.elab_label(value) }),
      ])
    Continue(args~, label~, loc~) =>
      self.node("Expr::Continue", [
        self.field("continue", self.keyword_atom(content="continue", loc~)),
        self.field(
          "args",
          self.list_node("Expr::Continue::Args", args, fn(value) {
            self.elab_expr(value)
          }),
        ),
        self.field_option("label", label, fn(value) { self.elab_label(value) }),
      ])
    Loop(arg~, body~, label~, loop_loc~, loc=_) =>
      self.node("Expr::Loop", [
        self.field("loop", self.keyword_atom(content="loop", loc=loop_loc)),
        self.field("arg", self.elab_expr(arg)),
        self.field(
          "body",
          self.list_node("Expr::Loop::Body", body, fn(value) {
            self.elab_case(value)
          }),
        ),
        self.field_option("label", label, fn(value) { self.elab_label(value) }),
      ])
    For(
      binders~,
      condition~,
      continue_block~,
      body~,
      for_else~,
      where_clause~,
      label~,
      loc=_
    ) =>
      self.node("Expr::For", [
        self.field(
          "binders",
          self.list_node("Expr::For::Binders", binders, fn(value) {
            self.elab_binder_expr_pair(value)
          }),
        ),
        self.field_option("condition", condition, fn(value) {
          self.elab_expr(value)
        }),
        self.field(
          "continue_block",
          self.list_node("Expr::For::ContinueBlock", continue_block, fn(value) {
            self.elab_binder_expr_pair(value)
          }),
        ),
        self.field("body", self.elab_expr(body)),
        self.field_option("for_else", for_else, fn(value) {
          self.elab_expr(value)
        }),
        self.field_option("where_clause", where_clause, fn(value) {
          self.elab_where_clause(value)
        }),
        self.field_option("label", label, fn(value) { self.elab_label(value) }),
      ])
    ForEach(binders~, expr~, body~, else_block~, label~, loc=_) =>
      self.node("Expr::ForEach", [
        self.field(
          "binders",
          self.list_node("Expr::ForEach::Binders", binders, fn(value) {
            self.elab_optional_binder(value)
          }),
        ),
        self.field("expr", self.elab_expr(expr)),
        self.field("body", self.elab_expr(body)),
        self.field_option("else_block", else_block, fn(value) {
          self.elab_expr(value)
        }),
        self.field_option("label", label, fn(value) { self.elab_label(value) }),
      ])
    Try(
      body~,
      catch_~,
      catch_all~,
      try_else~,
      has_try~,
      try_loc~,
      catch_loc~,
      else_loc~,
      loc=_
    ) =>
      self.node("Expr::Try", [
        self.field("try", self.keyword_atom(content="try", loc=try_loc)),
        self.field("body", self.elab_expr(body)),
        self.field("catch", self.keyword_atom(content="catch", loc=catch_loc)),
        self.field(
          "catch_",
          self.list_node("Expr::Try::Catch", catch_, fn(value) {
            self.elab_case(value)
          }),
        ),
        self.field_bool("catch_all", catch_all),
        self.field(
          "try_else",
          self.option_node(try_else, fn(cases) {
            self.node("Expr::Try::Else", [
              self.keyword_atom(content="else", loc=else_loc),
              self.list_node("Expr::Try::Else::Cases", cases, fn(value) {
                self.elab_case(value)
              }),
            ])
          }),
        ),
        self.field_bool("has_try", has_try),
      ])
    TryOperator(body~, kind~, try_loc~, loc=_) =>
      self.node("Expr::TryOperator", [
        self.field("body", self.elab_expr(body)),
        self.field("kind", self.elab_try_operator_kind(kind)),
        self.field(
          "operator",
          self.keyword_atom(
            content=match kind {
              TryOperatorKind::Question => "?"
              Exclamation => "!"
            },
            loc=try_loc,
          ),
        ),
      ])
    Map(elems~, loc=_) =>
      self.node("Expr::Map", [
        self.list_node("Expr::Map::Elems", elems, fn(value) {
          self.elab_map_expr_elem(value)
        }),
      ])
    Group(expr~, group~, loc=_) =>
      self.node("Expr::Group", [
        self.field("expr", self.elab_expr(expr)),
        self.field("group", self.elab_group(group)),
      ])
    StaticAssert(asserts~, body~) =>
      // TODO: `Expr::StaticAssert` has no dedicated location in parser AST.
      self.node("Expr::StaticAssert", [
        self.field(
          "asserts",
          self.list_node("Expr::StaticAssert::Asserts", asserts, fn(value) {
            self.elab_static_assertion(value)
          }),
        ),
        self.field("body", self.elab_expr(body)),
      ])
  }
}
