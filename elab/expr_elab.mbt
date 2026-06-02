///|UUID(61de24a4-fcc3-48b7-a730-6260ff9e61ee)
fn ElabCtx::expr_loc(self : Self, expr : Expr) -> Location {
  match expr {
    StaticAssert(asserts~, body~) => {
      let mut loc = Some(self.expr_loc(body))
      asserts.each(fn(assertion) {
        loc = merge_loc_option(loc, Some(assertion.loc))
      })
      loc.unwrap_or(self.expr_loc(body))
    }
    _ => expr.loc()
  }
}

///|UUID(42338b7d-6aea-4cf6-9c53-7579f11e4d7d)
fn ElabCtx::pattern_loc(self : Self, pat : Pattern) -> Location {
  ignore(self)
  pat.loc()
}

///|UUID(ac1b66c1-e405-4a76-b584-dbceb8659760)
fn argument_kind_loc(kind : ArgumentKind) -> Location? {
  match kind {
    Positional => None
    Labelled(label~, equal_loc~) =>
      merge_loc_option(Some(label.loc), Some(equal_loc))
    LabelledPun(label) => Some(label.loc)
    LabelledOption(label~, question_loc~, equal_loc~) => {
      let loc = merge_loc_option(Some(label.loc), Some(question_loc))
      merge_loc_option(loc, Some(equal_loc))
    }
    LabelledOptionPun(label~, question_loc~) =>
      merge_loc_option(Some(label.loc), Some(question_loc))
  }
}

///|UUID(e4273ff6-fda9-4898-a9e1-d3dcd3d7eddd)
fn ElabCtx::argument_loc(self : Self, argument : Argument) -> Location {
  let mut loc = Some(self.expr_loc(argument.value))
  loc = merge_loc_option(loc, argument_kind_loc(argument.kind))
  loc.unwrap_or(self.expr_loc(argument.value))
}

///|UUID(2ced3e61-8cf2-404b-8ab1-9674bfe7117f)
fn ElabCtx::elab_argument(self : Self, argument : Argument) -> Syntax {
  let loc = self.argument_loc(argument)
  match argument.kind {
    Positional | LabelledPun(_) | LabelledOptionPun(..) =>
      self.region(loc, [self.part_expr(argument.value)])
    Labelled(label~, ..) | LabelledOption(label~, ..) =>
      self.region(loc, [self.part_label(label), self.part_expr(argument.value)])
  }
}

///|UUID(c57dbdcf-174c-40ba-a012-0df1a3c0f973)
fn ElabCtx::part_argument(self : Self, argument : Argument) -> Part {
  let loc = self.argument_loc(argument)
  self.part(self.elab_argument(argument), Some(loc))
}

///|UUID(0bd70c30-cfa3-4bb7-b2f1-0115b688ca9f)
fn ElabCtx::parameter_loc(self : Self, parameter : Parameter) -> Location {
  match parameter {
    DiscardPositional(ty~, loc~, colon_loc~) => {
      let mut full = Some(loc)
      full = merge_loc_option(full, colon_loc)
      full = merge_loc_option(full, ty.map(fn(ty) { self.type_loc(ty) }))
      full.unwrap_or(loc)
    }
    Positional(binder~, ty~, colon_loc~) => {
      let mut full = Some(binder.loc)
      full = merge_loc_option(full, colon_loc)
      full = merge_loc_option(full, ty.map(fn(ty) { self.type_loc(ty) }))
      full.unwrap_or(binder.loc)
    }
    Labelled(binder~, ty~, post_label_loc~, colon_loc~) => {
      let mut full = Some(binder.loc)
      full = merge_loc_option(full, post_label_loc)
      full = merge_loc_option(full, colon_loc)
      full = merge_loc_option(full, ty.map(fn(ty) { self.type_loc(ty) }))
      full.unwrap_or(binder.loc)
    }
    Optional(
      binder~,
      default~,
      ty~,
      post_label_loc~,
      question_loc~,
      colon_loc~,
      equal_loc~
    ) => {
      let mut full = Some(binder.loc)
      full = merge_loc_option(full, post_label_loc)
      full = merge_loc_option(full, question_loc)
      full = merge_loc_option(full, colon_loc)
      full = merge_loc_option(full, Some(equal_loc))
      full = merge_loc_option(full, ty.map(fn(ty) { self.type_loc(ty) }))
      full = merge_loc_option(full, Some(self.expr_loc(default)))
      full.unwrap_or(binder.loc)
    }
    QuestionOptional(binder~, ty~, question_loc~, colon_loc~) => {
      let mut full = Some(binder.loc)
      full = merge_loc_option(full, Some(question_loc))
      full = merge_loc_option(full, colon_loc)
      full = merge_loc_option(full, ty.map(fn(ty) { self.type_loc(ty) }))
      full.unwrap_or(binder.loc)
    }
  }
}

///|UUID(183a6ecd-6c9c-46fa-9faf-945d1e70ea88)
fn ElabCtx::elab_parameter(self : Self, parameter : Parameter) -> Syntax {
  let loc = self.parameter_loc(parameter)
  match parameter {
    DiscardPositional(ty~, loc=discard_loc, ..) => {
      let parts = Array::new()
      parts.push(self.part(self.tokenize_loc(discard_loc), Some(discard_loc)))
      self.append_part(parts, ty.map(fn(ty) { self.part_type(ty) }))
      self.region(loc, parts)
    }
    Positional(binder~, ty~, ..)
    | Labelled(binder~, ty~, ..)
    | QuestionOptional(binder~, ty~, ..) => {
      let parts = Array::new()
      parts.push(self.part_binder(binder))
      self.append_part(parts, ty.map(fn(ty) { self.part_type(ty) }))
      self.region(loc, parts)
    }
    Optional(binder~, default~, ty~, ..) => {
      let parts = Array::new()
      parts.push(self.part_binder(binder))
      self.append_part(parts, ty.map(fn(ty) { self.part_type(ty) }))
      parts.push(self.part_expr(default))
      self.region(loc, parts)
    }
  }
}

///|UUID(89ea4048-979d-4840-a2bb-7a729d9dc4f8)
fn ElabCtx::part_parameter(self : Self, parameter : Parameter) -> Part {
  let loc = self.parameter_loc(parameter)
  self.part(self.elab_parameter(parameter), Some(loc))
}

///|UUID(4ef38ae0-a02e-43b8-8ff7-f64a89e7af0f)
fn ElabCtx::case_loc(self : Self, case_ : Case) -> Location {
  let mut loc = Some(self.pattern_loc(case_.pattern))
  loc = merge_loc_option(
    loc,
    case_.guard_.map(fn(expr) { self.expr_loc(expr) }),
  )
  loc = merge_loc_option(loc, case_.if_loc)
  loc = merge_loc_option(loc, case_.fat_arrow_loc)
  loc = merge_loc_option(loc, Some(self.expr_loc(case_.body)))
  loc.unwrap_or(self.pattern_loc(case_.pattern))
}

///|UUID(06bcd4d0-bbf8-44ee-88c1-50579df54725)
fn ElabCtx::elab_case(self : Self, case_ : Case) -> Syntax {
  let loc = self.case_loc(case_)
  let parts = Array::new()
  parts.push(self.part_pattern(case_.pattern))
  self.append_part(parts, case_.guard_.map(fn(expr) { self.part_expr(expr) }))
  parts.push(self.part_expr(case_.body))
  self.region(loc, parts)
}

///|UUID(3b2f0c02-00cc-42be-8ac1-802b1f5aac14)
fn ElabCtx::part_case(self : Self, case_ : Case) -> Part {
  let loc = self.case_loc(case_)
  self.part(self.elab_case(case_), Some(loc))
}

///|UUID(8aa25c95-f70f-4ba0-96cb-110d1ec8ff88)
fn lex_pattern_loc(pat : LexPattern) -> Location {
  match pat {
    Regex(loc~, ..)
    | RegexInterp(loc~, ..)
    | ConstantRef(loc~, ..)
    | Alias(loc~, ..)
    | Sequence(loc~, ..) => loc
  }
}

