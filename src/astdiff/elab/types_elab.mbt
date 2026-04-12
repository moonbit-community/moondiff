///|UUID(38201113-d93b-4603-ae9f-25f6a9328f4c)
fn ElabCtx::elab_doc_string(self : Self, doc : DocString) -> Syntax {
  self.comment_from_loc(doc.loc)
}

///|UUID(8ca7c2f3-2643-46aa-8e38-12b33c0bdf55)
fn ElabCtx::elab_attribute(self : Self, attr : Attribute) -> Syntax {
  self.atom_from_loc(attr.loc)
}

///|UUID(d8cb1320-c8f0-4708-8e46-62151819a8b0)
fn ElabCtx::elab_constant(
  self : Self,
  constant : Constant,
  loc : Location,
) -> Syntax {
  match constant {
    Bool(_) => self.atom_from_loc(loc, kind=AtomKind::Keyword)
    Byte(_) | Bytes(_) | Char(_) | Constant::String(_) =>
      self.string_from_loc(loc)
    Int(_)
    | Int64(_)
    | UInt(_)
    | UInt64(_)
    | Float(_)
    | Double(_)
    | BigInt(_) => self.atom_from_loc(loc)
  }
}

///|UUID(7d8b1947-eaea-4540-aa39-6d8bd262b2b6)
fn ElabCtx::elab_label(self : Self, label : Label) -> Syntax {
  self.tokenize_loc(label.loc)
}

///|UUID(20468bd7-8a56-4883-a5f1-3460e9c3b9bf)
fn ElabCtx::elab_binder(self : Self, binder : Binder) -> Syntax {
  self.tokenize_loc(binder.loc)
}

///|UUID(ba8be93c-f347-4787-9991-f23b871054f5)
fn ElabCtx::elab_constr_name(self : Self, name : ConstrName) -> Syntax {
  self.tokenize_loc(name.loc, word_kind=AtomKind::Type)
}

///|UUID(2bbf5284-963e-403b-a0d1-25c77c250147)
fn ElabCtx::elab_long_ident(
  self : Self,
  ident : LongIdent,
  loc : Location,
  atom_kind : AtomKind,
) -> Syntax {
  ignore(ident)
  self.tokenize_loc(loc, word_kind=atom_kind)
}

///|UUID(b27e66a8-5e01-46dc-9b48-deac49285613)
fn ElabCtx::elab_type_name(self : Self, type_name : TypeName) -> Syntax {
  self.elab_long_ident(type_name.name, type_name.loc, AtomKind::Type)
}

///|UUID(8391d388-d9b4-4f1b-96c0-8ba1869f5bbd)
fn ElabCtx::elab_constr_id(self : Self, constr_id : ConstrId) -> Syntax {
  self.elab_long_ident(constr_id.id, constr_id.loc, AtomKind::Type)
}

///|UUID(91e301ac-bdde-4300-9578-0e123a0148a5)
fn ElabCtx::elab_var(self : Self, var_ : Var) -> Syntax {
  self.elab_long_ident(var_.name, var_.loc, AtomKind::Normal)
}

///|UUID(767e5d8e-0223-43d6-997b-2c2642f32930)
fn ElabCtx::elab_constructor(self : Self, ctor : Constructor) -> Syntax {
  self.tokenize_loc(ctor.loc, word_kind=AtomKind::Type)
}

///|UUID(7e1f9a37-89c7-424c-8a58-0e5fc90145e7)
fn ElabCtx::elab_accessor(self : Self, accessor : Accessor) -> Syntax {
  match accessor {
    Label(label) => self.elab_label(label)
    Index(loc~, ..) | Newtype(loc~) => self.tokenize_loc(loc)
  }
}

///|UUID(b8bd070f-d02a-43d0-a8fd-10f0c530b997)
fn ElabCtx::type_loc(self : Self, ty : Type) -> Location {
  ignore(self)
  match ty {
    Object(constr_id~, amp_loc~) =>
      merge_loc_option(Some(constr_id.loc), amp_loc).unwrap_or(constr_id.loc)
    _ => ty.loc()
  }
}

