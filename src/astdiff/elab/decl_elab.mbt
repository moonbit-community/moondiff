///|UUID(67c1d4d7-f89c-4654-a9ce-18873f9c72fa)
fn ElabCtx::elab_constr_param(self : Self, param : ConstrParam) -> Syntax {
  let parts = Array::new()
  self.append_part(parts, param.label.map(fn(label) { self.part_label(label) }))
  parts.push(self.part_type(param.ty))
  self.region(param.loc, parts)
}

///|UUID(ac988fa0-272d-477b-a1e1-f2ec1d24ce1d)
fn ElabCtx::part_constr_param(self : Self, param : ConstrParam) -> Part {
  self.part(self.elab_constr_param(param), Some(param.loc))
}

///|UUID(70e14edc-8d74-431c-9c01-4b723440d446)
fn ElabCtx::elab_constr_decl(self : Self, decl : ConstrDecl) -> Syntax {
  let parts = Array::new()
  self.append_part(parts, self.part_doc(decl.doc))
  decl.attrs.each(fn(attr) { parts.push(self.part_attribute(attr)) })
  parts.push(self.part(self.elab_constr_name(decl.name), Some(decl.name.loc)))
  match decl.args {
    Some(args) => {
      let search_end = match decl.tag {
        Some((_, tag_loc)) => tag_loc.start.cnum
        None => decl.loc.end.cnum
      }
      let arg_parts = self.parts_from_list(args, fn(arg) {
        self.part_constr_param(arg)
      })
      match
        (
          self.find_char_forward(decl.name.loc.end.cnum, search_end, '('),
          self.find_char_backward(decl.name.loc.end.cnum, search_end, ')'),
        ) {
        (Some(open_loc), Some(close_loc)) =>
          parts.push(
            self.part(
              self.delimited(open_loc, arg_parts, close_loc),
              Some(open_loc.merge(close_loc)),
            ),
          )
        _ =>
          self.append_part(
            parts,
            merge_part_locs(arg_parts).map(fn(arg_loc) {
              self.part(self.region(arg_loc, arg_parts), Some(arg_loc))
            }),
          )
      }
    }
    None => ()
  }
  match decl.tag {
    Some((_, tag_loc)) =>
      parts.push(self.part(self.atom_from_loc(tag_loc), Some(tag_loc)))
    None => ()
  }
  self.region(decl.loc, parts)
}

///|UUID(65050346-09d8-4a1c-aa15-d0f55828f3fd)
fn ElabCtx::part_constr_decl(self : Self, decl : ConstrDecl) -> Part {
  self.part(self.elab_constr_decl(decl), Some(decl.loc))
}

///|UUID(ea969b90-c348-47c1-b475-7577eff8f9c1)
fn ElabCtx::elab_field_name(self : Self, name : FieldName) -> Syntax {
  self.tokenize_loc(name.loc)
}

///|UUID(2c1a2eb4-8961-4f35-b66d-c6d87c63dbfa)
fn ElabCtx::part_field_name(self : Self, name : FieldName) -> Part {
  self.part(self.elab_field_name(name), Some(name.loc))
}

///|UUID(8707a3ef-68eb-44f6-aeff-aa2570e10dd2)
fn ElabCtx::elab_field_decl(self : Self, decl : FieldDecl) -> Syntax {
  let parts = Array::new()
  self.append_part(parts, self.part_doc(decl.doc))
  decl.attrs.each(fn(attr) { parts.push(self.part_attribute(attr)) })
  self.append_part(parts, self.part_visibility(decl.vis))
  parts.push(self.part_field_name(decl.name))
  parts.push(self.part_type(decl.ty))
  self.region(decl.loc, parts)
}

///|UUID(aa43129b-f411-42ce-a276-b7f7c64298bb)
fn ElabCtx::part_field_decl(self : Self, decl : FieldDecl) -> Part {
  self.part(self.elab_field_decl(decl), Some(decl.loc))
}

