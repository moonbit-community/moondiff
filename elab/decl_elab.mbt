///|UUID(67c1d4d7-f89c-4654-a9ce-18873f9c72fa)
fn ElabCtx::constr_param_loc(self : Self, param : ConstrParam) -> Location {
  let mut loc = Some(self.type_loc(param.ty))
  loc = merge_loc_option(loc, param.mut_loc)
  match param.label {
    Some(label) => loc = merge_loc_option(loc, Some(label.loc))
    None => ()
  }
  loc = merge_loc_option(loc, param.post_label_loc)
  loc = merge_loc_option(loc, param.colon_loc)
  loc.unwrap_or(self.type_loc(param.ty))
}

///|UUID(67c1d4d7-f89c-4654-a9ce-18873f9c72fa)
fn ElabCtx::elab_constr_param(self : Self, param : ConstrParam) -> Syntax {
  let loc = self.constr_param_loc(param)
  let parts = Array::new()
  self.append_part(parts, param.label.map(fn(label) { self.part_label(label) }))
  parts.push(self.part_type(param.ty))
  self.region(loc, parts)
}

///|UUID(ac988fa0-272d-477b-a1e1-f2ec1d24ce1d)
fn ElabCtx::part_constr_param(self : Self, param : ConstrParam) -> Part {
  self.part(self.elab_constr_param(param), Some(self.constr_param_loc(param)))
}

