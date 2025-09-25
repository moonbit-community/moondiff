///|
trait Elab {
  elab(Self, LineWidths) -> Syntax
}

///|
impl Elab for @syntax.Impl with elab(impl_, line_widths) {
  match impl_ {
    TopView(
      quantifiers~,
      source_ty~,
      view_type_name~,
      view_type_loc~,
      view_constrs~,
      view_func_name~,
      parameters~,
      params_loc~,
      body~,
      vis~,
      loc~,
      attrs~
    ) => ...
    TopImpl(
      self_ty~,
      trait_~,
      method_name~,
      has_error~,
      quantifiers~,
      params~,
      ret_ty~,
      err_ty~,
      body~,
      vis~,
      loc~,
      attrs~,
      doc~
    ) => ...
    TopBatchTraitAlias(pkg~, targets~, vis~, loc~, attrs~, is_list~, doc~) =>
      ...
    TopBatchTypeAlias(pkg~, targets~, vis~, loc~, attrs~, is_list~, doc~) => ...
    TopTrait(_) => ...
    TopLetDef(_) => ...
    TopFuncAlias(_) => ...
    TopFuncDef(fun_decl~, decl_body~, loc~) => {
      let vis = Elab::elab(fun_decl.vis, line_widths)
      let name = Elab::elab(fun_decl.name, line_widths)
      let extern_ = panic()
      let typename = if fun_decl.type_name is Some(type_name) {
        Elab::elab(type_name, line_widths)
      } else {
        Syntax::default()
      }
      let quantifiers = fun_decl.quantifiers
        .map(Elab::elab(_, line_widths))
        .to_array()
      ...
    }
    TopTypeDef(_) => ...
    TopTest(_) => ...
    TopExpr(_) => ...
    TopImplRelation(_) => ...
  }
}

///|
impl Elab for @syntax.Parameter with elab(parameter, line_widths) {
  match parameter {
    DiscardPositional(loc~, ty=None) =>
      Syntax::atom(
        content="_",
        position=line_widths.loc_to_spans(loc),
        kind=Normal,
      )
    DiscardPositional(loc~, ty=Some(ty)) => {
      let underscore_loc = loc.sub(1)
      let underscore = Syntax::atom(
        content="_",
        position=line_widths.loc_to_spans(underscore_loc),
        kind=Normal,
      )
      let ty = Elab::elab(ty, line_widths)
      Syntax::simple_list(
        open_position=[loc.start_to_span()],
        children=[underscore, ty],
        close_position=[loc.end_to_span()],
      )
    }
    Positional(binder~, ty=Some(ty))
    | QuestionOptional(binder~, ty=Some(ty))
    | Labelled(binder~, ty=Some(ty))
    | Optional(binder~, ty=Some(ty), ..) => ...
    Positional(binder~, ty=None)
    | QuestionOptional(binder~, ty=None)
    | Labelled(binder~, ty=None)
    | Optional(binder~, ty=None, ..) => Elab::elab(binder, line_widths)
  }
}

///|
impl Elab for @syntax.Type with elab(ty, line_widths) {
  match ty {
    Option(question_loc~, ty~, loc~) => {
      let question = Syntax::atom(
        content="?",
        position=line_widths.loc_to_spans(question_loc),
        kind=Normal,
      )
      let inner_type = Elab::elab(ty, line_widths)
      Syntax::simple_list(
        open_position=[loc.start_to_span()],
        children=[inner_type, question],
        close_position=[loc.end_to_span()],
      )
    }
    Name(constr_id~, tys~, loc~) => {
      let constr_str = constr_id.id.to_str()
      let constr_id = Syntax::atom(
        content=constr_str,
        position=line_widths.loc_to_spans(constr_id.loc),
        kind=Normal,
      )
      if tys.is_empty() {
        constr_id
      } else {
        let (tys_open_pos, tys_close_pos) = lst_search_symmetric(
          line_widths,
          tys,
          loc_of=loc_of_type,
          open='[',
          close=']',
        )
        let tys = tys.map(Elab::elab(_, line_widths)).to_array()
        Syntax::simple_list(
          open_position=[loc.start_to_span()],
          children=[
            constr_id,
            Syntax::list(
              open_content="[",
              open_position=[tys_open_pos],
              children=tys,
              close_content="]",
              close_position=[tys_close_pos],
            ),
          ],
          close_position=[loc.end_to_span()],
        )
      }
    }
    Tuple(loc~, tys~) => {
      let children = tys.map(Elab::elab(_, line_widths)).to_array()
      Syntax::simple_list(open_position=[loc.start_to_span()], children~, close_position=[
        loc.end_to_span(),
      ])
    }
    Arrow(loc~, args~, res~, err~, is_async~) => {
      let res_loc = loc_of_type(res)
      let args_close_pos = line_widths.backward_search(')', res_loc.start)
      let args_open_pos = if args.is_empty() {
        line_widths.backward_search('(', res_loc.start)
      } else {
        let first_loc = loc_of_type(args.head().unwrap())
        line_widths.backward_search('(', first_loc.start)
      }
      let args = args.map(Elab::elab(_, line_widths)).to_array()
      let args = Syntax::list(
        open_content="(",
        open_position=[args_open_pos],
        children=args,
        close_content=")",
        close_position=[args_close_pos],
      )
      let res = Elab::elab(res, line_widths)
      let err = if err is NoErrorType {
        Syntax::default()
      } else {
        Elab::elab(err, line_widths)
      }
      let is_async = if is_async {
        Syntax::atom(
          content="async",
          position=[loc.sub(5).start_to_span()],
          kind=Normal,
        )
      } else {
        Syntax::default()
      }
      Syntax::simple_list(
        open_position=[loc.start_to_span()],
        children=[is_async, args, res, err],
        close_position=[loc.end_to_span()],
      )
    }
    Any(loc~) =>
      Syntax::atom(
        content="_",
        position=line_widths.loc_to_spans(loc),
        kind=Normal,
      )
    Object(ty) => {
      // &Typ => get loc of '&'
      let prefix_pos = ty.loc.start_to_span()
      let prefix_pos = {
        ..prefix_pos,
        start_col: prefix_pos.start_col - 1,
        end_col: prefix_pos.end_col,
      }
      let prefix = Syntax::atom(content="&", position=[prefix_pos], kind=Normal)
      let typ = Elab::elab(ty, line_widths)
      Syntax::simple_list(
        open_position=[{ ..prefix_pos, end_col: prefix_pos.end_col - 1 }],
        children=[prefix, typ],
        close_position=[ty.loc.end_to_span()],
      )
    }
  }
}