///|UUID(1b6d0d8b-6b3e-49dc-a264-a60120490495)
fn ElabCtx::exception_decl_parts(
  self : Self,
  decl : ExceptionDecl,
) -> Array[Part] {
  match decl {
    NoPayload => []
    SinglePayload(ty) => [self.part_type(ty)]
    EnumPayload(constrs) =>
      self.parts_from_list(constrs, fn(constr) { self.part_constr_decl(constr) })
  }
}

///|UUID(07ec8657-9207-4d74-9cfe-21f1b3f388d5)
fn ElabCtx::type_desc_parts(self : Self, desc : TypeDesc) -> Array[Part] {
  match desc {
    Abstract | Extern => []
    Error(exception_decl) => self.exception_decl_parts(exception_decl)
    Variant(constrs) =>
      self.parts_from_list(constrs, fn(constr) { self.part_constr_decl(constr) })
    Record(fields~, constr_decl~) => {
      let parts = self.parts_from_list(fields, fn(field) {
        self.part_field_decl(field)
      })
      self.append_part(
        parts,
        constr_decl.map(fn(decl) { self.part_fun_decl(decl) }),
      )
      parts
    }
    TupleStruct(tys) => self.parts_from_list(tys, fn(ty) { self.part_type(ty) })
    Alias(ty) => [self.part_type(ty)]
  }
}

///|UUID(eec0af22-06e4-45b1-acd8-7d5a6d8de72d)
fn ElabCtx::type_desc_part(
  self : Self,
  desc : TypeDesc,
  body_lbrace_loc : Location?,
  body_rbrace_loc : Location?,
  body_lparen_loc : Location?,
  body_rparen_loc : Location?,
) -> Part? {
  let parts = self.type_desc_parts(desc)
  match (body_lbrace_loc, body_rbrace_loc) {
    (Some(lbrace_loc), Some(rbrace_loc)) =>
      Some(
        self.part(
          self.delimited(lbrace_loc, parts, rbrace_loc),
          Some(lbrace_loc.merge(rbrace_loc)),
        ),
      )
    _ =>
      match (body_lparen_loc, body_rparen_loc) {
        (Some(lparen_loc), Some(rparen_loc)) =>
          Some(
            self.part(
              self.delimited(lparen_loc, parts, rparen_loc),
              Some(lparen_loc.merge(rparen_loc)),
            ),
          )
        _ =>
          merge_part_locs(parts).map(fn(loc) {
            self.part(self.region(loc, parts), Some(loc))
          })
      }
  }
}

///|UUID(a96a2c35-4d3d-40af-98bf-4caa3a52776d)
fn ElabCtx::elab_deriving_directive(
  self : Self,
  directive : DerivingDirective,
) -> Syntax {
  let parts = Array::new()
  parts.push(
    self.part(
      self.elab_type_name(directive.type_name),
      Some(directive.type_name.loc),
    ),
  )
  if !directive.args.is_empty() {
    match
      (
        self.find_char_forward(
          directive.type_name.loc.end.cnum,
          directive.loc.end.cnum,
          '(',
        ),
        self.find_char_backward(
          directive.type_name.loc.end.cnum,
          directive.loc.end.cnum,
          ')',
        ),
      ) {
      (Some(open_loc), Some(close_loc)) =>
        parts.push(
          self.part(
            self.delimited(
              open_loc,
              self.parts_from_list(directive.args, fn(arg) {
                self.part_argument(arg)
              }),
              close_loc,
            ),
            Some(open_loc.merge(close_loc)),
          ),
        )
      _ => ()
    }
  }
  self.region(directive.loc, parts)
}

///|UUID(b7181f9f-fb34-48b9-8db8-b15ed1c0a243)
fn ElabCtx::part_deriving_directive(
  self : Self,
  directive : DerivingDirective,
) -> Part {
  self.part(self.elab_deriving_directive(directive), Some(directive.loc))
}