///|UUID(25e49382-f18a-4f0d-baf4-5768eaeaa370)
fn lex_top_pattern_loc(pat : LexTopPattern) -> Location {
  match pat {
    Pattern(pat) => lex_pattern_loc(pat)
    Binder(binder) => binder.loc
    Wildcard(loc~) => loc
  }
}

///|UUID(0a7b2289-91b5-49ff-b15b-3a80a5c2c8e0)
fn ElabCtx::elab_lex_pattern(self : Self, pat : LexPattern) -> Syntax {
  match pat {
    Regex(loc~, ..) | RegexInterp(loc~, ..) => self.string_from_loc(loc)
    ConstantRef(lid~, loc~) => self.elab_long_ident(lid, loc, AtomKind::Normal)
    Alias(pat~, binder~, loc~, ..) =>
      self.region(loc, [
        self.part(self.elab_lex_pattern(pat), Some(lex_pattern_loc(pat))),
        self.part_binder(binder),
      ])
    Sequence(pats~, loc~, ..) =>
      self.region(
        loc,
        self.parts_from_list(pats, fn(pat) {
          self.part(self.elab_lex_pattern(pat), Some(lex_pattern_loc(pat)))
        }),
      )
  }
}

///|UUID(a0bd3b15-3330-465e-b5ff-9c15371cbb06)
fn ElabCtx::elab_lex_top_pattern(self : Self, pat : LexTopPattern) -> Syntax {
  match pat {
    Pattern(pat) => self.elab_lex_pattern(pat)
    Binder(binder) => self.elab_binder(binder)
    Wildcard(loc~) => self.tokenize_loc(loc, classify_keywords=true)
  }
}

///|UUID(6a9fbb10-091e-4e12-8a4b-24e5d54b0f2a)
fn ElabCtx::part_lex_top_pattern(self : Self, pat : LexTopPattern) -> Part {
  let loc = lex_top_pattern_loc(pat)
  self.part(self.elab_lex_top_pattern(pat), Some(loc))
}

///|UUID(b08668fa-6b53-43f4-b8f4-80666737fbdb)
fn ElabCtx::lex_case_loc(self : Self, case_ : LexCase) -> Location {
  let mut loc = Some(case_.pat_loc)
  loc = merge_loc_option(
    loc,
    case_.guard_.map(fn(expr) { self.expr_loc(expr) }),
  )
  loc = merge_loc_option(loc, case_.if_loc)
  loc = merge_loc_option(loc, case_.fat_arrow_loc)
  loc = merge_loc_option(loc, Some(self.expr_loc(case_.body)))
  loc.unwrap_or(case_.pat_loc)
}

///|UUID(1e4244d6-7ec2-4737-b9db-5805960d50f0)
fn ElabCtx::elab_lex_case(self : Self, case_ : LexCase) -> Syntax {
  let loc = self.lex_case_loc(case_)
  let pat_parts = self.parts_from_list(case_.pat, fn(pat) {
    self.part_lex_top_pattern(pat)
  })
  let pat_syntax = self.region(case_.pat_loc, pat_parts)
  let parts = Array::new()
  parts.push(self.part(pat_syntax, Some(case_.pat_loc)))
  self.append_part(parts, case_.guard_.map(fn(expr) { self.part_expr(expr) }))
  parts.push(self.part_expr(case_.body))
  self.region(loc, parts)
}

///|UUID(ca69de31-b988-4177-84bc-9170b72fb18a)
fn ElabCtx::part_lex_case(self : Self, case_ : LexCase) -> Part {
  let loc = self.lex_case_loc(case_)
  self.part(self.elab_lex_case(case_), Some(loc))
}

///|UUID(cf803cd3-2086-4b49-b751-c58573acb998)
fn regex_pattern_loc(pat : RegexPattern) -> Location {
  match pat {
    Literal(loc~, ..)
    | Reference(loc~, ..)
    | Sequence(loc~, ..)
    | Alternation(loc~, ..)
    | Alias(loc~, ..) => loc
  }
}

///|UUID(cf803cd3-2086-4b49-b751-c58573acb998)
fn ElabCtx::elab_regex_pattern(self : Self, pat : RegexPattern) -> Syntax {
  match pat {
    Literal(loc~, ..) => self.string_from_loc(loc)
    Reference(lid~, loc~) => self.elab_long_ident(lid, loc, AtomKind::Normal)
    Sequence(pat1~, pat2~, loc~, ..) | Alternation(pat1~, pat2~, loc~, ..) =>
      self.region(loc, [
        self.part(self.elab_regex_pattern(pat1), Some(regex_pattern_loc(pat1))),
        self.part(self.elab_regex_pattern(pat2), Some(regex_pattern_loc(pat2))),
      ])
    Alias(pat~, binder~, loc~, ..) =>
      self.region(loc, [
        self.part(self.elab_regex_pattern(pat), Some(regex_pattern_loc(pat))),
        self.part_binder(binder),
      ])
  }
}

///|UUID(cf803cd3-2086-4b49-b751-c58573acb998)
fn ElabCtx::part_regex_pattern(self : Self, pat : RegexPattern) -> Part {
  let loc = regex_pattern_loc(pat)
  self.part(self.elab_regex_pattern(pat), Some(loc))
}

///|UUID(cf803cd3-2086-4b49-b751-c58573acb998)
fn ElabCtx::elab_spreadable_elem(self : Self, elem : SpreadableElem) -> Syntax {
  match elem {
    Regular(expr) => self.elab_expr(expr)
    Spread(expr~, loc~, ..) => self.region(loc, [self.part_expr(expr)])
  }
}

///|UUID(8fcbb603-e83f-4fbf-b31f-f2864311befe)
fn ElabCtx::spreadable_elem_loc(self : Self, elem : SpreadableElem) -> Location {
  match elem {
    Regular(expr) => self.expr_loc(expr)
    Spread(loc~, ..) => loc
  }
}

///|UUID(3f331a03-b48b-43d1-bb8c-085630a5c8f7)
fn ElabCtx::part_spreadable_elem(self : Self, elem : SpreadableElem) -> Part {
  let loc = self.spreadable_elem_loc(elem)
  self.part(self.elab_spreadable_elem(elem), Some(loc))
}

///|UUID(d2e13d50-473e-4210-a13a-65b5fe4d51cd)
fn ElabCtx::elab_map_expr_elem(self : Self, elem : MapExprElem) -> Syntax {
  self.region(elem.loc, [
    self.part(self.elab_constant(elem.key, elem.key_loc), Some(elem.key_loc)),
    self.part_expr(elem.expr),
  ])
}

///|UUID(17b4e1d4-61bb-4d65-bd37-6c15bd4afc79)
fn ElabCtx::part_map_expr_elem(self : Self, elem : MapExprElem) -> Part {
  self.part(self.elab_map_expr_elem(elem), Some(elem.loc))
}

///|UUID(4033290e-d682-4221-a341-4032917c0566)
fn ElabCtx::elab_func(self : Self, func : Func) -> Syntax {
  let parts = Array::new()
  let param_parts = self.parts_from_list(func.parameters, fn(parameter) {
    self.part_parameter(parameter)
  })
  let params_syntax = match self.outer_delim_locs(func.params_loc, '(', ')') {
    Some((open_loc, close_loc)) =>
      self.delimited(open_loc, param_parts, close_loc)
    None => self.region(func.params_loc, param_parts)
  }
  parts.push(self.part(params_syntax, Some(func.params_loc)))
  self.append_part(parts, func.return_type.map(fn(ty) { self.part_type(ty) }))
  self.append_part(parts, self.part_error_type(func.error_type))
  let body_part = self
    .make_block_part(
      func.body_lbrace_loc,
      Some(func.body),
      func.body_rbrace_loc,
    )
    .unwrap_or(self.part_expr(func.body))
  parts.push(body_part)
  self.region(func.loc, parts)
}

///|UUID(41fb5be0-f951-45dd-bdb3-c817763009dc)
fn ElabCtx::part_func(self : Self, func : Func) -> Part {
  self.part(self.elab_func(func), Some(func.loc))
}