///|
impl Elab for @syntax.ErrorType with elab(err_ty, line_widths) {
  match err_ty {
    Noraise(loc~) =>
      Syntax::atom(
        content="noraise",
        position=line_widths.loc_to_spans(loc),
        kind=Normal,
      )
    NoErrorType => Syntax::default()
    DefaultErrorType(loc~) =>
      Syntax::atom(
        content="raise",
        position=line_widths.loc_to_spans(loc),
        kind=Normal,
      )
    ErrorType(ty~) => Elab::elab(ty, line_widths)
    MaybeError(ty~) => {
      let loc = loc_of_type(ty)
      Syntax::atom(
        content="raise?",
        position=line_widths.loc_to_spans(loc),
        kind=Normal,
      )
    }
  }
}

///|
impl Elab for @syntax.TypeVarBinder with elab(type_var_binder, line_widths) {
  if type_var_binder.constraints.is_empty() {
    Syntax::atom(
      content=type_var_binder.name,
      position=line_widths.loc_to_spans(panic()),
      kind=Normal,
    )
  } else {
    let tvar_name = Syntax::atom(
      content=type_var_binder.name,
      position=line_widths.loc_to_spans(panic()),
      kind=Normal,
    )
    if type_var_binder.constraints.is_empty() {
      return tvar_name
    }
    let (constraint_open_pos, constraint_close_pos) = lst_pos_pair(
      type_var_binder.constraints,
      loc_of=constraint => constraint.loc,
    )
    let constraints = type_var_binder.constraints
      .map(Elab::elab(_, line_widths))
      .to_array()
    let constraints = Syntax::simple_list(
      open_position=[constraint_open_pos],
      children=constraints,
      close_position=[constraint_close_pos],
    )
    Syntax::simple_list(
      open_position=[panic()],
      children=[tvar_name, constraints],
      close_position=[panic()],
    )
  }
}

///|
impl Elab for @syntax.TypeVarConstraint with elab(
  type_var_constraint,
  line_widths,
) {
  let content = type_var_constraint.trait_.to_str()
  Syntax::atom(
    content~,
    position=line_widths.loc_to_spans(type_var_constraint.loc),
    kind=Normal,
  )
}

///|
impl Elab for @syntax.TypeName with elab(type_name, line_widths) {
  let content = type_name.name.to_str()
  Syntax::atom(
    content~,
    position=line_widths.loc_to_spans(type_name.loc),
    kind=Normal,
  )
}

///|
impl Elab for @syntax.Binder with elab(binder, line_widths) {
  Syntax::atom(
    content=binder.name,
    position=line_widths.loc_to_spans(binder.loc),
    kind=Normal,
  )
}

///|
impl Elab for @syntax.Visibility with elab(vis, line_widths) {
  match vis {
    Default => Syntax::default()
    Pub(loc~, attr~) => {
      let content = if attr is Some(attr) { "pub(\{attr})" } else { "pub" }
      Syntax::atom(
        content~,
        position=line_widths.loc_to_spans(loc),
        kind=Normal,
      )
    }
    Priv(loc~) => {
      let content = "priv"
      Syntax::atom(
        content~,
        position=line_widths.loc_to_spans(loc),
        kind=Normal,
      )
    }
  }
}

///|
impl Elab for @syntax.Label with elab(label, line_widths) {
  Syntax::atom(
    content=label.name,
    position=line_widths.loc_to_spans(label.loc),
    kind=Normal,
  )
}

///|
impl Elab for @syntax.ConstrName with elab(constr_name, line_widths) {
  ...
}

///|
impl Elab for @syntax.ConstrId with elab(constr_id, line_widths) {
  ...
}

///|
impl Elab for @syntax.ConstrParam with elab(constr_param, line_widths) {
  ...
}

///|
impl Elab for @syntax.ConstrDecl with elab(constr_decl, line_widths) {
  ...
}

///|
impl Elab for @syntax.FieldName with elab(field_name, line_widths) {
  ...
}

///|
impl Elab for @syntax.FieldDecl with elab(field_decl, line_widths) {
  ...
}

///|
impl Elab for @syntax.TypeDeclBinder with elab(type_decl_binder, line_widths) {
  ...
}

///|
impl Elab for @syntax.Var with elab(var, line_widths) {
  ...
}

///|
impl Elab for @syntax.Constructor with elab(constructor, line_widths) {
  ...
}

///|
impl Elab for @syntax.AliasTarget with elab(alias_target, line_widths) {
  ...
}

