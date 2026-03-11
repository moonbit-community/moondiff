///|UUID(38201113-d93b-4603-ae9f-25f6a9328f4c)
fn ElabCtx::elab_doc_string(self : Self, doc : DocString) -> Syntax {
  // TODO: `DocString` keeps only the merged range of the whole docstring.
  // Per-line prefix spans such as `///` or `#|` are not exposed.
  self.node("DocString", [
    self.comment_atom(content=join_lines(doc.content), loc=doc.loc),
  ])
}

///|UUID(8ca7c2f3-2643-46aa-8e38-12b33c0bdf55)
fn ElabCtx::elab_attribute(self : Self, attr : Attribute) -> Syntax {
  let children = [
    self.field("raw", self.atom(content=attr.raw, loc=attr.loc)),
    self.field(
      "parsed",
      self.option_node(attr.parsed, fn(parsed) {
        // TODO: `attribute.Expr` nodes do not carry locations, so the
        // parsed payload can only be preserved as synthetic text.
        self.synthetic_atom(content="\{@debug.render(parsed.to_repr())}")
      }),
    ),
  ]
  self.node("Attribute", children)
}

///|UUID(7018fcb4-8f7a-471b-9286-4e5bf965fc36)
fn ElabCtx::elab_visibility(self : Self, vis : Visibility) -> Syntax {
  match vis {
    Default => self.node("Visibility::Default", [])
    Pub(attr~, loc~) =>
      // TODO: `Visibility::Pub` only stores the `pub` keyword location.
      // Any trailing visibility attribute string has no standalone span.
      self.node("Visibility::Pub", [
        self.keyword_atom(content="pub", loc~),
        self.field(
          "attr",
          self.option_node(attr, fn(attr) { self.synthetic_atom(content=attr) }),
        ),
      ])
    Priv(loc~) =>
      self.node("Visibility::Priv", [self.keyword_atom(content="priv", loc~)])
  }
}

///|UUID(d8cb1320-c8f0-4708-8e46-62151819a8b0)
fn ElabCtx::elab_constant(
  self : Self,
  constant : Constant,
  loc : Location,
) -> Syntax {
  match constant {
    Bool(value) => self.keyword_atom(content=show_bool(value), loc~)
    Byte(value) | Bytes(value) | Char(value) | Constant::String(value) =>
      self.string_atom(content=value, loc~)
    Int(value)
    | Int64(value)
    | UInt(value)
    | UInt64(value)
    | Float(value)
    | Double(value)
    | BigInt(value) => self.atom(content=value, loc~)
  }
}

///|UUID(7d8b1947-eaea-4540-aa39-6d8bd262b2b6)
fn ElabCtx::elab_label(self : Self, label : Label) -> Syntax {
  self.node("Label", [self.atom(content=label.name, loc=label.loc)])
}

///|UUID(ba8be93c-f347-4787-9991-f23b871054f5)
fn ElabCtx::elab_constr_name(self : Self, name : ConstrName) -> Syntax {
  self.node("ConstrName", [self.type_atom(content=name.name, loc=name.loc)])
}

///|UUID(2bbf5284-963e-403b-a0d1-25c77c250147)
fn ElabCtx::elab_long_ident(
  self : Self,
  ident : LongIdent,
  loc : Location,
  atom_kind : AtomKind,
) -> Syntax {
  match ident {
    Ident(name~) => self.atom(content=name, loc~, kind=atom_kind)
    Dot(pkg~, id~) =>
      // TODO: `LongIdent::Dot` does not record separate locations for the
      // package segment, the dot, and the final identifier.
      self.node("LongIdent::Dot", [
        self.atom(content=pkg + "." + id, loc~, kind=atom_kind),
      ])
  }
}