///|UUID(70e14edc-8d74-431c-9c01-4b723440d446)
fn ElabCtx::elab_constr_decl(self : Self, decl : ConstrDecl) -> Syntax {
  let parts = Array::new()
  self.append_part(parts, self.part_doc(decl.doc))
  decl.attrs.each(fn(attr) { parts.push(self.part_attribute(attr)) })
  parts.push(self.part(self.elab_constr_name(decl.name), Some(decl.name.loc)))
  match decl.args {
    Some(args) => {
      let arg_parts = self.parts_from_list(args, fn(arg) {
        self.part_constr_param(arg)
      })
      match (decl.args_lparen_loc, decl.args_rparen_loc) {
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

///|UUID(eec0af22-06e4-45b1-acd8-7d5a6d8de72d)
fn ElabCtx::type_desc_part(self : Self, desc : TypeDesc) -> Part? {
  match desc {
    Abstract | Error(NoPayload) => None
    Error(EnumPayload(constrs~, lbrace_loc~, rbrace_loc~, ..))
    | ExtensibleEnum(constrs~, lbrace_loc~, rbrace_loc~, ..)
    | Variant(constrs~, lbrace_loc~, rbrace_loc~, ..) => {
      let parts = self.parts_from_list(constrs, fn(constr) {
        self.part_constr_decl(constr)
      })
      Some(
        self.part(
          self.delimited(lbrace_loc, parts, rbrace_loc),
          Some(lbrace_loc.merge(rbrace_loc)),
        ),
      )
    }
    ExtendEnum(target~, constructors~, lbrace_loc~, rbrace_loc~, ..) => {
      let parts = Array::new()
      parts.push(self.part(self.elab_type_name(target), Some(target.loc)))
      let constr_parts = self.parts_from_list(constructors, fn(constr) {
        self.part_constr_decl(constr)
      })
      parts.push(
        self.part(
          self.delimited(lbrace_loc, constr_parts, rbrace_loc),
          Some(lbrace_loc.merge(rbrace_loc)),
        ),
      )
      let loc = target.loc.merge(rbrace_loc)
      Some(self.part(self.region(loc, parts), Some(loc)))
    }
    Record(fields~, constr_decl~, lbrace_loc~, rbrace_loc~, ..) => {
      let parts = self.parts_from_list(fields, fn(field) {
        self.part_field_decl(field)
      })
      self.append_part(
        parts,
        constr_decl.map(fn(decl) { self.part_fun_decl(decl) }),
      )
      Some(
        self.part(
          self.delimited(lbrace_loc, parts, rbrace_loc),
          Some(lbrace_loc.merge(rbrace_loc)),
        ),
      )
    }
    TupleStruct(types~, lparen_loc~, rparen_loc~, ..) => {
      let parts = self.parts_from_list(types, fn(ty) { self.part_type(ty) })
      Some(
        self.part(
          self.delimited(lparen_loc, parts, rparen_loc),
          Some(lparen_loc.merge(rparen_loc)),
        ),
      )
    }
    Alias(type_~, ..) => Some(self.part_type(type_))
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
    (decl.params_lbracket_loc is Some(_) && decl.params_rbracket_loc is Some(_)) {
    let param_parts = self.parts_from_list(decl.params, fn(param) {
      self.part_type_decl_binder(param)
    })
    let loc = match
      (
        decl.params_lbracket_loc,
        decl.params_rbracket_loc,
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
            decl.params_lbracket_loc,
            param_parts,
            decl.params_rbracket_loc,
          ),
          Some(loc),
        )
      }),
    )
  }
  self.append_part(parts, self.type_desc_part(decl.components))
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

///|UUID(89dde800-da7e-45ae-87be-97be65d4a5bf)
fn func_stubs_loc(stubs : FuncStubs) -> Location {
  match stubs {
    Import(module_name_loc~, func_name_loc~, ..) =>
      module_name_loc.merge(func_name_loc)
    Embedded(code_loc~, ..) => code_loc
  }
}

///|UUID(89dde800-da7e-45ae-87be-97be65d4a5bf)
fn ElabCtx::elab_func_stubs(self : Self, stubs : FuncStubs) -> Syntax {
  match stubs {
    Import(module_name_loc~, func_name_loc~, ..) => {
      let loc = module_name_loc.merge(func_name_loc)
      self.region(loc, [
        self.part(self.string_from_loc(module_name_loc), Some(module_name_loc)),
        self.part(self.string_from_loc(func_name_loc), Some(func_name_loc)),
      ])
    }
    Embedded(code=CodeString(_, loc=literal_loc), ..) =>
      self.string_from_loc(literal_loc)
    Embedded(code=CodeMultilineString(_, string_locs~), code_loc~, ..) =>
      self.region(
        code_loc,
        self.parts_from_list(string_locs, fn(loc) {
          self.part(self.string_from_loc(loc), Some(loc))
        }),
      )
  }
}

///|UUID(89dde800-da7e-45ae-87be-97be65d4a5bf)
fn ElabCtx::part_func_stubs(self : Self, stubs : FuncStubs) -> Part {
  let loc = func_stubs_loc(stubs)
  self.part(self.elab_func_stubs(stubs), Some(loc))
}

///|UUID(224a8f8a-6271-47d9-9a95-d9872e3b9c7d)
fn ElabCtx::decl_body_loc(self : Self, body : DeclBody) -> Location? {
  match body {
    DeclBody(expr~, lbrace_loc~, rbrace_loc~) => {
      let mut loc = Some(self.expr_loc(expr))
      loc = merge_loc_option(loc, lbrace_loc)
      loc = merge_loc_option(loc, rbrace_loc)
      loc
    }
    DeclStubs(stubs, equal_loc~) => Some(equal_loc.merge(func_stubs_loc(stubs)))
    DeclNone => None
  }
}

///|UUID(273eff4f-e996-44a9-a043-0070d774fbef)
fn ElabCtx::elab_decl_body(self : Self, body : DeclBody) -> Syntax {
  match body {
    DeclBody(expr~, lbrace_loc~, rbrace_loc~) => {
      let parts = match (lbrace_loc, rbrace_loc) {
        (Some(_), Some(_)) => self.block_stmt_parts(expr)
        _ => [self.part_expr(expr)]
      }
      match self.decl_body_loc(body) {
        Some(loc) =>
          self.delimited_or_region(loc, lbrace_loc, parts, rbrace_loc)
        None => self.empty()
      }
    }
    DeclStubs(stubs, ..) =>
      match self.decl_body_loc(body) {
        Some(loc) => self.region(loc, [self.part_func_stubs(stubs)])
        None => self.empty()
      }
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
      Some(decl.params_lparen_loc),
      Some(decl.params_rparen_loc),
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
  parts.push(
    self.part(
      self.delimited(
        decl.lbrace_loc,
        self.parts_from_list(decl.methods, fn(method_decl) {
          self.part_trait_method_decl(method_decl)
        }),
        decl.rbrace_loc,
      ),
      Some(decl.lbrace_loc.merge(decl.rbrace_loc)),
    ),
  )
  self.region(decl.loc, parts)
}

///|UUID(6094e4c4-1b51-4310-89d9-c32f66988f67)
pub fn ElabCtx::elab_impl(self : Self, impl_ : Impl) -> Syntax {
  match impl_ {
    TopExpr(expr~, loc~, ..) => {
      let parts = Array::new()
      parts.push(self.part_expr(expr))
      self.region(loc, parts)
    }
    TopTest(
      expr~,
      name~,
      params~,
      loc~,
      attrs~,
      doc~,
      params_lparen_loc~,
      params_rparen_loc~,
      body_lbrace_loc~,
      body_rbrace_loc~,
      ..
    ) => {
      let parts = Array::new()
      self.append_part(parts, self.part_doc(doc))
      attrs.each(fn(attr) { parts.push(self.part_attribute(attr)) })
      match name {
        Some((_, name_loc)) =>
          parts.push(self.part(self.string_from_loc(name_loc), Some(name_loc)))
        None => ()
      }
      self.append_part(
        parts,
        self.fun_params_part(params, params_lparen_loc, params_rparen_loc),
      )
      parts.push(
        self.part(
          self.delimited(
            body_lbrace_loc,
            self.block_stmt_parts(expr),
            body_rbrace_loc,
          ),
          Some(body_lbrace_loc.merge(body_rbrace_loc)),
        ),
      )
      self.region(loc, parts)
    }
    TopTypeDef(type_decl) => self.elab_type_decl(type_decl)
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
    TopTrait(trait_decl) => self.elab_trait_decl(trait_decl)
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
        self.fun_params_part(
          Some(params),
          Some(params_lparen_loc),
          Some(params_rparen_loc),
        ),
      )
      self.append_part(parts, ret_ty.map(fn(ty) { self.part_type(ty) }))
      self.append_part(parts, self.part_error_type(err_ty))
      self.append_part(parts, self.part_decl_body(body))
      self.region(loc, parts)
    }
    TopView(
      quantifiers~,
      source_ty~,
      view_type_name=_,
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
      lbrace_loc~,
      rbrace_loc~,
      params_lparen_loc~,
      params_rparen_loc~,
      body_lbrace_loc~,
      body_rbrace_loc~,
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
      parts.push(self.part_binder(view_func_name))
      self.append_part(
        parts,
        self.fun_params_part(
          Some(parameters),
          Some(params_lparen_loc),
          Some(params_rparen_loc),
        ),
      )
      parts.push(
        self.part(
          self.delimited(
            body_lbrace_loc,
            self.block_stmt_parts(body),
            body_rbrace_loc,
          ),
          Some(body_lbrace_loc.merge(body_rbrace_loc)),
        ),
      )
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
      parts.push(self.part(self.package_atom_from_loc(pkg.loc), Some(pkg.loc)))
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
      self.region(loc, parts)
    }
  }
}