///|UUID(cab5082b-771c-41f0-a4f2-0efa59113fd5)
fn ElabCtx::deriving_part(
  self : Self,
  deriving : @list.List[DerivingDirective],
  derive_lparen_loc : Location?,
  derive_rparen_loc : Location?,
) -> Part? {
  if deriving.is_empty() &&
    !(derive_lparen_loc is Some(_) && derive_rparen_loc is Some(_)) {
    return None
  }
  let parts = self.parts_from_list(deriving, fn(directive) {
    self.part_deriving_directive(directive)
  })
  match (derive_lparen_loc, derive_rparen_loc) {
    (Some(lparen_loc), Some(rparen_loc)) =>
      Some(
        self.part(
          self.delimited(lparen_loc, parts, rparen_loc),
          Some(lparen_loc.merge(rparen_loc)),
        ),
      )
    _ =>
      merge_part_locs(parts).map(fn(loc) {
        self.part(self.region(loc, parts), Some(loc))
      })
  }
}

///|UUID(82262a44-a402-4d01-aa77-25b5fd85d91c)
fn ElabCtx::local_type_decl_loc(self : Self, decl : LocalTypeDecl) -> Location {
  let mut loc = Some(decl.tycon_loc)
  loc = merge_loc_option(loc, decl.keyword_loc)
  loc = merge_loc_option(loc, decl.body_lbrace_loc)
  loc = merge_loc_option(loc, decl.body_rbrace_loc)
  loc = merge_loc_option(loc, decl.body_lparen_loc)
  loc = merge_loc_option(loc, decl.body_rparen_loc)
  loc = merge_loc_option(loc, decl.derive_loc)
  loc = merge_loc_option(loc, decl.derive_lparen_loc)
  loc = merge_loc_option(loc, decl.derive_rparen_loc)
  loc = merge_loc_option(
    loc,
    merge_part_locs(self.type_desc_parts(decl.components)),
  )
  decl.deriving.each(fn(directive) {
    loc = merge_loc_option(loc, Some(directive.loc))
  })
  loc.unwrap_or(decl.tycon_loc)
}

///|UUID(3e527f9c-cba3-4bbc-a114-36dc99f533dd)
fn ElabCtx::elab_local_type_decl(self : Self, decl : LocalTypeDecl) -> Syntax {
  let loc = self.local_type_decl_loc(decl)
  let parts = Array::new()
  parts.push(
    self.part(
      self.tokenize_loc(decl.tycon_loc, word_kind=AtomKind::Type),
      Some(decl.tycon_loc),
    ),
  )
  self.append_part(
    parts,
    self.type_desc_part(
      decl.components,
      decl.body_lbrace_loc,
      decl.body_rbrace_loc,
      decl.body_lparen_loc,
      decl.body_rparen_loc,
    ),
  )
  self.append_part(
    parts,
    self.deriving_part(
      decl.deriving,
      decl.derive_lparen_loc,
      decl.derive_rparen_loc,
    ),
  )
  self.region(loc, parts)
}

///|UUID(4d3545ab-99ae-4f3c-a446-d5c7cd827768)
fn ElabCtx::part_local_type_decl(self : Self, decl : LocalTypeDecl) -> Part {
  let loc = self.local_type_decl_loc(decl)
  self.part(self.elab_local_type_decl(decl), Some(loc))
}

///|UUID(f04187ea-2945-441a-af06-befda367f752)
fn ElabCtx::elab_type_decl(self : Self, decl : TypeDecl) -> Syntax {
  let parts = Array::new()
  self.append_part(parts, self.part_doc(decl.doc))
  decl.attrs.each(fn(attr) { parts.push(self.part_attribute(attr)) })
  self.append_part(parts, self.part_visibility(decl.type_vis))
  parts.push(
    self.part(
      self.tokenize_loc(decl.tycon_loc, word_kind=AtomKind::Type),
      Some(decl.tycon_loc),
    ),
  )
  if !decl.params.is_empty() ||
    (
      decl.type_params_lbracket_loc is Some(_) &&
      decl.type_params_rbracket_loc is Some(_)
    ) {
    let param_parts = self.parts_from_list(decl.params, fn(param) {
      self.part_type_decl_binder(param)
    })
    let loc = match
      (
        decl.type_params_lbracket_loc,
        decl.type_params_rbracket_loc,
        merge_part_locs(param_parts),
      ) {
      (Some(lbracket_loc), Some(rbracket_loc), _) =>
        Some(lbracket_loc.merge(rbracket_loc))
      (_, _, Some(loc)) => Some(loc)
      _ => None
    }
    self.append_part(
      parts,
      loc.map(fn(loc) {
        self.part(
          self.delimited_or_region(
            loc,
            decl.type_params_lbracket_loc,
            param_parts,
            decl.type_params_rbracket_loc,
          ),
          Some(loc),
        )
      }),
    )
  }
  self.append_part(
    parts,
    self.type_desc_part(
      decl.components,
      decl.body_lbrace_loc,
      decl.body_rbrace_loc,
      decl.body_lparen_loc,
      decl.body_rparen_loc,
    ),
  )
  self.append_part(
    parts,
    self.deriving_part(
      decl.deriving,
      decl.derive_lparen_loc,
      decl.derive_rparen_loc,
    ),
  )
  self.region(decl.loc, parts)
}