///|
impl Elab for @syntax.Argument with elab(argument, line_widths) {
  let value = Elab::elab(argument.value, line_widths)
  let kind = Elab::elab(argument.kind, line_widths)
  Syntax::simple_list(open_position=[], children=[kind, value], close_position=[])
}

///|
impl Elab for @syntax.Case with elab(case, line_widths) {
  let pattern = Elab::elab(case.pattern, line_widths)
  let guard_expr = if case.guard_ is Some(g) {
    Elab::elab(g, line_widths)
  } else {
    Syntax::default()
  }
  let body = Elab::elab(case.body, line_widths)
  Syntax::simple_list(open_position=[], children=[pattern, guard_expr, body], close_position=[])
}

///|
impl Elab for @syntax.MultiArgCase with elab(multi_arg_case, line_widths) {
  let patterns = multi_arg_case.patterns
    .map(Elab::elab(_, line_widths))
    .to_array()
  let guard_expr = if multi_arg_case.guard_ is Some(g) {
    Elab::elab(g, line_widths)
  } else {
    Syntax::default()
  }
  let body = Elab::elab(multi_arg_case.body, line_widths)
  Syntax::simple_list(
    open_position=[],
    children=patterns + [guard_expr, body],
    close_position=[],
  )
}

///|
impl Elab for @syntax.MapExprElem with elab(map_expr_elem, line_widths) {
  let key = Elab::elab(map_expr_elem.key, line_widths)
  let expr = Elab::elab(map_expr_elem.expr, line_widths)
  Syntax::simple_list(
    open_position=line_widths.loc_to_spans(map_expr_elem.loc),
    children=[key, expr],
    close_position=line_widths.loc_to_spans(map_expr_elem.loc),
  )
}

///|
impl Elab for @syntax.StaticAssertion with elab(static_assertion, line_widths) {
  let ty = Elab::elab(static_assertion.ty, line_widths)
  let trait_name = Elab::elab(static_assertion.trait_, line_widths)
  let msg = if static_assertion.msg.is_empty() {
    Syntax::default()
  } else {
    Syntax::atom(content=static_assertion.msg, position=[], kind=String(Text))
  }
  Syntax::simple_list(
    open_position=line_widths.loc_to_spans(static_assertion.loc),
    children=[ty, trait_name, msg],
    close_position=line_widths.loc_to_spans(static_assertion.loc),
  )
}

///|
impl Elab for @syntax.FieldDef with elab(field_def, line_widths) {
  let label = Elab::elab(field_def.label, line_widths)
  let expr = if field_def.is_pun {
    Syntax::default()
  } else {
    Elab::elab(field_def.expr, line_widths)
  }
  Syntax::simple_list(
    open_position=line_widths.loc_to_spans(field_def.loc),
    children=[label, expr],
    close_position=line_widths.loc_to_spans(field_def.loc),
  )
}

///|
impl Elab for @syntax.FieldPat with elab(field_pat, line_widths) {
  let label = Elab::elab(field_pat.label, line_widths)
  let pattern = if field_pat.is_pun {
    Syntax::default()
  } else {
    Elab::elab(field_pat.pattern, line_widths)
  }
  Syntax::simple_list(
    open_position=line_widths.loc_to_spans(field_pat.loc),
    children=[label, pattern],
    close_position=line_widths.loc_to_spans(field_pat.loc),
  )
}

///|
impl Elab for @syntax.ConstrPatArg with elab(constr_pat_arg, line_widths) {
  let pat = Elab::elab(constr_pat_arg.pat, line_widths)
  let kind = Elab::elab(constr_pat_arg.kind, line_widths)
  Syntax::simple_list(open_position=[], children=[kind, pat], close_position=[])
}

///|
impl Elab for @syntax.MapPatElem with elab(map_pat_elem, line_widths) {
  let key = Elab::elab(map_pat_elem.key, line_widths)
  let pat = Elab::elab(map_pat_elem.pat, line_widths)
  let absent = if map_pat_elem.match_absent {
    Syntax::atom(content="absent", position=[], kind=Normal)
  } else {
    Syntax::default()
  }
  Syntax::simple_list(
    open_position=line_widths.loc_to_spans(map_pat_elem.loc),
    children=[key, pat, absent],
    close_position=line_widths.loc_to_spans(map_pat_elem.loc),
  )
}

///|
impl Elab for @syntax.LocalTypeDecl with elab(local_type_decl, line_widths) {
  let tycon = Syntax::atom(
    content=local_type_decl.tycon,
    position=line_widths.loc_to_spans(local_type_decl.tycon_loc),
    kind=Type,
  )
  let components = Elab::elab(local_type_decl.components, line_widths)
  let deriving_syntaxes = local_type_decl.deriving
    .map(Elab::elab(_, line_widths))
    .to_array()
  Syntax::simple_list(
    open_position=line_widths.loc_to_spans(local_type_decl.tycon_loc),
    children=[tycon, components] + deriving_syntaxes,
    close_position=line_widths.loc_to_spans(local_type_decl.tycon_loc),
  )
}

///|
impl Elab for @syntax.DerivingDirective with elab(
  deriving_directive,
  line_widths,
) {
  let type_name = Elab::elab(deriving_directive.type_name, line_widths)
  let args = deriving_directive.args.map(Elab::elab(_, line_widths)).to_array()
  Syntax::simple_list(
    open_position=line_widths.loc_to_spans(deriving_directive.loc),
    children=[type_name] + args,
    close_position=line_widths.loc_to_spans(deriving_directive.loc),
  )
}