///|UUID(b27e66a8-5e01-46dc-9b48-deac49285613)
fn ElabCtx::elab_type_name(self : Self, type_name : TypeName) -> Syntax {
  self.node("TypeName", [
    self.field(
      "name",
      self.elab_long_ident(type_name.name, type_name.loc, AtomKind::Type),
    ),
    self.field_bool("is_object", type_name.is_object),
  ])
}

///|UUID(8391d388-d9b4-4f1b-96c0-8ba1869f5bbd)
fn ElabCtx::elab_constr_id(self : Self, constr_id : ConstrId) -> Syntax {
  self.node("ConstrId", [
    self.field(
      "id",
      self.elab_long_ident(constr_id.id, constr_id.loc, AtomKind::Type),
    ),
  ])
}

///|UUID(6f849862-455a-4b6e-b909-673c48c8b758)
pub fn ElabCtx::elab_type(self : Self, ty : Type) -> Syntax {
  // TODO: most `Type` variants only keep whole-node locations, so token
  // spans for separators such as `(`, `)`, `,`, and `->` are unavailable.
  match ty {
    Any(loc~) => self.node("Type::Any", [self.type_atom(content="_", loc~)])
    Arrow(args~, res~, err~, is_async~, loc=_) =>
      self.node("Type::Arrow", [
        self.field(
          "args",
          self.list_node("Type::Arrow::Args", args, fn(value) {
            self.elab_type(value)
          }),
        ),
        self.field("res", self.elab_type(res)),
        self.field("err", self.elab_error_type(err)),
        self.field_option("is_async", is_async, fn(loc) {
          self.keyword_atom(content="async", loc~)
        }),
      ])
    Tuple(tys~, loc=_) =>
      self.node("Type::Tuple", [
        self.list_node("Type::Tuple::Items", tys, fn(value) {
          self.elab_type(value)
        }),
      ])
    Name(constr_id~, tys~, loc=_) =>
      self.node("Type::Name", [
        self.field("constr_id", self.elab_constr_id(constr_id)),
        self.field(
          "tys",
          self.list_node("Type::Name::Args", tys, fn(value) {
            self.elab_type(value)
          }),
        ),
      ])
    Option(ty~, loc=_, question_loc~) =>
      self.node("Type::Option", [
        self.field("ty", self.elab_type(ty)),
        self.field("question", self.keyword_atom(content="?", loc=question_loc)),
      ])
    Object(constr_id) =>
      self.node("Type::Object", [
        self.field("constr_id", self.elab_constr_id(constr_id)),
      ])
  }
}

///|UUID(3c562e37-31b5-4d77-9917-fbda6c697b92)
fn ElabCtx::elab_error_type(self : Self, err : ErrorType) -> Syntax {
  match err {
    ErrorType(ty~) =>
      self.node("ErrorType::ErrorType", [self.field("ty", self.elab_type(ty))])
    DefaultErrorType(loc~) =>
      // TODO: `DefaultErrorType` normalizes both `raise` and postfix `!`
      // into the same variant, so the original token text is lost.
      self.node("ErrorType::DefaultErrorType", [
        self.keyword_atom(content="raise", loc~),
      ])
    NoErrorType => self.node("ErrorType::NoErrorType", [])
    Noraise(loc~) =>
      self.node("ErrorType::Noraise", [
        self.keyword_atom(content="noraise", loc~),
      ])
    MaybeError(ty~) =>
      // TODO: `MaybeError` retains the payload type but not the `?` token span.
      self.node("ErrorType::MaybeError", [self.field("ty", self.elab_type(ty))])
  }
}

///|UUID(344c407a-df99-4554-b90c-563d76137821)
fn ElabCtx::elab_constr_param(self : Self, param : ConstrParam) -> Syntax {
  // TODO: `ConstrParam` has no overall location and does not expose the
  // `mut` keyword span, so only its child nodes can be positioned.
  self.node("ConstrParam", [
    self.field("ty", self.elab_type(param.ty)),
    self.field_bool("mut", param.mut_),
    self.field_option("label", param.label, fn(value) { self.elab_label(value) }),
  ])
}