///|UUID(3e3d276f-5591-4a1f-b13a-9bb7d2c438b8)
fn ElabCtx::part_type_decl(self : Self, decl : TypeDecl) -> Part {
  self.part(self.elab_type_decl(decl), Some(decl.loc))
}

///|UUID(89dde800-da7e-45ae-87be-97be65d4a5bf)
fn ElabCtx::elab_func_stubs(self : Self, stubs : FuncStubs) -> Syntax {
  ignore(self)
  ignore(stubs)
  Syntax::simple_list(open_position=[], children=[], close_position=[])
}

///|UUID(7c5e356b-9d30-4585-a847-58778c5f5bf8)
fn ElabCtx::elab_embedded_code(self : Self, code : EmbeddedCode) -> Syntax {
  ignore(self)
  ignore(code)
  Syntax::simple_list(open_position=[], children=[], close_position=[])
}

///|UUID(224a8f8a-6271-47d9-9a95-d9872e3b9c7d)
fn ElabCtx::decl_body_loc(self : Self, body : DeclBody) -> Location? {
  match body {
    DeclBody(
      local_types~,
      expr~,
      lbrace_loc~,
      rbrace_loc~,
      semi_locs~,
      trailing_semi_loc~
    ) => {
      let mut loc = Some(self.expr_loc(expr))
      self
      .parts_from_list(local_types, fn(local_type) {
        self.part_local_type_decl(local_type)
      })
      .each(fn(part) { loc = merge_loc_option(loc, part.loc) })
      loc = merge_loc_option(loc, lbrace_loc)
      loc = merge_loc_option(loc, rbrace_loc)
      loc = merge_loc_option(loc, merge_loc_list(semi_locs))
      loc = merge_loc_option(loc, trailing_semi_loc)
      loc
    }
    DeclStubs(_) | DeclNone => None
  }
}

///|UUID(273eff4f-e996-44a9-a043-0070d774fbef)
fn ElabCtx::elab_decl_body(self : Self, body : DeclBody) -> Syntax {
  match body {
    DeclBody(local_types~, expr~, lbrace_loc~, rbrace_loc~, ..) => {
      let parts = self.parts_from_list(local_types, fn(local_type) {
        self.part_local_type_decl(local_type)
      })
      parts.push(self.part_expr(expr))
      match self.decl_body_loc(body) {
        Some(loc) =>
          self.delimited_or_region(loc, lbrace_loc, parts, rbrace_loc)
        None => self.empty()
      }
    }
    DeclStubs(stubs) => self.elab_func_stubs(stubs)
    DeclNone => self.empty()
  }
}

///|UUID(5a7f5722-f365-42e6-8db8-f7a219f50cfc)
fn ElabCtx::part_decl_body(self : Self, body : DeclBody) -> Part? {
  self
  .decl_body_loc(body)
  .map(fn(loc) { self.part(self.elab_decl_body(body), Some(loc)) })
}