///|
impl Elab for @syntax.TypeDecl with elab(type_decl, line_widths) {
  let tycon = Syntax::atom(
    content=type_decl.tycon,
    position=line_widths.loc_to_spans(type_decl.tycon_loc),
    kind=Type,
  )
  let params = type_decl.params.map(Elab::elab(_, line_widths)).to_array()
  let components = Elab::elab(type_decl.components, line_widths)
  let vis = Elab::elab(type_decl.type_vis, line_widths)
  let deriving_syntaxes = type_decl.deriving
    .map(Elab::elab(_, line_widths))
    .to_array()
  Syntax::simple_list(
    open_position=line_widths.loc_to_spans(type_decl.loc),
    children=[vis, tycon, components] + params + deriving_syntaxes,
    close_position=line_widths.loc_to_spans(type_decl.loc),
  )
}

///|
impl Elab for @syntax.TraitMethodDecl with elab(trait_method_decl, line_widths) {
  let name = Elab::elab(trait_method_decl.name, line_widths)
  let quantifiers = trait_method_decl.quantifiers
    .map(Elab::elab(_, line_widths))
    .to_array()
  let params = trait_method_decl.params
    .map(Elab::elab(_, line_widths))
    .to_array()
  let return_type = if trait_method_decl.return_type is Some(rt) {
    Elab::elab(rt, line_widths)
  } else {
    Syntax::default()
  }
  let error_type = Elab::elab(trait_method_decl.error_type, line_widths)
  let async_syntax = if trait_method_decl.is_async {
    Syntax::atom(content="async", position=[], kind=Keyword)
  } else {
    Syntax::default()
  }
  let error_syntax = if trait_method_decl.has_error is Some(loc) {
    Syntax::atom(
      content="raise",
      position=line_widths.loc_to_spans(loc),
      kind=Keyword,
    )
  } else {
    Syntax::default()
  }
  let default_syntax = if trait_method_decl.has_default is Some(loc) {
    Syntax::atom(
      content="= _",
      position=line_widths.loc_to_spans(loc),
      kind=Normal,
    )
  } else {
    Syntax::default()
  }
  Syntax::simple_list(
    open_position=line_widths.loc_to_spans(trait_method_decl.loc),
    children=[
        async_syntax, name, error_syntax, return_type, error_type, default_syntax,
      ] +
      quantifiers +
      params,
    close_position=line_widths.loc_to_spans(trait_method_decl.loc),
  )
}

///|
impl Elab for @syntax.TraitDecl with elab(trait_decl, line_widths) {
  let name = Elab::elab(trait_decl.name, line_widths)
  let vis = Elab::elab(trait_decl.vis, line_widths)
  let supers = trait_decl.supers.map(Elab::elab(_, line_widths)).to_array()
  let methods = trait_decl.methods.map(Elab::elab(_, line_widths)).to_array()
  Syntax::simple_list(
    open_position=line_widths.loc_to_spans(trait_decl.loc),
    children=[vis, name] + supers + methods,
    close_position=line_widths.loc_to_spans(trait_decl.loc),
  )
}

///|
impl Elab for @syntax.Constant with elab(constant, line_widths) {
  match constant {
    Bool(_) => ...
    Byte(_) => ...
    Bytes(_) => ...
    Char(_) => ...
    Int(_) => ...
    Int64(_) => ...
    UInt(_) => ...
    UInt64(_) => ...
    Float(_) => ...
    Double(_) => ...
    String(_) => ...
    BigInt(_) => ...
  }
}

///|
impl Elab for @syntax.LongIdent with elab(long_ident, line_widths) {
  match long_ident {
    Ident(name~) => ...
    Dot(pkg~, id~) => ...
  }
}

///|
impl Elab for @syntax.ExceptionDecl with elab(exception_decl, line_widths) {
  match exception_decl {
    NoPayload => Syntax::default()
    SinglePayload(ty) => Elab::elab(ty, line_widths)
    EnumPayload(constrs) => {
      let constr_syntaxes = constrs.map(Elab::elab(_, line_widths)).to_array()
      Syntax::simple_list(open_position=[], children=constr_syntaxes, close_position=[])
    }
  }
}

///|
impl Elab for @syntax.TypeDesc with elab(type_desc, line_widths) {
  match type_desc {
    Abstract => Syntax::atom(content="abstract", position=[], kind=Keyword)
    Extern => Syntax::atom(content="extern", position=[], kind=Keyword)
    Newtype(ty) => {
      let newtype_kw = Syntax::atom(
        content="newtype",
        position=[],
        kind=Keyword,
      )
      let ty_syntax = Elab::elab(ty, line_widths)
      Syntax::simple_list(open_position=[], children=[newtype_kw, ty_syntax], close_position=[])
    }
    Error(exception_decl) => {
      let error_kw = Syntax::atom(content="error", position=[], kind=Keyword)
      let exception_syntax = Elab::elab(exception_decl, line_widths)
      Syntax::simple_list(
        open_position=[],
        children=[error_kw, exception_syntax],
        close_position=[],
      )
    }
    Variant(constrs) => {
      let variant_kw = Syntax::atom(
        content="variant",
        position=[],
        kind=Keyword,
      )
      let constr_syntaxes = constrs.map(Elab::elab(_, line_widths)).to_array()
      Syntax::simple_list(
        open_position=[],
        children=[variant_kw] + constr_syntaxes,
        close_position=[],
      )
    }
    Record(fields) => {
      let record_kw = Syntax::atom(content="record", position=[], kind=Keyword)
      let field_syntaxes = fields.map(Elab::elab(_, line_widths)).to_array()
      Syntax::simple_list(
        open_position=[],
        children=[record_kw] + field_syntaxes,
        close_position=[],
      )
    }
    TupleStruct(types) => {
      let tuple_kw = Syntax::atom(content="tuple", position=[], kind=Keyword)
      let type_syntaxes = types.map(Elab::elab(_, line_widths)).to_array()
      Syntax::simple_list(
        open_position=[],
        children=[tuple_kw] + type_syntaxes,
        close_position=[],
      )
    }
    Alias(ty) => {
      let alias_kw = Syntax::atom(content="alias", position=[], kind=Keyword)
      let ty_syntax = Elab::elab(ty, line_widths)
      Syntax::simple_list(open_position=[], children=[alias_kw, ty_syntax], close_position=[])
    }
  }
}