///|UUID(6f849862-455a-4b6e-b909-673c48c8b758)
pub fn ElabCtx::elab_type(self : Self, ty : Type) -> Syntax {
  match ty {
    Any(loc~) => self.tokenize_loc(loc, word_kind=AtomKind::Type)
    Arrow(args~, res~, err~, loc~, lparen_loc~, rparen_loc~, ..) => {
      let parts = Array::new()
      if lparen_loc is Some(lparen) && rparen_loc is Some(rparen) {
        let arg_parts = self.parts_from_list(args, fn(arg) {
          self.part_type(arg)
        })
        parts.push(
          self.part(
            self.delimited(lparen, arg_parts, rparen),
            Some(lparen.merge(rparen)),
          ),
        )
      } else {
        parts.push_iter(
          self.parts_from_list(args, fn(arg) { self.part_type(arg) }).iter(),
        )
      }
      parts.push(self.part_type(res))
      self.append_part(parts, self.part_error_type(err))
      self.region(loc, parts)
    }
    Tuple(tys~, loc~, lparen_loc~, rparen_loc~, ..) => {
      let parts = self.parts_from_list(tys, fn(ty) { self.part_type(ty) })
      self.delimited_or_region(loc, lparen_loc, parts, rparen_loc)
    }
    Name(constr_id~, tys~, loc~, lbracket_loc~, rbracket_loc~, ..) => {
      let parts = Array::new()
      parts.push(self.part(self.elab_constr_id(constr_id), Some(constr_id.loc)))
      if !tys.is_empty() || (lbracket_loc is Some(_) && rbracket_loc is Some(_)) {
        let ty_parts = self.parts_from_list(tys, fn(ty) { self.part_type(ty) })
        let arg_loc = match
          (lbracket_loc, rbracket_loc, merge_part_locs(ty_parts)) {
          (Some(lbracket), Some(rbracket), _) => Some(lbracket.merge(rbracket))
          (_, _, Some(inner_loc)) => Some(inner_loc)
          _ => None
        }
        parts.push(
          self.part(
            match (lbracket_loc, rbracket_loc, arg_loc) {
              (Some(lbracket), Some(rbracket), _) =>
                self.delimited(lbracket, ty_parts, rbracket)
              (_, _, Some(arg_loc)) => self.region(arg_loc, ty_parts)
              _ => self.empty()
            },
            arg_loc,
          ),
        )
      }
      self.region(loc, parts)
    }
    Option(ty~, loc~, ..) => self.region(loc, [self.part_type(ty)])
    Object(constr_id~, amp_loc~) => {
      let loc = merge_loc_option(Some(constr_id.loc), amp_loc).unwrap_or(
        constr_id.loc,
      )
      self.region(loc, [
        self.part(self.elab_constr_id(constr_id), Some(constr_id.loc)),
      ])
    }
  }
}

///|UUID(3c562e37-31b5-4d77-9917-fbda6c697b92)
fn ElabCtx::error_type_loc(self : Self, err : ErrorType) -> Location? {
  match err {
    ErrorType(ty~) => Some(self.type_loc(ty))
    DefaultErrorType(loc~) => Some(loc)
    NoErrorType => None
    Noraise(loc~) => Some(loc)
    MaybeError(ty~, question_loc~) =>
      merge_loc_option(Some(self.type_loc(ty)), question_loc)
  }
}

///|UUID(03d7a22b-a3ea-44df-a6f7-43ff5e02104c)
fn ElabCtx::part_error_type(self : Self, err : ErrorType) -> Part? {
  self
  .error_type_loc(err)
  .map(fn(loc) { self.part(self.elab_error_type(err), Some(loc)) })
}

///|UUID(6e4024b0-ab2c-4b97-8ee8-50e774a9846c)
fn ElabCtx::elab_error_type(self : Self, err : ErrorType) -> Syntax {
  match err {
    ErrorType(ty~) => self.elab_type(ty)
    DefaultErrorType(loc~) | Noraise(loc~) =>
      self.tokenize_loc(loc, classify_keywords=true)
    NoErrorType => self.empty()
    MaybeError(ty~, question_loc~) => {
      let loc = merge_loc_option(Some(self.type_loc(ty)), question_loc).unwrap_or(
        self.type_loc(ty),
      )
      self.region(loc, [self.part_type(ty)])
    }
  }
}