///|UUID(d0ba693d-3dc8-4ccc-8b24-93ad748b8f5b)
fn ElabCtx::fun_params_part(
  self : Self,
  decl_params : @list.List[Parameter]?,
  params_lparen_loc : Location?,
  params_rparen_loc : Location?,
) -> Part? {
  match (decl_params, params_lparen_loc, params_rparen_loc) {
    (Some(params), Some(lparen_loc), Some(rparen_loc)) =>
      Some(
        self.part(
          self.delimited(
            lparen_loc,
            self.parts_from_list(params, fn(param) {
              self.part_parameter(param)
            }),
            rparen_loc,
          ),
          Some(lparen_loc.merge(rparen_loc)),
        ),
      )
    (Some(params), _, _) =>
      merge_part_locs(
        self.parts_from_list(params, fn(param) { self.part_parameter(param) }),
      ).map(fn(loc) {
        self.part(
          self.region(
            loc,
            self.parts_from_list(params, fn(param) {
              self.part_parameter(param)
            }),
          ),
          Some(loc),
        )
      })
    (None, Some(lparen_loc), Some(rparen_loc)) =>
      Some(
        self.part(
          self.delimited(lparen_loc, [], rparen_loc),
          Some(lparen_loc.merge(rparen_loc)),
        ),
      )
    _ => None
  }
}

///|UUID(dda25ac8-8bdb-42aa-b8a5-9df591630071)
fn ElabCtx::elab_fun_decl(self : Self, decl : FunDecl) -> Syntax {
  let parts = Array::new()
  self.append_part(parts, self.part_doc(decl.doc))
  decl.attrs.each(fn(attr) { parts.push(self.part_attribute(attr)) })
  self.append_part(parts, self.part_visibility(decl.vis))
  self.append_part(
    parts,
    decl.type_name.map(fn(type_name) {
      self.part(self.elab_type_name(type_name), Some(type_name.loc))
    }),
  )
  parts.push(self.part_binder(decl.name))
  self.append_part(
    parts,
    self.fun_params_part(
      decl.decl_params,
      decl.params_lparen_loc,
      decl.params_rparen_loc,
    ),
  )
  if !decl.quantifiers.is_empty() ||
    (
      decl.type_params_lbracket_loc is Some(_) &&
      decl.type_params_rbracket_loc is Some(_)
    ) {
    let parts_ = self.parts_from_list(decl.quantifiers, fn(q) {
      self.part_type_var_binder(q)
    })
    let loc = match
      (
        decl.type_params_lbracket_loc,
        decl.type_params_rbracket_loc,
        merge_part_locs(parts_),
      ) {
      (Some(lbracket_loc), Some(rbracket_loc), _) =>
        Some(lbracket_loc.merge(rbracket_loc))
      (_, _, Some(loc)) => Some(loc)
      _ => None
    }
    self.append_part(
      parts,
      loc.map(fn(loc) {
        self.part(
          self.delimited_or_region(
            loc,
            decl.type_params_lbracket_loc,
            parts_,
            decl.type_params_rbracket_loc,
          ),
          Some(loc),
        )
      }),
    )
  }
  self.append_part(parts, decl.return_type.map(fn(ty) { self.part_type(ty) }))
  self.append_part(parts, self.part_error_type(decl.error_type))
  self.region(decl.loc, parts)
}

///|UUID(f9b4a60b-a16c-402e-a4c4-c4596d07eb56)
fn ElabCtx::part_fun_decl(self : Self, decl : FunDecl) -> Part {
  self.part(self.elab_fun_decl(decl), Some(decl.loc))
}

///|UUID(86c60871-a051-42fe-ba5d-f346c39e537f)
fn ElabCtx::elab_trait_method_decl(
  self : Self,
  decl : TraitMethodDecl,
) -> Syntax {
  let parts = Array::new()
  decl.attrs.each(fn(attr) { parts.push(self.part_attribute(attr)) })
  parts.push(self.part_binder(decl.name))
  if !decl.quantifiers.is_empty() ||
    (
      decl.type_params_lbracket_loc is Some(_) &&
      decl.type_params_rbracket_loc is Some(_)
    ) {
    let parts_ = self.parts_from_list(decl.quantifiers, fn(q) {
      self.part_type_var_binder(q)
    })
    let loc = match
      (
        decl.type_params_lbracket_loc,
        decl.type_params_rbracket_loc,
        merge_part_locs(parts_),
      ) {
      (Some(lbracket_loc), Some(rbracket_loc), _) =>
        Some(lbracket_loc.merge(rbracket_loc))
      (_, _, Some(loc)) => Some(loc)
      _ => None
    }
    self.append_part(
      parts,
      loc.map(fn(loc) {
        self.part(
          self.delimited_or_region(
            loc,
            decl.type_params_lbracket_loc,
            parts_,
            decl.type_params_rbracket_loc,
          ),
          Some(loc),
        )
      }),
    )
  }
  self.append_part(
    parts,
    self.fun_params_part(
      Some(decl.params),
      decl.params_lparen_loc,
      decl.params_rparen_loc,
    ),
  )
  self.append_part(parts, decl.return_type.map(fn(ty) { self.part_type(ty) }))
  self.append_part(parts, self.part_error_type(decl.error_type))
  self.region(decl.loc, parts)
}