///|UUID(1be9d5ca-7c9f-48e4-a308-66686a25e11d)
fn ElabCtx::elab_field_def(self : Self, field : FieldDef) -> Syntax {
  if field.is_pun {
    self.region(field.loc, [self.part_expr(field.expr)])
  } else {
    self.region(field.loc, [
      self.part_label(field.label),
      self.part_expr(field.expr),
    ])
  }
}

///|UUID(c0fb8867-bd8c-4eb4-b97b-ee509881af07)
fn ElabCtx::part_field_def(self : Self, field : FieldDef) -> Part {
  self.part(self.elab_field_def(field), Some(field.loc))
}

///|UUID(7e7033c9-cac5-4f0c-a580-b848f0e89958)
fn ElabCtx::elab_where_clause(
  self : Self,
  where_clause : WhereClause,
) -> Syntax {
  let field_parts = self.parts_from_list(where_clause.fields, fn(field) {
    self.part_field_def(field)
  })
  let parts = Array::new()
  parts.push(
    self.part(
      self.delimited(
        where_clause.lbrace_loc,
        field_parts,
        where_clause.rbrace_loc,
      ),
      Some(where_clause.lbrace_loc.merge(where_clause.rbrace_loc)),
    ),
  )
  self.region(where_clause.loc, parts)
}

///|UUID(fb7669ef-f6a0-4d06-8ef4-a5120a0ef5e1)
fn ElabCtx::part_where_clause(self : Self, where_clause : WhereClause) -> Part {
  self.part(self.elab_where_clause(where_clause), Some(where_clause.loc))
}

///|UUID(cf7ec82c-47e9-4e1c-92ff-c511f2fd534f)
fn ElabCtx::elab_field_pat(self : Self, field : FieldPat) -> Syntax {
  if field.is_pun {
    self.region(field.loc, [self.part_pattern(field.pattern)])
  } else {
    self.region(field.loc, [
      self.part_label(field.label),
      self.part_pattern(field.pattern),
    ])
  }
}

///|UUID(4f060afc-96b0-46d1-8cd8-8aeab6966482)
fn ElabCtx::part_field_pat(self : Self, field : FieldPat) -> Part {
  self.part(self.elab_field_pat(field), Some(field.loc))
}

///|UUID(d3a3276a-ab31-4c3d-b5ea-c5cfcfe88de7)
fn ElabCtx::constr_pat_arg_loc(self : Self, arg : ConstrPatArg) -> Location {
  let mut loc = Some(self.pattern_loc(arg.pat))
  loc = merge_loc_option(loc, argument_kind_loc(arg.kind))
  loc = merge_loc_option(loc, arg.equal_loc)
  loc.unwrap_or(self.pattern_loc(arg.pat))
}

///|UUID(8c265480-60a5-4d57-903f-b9416720b2bb)
fn ElabCtx::elab_constr_pat_arg(self : Self, arg : ConstrPatArg) -> Syntax {
  let loc = self.constr_pat_arg_loc(arg)
  match arg.kind {
    Positional | LabelledPun(_) | LabelledOptionPun(..) =>
      self.region(loc, [self.part_pattern(arg.pat)])
    Labelled(label~, ..) | LabelledOption(label~, ..) =>
      self.region(loc, [self.part_label(label), self.part_pattern(arg.pat)])
  }
}

///|UUID(c6993733-9f50-4dc4-8fce-317df1f913d3)
fn ElabCtx::part_constr_pat_arg(self : Self, arg : ConstrPatArg) -> Part {
  let loc = self.constr_pat_arg_loc(arg)
  self.part(self.elab_constr_pat_arg(arg), Some(loc))
}

///|UUID(2457474d-18fa-46e9-bc60-7b6334e3856a)
fn ElabCtx::elab_map_pat_elem(self : Self, elem : MapPatElem) -> Syntax {
  self.region(elem.loc, [
    self.part(self.elab_constant(elem.key, elem.key_loc), Some(elem.key_loc)),
    self.part_pattern(elem.pat),
  ])
}

///|UUID(781e1f35-55ae-434a-b840-dd903832c85c)
fn ElabCtx::part_map_pat_elem(self : Self, elem : MapPatElem) -> Part {
  self.part(self.elab_map_pat_elem(elem), Some(elem.loc))
}

///|UUID(af52eb7b-c8b0-484d-97b0-2ed9ef9eef77)
fn array_pattern_loc(pattern : ArrayPattern) -> Location {
  match pattern {
    Pattern(pat) => pat.loc()
    StringSpread(loc~, dotdot_loc~, ..) | BytesSpread(loc~, dotdot_loc~, ..) =>
      merge_loc_option(Some(loc), Some(dotdot_loc)).unwrap_or(loc)
    ConstSpread(loc~, dotdot_loc~, ..) =>
      merge_loc_option(Some(loc), Some(dotdot_loc)).unwrap_or(loc)
  }
}

///|UUID(1051e876-f9a4-4ecc-8d20-2b9012b86f0a)
fn ElabCtx::elab_array_pattern(self : Self, pat : ArrayPattern) -> Syntax {
  match pat {
    ArrayPattern::Pattern(pat) => self.elab_pattern(pat)
    StringSpread(loc=literal_loc, dotdot_loc~, ..) => {
      let loc = merge_loc_option(Some(literal_loc), Some(dotdot_loc)).unwrap_or(
        literal_loc,
      )
      self.region(loc, [
        self.part(self.string_from_loc(literal_loc), Some(literal_loc)),
      ])
    }
    BytesSpread(loc=literal_loc, dotdot_loc~, ..) => {
      let loc = merge_loc_option(Some(literal_loc), Some(dotdot_loc)).unwrap_or(
        literal_loc,
      )
      self.region(loc, [
        self.part(self.string_from_loc(literal_loc), Some(literal_loc)),
      ])
    }
    ConstSpread(binder~, loc~, ..) =>
      self.region(loc, [self.part_binder(binder)])
  }
}

///|UUID(8fd6d4a1-9bfc-4bfd-b5c2-c8f7237189be)
fn ElabCtx::part_array_pattern(self : Self, pat : ArrayPattern) -> Part {
  let loc = array_pattern_loc(pat)
  self.part(self.elab_array_pattern(pat), Some(loc))
}

///|UUID(f163a85d-6d5d-4a7e-bd39-9af8b93d14e6)
fn ElabCtx::dotdot_binder_part(self : Self, binder : DotDotBinder) -> Part? {
  match binder {
    BinderAs(binder~, ..) | DotDotBinder::Binder(binder~, ..) =>
      Some(self.part_binder(binder))
    Underscore(..) | NoBinder(..) => None
  }
}

///|UUID(4f3b7cb3-da7f-43c0-a588-7e6b1c80446a)
fn ElabCtx::array_pattern_parts(
  self : Self,
  patterns : ArrayPatterns,
) -> Array[Part] {
  match patterns {
    Closed(items, ..) =>
      self.parts_from_list(items, fn(item) { self.part_array_pattern(item) })
    Open(prefix, suffix, binder, ..) => {
      let parts = self.parts_from_list(prefix, fn(item) {
        self.part_array_pattern(item)
      })
      self.append_part(parts, self.dotdot_binder_part(binder))
      parts.push_iter(
        self
        .parts_from_list(suffix, fn(item) { self.part_array_pattern(item) })
        .iter(),
      )
      parts
    }
  }
}