///|
impl Elab for @syntax.Hole with elab(hole, line_widths) {
  match hole {
    Synthesized => Syntax::atom(content="_", position=[], kind=Normal)
    Incomplete => Syntax::atom(content="?", position=[], kind=Normal)
    Todo => Syntax::atom(content="todo", position=[], kind=Normal)
  }
}

///|
impl Elab for @syntax.ArgumentKind with elab(argument_kind, line_widths) {
  match argument_kind {
    Positional => Syntax::default()
    Labelled(label) => Elab::elab(label, line_widths)
    LabelledPun(label) => Elab::elab(label, line_widths)
    LabelledOption(label~, question_loc~) => {
      let label_syntax = Elab::elab(label, line_widths)
      let question = Syntax::atom(
        content="?",
        position=line_widths.loc_to_spans(question_loc),
        kind=Normal,
      )
      Syntax::simple_list(open_position=[], children=[label_syntax, question], close_position=[])
    }
    LabelledOptionPun(label~, question_loc~) => {
      let label_syntax = Elab::elab(label, line_widths)
      let question = Syntax::atom(
        content="?",
        position=line_widths.loc_to_spans(question_loc),
        kind=Normal,
      )
      Syntax::simple_list(open_position=[], children=[label_syntax, question], close_position=[])
    }
  }
}

///|
impl Elab for @syntax.FnKind with elab(fn_kind, line_widths) {
  match fn_kind {
    Lambda => Syntax::atom(content="fn", position=[], kind=Normal)
    Matrix => Syntax::atom(content="match", position=[], kind=Normal)
    Arrow => Syntax::atom(content="=>", position=[], kind=Normal)
  }
}

///|
impl Elab for @syntax.Group with elab(group, line_widths) {
  match group {
    Brace => Syntax::atom(content="{}", position=[], kind=Normal)
    Paren => Syntax::atom(content="()", position=[], kind=Normal)
  }
}

///|
impl Elab for @syntax.TrailingMark with elab(trailing_mark, line_widths) {
  match trailing_mark {
    Comma => Syntax::atom(content=",", position=[], kind=Normal)
    Semi => Syntax::atom(content=";", position=[], kind=Normal)
    None => Syntax::default()
  }
}

///|
impl Elab for @syntax.ApplyAttr with elab(apply_attr, line_widths) {
  match apply_attr {
    NoAttr => Syntax::default()
    Exclamation => Syntax::atom(content="!", position=[], kind=Normal)
    Question => Syntax::atom(content="?", position=[], kind=Normal)
  }
}

///|
impl Elab for @syntax.ConstructorExtraInfo with elab(
  constructor_extra_info,
  line_widths,
) {
  match constructor_extra_info {
    TypeName(type_name) => Elab::elab(type_name, line_widths)
    Package(pkg_name) =>
      Syntax::atom(content="@\{pkg_name}", position=[], kind=Normal)
    NoExtraInfo => Syntax::default()
  }
}

///|
impl Elab for @syntax.Accessor with elab(accessor, line_widths) {
  match accessor {
    Label(label) => Elab::elab(label, line_widths)
    Index(tuple_index~, loc~) =>
      Syntax::atom(
        content=tuple_index.to_string(),
        position=line_widths.loc_to_spans(loc),
        kind=Normal,
      )
    Newtype(loc~) =>
      Syntax::atom(
        content="0",
        position=line_widths.loc_to_spans(loc),
        kind=Normal,
      )
  }
}

///|
impl Elab for @syntax.SpreadableElem with elab(spreadable_elem, line_widths) {
  match spreadable_elem {
    Regular(expr) => Elab::elab(expr, line_widths)
    Spread(expr~, loc~) => {
      let spread_op = Syntax::atom(
        content="..",
        position=line_widths.loc_to_spans(loc),
        kind=Normal,
      )
      let expr_syntax = Elab::elab(expr, line_widths)
      Syntax::simple_list(
        open_position=[loc.start_to_span()],
        children=[spread_op, expr_syntax],
        close_position=[loc.end_to_span()],
      )
    }
  }
}