///|UUID(340169b9-f4da-4304-88b4-454777ca8f58)
fn ElabCtx::part_trait_method_decl(self : Self, decl : TraitMethodDecl) -> Part {
  self.part(self.elab_trait_method_decl(decl), Some(decl.loc))
}

///|UUID(0dacaa83-bd09-4604-a0d6-5911112e7bfa)
fn ElabCtx::elab_trait_decl(self : Self, decl : TraitDecl) -> Syntax {
  let parts = Array::new()
  self.append_part(parts, self.part_doc(decl.doc))
  decl.attrs.each(fn(attr) { parts.push(self.part_attribute(attr)) })
  self.append_part(parts, self.part_visibility(decl.vis))
  parts.push(self.part_binder(decl.name))
  parts.push_iter(
    self
    .parts_from_list(decl.supers, fn(super_) {
      self.part(self.elab_type_var_constraint(super_), Some(super_.loc))
    })
    .iter(),
  )
  match (decl.lbrace_loc, decl.rbrace_loc) {
    (Some(lbrace_loc), Some(rbrace_loc)) =>
      parts.push(
        self.part(
          self.delimited(
            lbrace_loc,
            self.parts_from_list(decl.methods, fn(method_decl) {
              self.part_trait_method_decl(method_decl)
            }),
            rbrace_loc,
          ),
          Some(lbrace_loc.merge(rbrace_loc)),
        ),
      )
    _ => ()
  }
  self.region(decl.loc, parts)
}

///|UUID(1f1434ab-82b9-4c03-a51c-c0c372f854bf)
fn ElabCtx::part_trait_decl(self : Self, decl : TraitDecl) -> Part {
  self.part(self.elab_trait_decl(decl), Some(decl.loc))
}