///|UUID(16357efa-aba6-4c12-8349-55ac81a81c57)
pub fn ElabCtx::elab_pattern(self : Self, pat : Pattern) -> Syntax {
  match pat {
    Alias(pat~, alias_~, loc~, ..) =>
      self.region(loc, [self.part_pattern(pat), self.part_binder(alias_)])
    Any(loc~) => self.tokenize_loc(loc, classify_keywords=true)
    Pattern::Array(pats~, loc~, lbracket_loc~, rbracket_loc~) =>
      self.delimited_or_region(
        loc,
        Some(lbracket_loc),
        self.array_pattern_parts(pats),
        Some(rbracket_loc),
      )
    Constant(c~, loc~) => self.elab_constant(c, loc)
    Constraint(pat~, ty~, loc~, ..) =>
      self.outer_delimited_or_region(loc, '(', ')', [
        self.part_pattern(pat),
        self.part_type(ty),
      ])
    Constr(constr~, args~, loc~, args_lparen_loc~, args_rparen_loc~, ..) => {
      let parts = Array::new()
      parts.push(self.part(self.elab_constructor(constr), Some(constr.loc)))
      match args {
        Some(args) => {
          let arg_parts = self.parts_from_list(args, fn(arg) {
            self.part_constr_pat_arg(arg)
          })
          let arg_loc = match
            (args_lparen_loc, args_rparen_loc, merge_part_locs(arg_parts)) {
            (Some(lparen_loc), Some(rparen_loc), _) =>
              Some(lparen_loc.merge(rparen_loc))
            (_, _, Some(arg_loc)) => Some(arg_loc)
            _ => None
          }
          self.append_part(
            parts,
            arg_loc.map(fn(arg_loc) {
              self.part(
                self.delimited_or_region(
                  arg_loc, args_lparen_loc, arg_parts, args_rparen_loc,
                ),
                Some(arg_loc),
              )
            }),
          )
        }
        None =>
          if args_lparen_loc is Some(lparen_loc) &&
            args_rparen_loc is Some(rparen_loc) {
            let arg_loc = lparen_loc.merge(rparen_loc)
            parts.push(
              self.part(
                self.delimited(lparen_loc, [], rparen_loc),
                Some(arg_loc),
              ),
            )
          }
      }
      self.region(loc, parts)
    }
    Or(pat1~, pat2~, loc~, ..) =>
      self.region(loc, [self.part_pattern(pat1), self.part_pattern(pat2)])
    Tuple(pats~, loc~, lparen_loc~, rparen_loc~, ..) =>
      self.delimited_or_region(
        loc,
        Some(lparen_loc),
        self.parts_from_list(pats, fn(pat) { self.part_pattern(pat) }),
        Some(rparen_loc),
      )
    Pattern::Var(binder) => self.elab_binder(binder)
    Record(fields~, loc~, lbrace_loc~, rbrace_loc~, ..) =>
      self.delimited_or_region(
        loc,
        Some(lbrace_loc),
        self.parts_from_list(fields, fn(field) { self.part_field_pat(field) }),
        Some(rbrace_loc),
      )
    Map(elems~, loc~, lbrace_loc~, rbrace_loc~, ..) =>
      self.delimited_or_region(
        loc,
        Some(lbrace_loc),
        self.parts_from_list(elems, fn(elem) { self.part_map_pat_elem(elem) }),
        Some(rbrace_loc),
      )
    Range(lhs~, rhs~, loc~, ..) =>
      self.region(loc, [self.part_pattern(lhs), self.part_pattern(rhs)])
    SpecialConstr(binder~, args~, loc~, ..) => {
      let parts = Array::new()
      parts.push(self.part_binder(binder))
      parts.push_iter(
        self
        .parts_from_list(args, fn(arg) { self.part_constr_pat_arg(arg) })
        .iter(),
      )
      self.region(loc, parts)
    }
  }
}

///|UUID(7043dcb6-12e7-4439-9596-1d1f854cdfc0)
fn ElabCtx::binder_expr_pair_loc(
  self : Self,
  pair : (Binder, Expr),
) -> Location {
  let (binder, expr) = pair
  binder.loc.merge(self.expr_loc(expr))
}

///|UUID(ddd37f3e-c143-42a8-8cbc-63e060af5ec4)
fn ElabCtx::binder_type_func_triple_loc(
  self : Self,
  triple : (Binder, Type?, Func),
) -> Location {
  let (binder, ty, func) = triple
  let mut loc = Some(binder.loc)
  loc = merge_loc_option(loc, ty.map(fn(ty) { self.type_loc(ty) }))
  loc = merge_loc_option(loc, Some(func.loc))
  loc.unwrap_or(binder.loc)
}

///|UUID(5f0b57ae-0c1d-4bcc-b77b-2bcb66fc2e53)
fn ElabCtx::part_binder_expr_pair(self : Self, pair : (Binder, Expr)) -> Part {
  let loc = self.binder_expr_pair_loc(pair)
  let (binder, expr) = pair
  self.part(
    self.region(loc, [self.part_binder(binder), self.part_expr(expr)]),
    Some(loc),
  )
}

///|UUID(c4040a96-a4f1-43f1-ad68-50b236dbf9b5)
fn ElabCtx::part_binder_type_func_triple(
  self : Self,
  triple : (Binder, Type?, Func),
) -> Part {
  let loc = self.binder_type_func_triple_loc(triple)
  let (binder, ty, func) = triple
  let parts = Array::new()
  parts.push(self.part_binder(binder))
  self.append_part(parts, ty.map(fn(ty) { self.part_type(ty) }))
  parts.push(self.part_func(func))
  self.part(self.region(loc, parts), Some(loc))
}

///|UUID(e523b5fc-1f77-4eec-8d17-69f7881a1988)
fn ElabCtx::optional_binder_part(self : Self, binder : Binder?) -> Part? {
  binder.map(fn(binder) { self.part_binder(binder) })
}

///|UUID(b6283c55-4a56-4fa1-8a8d-0a21b5099c84)
fn ElabCtx::list_comprehension_kind_parts(
  self : Self,
  kind : ListComprehensionKind,
) -> Array[Part] {
  let parts = Array::new()
  match kind {
    Foreach(binders~, expr~, init~, continue_block~, ..) => {
      binders.each(fn(binder) {
        self.append_part(parts, self.optional_binder_part(binder))
      })
      parts.push(self.part_expr(expr))
      parts.push_iter(
        self
        .parts_from_list(init, fn(binding) {
          self.part_binder_expr_pair(binding)
        })
        .iter(),
      )
      parts.push_iter(
        self
        .parts_from_list(continue_block, fn(binding) {
          self.part_binder_expr_pair(binding)
        })
        .iter(),
      )
    }
    For(binders~, condition~, continue_block~, ..) => {
      parts.push_iter(
        self
        .parts_from_list(binders, fn(binding) {
          self.part_binder_expr_pair(binding)
        })
        .iter(),
      )
      self.append_part(parts, condition.map(fn(expr) { self.part_expr(expr) }))
      parts.push_iter(
        self
        .parts_from_list(continue_block, fn(binding) {
          self.part_binder_expr_pair(binding)
        })
        .iter(),
      )
    }
  }
  parts
}

///|UUID(b6283c55-4a56-4fa1-8a8d-0a21b5099c84)
fn ElabCtx::make_block_part(
  self : Self,
  open_loc : Location?,
  body : Expr?,
  close_loc : Location?,
) -> Part? {
  match (open_loc, close_loc, body) {
    (Some(open_loc), Some(close_loc), Some(body)) => {
      let loc = open_loc.merge(close_loc)
      Some(
        self.part(
          self.delimited(open_loc, self.block_stmt_parts(body), close_loc),
          Some(loc),
        ),
      )
    }
    (Some(open_loc), Some(close_loc), None) => {
      let loc = open_loc.merge(close_loc)
      Some(self.part(self.delimited(open_loc, [], close_loc), Some(loc)))
    }
    (_, _, Some(body)) => Some(self.part_expr(body))
    _ => None
  }
}

///|UUID(0fec1456-4021-453c-b5d2-b0dd0947559a)
fn ElabCtx::make_cases_block_part(
  self : Self,
  open_loc : Location?,
  cases : @list.List[Case],
  close_loc : Location?,
) -> Part? {
  match (open_loc, close_loc) {
    (Some(open_loc), Some(close_loc)) => {
      let loc = open_loc.merge(close_loc)
      let case_parts = self.parts_from_list(cases, fn(case_) {
        self.part_case(case_)
      })
      Some(
        self.part(self.delimited(open_loc, case_parts, close_loc), Some(loc)),
      )
    }
    _ =>
      match merge_loc_list(cases.map(fn(case_) { self.case_loc(case_) })) {
        Some(loc) =>
          Some(
            self.part(
              self.region(
                loc,
                self.parts_from_list(cases, fn(case_) { self.part_case(case_) }),
              ),
              Some(loc),
            ),
          )
        None => None
      }
  }
}