///|UUID(70e14edc-8d74-431c-9c01-4b723440d446)
fn ElabCtx::elab_constr_decl(self : Self, decl : ConstrDecl) -> Syntax {
  self.node("ConstrDecl", [
    self.field("name", self.elab_constr_name(decl.name)),
    self.field(
      "args",
      self.option_node(decl.args, fn(args) {
        self.list_node("ConstrDecl::Args", args, fn(value) {
          self.elab_constr_param(value)
        })
      }),
    ),
    self.field(
      "tag",
      self.option_node(decl.tag, fn(tag) {
        let (value, loc) = tag
        self.atom(content=value, loc~)
      }),
    ),
    self.field(
      "attrs",
      self.list_node("ConstrDecl::Attrs", decl.attrs, fn(value) {
        self.elab_attribute(value)
      }),
    ),
    self.field("doc", self.elab_doc_string(decl.doc)),
  ])
}

///|UUID(927bb83d-f535-4519-9cdd-6eee0b35acc9)
fn ElabCtx::elab_exception_decl(self : Self, decl : ExceptionDecl) -> Syntax {
  match decl {
    NoPayload => self.node("ExceptionDecl::NoPayload", [])
    SinglePayload(ty) =>
      self.node("ExceptionDecl::SinglePayload", [
        self.field("ty", self.elab_type(ty)),
      ])
    EnumPayload(constrs) =>
      self.node("ExceptionDecl::EnumPayload", [
        self.list_node("ExceptionDecl::EnumPayload::Constrs", constrs, fn(
          value,
        ) {
          self.elab_constr_decl(value)
        }),
      ])
  }
}

///|UUID(ea969b90-c348-47c1-b475-7577eff8f9c1)
fn ElabCtx::elab_field_name(self : Self, name : FieldName) -> Syntax {
  self.node("FieldName", [self.atom(content=name.label, loc=name.loc)])
}

///|UUID(8707a3ef-68eb-44f6-aeff-aa2570e10dd2)
fn ElabCtx::elab_field_decl(self : Self, decl : FieldDecl) -> Syntax {
  self.node("FieldDecl", [
    self.field("name", self.elab_field_name(decl.name)),
    self.field("ty", self.elab_type(decl.ty)),
    self.field_bool("mut", decl.mut_),
    self.field("vis", self.elab_visibility(decl.vis)),
    self.field(
      "attrs",
      self.list_node("FieldDecl::Attrs", decl.attrs, fn(value) {
        self.elab_attribute(value)
      }),
    ),
    self.field("doc", self.elab_doc_string(decl.doc)),
  ])
}

///|UUID(1c2b47df-f3f9-49ee-a3a9-634f59dc2c7e)
fn ElabCtx::elab_type_desc(self : Self, desc : TypeDesc) -> Syntax {
  match desc {
    Abstract => self.node("TypeDesc::Abstract", [])
    Extern => self.node("TypeDesc::Extern", [])
    Newtype(ty) =>
      self.node("TypeDesc::Newtype", [self.field("ty", self.elab_type(ty))])
    Error(exception_decl) =>
      self.node("TypeDesc::Error", [
        self.field("exception_decl", self.elab_exception_decl(exception_decl)),
      ])
    Variant(constrs) =>
      self.node("TypeDesc::Variant", [
        self.list_node("TypeDesc::Variant::Constrs", constrs, fn(value) {
          self.elab_constr_decl(value)
        }),
      ])
    Record(fields~, constr_decl~) =>
      self.node("TypeDesc::Record", [
        self.field(
          "fields",
          self.list_node("TypeDesc::Record::Fields", fields, fn(value) {
            self.elab_field_decl(value)
          }),
        ),
        self.field_option("constr_decl", constr_decl, fn(value) {
          self.elab_fun_decl(value)
        }),
      ])
    TupleStruct(tys) =>
      self.node("TypeDesc::TupleStruct", [
        self.list_node("TypeDesc::TupleStruct::Items", tys, fn(value) {
          self.elab_type(value)
        }),
      ])
    Alias(ty) =>
      self.node("TypeDesc::Alias", [self.field("ty", self.elab_type(ty))])
  }
}