///|UUID(20a1e4bf-d412-41a4-9af0-592bb40fa956)
fn ElabCtx::elab_type_var_constraint(
  self : Self,
  constraint : TypeVarConstraint,
) -> Syntax {
  self.tokenize_loc(constraint.loc, word_kind=AtomKind::Type)
}

///|UUID(3cf65b90-c5c7-4550-bc0a-fdcdf7856740)
fn ElabCtx::type_var_binder_loc(
  self : Self,
  binder : TypeVarBinder,
) -> Location {
  ignore(self)
  let mut loc = Some(binder.name_loc)
  loc = merge_loc_option(loc, binder.colon_loc)
  loc = merge_loc_option(loc, merge_loc_list(binder.plus_locs))
  binder.constraints.each(fn(constraint) {
    loc = merge_loc_option(loc, Some(constraint.loc))
  })
  loc.unwrap_or(binder.name_loc)
}

///|UUID(e81e3f03-f160-47db-a8c7-3d1e545704a0)
fn ElabCtx::elab_type_var_binder(self : Self, binder : TypeVarBinder) -> Syntax {
  let loc = self.type_var_binder_loc(binder)
  let parts = Array::new()
  parts.push(
    self.part(
      self.tokenize_loc(binder.name_loc, word_kind=AtomKind::Type),
      Some(binder.name_loc),
    ),
  )
  parts.push_iter(
    self
    .parts_from_list(binder.constraints, fn(constraint) {
      self.part(self.elab_type_var_constraint(constraint), Some(constraint.loc))
    })
    .iter(),
  )
  self.region(loc, parts)
}

///|UUID(7b5e1f40-9419-44df-a9c4-2571bc79bf1a)
fn ElabCtx::part_type_var_binder(self : Self, binder : TypeVarBinder) -> Part {
  let loc = self.type_var_binder_loc(binder)
  self.part(self.elab_type_var_binder(binder), Some(loc))
}

///|UUID(bb027bb7-f593-4d4a-87c9-0c4a54124b8e)
fn ElabCtx::elab_type_decl_binder(
  self : Self,
  binder : TypeDeclBinder,
) -> Syntax {
  self.tokenize_loc(binder.loc, word_kind=AtomKind::Type)
}

///|UUID(3ad9ab30-c458-4cb0-9e6f-6653fd85a782)
fn ElabCtx::part_type_decl_binder(self : Self, binder : TypeDeclBinder) -> Part {
  self.part(self.elab_type_decl_binder(binder), Some(binder.loc))
}

///|UUID(a2ce8894-89bf-47b3-8758-8b6ffa3a1f62)
fn ElabCtx::elab_alias_target(self : Self, target : AliasTarget) -> Syntax {
  let loc = target.loc()
  let parts = Array::new()
  match target.target {
    Some(label) => parts.push(self.part_label(label))
    None => ()
  }
  parts.push(self.part_binder(target.binder))
  self.region(loc, parts)
}

///|UUID(8196165c-f05f-4f96-945c-0d86da0d4974)
fn ElabCtx::part_alias_target(self : Self, target : AliasTarget) -> Part {
  let loc = target.loc()
  self.part(self.elab_alias_target(target), Some(loc))
}

///|UUID(7018fcb4-8f7a-471b-9286-4e5bf965fc36)
fn ElabCtx::elab_visibility(self : Self, vis : Visibility) -> Syntax {
  match vis {
    Default => self.empty()
    Pub(loc~, ..) | Priv(loc~) => self.tokenize_loc(loc, classify_keywords=true)
  }
}

///|UUID(6d20aaf2-0318-4d93-a6f1-a8b4b8386ab4)
fn ElabCtx::part_visibility(self : Self, vis : Visibility) -> Part? {
  match vis {
    Default => None
    Pub(loc~, ..) | Priv(loc~) =>
      Some(self.part(self.elab_visibility(vis), Some(loc)))
  }
}

///|UUID(c09eac47-a0ce-40ab-b077-fcaf58776586)
fn ElabCtx::elab_hole(self : Self, kind : Hole, loc : Location) -> Syntax {
  match kind {
    Synthesized => self.empty()
    Incomplete | Todo => self.tokenize_loc(loc, classify_keywords=true)
  }
}