///|UUID(08d3faf4-4ce1-4ae6-bf66-26cd0afaf607)
fn ElabCtx::make_lex_cases_block_part(
  self : Self,
  open_loc : Location?,
  cases : @list.List[LexCase],
  close_loc : Location?,
) -> Part? {
  match (open_loc, close_loc) {
    (Some(open_loc), Some(close_loc)) => {
      let loc = open_loc.merge(close_loc)
      let case_parts = self.parts_from_list(cases, fn(case_) {
        self.part_lex_case(case_)
      })
      Some(
        self.part(self.delimited(open_loc, case_parts, close_loc), Some(loc)),
      )
    }
    _ =>
      match
        merge_part_locs(
          self.parts_from_list(cases, fn(case_) { self.part_lex_case(case_) }),
        ) {
        Some(loc) =>
          Some(
            self.part(
              self.region(
                loc,
                self.parts_from_list(cases, fn(case_) {
                  self.part_lex_case(case_)
                }),
              ),
              Some(loc),
            ),
          )
        None => None
      }
  }
}

///|UUID(6f6ca728-c4dc-4c8a-89ec-c4f6d9878991)
fn ElabCtx::part_guard_stmt(
  self : Self,
  cond : Expr,
  otherwise : Expr?,
  guard_loc : Location?,
  else_loc : Location?,
  else_lbrace_loc : Location?,
  else_rbrace_loc : Location?,
  else_trailing_semi_loc : Location?,
  semi_loc : Location?,
) -> Part {
  let parts = Array::new()
  parts.push(self.part_expr(cond))
  self.append_part(
    parts,
    otherwise.map(fn(expr) {
      self
      .make_block_part(else_lbrace_loc, Some(expr), else_rbrace_loc)
      .unwrap_or(self.part_expr(expr))
    }),
  )
  let mut loc = merge_part_locs(parts)
  loc = merge_loc_option(loc, guard_loc)
  loc = merge_loc_option(loc, else_loc)
  loc = merge_loc_option(loc, else_trailing_semi_loc)
  loc = merge_loc_option(loc, semi_loc)
  let loc = loc.unwrap_or(self.expr_loc(cond))
  self.part(self.region(loc, parts), Some(loc))
}

///|UUID(3672ec6f-bcec-4526-b448-4c038a96b8f1)
fn ElabCtx::part_defer_stmt(
  self : Self,
  expr : Expr,
  defer_loc : Location?,
  semi_loc : Location?,
) -> Part {
  let parts = [self.part_expr(expr)]
  let mut loc = merge_part_locs(parts)
  loc = merge_loc_option(loc, defer_loc)
  loc = merge_loc_option(loc, semi_loc)
  let loc = loc.unwrap_or(self.expr_loc(expr))
  self.part(self.region(loc, parts), Some(loc))
}

///|UUID(7576d9df-3fcf-4bbe-8853-25ad3dc366ca)
fn ElabCtx::part_let_fn_stmt(
  self : Self,
  name : Binder,
  func : Func,
  fn_loc : Location?,
  semi_loc : Location?,
) -> Part {
  let parts = [self.part_binder(name), self.part_func(func)]
  let mut loc = merge_part_locs(parts)
  loc = merge_loc_option(loc, fn_loc)
  loc = merge_loc_option(loc, semi_loc)
  let loc = loc.unwrap_or(name.loc.merge(func.loc))
  self.part(self.region(loc, parts), Some(loc))
}

///|UUID(5d6933ec-6fee-4928-8b9c-dce90ad2d428)
fn ElabCtx::part_letand_stmt(
  self : Self,
  bindings : @list.List[(Binder, Type?, Func)],
  letrec_loc : Location?,
  semi_loc : Location?,
) -> Part {
  let parts = self.parts_from_list(bindings, fn(binding) {
    self.part_binder_type_func_triple(binding)
  })
  let mut loc = merge_part_locs(parts)
  loc = merge_loc_option(loc, letrec_loc)
  loc = merge_loc_option(loc, semi_loc)
  let loc = loc.unwrap_or_else(fn() { panic() })
  self.part(self.region(loc, parts), Some(loc))
}

///|UUID(c529f7b6-c8de-4fe9-a303-f094558eb9f3)
fn ElabCtx::part_let_stmt(
  self : Self,
  pattern : Pattern,
  expr : Expr,
  let_loc : Location?,
  equal_loc : Location?,
  semi_loc : Location?,
) -> Part {
  let parts = [self.part_pattern(pattern), self.part_expr(expr)]
  let mut loc = merge_part_locs(parts)
  loc = merge_loc_option(loc, let_loc)
  loc = merge_loc_option(loc, equal_loc)
  loc = merge_loc_option(loc, semi_loc)
  let loc = loc.unwrap_or(self.pattern_loc(pattern).merge(self.expr_loc(expr)))
  self.part(self.region(loc, parts), Some(loc))
}

///|UUID(1e7c1eca-657c-4fd2-9387-15b1d23b071c)
fn ElabCtx::part_letmut_stmt(
  self : Self,
  binder : Binder,
  ty : Type?,
  expr : Expr,
  let_loc : Location?,
  mut_loc : Location?,
  equal_loc : Location?,
  semi_loc : Location?,
) -> Part {
  let parts = Array::new()
  parts.push(self.part_binder(binder))
  self.append_part(parts, ty.map(fn(ty) { self.part_type(ty) }))
  parts.push(self.part_expr(expr))
  let mut loc = merge_part_locs(parts)
  loc = merge_loc_option(loc, let_loc)
  loc = merge_loc_option(loc, mut_loc)
  loc = merge_loc_option(loc, equal_loc)
  loc = merge_loc_option(loc, semi_loc)
  let loc = loc.unwrap_or(binder.loc.merge(self.expr_loc(expr)))
  self.part(self.region(loc, parts), Some(loc))
}

///|UUID(66408798-0e70-4af3-a3f4-52bc8fdd3c09)
fn ElabCtx::append_stmt_chain_parts(
  self : Self,
  parts : Array[Part],
  expr : Expr,
) -> Unit {
  match expr {
    Guard(
      cond~,
      otherwise~,
      body~,
      loc=_,
      guard_loc~,
      else_loc~,
      else_lbrace_loc~,
      else_rbrace_loc~,
      semi_loc~
    ) => {
      parts.push(
        self.part_guard_stmt(
          cond,
          otherwise,
          Some(guard_loc),
          else_loc,
          else_lbrace_loc,
          else_rbrace_loc,
          None,
          semi_loc,
        ),
      )
      self.append_stmt_chain_parts(parts, body)
    }
    Defer(expr~, body~, loc=_, defer_loc~, semi_loc~) => {
      parts.push(self.part_defer_stmt(expr, Some(defer_loc), semi_loc))
      self.append_stmt_chain_parts(parts, body)
    }
    LetFn(name~, func~, body~, loc=_, semi_loc~) => {
      parts.push(self.part_let_fn_stmt(name, func, func.fn_loc, semi_loc))
      self.append_stmt_chain_parts(parts, body)
    }
    LetAnd(bindings~, body~, loc=_, letrec_loc~, semi_loc~, ..) => {
      parts.push(self.part_letand_stmt(bindings, Some(letrec_loc), semi_loc))
      self.append_stmt_chain_parts(parts, body)
    }
    Let(
      pattern~,
      expr=bound_expr,
      body~,
      loc=_,
      let_loc~,
      equal_loc~,
      semi_loc~,
      ..
    ) => {
      parts.push(
        self.part_let_stmt(
          pattern,
          bound_expr,
          Some(let_loc),
          Some(equal_loc),
          semi_loc,
        ),
      )
      self.append_stmt_chain_parts(parts, body)
    }
    LetMut(
      binder~,
      ty~,
      expr=bound_expr,
      body~,
      loc=_,
      let_loc~,
      mut_loc~,
      equal_loc~,
      semi_loc~,
      ..
    ) => {
      parts.push(
        self.part_letmut_stmt(
          binder,
          ty,
          bound_expr,
          Some(let_loc),
          Some(mut_loc),
          Some(equal_loc),
          semi_loc,
        ),
      )
      self.append_stmt_chain_parts(parts, body)
    }
    _ => parts.push(self.part_expr(expr))
  }
}