///|UUID(c09eac47-a0ce-40ab-b077-fcaf58776586)
fn ElabCtx::elab_hole(self : Self, kind : Hole, loc : Location) -> Syntax {
  match kind {
    Synthesized => self.node("Hole::Synthesized", [])
    Incomplete =>
      self.node("Hole::Incomplete", [self.keyword_atom(content="_", loc~)])
    Todo => self.node("Hole::Todo", [self.keyword_atom(content="...", loc~)])
  }
}

///|UUID(18ea13c9-409d-46de-9cbe-5e6e01cd95aa)
fn ElabCtx::elab_argument_kind(self : Self, kind : ArgumentKind) -> Syntax {
  match kind {
    Positional => self.node("ArgumentKind::Positional", [])
    Labelled(label) =>
      self.node("ArgumentKind::Labelled", [
        self.field("label", self.elab_label(label)),
      ])
    LabelledPun(label) =>
      self.node("ArgumentKind::LabelledPun", [
        self.field("label", self.elab_label(label)),
      ])
    LabelledOption(label~, question_loc~) =>
      self.node("ArgumentKind::LabelledOption", [
        self.field("label", self.elab_label(label)),
        self.field("question", self.keyword_atom(content="?", loc=question_loc)),
      ])
    LabelledOptionPun(label~, question_loc~) =>
      self.node("ArgumentKind::LabelledOptionPun", [
        self.field("label", self.elab_label(label)),
        self.field("question", self.keyword_atom(content="?", loc=question_loc)),
      ])
  }
}

///|UUID(95a9d01e-d983-4d61-bebb-c8dd259f8b39)
fn ElabCtx::elab_fn_kind(self : Self, kind : FnKind) -> Syntax {
  ignore(self)
  match kind {
    Lambda =>
      Syntax::list(
        open_content="FnKind::Lambda",
        open_position=[],
        children=[],
        close_content="",
        close_position=[],
      )
    Arrow =>
      Syntax::list(
        open_content="FnKind::Arrow",
        open_position=[],
        children=[],
        close_content="",
        close_position=[],
      )
  }
}

///|UUID(18ecb2fd-78a9-41b8-888c-860383a345d9)
fn ElabCtx::elab_group(self : Self, group : Group) -> Syntax {
  ignore(self)
  match group {
    Brace => self.node("Group::Brace", [])
    Paren => self.node("Group::Paren", [])
  }
}

///|UUID(3921f5fc-e6f5-49fb-8500-815d95776702)
fn ElabCtx::elab_trailing_mark(self : Self, mark : TrailingMark) -> Syntax {
  ignore(self)
  match mark {
    Comma => self.node("TrailingMark::Comma", [])
    Semi => self.node("TrailingMark::Semi", [])
    TrailingMark::None => self.node("TrailingMark::None", [])
  }
}

///|UUID(12bba2f7-0db8-46af-8335-1928b0c9e0da)
fn ElabCtx::elab_apply_attr(self : Self, attr : ApplyAttr) -> Syntax {
  // TODO: `ApplyAttr` retains only the attr kind, not the position of the
  // source `!` / `?` token attached to the call.
  ignore(self)
  match attr {
    NoAttr => self.node("ApplyAttr::NoAttr", [])
    Exclamation => self.node("ApplyAttr::Exclamation", [])
    Question => self.node("ApplyAttr::Question", [])
  }
}

///|UUID(20a1e4bf-d412-41a4-9af0-592bb40fa956)
fn ElabCtx::elab_type_var_constraint(
  self : Self,
  constraint : TypeVarConstraint,
) -> Syntax {
  self.node("TypeVarConstraint", [
    self.field(
      "trait",
      self.elab_long_ident(constraint.trait_, constraint.loc, AtomKind::Type),
    ),
  ])
}