///|
impl Elab for @syntax.Func with elab(func, line_widths) {
  match func {
    Lambda(
      parameters~,
      params_loc~,
      body~,
      return_type~,
      error_type~,
      kind~,
      has_error~,
      is_async~,
      loc~
    ) => {
      let param_syntaxes = parameters.map(Elab::elab(_, line_widths)).to_array()
      let body_syntax = Elab::elab(body, line_widths)
      let return_type_syntax = if return_type is Some(rt) {
        Elab::elab(rt, line_widths)
      } else {
        Syntax::default()
      }
      let error_type_syntax = Elab::elab(error_type, line_widths)
      let kind_syntax = Elab::elab(kind, line_widths)
      let async_syntax = if is_async {
        Syntax::atom(content="async", position=[], kind=Keyword)
      } else {
        Syntax::default()
      }
      let error_syntax = if has_error is Some(loc) {
        Syntax::atom(
          content="raise",
          position=line_widths.loc_to_spans(loc),
          kind=Keyword,
        )
      } else {
        Syntax::default()
      }
      Syntax::simple_list(
        open_position=line_widths.loc_to_spans(loc),
        children=[
            async_syntax, kind_syntax, error_syntax, return_type_syntax, error_type_syntax,
            body_syntax,
          ] +
          param_syntaxes,
        close_position=line_widths.loc_to_spans(loc),
      )
    }
    Match(cases~, has_error~, is_async~, fn_loc~, loc~) => {
      let case_syntaxes = cases.map(Elab::elab(_, line_widths)).to_array()
      let match_kw = Syntax::atom(
        content="match",
        position=line_widths.loc_to_spans(fn_loc),
        kind=Keyword,
      )
      let async_syntax = if is_async {
        Syntax::atom(content="async", position=[], kind=Keyword)
      } else {
        Syntax::default()
      }
      let error_syntax = if has_error is Some(loc) {
        Syntax::atom(
          content="raise",
          position=line_widths.loc_to_spans(loc),
          kind=Keyword,
        )
      } else {
        Syntax::default()
      }
      Syntax::simple_list(
        open_position=line_widths.loc_to_spans(loc),
        children=[async_syntax, match_kw, error_syntax] + case_syntaxes,
        close_position=line_widths.loc_to_spans(loc),
      )
    }
  }
}

///|
impl Elab for @syntax.InterpElem with elab(interp_elem, line_widths) {
  match interp_elem {
    Literal(repr~, loc~) => {
      let content = repr.to_string()
      Syntax::atom(
        content~,
        position=line_widths.loc_to_spans(loc),
        kind=String(StringLiteral),
      )
    }
    Expr(expr~, loc~) => {
      let expr_syntax = Elab::elab(expr, line_widths)
      Syntax::simple_list(
        open_position=line_widths.loc_to_spans(loc),
        children=[expr_syntax],
        close_position=line_widths.loc_to_spans(loc),
      )
    }
    Source(_source) =>
      Syntax::atom(content="<source>", position=[], kind=Normal)
  }
}

///|
impl Elab for @syntax.MultilineStringElem with elab(
  multiline_string_elem,
  line_widths,
) {
  match multiline_string_elem {
    String(str) =>
      Syntax::atom(content=str, position=[], kind=String(StringLiteral))
    Interp(interp_elems) => {
      let children = interp_elems.map(Elab::elab(_, line_widths)).to_array()
      Syntax::simple_list(open_position=[], children~, close_position=[])
    }
  }
}

///|
impl Elab for @syntax.Expr with elab(expr, line_widths) {
  match expr {
    Apply(func~, args~, attr~, loc~) => ...
    Infix(op~, lhs~, rhs~, loc~) => ...
    Unary(op~, expr~, loc~) => ...
    Array(exprs~, loc~) => ...
    ArraySpread(elems~, loc~) => ...
    ArrayGet(array~, index~, loc~) => ...
    ArrayGetSlice(array~, start_index~, end_index~, index_loc~, loc~) => ...
    ArraySet(array~, index~, value~, loc~) => ...
    ArrayAugmentedSet(op~, array~, index~, value~, loc~) => ...
    Constant(c~, loc~) => ...
    MultilineString(elems~, loc~) => ...
    Interp(elems~, loc~) => ...
    Constraint(expr~, ty~, loc~) => ...
    Constr(constr~, loc~) => ...
    While(loop_cond~, loop_body~, while_else~, label~, loc~) => ...
    Function(func~, loc~) => ...
    Ident(id~, loc~) => ...
    If(cond~, ifso~, ifnot~, loc~) => ...
    Guard(cond~, otherwise~, body~, loc~) => ...
    Is(expr~, pat~, loc~) => ...
    Defer(expr~, body~, loc~) => ...
    LetFn(name~, func~, body~, loc~) => ...
    LetRec(bindings~, body~, loc~) => ...
    LetAnd(bindings~, body~, loc~) => ...
    Let(pattern~, expr~, body~, loc~) => ...
    Sequence(exprs~, last_expr~, loc~) => ...
    Tuple(exprs~, loc~) => ...
    Record(type_name~, fields~, trailing~, loc~) => ...
    RecordUpdate(type_name~, record~, fields~, loc~) => ...
    Field(record~, accessor~, loc~) => ...
    Method(type_name~, method_name~, loc~) => ...
    DotApply(self~, method_name~, args~, return_self~, attr~, loc~) => ...
    As(expr~, trait_~, loc~) => ...
    Mutate(record~, accessor~, field~, augmented_by~, loc~) => ...
    Match(expr~, cases~, match_loc~, using_~, loc~) => ...
    LetMut(binder~, ty~, expr~, body~, loc~) => ...
    Pipe(lhs~, rhs~, loc~) => ...
    Assign(var_~, expr~, augmented_by~, loc~) => ...
    Hole(loc~, kind~) => ...
    Return(return_value~, loc~) => ...
    Raise(err_value~, loc~) => ...
    Unit(loc~, faked~) => ...
    Break(arg~, label~, loc~) => ...
    Continue(args~, label~, loc~) => ...
    Loop(args~, body~, label~, loop_loc~, loc~) => ...
    For(binders~, condition~, continue_block~, body~, for_else~, label~, loc~) =>
      ...
    ForEach(binders~, expr~, body~, else_block~, label~, loc~) => ...
    Try(
      body~,
      catch_~,
      catch_all~,
      try_else~,
      has_try~,
      try_loc~,
      catch_loc~,
      else_loc~,
      loc~
    ) => ...
    TryOperator(body~, kind~, try_loc~, loc~) => ...
    Map(elems~, loc~) => ...
    Group(expr~, group~, loc~) => ...
    StaticAssert(asserts~, body~) => ...
  }
}