///|UUID(5f2cf05c-07bb-4111-af54-b216275267de)
fn ElabCtx::append_block_stmt_parts(
  self : Self,
  parts : Array[Part],
  expr : Expr,
) -> Unit {
  match expr {
    Sequence(exprs~, last_expr~, ..) => {
      exprs.each(fn(expr) { self.append_block_stmt_parts(parts, expr) })
      self.append_block_stmt_parts(parts, last_expr)
    }
    _ => self.append_block_stmt_chain_parts(parts, expr)
  }
}

///|UUID(b95c5c39-91b8-4b5b-aa10-d2f1a21c168d)
fn ElabCtx::append_block_stmt_chain_parts(
  self : Self,
  parts : Array[Part],
  expr : Expr,
) -> Unit {
  match expr {
    Guard(
      cond~,
      otherwise~,
      body~,
      loc=_,
      guard_loc~,
      else_loc~,
      else_lbrace_loc~,
      else_rbrace_loc~,
      semi_loc~
    ) => {
      parts.push(
        self.part_guard_stmt(
          cond,
          otherwise,
          Some(guard_loc),
          else_loc,
          else_lbrace_loc,
          else_rbrace_loc,
          None,
          semi_loc,
        ),
      )
      self.append_block_stmt_parts(parts, body)
    }
    Defer(expr~, body~, loc=_, defer_loc~, semi_loc~) => {
      parts.push(self.part_defer_stmt(expr, Some(defer_loc), semi_loc))
      self.append_block_stmt_parts(parts, body)
    }
    LetFn(name~, func~, body~, loc=_, semi_loc~) => {
      parts.push(self.part_let_fn_stmt(name, func, func.fn_loc, semi_loc))
      self.append_block_stmt_parts(parts, body)
    }
    LetAnd(bindings~, body~, loc=_, letrec_loc~, semi_loc~, ..) => {
      parts.push(self.part_letand_stmt(bindings, Some(letrec_loc), semi_loc))
      self.append_block_stmt_parts(parts, body)
    }
    Let(
      pattern~,
      expr=bound_expr,
      body~,
      loc=_,
      let_loc~,
      equal_loc~,
      semi_loc~,
      ..
    ) => {
      parts.push(
        self.part_let_stmt(
          pattern,
          bound_expr,
          Some(let_loc),
          Some(equal_loc),
          semi_loc,
        ),
      )
      self.append_block_stmt_parts(parts, body)
    }
    LetMut(
      binder~,
      ty~,
      expr=bound_expr,
      body~,
      loc=_,
      let_loc~,
      mut_loc~,
      equal_loc~,
      semi_loc~,
      ..
    ) => {
      parts.push(
        self.part_letmut_stmt(
          binder,
          ty,
          bound_expr,
          Some(let_loc),
          Some(mut_loc),
          Some(equal_loc),
          semi_loc,
        ),
      )
      self.append_block_stmt_parts(parts, body)
    }
    _ => parts.push(self.part_expr(expr))
  }
}

///|UUID(8c8bc1b7-18c4-4789-a9eb-ee19dd3a1cf7)
fn ElabCtx::block_stmt_parts(self : Self, expr : Expr) -> Array[Part] {
  let parts = Array::new()
  self.append_block_stmt_parts(parts, expr)
  parts
}

///|UUID(82d65bb4-51f7-460a-8674-b33819aad968)
fn accessor_loc(accessor : Accessor) -> Location {
  match accessor {
    Label(label) => label.loc
    Index(loc~, ..) | Newtype(loc~) => loc
  }
}