///|UUID(e81e3f03-f160-47db-a8c7-3d1e545704a0)
fn ElabCtx::elab_type_var_binder(self : Self, binder : TypeVarBinder) -> Syntax {
  // TODO: `TypeVarBinder` stores the bound name location and each
  // constraint location, but not the spans for `[` / `]`, `:`, or `+`.
  self.node("TypeVarBinder", [
    self.field("name", self.type_atom(content=binder.name, loc=binder.name_loc)),
    self.field(
      "constraints",
      self.list_node("TypeVarBinder::Constraints", binder.constraints, fn(
        value,
      ) {
        self.elab_type_var_constraint(value)
      }),
    ),
  ])
}

///|UUID(bb027bb7-f593-4d4a-87c9-0c4a54124b8e)
fn ElabCtx::elab_type_decl_binder(
  self : Self,
  binder : TypeDeclBinder,
) -> Syntax {
  let name = match binder.name {
    Some(name) => self.type_atom(content=name, loc=binder.loc)
    None => self.type_atom(content="_", loc=binder.loc)
  }
  self.node("TypeDeclBinder", [self.field("name", name)])
}

///|UUID(20468bd7-8a56-4883-a5f1-3460e9c3b9bf)
fn ElabCtx::elab_binder(self : Self, binder : Binder) -> Syntax {
  self.node("Binder", [self.atom(content=binder.name, loc=binder.loc)])
}

///|UUID(91e301ac-bdde-4300-9578-0e123a0148a5)
fn ElabCtx::elab_var(self : Self, var_ : Var) -> Syntax {
  self.node("Var", [
    self.field(
      "name",
      self.elab_long_ident(var_.name, var_.loc, AtomKind::Normal),
    ),
  ])
}

///|UUID(77b81a53-fe72-4319-8473-1c4286ecdec8)
fn ElabCtx::elab_constructor_extra_info(
  self : Self,
  info : ConstructorExtraInfo,
) -> Syntax {
  match info {
    TypeName(type_name) =>
      self.node("ConstructorExtraInfo::TypeName", [
        self.field("type_name", self.elab_type_name(type_name)),
      ])
    Package(pkg) =>
      self.node("ConstructorExtraInfo::Package", [
        self.synthetic_atom(content=pkg, kind=AtomKind::Type),
      ])
    NoExtraInfo => self.node("ConstructorExtraInfo::NoExtraInfo", [])
  }
}

///|UUID(767e5d8e-0223-43d6-997b-2c2642f32930)
fn ElabCtx::elab_constructor(self : Self, ctor : Constructor) -> Syntax {
  self.node("Constructor", [
    self.field("name", self.elab_constr_name(ctor.name)),
    self.field("extra_info", self.elab_constructor_extra_info(ctor.extra_info)),
  ])
}

///|UUID(7e1f9a37-89c7-424c-8a58-0e5fc90145e7)
fn ElabCtx::elab_accessor(self : Self, accessor : Accessor) -> Syntax {
  match accessor {
    Label(label) =>
      self.node("Accessor::Label", [self.field("label", self.elab_label(label))])
    Index(tuple_index~, loc~) =>
      self.node("Accessor::Index", [self.atom(content=".\{tuple_index}", loc~)])
    Newtype(loc~) =>
      self.node("Accessor::Newtype", [self.atom(content="._", loc~)])
  }
}

///|UUID(a2ce8894-89bf-47b3-8758-8b6ffa3a1f62)
fn ElabCtx::elab_alias_target(self : Self, target : AliasTarget) -> Syntax {
  self.node("AliasTarget", [
    self.field("binder", self.elab_binder(target.binder)),
    self.field_option("target", target.target, fn(value) {
      self.elab_label(value)
    }),
  ])
}