///|
impl Elab for @syntax.TryOperatorKind with elab(try_operator_kind, line_widths) {
  match try_operator_kind {
    Question => Syntax::atom(content="?", position=[], kind=Normal)
    Exclamation => Syntax::atom(content="!", position=[], kind=Normal)
  }
}

///|
impl Elab for @syntax.DotDotBinder with elab(dot_dot_binder, line_widths) {
  match dot_dot_binder {
    Underscore => Syntax::atom(content="_", position=[], kind=Normal)
    NoBinder => Syntax::default()
    BinderAs(binder) => {
      let dot_dot = Syntax::atom(content="..", position=[], kind=Normal)
      let binder_syntax = Elab::elab(binder, line_widths)
      Syntax::simple_list(open_position=[], children=[dot_dot, binder_syntax], close_position=[])
    }
    Binder(binder) => Elab::elab(binder, line_widths)
  }
}

///|
impl Elab for @syntax.ArrayPattern with elab(array_pattern, line_widths) {
  match array_pattern {
    Pattern(pattern) => Elab::elab(pattern, line_widths)
    StringSpread(str_lit) => {
      let spread = Syntax::atom(content="..", position=[], kind=Normal)
      let string_content = str_lit.to_string()
      let string_syntax = Syntax::atom(
        content=string_content,
        position=[],
        kind=String(StringLiteral),
      )
      Syntax::simple_list(open_position=[], children=[spread, string_syntax], close_position=[])
    }
    BytesSpread(bytes_lit) => {
      let spread = Syntax::atom(content="..", position=[], kind=Normal)
      let bytes_content = bytes_lit.to_string()
      let bytes_syntax = Syntax::atom(
        content=bytes_content,
        position=[],
        kind=Normal,
      )
      Syntax::simple_list(open_position=[], children=[spread, bytes_syntax], close_position=[])
    }
    ConstSpread(binder~, pkg~, loc~) => {
      let spread = Syntax::atom(content="..", position=[], kind=Normal)
      let binder_syntax = Elab::elab(binder, line_widths)
      let pkg_syntax = if pkg is Some(p) {
        Syntax::atom(content="@\{p}", position=[], kind=Normal)
      } else {
        Syntax::default()
      }
      Syntax::simple_list(
        open_position=line_widths.loc_to_spans(loc),
        children=[spread, pkg_syntax, binder_syntax],
        close_position=line_widths.loc_to_spans(loc),
      )
    }
  }
}

///|
impl Elab for @syntax.ArrayPatterns with elab(array_patterns, line_widths) {
  match array_patterns {
    Closed(patterns) => {
      let pattern_syntaxes = patterns.map(Elab::elab(_, line_widths)).to_array()
      Syntax::simple_list(open_position=[], children=pattern_syntaxes, close_position=[])
    }
    Open(prefix, suffix, dot_dot_binder) => {
      let prefix_syntaxes = prefix.map(Elab::elab(_, line_widths)).to_array()
      let suffix_syntaxes = suffix.map(Elab::elab(_, line_widths)).to_array()
      let dot_dot_syntax = Elab::elab(dot_dot_binder, line_widths)
      Syntax::simple_list(
        open_position=[],
        children=prefix_syntaxes + [dot_dot_syntax] + suffix_syntaxes,
        close_position=[],
      )
    }
  }
}