///|UUID(6d24eb1c-1e72-444a-bfbb-5a9804ff3da7)
pub fn ElabCtx::elab_expr(self : Self, expr : Expr) -> Syntax {
  match expr {
    Apply(func~, args~, loc~, lparen_loc~, rparen_loc~, ..) => {
      let parts = Array::new()
      parts.push(self.part_expr(func))
      let arg_loc = lparen_loc.merge(rparen_loc)
      parts.push(
        self.part(
          self.delimited(
            lparen_loc,
            self.parts_from_list(args, fn(arg) { self.part_argument(arg) }),
            rparen_loc,
          ),
          Some(arg_loc),
        ),
      )
      self.region(loc, parts)
    }
    Infix(op~, lhs~, rhs~, loc~) =>
      self.region(loc, [
        self.part_expr(lhs),
        self.part(self.elab_var(op), Some(op.loc)),
        self.part_expr(rhs),
      ])
    Unary(op~, expr~, loc~) =>
      self.region(loc, [
        self.part(self.elab_var(op), Some(op.loc)),
        self.part_expr(expr),
      ])
    Array(exprs~, loc~, lbracket_loc~, rbracket_loc~, ..) =>
      self.delimited_or_region(
        loc,
        Some(lbracket_loc),
        self.parts_from_list(exprs, fn(expr) { self.part_expr(expr) }),
        Some(rbracket_loc),
      )
    ArraySpread(elems~, loc~, lbracket_loc~, rbracket_loc~, ..) =>
      self.delimited_or_region(
        loc,
        Some(lbracket_loc),
        self.parts_from_list(elems, fn(elem) { self.part_spreadable_elem(elem) }),
        Some(rbracket_loc),
      )
    ListComprehension(
      kind~,
      guard_~,
      body~,
      loc~,
      lbracket_loc~,
      rbracket_loc~,
      ..
    ) => {
      let parts = self.list_comprehension_kind_parts(kind)
      self.append_part(parts, guard_.map(fn(expr) { self.part_expr(expr) }))
      parts.push(self.part_expr(body))
      self.delimited_or_region(
        loc,
        Some(lbracket_loc),
        parts,
        Some(rbracket_loc),
      )
    }
    ArrayGet(array~, index~, lbracket_loc~, rbracket_loc~, loc~) => {
      let parts = Array::new()
      parts.push(self.part_expr(array))
      let bracket_loc = lbracket_loc.merge(rbracket_loc)
      parts.push(
        self.part(
          self.delimited(lbracket_loc, [self.part_expr(index)], rbracket_loc),
          Some(bracket_loc),
        ),
      )
      self.region(loc, parts)
    }
    ArrayGetSlice(
      array~,
      start_index~,
      end_index~,
      lbracket_loc~,
      rbracket_loc~,
      loc~,
      ..
    ) => {
      let parts = Array::new()
      parts.push(self.part_expr(array))
      let index_parts = Array::new()
      self.append_part(
        index_parts,
        start_index.map(fn(expr) { self.part_expr(expr) }),
      )
      self.append_part(
        index_parts,
        end_index.map(fn(expr) { self.part_expr(expr) }),
      )
      let index_loc = lbracket_loc.merge(rbracket_loc)
      parts.push(
        self.part(
          self.delimited(lbracket_loc, index_parts, rbracket_loc),
          Some(index_loc),
        ),
      )
      self.region(loc, parts)
    }
    ArraySet(array~, index~, value~, lbracket_loc~, rbracket_loc~, loc~, ..) => {
      let parts = Array::new()
      parts.push(self.part_expr(array))
      let bracket_loc = lbracket_loc.merge(rbracket_loc)
      parts.push(
        self.part(
          self.delimited(lbracket_loc, [self.part_expr(index)], rbracket_loc),
          Some(bracket_loc),
        ),
      )
      parts.push(self.part_expr(value))
      self.region(loc, parts)
    }
    ArrayAugmentedSet(
      array~,
      index~,
      value~,
      lbracket_loc~,
      rbracket_loc~,
      loc~,
      ..
    ) => {
      let parts = Array::new()
      parts.push(self.part_expr(array))
      let bracket_loc = lbracket_loc.merge(rbracket_loc)
      parts.push(
        self.part(
          self.delimited(lbracket_loc, [self.part_expr(index)], rbracket_loc),
          Some(bracket_loc),
        ),
      )
      parts.push(self.part_expr(value))
      self.region(loc, parts)
    }
    Constant(c~, loc~) => self.elab_constant(c, loc)
    MultilineString(loc~, ..) | Interp(loc~, ..) => self.string_from_loc(loc)
    Constraint(expr~, ty~, loc~, ..) =>
      self.outer_delimited_or_region(loc, '(', ')', [
        self.part_expr(expr),
        self.part_type(ty),
      ])
    Constr(constr~, ..) => self.elab_constructor(constr)
    While(
      loop_cond~,
      loop_body~,
      while_else~,
      label~,
      loc~,
      body_lbrace_loc~,
      body_rbrace_loc~,
      nobreak_lbrace_loc~,
      nobreak_rbrace_loc~,
      ..
    ) => {
      let parts = Array::new()
      self.append_part(parts, label.map(fn(label) { self.part_label(label) }))
      parts.push(self.part_expr(loop_cond))
      self.append_part(
        parts,
        self.make_block_part(
          Some(body_lbrace_loc),
          Some(loop_body),
          Some(body_rbrace_loc),
        ),
      )
      self.append_part(
        parts,
        while_else.map(fn(expr) {
          self
          .make_block_part(nobreak_lbrace_loc, Some(expr), nobreak_rbrace_loc)
          .unwrap_or(self.part_expr(expr))
        }),
      )
      self.region(loc, parts)
    }
    Function(func~, ..) => self.elab_func(func)
    Ident(id~, ..) => self.elab_var(id)
    If(
      cond~,
      ifso~,
      ifnot~,
      loc~,
      then_lbrace_loc~,
      then_rbrace_loc~,
      else_lbrace_loc~,
      else_rbrace_loc~,
      ..
    ) => {
      let parts = Array::new()
      parts.push(self.part_expr(cond))
      self.append_part(
        parts,
        self.make_block_part(
          Some(then_lbrace_loc),
          Some(ifso),
          Some(then_rbrace_loc),
        ),
      )
      self.append_part(
        parts,
        ifnot.map(fn(expr) {
          self
          .make_block_part(else_lbrace_loc, Some(expr), else_rbrace_loc)
          .unwrap_or(self.part_expr(expr))
        }),
      )
      self.region(loc, parts)
    }
    Guard(
      cond~,
      otherwise~,
      body~,
      loc~,
      guard_loc~,
      else_loc~,
      else_lbrace_loc~,
      else_rbrace_loc~,
      semi_loc~
    ) => {
      let parts = Array::new()
      parts.push(
        self.part_guard_stmt(
          cond,
          otherwise,
          Some(guard_loc),
          else_loc,
          else_lbrace_loc,
          else_rbrace_loc,
          None,
          semi_loc,
        ),
      )
      self.append_stmt_chain_parts(parts, body)
      self.region(loc, parts)
    }
    Is(expr~, pat~, loc~, ..) =>
      self.region(loc, [self.part_expr(expr), self.part_pattern(pat)])
    IsLexMatch(expr~, strategy~, pat~, pat_loc~, loc~, ..) => {
      let parts = Array::new()
      parts.push(self.part_expr(expr))
      parts.push(
        self.part(
          self.region(
            pat_loc,
            self.parts_from_list(pat, fn(pat) { self.part_lex_top_pattern(pat) }),
          ),
          Some(pat_loc),
        ),
      )
      self.append_part(
        parts,
        strategy.map(fn(label) { self.part_label(label) }),
      )
      self.region(loc, parts)
    }
    RegexMatch(expr~, pat~, bindings~, loc~, ..) => {
      let parts = Array::new()
      parts.push(self.part_expr(expr))
      parts.push(self.part_regex_pattern(pat))
      bindings.each(fn(binding) {
        let (label, binder) = binding
        parts.push(self.part_label(label))
        self.append_part(
          parts,
          binder.map(fn(binder) { self.part_binder(binder) }),
        )
      })
      self.region(loc, parts)
    }
    Defer(expr~, body~, loc~, defer_loc~, semi_loc~) => {
      let parts = [self.part_defer_stmt(expr, Some(defer_loc), semi_loc)]
      self.append_stmt_chain_parts(parts, body)
      self.region(loc, parts)
    }
    LetFn(name~, func~, body~, loc~, semi_loc~) => {
      let parts = [self.part_let_fn_stmt(name, func, func.fn_loc, semi_loc)]
      self.append_stmt_chain_parts(parts, body)
      self.region(loc, parts)
    }
    LetAnd(bindings~, body~, loc~, letrec_loc~, semi_loc~, ..) => {
      let parts = [self.part_letand_stmt(bindings, Some(letrec_loc), semi_loc)]
      self.append_stmt_chain_parts(parts, body)
      self.region(loc, parts)
    }
    Let(
      pattern~,
      expr=bound_expr,
      body~,
      loc~,
      let_loc~,
      equal_loc~,
      semi_loc~,
      ..
    ) => {
      let parts = [
        self.part_let_stmt(
          pattern,
          bound_expr,
          Some(let_loc),
          Some(equal_loc),
          semi_loc,
        ),
      ]
      self.append_stmt_chain_parts(parts, body)
      self.region(loc, parts)
    }
    Sequence(exprs~, last_expr~, loc~, ..) => {
      let parts = self.parts_from_list(exprs, fn(expr) { self.part_expr(expr) })
      parts.push(self.part_expr(last_expr))
      self.region(loc, parts)
    }
    Tuple(exprs~, loc~, lparen_loc~, rparen_loc~, ..) =>
      self.delimited_or_region(
        loc,
        Some(lparen_loc),
        self.parts_from_list(exprs, fn(expr) { self.part_expr(expr) }),
        Some(rparen_loc),
      )
    Record(type_name~, fields~, loc~, lbrace_loc~, rbrace_loc~, ..) => {
      let parts = Array::new()
      self.append_part(
        parts,
        type_name.map(fn(type_name) {
          self.part(self.elab_type_name(type_name), Some(type_name.loc))
        }),
      )
      let braces_loc = lbrace_loc.merge(rbrace_loc)
      let field_part = self.part(
        self.delimited_or_region(
          braces_loc,
          Some(lbrace_loc),
          self.parts_from_list(fields, fn(field) { self.part_field_def(field) }),
          Some(rbrace_loc),
        ),
        Some(braces_loc),
      )
      parts.push(field_part)
      self.region(loc, parts)
    }
    RecordUpdate(
      type_name~,
      record~,
      fields~,
      loc~,
      lbrace_loc~,
      rbrace_loc~,
      ..
    ) => {
      let parts = Array::new()
      self.append_part(
        parts,
        type_name.map(fn(type_name) {
          self.part(self.elab_type_name(type_name), Some(type_name.loc))
        }),
      )
      let inner_parts = Array::new()
      inner_parts.push(self.part_expr(record))
      inner_parts.push_iter(
        self
        .parts_from_list(fields, fn(field) { self.part_field_def(field) })
        .iter(),
      )
      let braces_loc = lbrace_loc.merge(rbrace_loc)
      parts.push(
        self.part(
          self.delimited_or_region(
            braces_loc,
            Some(lbrace_loc),
            inner_parts,
            Some(rbrace_loc),
          ),
          Some(braces_loc),
        ),
      )
      self.region(loc, parts)
    }
    Field(record~, accessor~, loc~) =>
      self.region(loc, [
        self.part_expr(record),
        self.part(self.elab_accessor(accessor), Some(accessor_loc(accessor))),
      ])
    Method(type_name~, method_name~, loc~, ..) =>
      self.region(loc, [
        self.part(self.elab_type_name(type_name), Some(type_name.loc)),
        self.part_label(method_name),
      ])
    DotApply(
      self=self_expr,
      method_name~,
      args~,
      loc~,
      lparen_loc~,
      rparen_loc~,
      ..
    ) => {
      let parts = Array::new()
      parts.push(self.part_expr(self_expr))
      parts.push(self.part_label(method_name))
      let arg_loc = lparen_loc.merge(rparen_loc)
      parts.push(
        self.part(
          self.delimited(
            lparen_loc,
            self.parts_from_list(args, fn(arg) { self.part_argument(arg) }),
            rparen_loc,
          ),
          Some(arg_loc),
        ),
      )
      self.region(loc, parts)
    }
    As(expr~, trait_~, loc~, ..) =>
      self.region(loc, [
        self.part_expr(expr),
        self.part(self.elab_type_name(trait_), Some(trait_.loc)),
      ])
    Mutate(record~, accessor~, field~, loc~, ..) =>
      self.region(loc, [
        self.part_expr(record),
        self.part(self.elab_accessor(accessor), Some(accessor_loc(accessor))),
        self.part_expr(field),
      ])
    Match(expr~, cases~, loc~, lbrace_loc~, rbrace_loc~, ..) => {
      let parts = Array::new()
      parts.push(self.part_expr(expr))
      self.append_part(
        parts,
        self.make_cases_block_part(Some(lbrace_loc), cases, Some(rbrace_loc)),
      )
      self.region(loc, parts)
    }
    LexMatch(strategy~, expr~, cases~, loc~, lbrace_loc~, rbrace_loc~, ..) => {
      let parts = Array::new()
      parts.push(self.part_expr(expr))
      self.append_part(
        parts,
        strategy.map(fn(label) { self.part_label(label) }),
      )
      self.append_part(
        parts,
        self.make_lex_cases_block_part(
          Some(lbrace_loc),
          cases,
          Some(rbrace_loc),
        ),
      )
      self.region(loc, parts)
    }
    LetMut(
      binder~,
      ty~,
      expr=bound_expr,
      body~,
      loc~,
      let_loc~,
      mut_loc~,
      equal_loc~,
      semi_loc~,
      ..
    ) => {
      let parts = [
        self.part_letmut_stmt(
          binder,
          ty,
          bound_expr,
          Some(let_loc),
          Some(mut_loc),
          Some(equal_loc),
          semi_loc,
        ),
      ]
      self.append_stmt_chain_parts(parts, body)
      self.region(loc, parts)
    }
    Pipe(lhs~, rhs~, loc~, ..) =>
      self.region(loc, [self.part_expr(lhs), self.part_expr(rhs)])
    RevPipe(lhs~, rhs~, loc~, ..) =>
      self.region(loc, [self.part_expr(lhs), self.part_expr(rhs)])
    Assign(var_~, expr~, loc~, ..) =>
      self.region(loc, [
        self.part(self.elab_var(var_), Some(var_.loc)),
        self.part_expr(expr),
      ])
    Expr::Hole(loc~, kind~) => self.elab_hole(kind, loc)
    Return(return_value~, loc~, ..) => {
      let parts = Array::new()
      self.append_part(
        parts,
        return_value.map(fn(expr) { self.part_expr(expr) }),
      )
      self.region(loc, parts)
    }
    Raise(err_value~, loc~, ..) => self.region(loc, [self.part_expr(err_value)])
    Quantifier(binder~, binder_ty~, body~, loc~, ..) =>
      self.region(loc, [
        self.part_binder(binder),
        self.part_type(binder_ty),
        self.part_expr(body),
      ])
    Implies(lhs~, rhs~, loc~, ..) =>
      self.region(loc, [self.part_expr(lhs), self.part_expr(rhs)])
    ProofAssert(expr~, loc~, ..) => self.region(loc, [self.part_expr(expr)])
    ProofLet(binder~, expr~, loc~, ..) =>
      self.region(loc, [self.part_binder(binder), self.part_expr(expr)])
    Unit(loc~, faked~, ..) =>
      if faked {
        self.empty()
      } else {
        self.outer_delimited_or_region(loc, '(', ')', [])
      }
    Break(arg~, label~, loc~, ..) => {
      let parts = Array::new()
      self.append_part(parts, label.map(fn(label) { self.part_label(label) }))
      self.append_part(parts, arg.map(fn(expr) { self.part_expr(expr) }))
      self.region(loc, parts)
    }
    Continue(args~, label~, loc~, ..) => {
      let parts = Array::new()
      self.append_part(parts, label.map(fn(label) { self.part_label(label) }))
      parts.push_iter(
        self.parts_from_list(args, fn(expr) { self.part_expr(expr) }).iter(),
      )
      self.region(loc, parts)
    }
    For(
      binders~,
      condition~,
      continue_block~,
      body~,
      for_else~,
      where_clause~,
      label~,
      loc~,
      body_lbrace_loc~,
      body_rbrace_loc~,
      nobreak_lbrace_loc~,
      nobreak_rbrace_loc~,
      ..
    ) => {
      let parts = Array::new()
      self.append_part(parts, label.map(fn(label) { self.part_label(label) }))
      parts.push_iter(
        self
        .parts_from_list(binders, fn(binding) {
          self.part_binder_expr_pair(binding)
        })
        .iter(),
      )
      self.append_part(parts, condition.map(fn(expr) { self.part_expr(expr) }))
      parts.push_iter(
        self
        .parts_from_list(continue_block, fn(binding) {
          self.part_binder_expr_pair(binding)
        })
        .iter(),
      )
      self.append_part(
        parts,
        self.make_block_part(
          Some(body_lbrace_loc),
          Some(body),
          Some(body_rbrace_loc),
        ),
      )
      self.append_part(
        parts,
        for_else.map(fn(expr) {
          self
          .make_block_part(nobreak_lbrace_loc, Some(expr), nobreak_rbrace_loc)
          .unwrap_or(self.part_expr(expr))
        }),
      )
      self.append_part(
        parts,
        where_clause.map(fn(where_clause) {
          self.part_where_clause(where_clause)
        }),
      )
      self.region(loc, parts)
    }
    ForEach(
      binders~,
      expr~,
      body~,
      else_block~,
      label~,
      loc~,
      body_lbrace_loc~,
      body_rbrace_loc~,
      nobreak_lbrace_loc~,
      nobreak_rbrace_loc~,
      ..
    ) => {
      let parts = Array::new()
      self.append_part(parts, label.map(fn(label) { self.part_label(label) }))
      binders.each(fn(binder) {
        self.append_part(parts, self.optional_binder_part(binder))
      })
      parts.push(self.part_expr(expr))
      self.append_part(
        parts,
        self.make_block_part(
          Some(body_lbrace_loc),
          Some(body),
          Some(body_rbrace_loc),
        ),
      )
      self.append_part(
        parts,
        else_block.map(fn(expr) {
          self
          .make_block_part(nobreak_lbrace_loc, Some(expr), nobreak_rbrace_loc)
          .unwrap_or(self.part_expr(expr))
        }),
      )
      self.region(loc, parts)
    }
    Try(
      body~,
      catch_~,
      try_else~,
      loc~,
      catch_lbrace_loc~,
      catch_rbrace_loc~,
      noraise_lbrace_loc~,
      noraise_rbrace_loc~,
      ..
    ) => {
      let parts = Array::new()
      parts.push(self.part_expr(body))
      self.append_part(
        parts,
        self.make_cases_block_part(
          Some(catch_lbrace_loc),
          catch_,
          Some(catch_rbrace_loc),
        ),
      )
      self.append_part(
        parts,
        try_else.map(fn(cases) {
          match
            self.make_cases_block_part(
              noraise_lbrace_loc, cases, noraise_rbrace_loc,
            ) {
            Some(part) => part
            None => self.part(self.empty(), None)
          }
        }),
      )
      self.region(loc, parts)
    }
    TryOperator(body~, loc~, ..) => self.region(loc, [self.part_expr(body)])
    Map(elems~, loc~, lbrace_loc~, rbrace_loc~, ..) =>
      self.delimited_or_region(
        loc,
        Some(lbrace_loc),
        self.parts_from_list(elems, fn(elem) { self.part_map_expr_elem(elem) }),
        Some(rbrace_loc),
      )
    Group(expr~, group~, loc~, left_delim_loc~, right_delim_loc~) =>
      match group {
        Paren =>
          self.delimited_or_region(
            loc,
            Some(left_delim_loc),
            [self.part_expr(expr)],
            Some(right_delim_loc),
          )
        Brace =>
          self.delimited_or_region(
            loc,
            Some(left_delim_loc),
            self.block_stmt_parts(expr),
            Some(right_delim_loc),
          )
      }
    TemplateWriting(expr~, template~, loc~, ..) =>
      self.region(loc, [self.part_expr(expr), self.part_expr(template)])
    StaticAssert(body~, ..) => self.elab_expr(body)
  }
}