///|UUID(6094e4c4-1b51-4310-89d9-c32f66988f67)
pub fn ElabCtx::elab_impl(self : Self, impl_ : Impl) -> Syntax {
  match impl_ {
    TopExpr(expr~, local_types~, loc~, ..) => {
      let parts = self.parts_from_list(local_types, fn(local_type) {
        self.part_local_type_decl(local_type)
      })
      parts.push(self.part_expr(expr))
      self.region(loc, parts)
    }
    TopTest(expr~, name~, params~, local_types~, loc~, attrs~, doc~, ..) => {
      let parts = Array::new()
      self.append_part(parts, self.part_doc(doc))
      attrs.each(fn(attr) { parts.push(self.part_attribute(attr)) })
      match name {
        Some((_, name_loc)) =>
          parts.push(self.part(self.string_from_loc(name_loc), Some(name_loc)))
        None => ()
      }
      match params {
        Some(params) =>
          self.append_part(
            parts,
            merge_part_locs(
              self.parts_from_list(params, fn(param) {
                self.part_parameter(param)
              }),
            ).map(fn(params_loc) {
              self.part(
                match self.outer_delim_locs(params_loc, '(', ')') {
                  Some((lparen_loc, rparen_loc)) =>
                    self.delimited(
                      lparen_loc,
                      self.parts_from_list(params, fn(param) {
                        self.part_parameter(param)
                      }),
                      rparen_loc,
                    )
                  None =>
                    self.region(
                      params_loc,
                      self.parts_from_list(params, fn(param) {
                        self.part_parameter(param)
                      }),
                    )
                },
                Some(params_loc),
              )
            }),
          )
        None => ()
      }
      parts.push_iter(
        self
        .parts_from_list(local_types, fn(local_type) {
          self.part_local_type_decl(local_type)
        })
        .iter(),
      )
      parts.push(self.part_expr(expr))
      self.region(loc, parts)
    }
    TopTypeDef(type_decl, ..) => self.elab_type_decl(type_decl)
    TopFuncDef(fun_decl~, decl_body~, loc~, ..) => {
      let parts = Array::new()
      parts.push(self.part_fun_decl(fun_decl))
      self.append_part(parts, self.part_decl_body(decl_body))
      self.region(loc, parts)
    }
    TopLetDef(binder~, ty~, expr~, vis~, loc~, attrs~, doc~, ..) => {
      let parts = Array::new()
      self.append_part(parts, self.part_doc(doc))
      attrs.each(fn(attr) { parts.push(self.part_attribute(attr)) })
      self.append_part(parts, self.part_visibility(vis))
      parts.push(self.part_binder(binder))
      self.append_part(parts, ty.map(fn(ty) { self.part_type(ty) }))
      parts.push(self.part_expr(expr))
      self.region(loc, parts)
    }
    TopTrait(trait_decl, ..) => self.elab_trait_decl(trait_decl)
    TopImpl(
      self_ty~,
      trait_~,
      method_name~,
      quantifiers~,
      params~,
      ret_ty~,
      err_ty~,
      body~,
      vis~,
      loc~,
      attrs~,
      doc~,
      type_params_lbracket_loc~,
      type_params_rbracket_loc~,
      params_lparen_loc~,
      params_rparen_loc~,
      ..
    ) => {
      let parts = Array::new()
      self.append_part(parts, self.part_doc(doc))
      attrs.each(fn(attr) { parts.push(self.part_attribute(attr)) })
      self.append_part(parts, self.part_visibility(vis))
      self.append_part(parts, self_ty.map(fn(ty) { self.part_type(ty) }))
      parts.push(self.part(self.elab_type_name(trait_), Some(trait_.loc)))
      parts.push(self.part_binder(method_name))
      if !quantifiers.is_empty() ||
        (
          type_params_lbracket_loc is Some(_) &&
          type_params_rbracket_loc is Some(_)
        ) {
        let parts_ = self.parts_from_list(quantifiers, fn(q) {
          self.part_type_var_binder(q)
        })
        let qloc = match
          (
            type_params_lbracket_loc,
            type_params_rbracket_loc,
            merge_part_locs(parts_),
          ) {
          (Some(lbracket_loc), Some(rbracket_loc), _) =>
            Some(lbracket_loc.merge(rbracket_loc))
          (_, _, Some(loc)) => Some(loc)
          _ => None
        }
        self.append_part(
          parts,
          qloc.map(fn(qloc) {
            self.part(
              self.delimited_or_region(
                qloc, type_params_lbracket_loc, parts_, type_params_rbracket_loc,
              ),
              Some(qloc),
            )
          }),
        )
      }
      self.append_part(
        parts,
        self.fun_params_part(Some(params), params_lparen_loc, params_rparen_loc),
      )
      self.append_part(parts, ret_ty.map(fn(ty) { self.part_type(ty) }))
      self.append_part(parts, self.part_error_type(err_ty))
      self.append_part(parts, self.part_decl_body(body))
      self.region(loc, parts)
    }
    TopView(
      quantifiers~,
      source_ty~,
      view_type_name~,
      view_type_loc~,
      view_constrs~,
      view_func_name~,
      parameters~,
      body~,
      vis~,
      loc~,
      attrs~,
      doc~,
      type_params_lbracket_loc~,
      type_params_rbracket_loc~,
      constr_lbrace_loc~,
      constr_rbrace_loc~,
      params_lparen_loc~,
      params_rparen_loc~,
      ..
    ) => {
      let parts = Array::new()
      self.append_part(parts, self.part_doc(doc))
      attrs.each(fn(attr) { parts.push(self.part_attribute(attr)) })
      self.append_part(parts, self.part_visibility(vis))
      if !quantifiers.is_empty() ||
        (
          type_params_lbracket_loc is Some(_) &&
          type_params_rbracket_loc is Some(_)
        ) {
        let parts_ = self.parts_from_list(quantifiers, fn(q) {
          self.part_type_var_binder(q)
        })
        let qloc = match
          (
            type_params_lbracket_loc,
            type_params_rbracket_loc,
            merge_part_locs(parts_),
          ) {
          (Some(lbracket_loc), Some(rbracket_loc), _) =>
            Some(lbracket_loc.merge(rbracket_loc))
          (_, _, Some(loc)) => Some(loc)
          _ => None
        }
        self.append_part(
          parts,
          qloc.map(fn(qloc) {
            self.part(
              self.delimited_or_region(
                qloc, type_params_lbracket_loc, parts_, type_params_rbracket_loc,
              ),
              Some(qloc),
            )
          }),
        )
      }
      parts.push(self.part_type(source_ty))
      parts.push(
        self.part(
          self.tokenize_loc(view_type_loc, word_kind=AtomKind::Type),
          Some(view_type_loc),
        ),
      )
      match (constr_lbrace_loc, constr_rbrace_loc) {
        (Some(lbrace_loc), Some(rbrace_loc)) =>
          parts.push(
            self.part(
              self.delimited(
                lbrace_loc,
                self.parts_from_list(view_constrs, fn(constr) {
                  self.part_constr_decl(constr)
                }),
                rbrace_loc,
              ),
              Some(lbrace_loc.merge(rbrace_loc)),
            ),
          )
        _ => ()
      }
      parts.push(self.part_binder(view_func_name))
      self.append_part(
        parts,
        self.fun_params_part(
          Some(parameters),
          params_lparen_loc,
          params_rparen_loc,
        ),
      )
      parts.push(self.part_expr(body))
      self.region(loc, parts)
    }
    TopImplRelation(
      self_ty~,
      trait_~,
      quantifiers~,
      vis~,
      attrs~,
      loc~,
      doc~,
      type_params_lbracket_loc~,
      type_params_rbracket_loc~,
      ..
    ) => {
      let parts = Array::new()
      self.append_part(parts, self.part_doc(doc))
      attrs.each(fn(attr) { parts.push(self.part_attribute(attr)) })
      self.append_part(parts, self.part_visibility(vis))
      if !quantifiers.is_empty() ||
        (
          type_params_lbracket_loc is Some(_) &&
          type_params_rbracket_loc is Some(_)
        ) {
        let parts_ = self.parts_from_list(quantifiers, fn(q) {
          self.part_type_var_binder(q)
        })
        let qloc = match
          (
            type_params_lbracket_loc,
            type_params_rbracket_loc,
            merge_part_locs(parts_),
          ) {
          (Some(lbracket_loc), Some(rbracket_loc), _) =>
            Some(lbracket_loc.merge(rbracket_loc))
          (_, _, Some(loc)) => Some(loc)
          _ => None
        }
        self.append_part(
          parts,
          qloc.map(fn(qloc) {
            self.part(
              self.delimited_or_region(
                qloc, type_params_lbracket_loc, parts_, type_params_rbracket_loc,
              ),
              Some(qloc),
            )
          }),
        )
      }
      parts.push(self.part(self.elab_type_name(trait_), Some(trait_.loc)))
      parts.push(self.part_type(self_ty))
      self.region(loc, parts)
    }
    TopUsing(
      pkg~,
      names~,
      vis~,
      attrs~,
      loc~,
      doc~,
      lbrace_loc~,
      rbrace_loc~,
      ..
    ) => {
      let parts = Array::new()
      self.append_part(parts, self.part_doc(doc))
      attrs.each(fn(attr) { parts.push(self.part_attribute(attr)) })
      self.append_part(parts, self.part_visibility(vis))
      parts.push(self.part_label(pkg))
      match (lbrace_loc, rbrace_loc) {
        (Some(lbrace_loc), Some(rbrace_loc)) =>
          parts.push(
            self.part(
              self.delimited(
                lbrace_loc,
                self.parts_from_list(names, fn(name) {
                  let (target, _kind) = name
                  self.part_alias_target(target)
                }),
                rbrace_loc,
              ),
              Some(lbrace_loc.merge(rbrace_loc)),
            ),
          )
        _ => ()
      }
      self.region(loc, parts)
    }
  }
}