///|
impl Elab for @syntax.Pattern with elab(pattern, line_widths) {
  match pattern {
    Alias(pat~, alias_~, loc~) => {
      let pat_syntax = Elab::elab(pat, line_widths)
      let alias_syntax = Elab::elab(alias_, line_widths)
      let as_kw = Syntax::atom(content="as", position=[], kind=Keyword)
      Syntax::simple_list(
        open_position=line_widths.loc_to_spans(loc),
        children=[pat_syntax, as_kw, alias_syntax],
        close_position=line_widths.loc_to_spans(loc),
      )
    }
    Any(loc~) =>
      Syntax::atom(
        content="_",
        position=line_widths.loc_to_spans(loc),
        kind=Normal,
      )
    Array(pats~, loc~) => {
      let patterns_syntax = Elab::elab(pats, line_widths)
      Syntax::simple_list(
        open_position=line_widths.loc_to_spans(loc),
        children=[patterns_syntax],
        close_position=line_widths.loc_to_spans(loc),
      )
    }
    Constant(c~, loc~) => {
      let constant_syntax = Elab::elab(c, line_widths)
      Syntax::simple_list(
        open_position=line_widths.loc_to_spans(loc),
        children=[constant_syntax],
        close_position=line_widths.loc_to_spans(loc),
      )
    }
    Constraint(pat~, ty~, loc~) => {
      let pat_syntax = Elab::elab(pat, line_widths)
      let ty_syntax = Elab::elab(ty, line_widths)
      let colon = Syntax::atom(content=":", position=[], kind=Normal)
      Syntax::simple_list(
        open_position=line_widths.loc_to_spans(loc),
        children=[pat_syntax, colon, ty_syntax],
        close_position=line_widths.loc_to_spans(loc),
      )
    }
    Constr(constr~, args~, is_open~, loc~) => {
      let constr_syntax = Elab::elab(constr, line_widths)
      let arg_syntaxes = if args is Some(a) {
        a.map(Elab::elab(_, line_widths)).to_array()
      } else {
        []
      }
      let open_marker = if is_open {
        Syntax::atom(content="..", position=[], kind=Normal)
      } else {
        Syntax::default()
      }
      Syntax::simple_list(
        open_position=line_widths.loc_to_spans(loc),
        children=[constr_syntax, open_marker] + arg_syntaxes,
        close_position=line_widths.loc_to_spans(loc),
      )
    }
    Or(pat1~, pat2~, loc~) => {
      let pat1_syntax = Elab::elab(pat1, line_widths)
      let pat2_syntax = Elab::elab(pat2, line_widths)
      let or_op = Syntax::atom(content="|", position=[], kind=Normal)
      Syntax::simple_list(
        open_position=line_widths.loc_to_spans(loc),
        children=[pat1_syntax, or_op, pat2_syntax],
        close_position=line_widths.loc_to_spans(loc),
      )
    }
    Tuple(pats~, loc~) => {
      let pat_syntaxes = pats.map(Elab::elab(_, line_widths)).to_array()
      Syntax::simple_list(
        open_position=line_widths.loc_to_spans(loc),
        children=pat_syntaxes,
        close_position=line_widths.loc_to_spans(loc),
      )
    }
    Var(binder) => Elab::elab(binder, line_widths)
    Record(fields~, is_closed~, loc~) => {
      let field_syntaxes = fields.map(Elab::elab(_, line_widths)).to_array()
      let closed_marker = if is_closed {
        Syntax::default()
      } else {
        Syntax::atom(content="..", position=[], kind=Normal)
      }
      Syntax::simple_list(
        open_position=line_widths.loc_to_spans(loc),
        children=field_syntaxes + [closed_marker],
        close_position=line_widths.loc_to_spans(loc),
      )
    }
    Map(elems~, is_closed~, loc~) => {
      let elem_syntaxes = elems.map(Elab::elab(_, line_widths)).to_array()
      let closed_marker = if is_closed {
        Syntax::default()
      } else {
        Syntax::atom(content="..", position=[], kind=Normal)
      }
      Syntax::simple_list(
        open_position=line_widths.loc_to_spans(loc),
        children=elem_syntaxes + [closed_marker],
        close_position=line_widths.loc_to_spans(loc),
      )
    }
    Range(lhs~, rhs~, inclusive~, loc~) => {
      let lhs_syntax = Elab::elab(lhs, line_widths)
      let rhs_syntax = Elab::elab(rhs, line_widths)
      let range_op = if inclusive {
        Syntax::atom(content="..=", position=[], kind=Normal)
      } else {
        Syntax::atom(content="..", position=[], kind=Normal)
      }
      Syntax::simple_list(
        open_position=line_widths.loc_to_spans(loc),
        children=[lhs_syntax, range_op, rhs_syntax],
        close_position=line_widths.loc_to_spans(loc),
      )
    }
  }
}

///|
// impl Elab for @syntax.DeclBody with elab(decl_body, line_widths) {
//   match decl_body {
//     DeclBody(local_types~, expr~) => {
//       let local_type_syntaxes = local_types
//         .map(Elab::elab(_, line_widths))
//         .to_array()
//       let expr_syntax = Elab::elab(expr, line_widths)
//       Syntax::simple_list(
//         open_position=[],
//         children=local_type_syntaxes + [expr_syntax],
//         close_position=[],
//       )
//     }
//     DeclStubs(stubs) => Elab::elab(stubs, line_widths)
//   }
// }

///|
// impl Elab for @syntax.FuncStubs with elab(func_stubs, line_widths) {
//   match func_stubs {
//     Import(module_name~, func_name~) => {
//       let import_kw = Syntax::atom(content="import", position=[], kind=Keyword)
//       let module_syntax = Syntax::atom(
//         content=module_name.to_string(),
//         position=[],
//         kind=String(StringLiteral),
//       )
//       let func_syntax = Syntax::atom(
//         content=func_name.to_string(),
//         position=[],
//         kind=String(StringLiteral),
//       )
//       Syntax::simple_list(
//         open_position=[],
//         children=[import_kw, module_syntax, func_syntax],
//         close_position=[],
//       )
//     }
//     Embedded(language~, code~) => {
//       let embedded_kw = Syntax::atom(
//         content="embedded",
//         position=[],
//         kind=Keyword,
//       )
//       let lang_syntax = if language is Some(lang) {
//         Syntax::atom(
//           content=lang.to_string(),
//           position=[],
//           kind=String(StringLiteral),
//         )
//       } else {
//         Syntax::default()
//       }
//       let code_syntax = Elab::elab(code, line_widths)
//       Syntax::simple_list(
//         open_position=[],
//         children=[embedded_kw, lang_syntax, code_syntax],
//         close_position=[],
//       )
//     }
//   }
// }

///|
// impl Elab for @syntax.EmbeddedCode with elab(embedded_code, line_widths) {
//   match embedded_code {
//     CodeString(str_lit) => {
//       let content = str_lit.to_string()
//       Syntax::atom(content~, position=[], kind=String(StringLiteral))
//     }
//     CodeMultilineString(lines) => {
//       let content = lines.to_array().join("\n")
//       Syntax::atom(content~, position=[], kind=String(Text))
//     }
//   }
// }
