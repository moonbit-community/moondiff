///|UUID(3e527f9c-cba3-4bbc-a114-36dc99f533dd)
fn ElabCtx::elab_local_type_decl(self : Self, decl : LocalTypeDecl) -> Syntax {
  // TODO: `LocalTypeDecl` does not keep an overall declaration location or
  // the `type` keyword span. Only the type constructor location is exposed.
  self.node("LocalTypeDecl", [
    self.field("tycon", self.type_atom(content=decl.tycon, loc=decl.tycon_loc)),
    self.field("components", self.elab_type_desc(decl.components)),
    self.field(
      "deriving",
      self.list_node("LocalTypeDecl::Deriving", decl.deriving, fn(value) {
        self.elab_deriving_directive(value)
      }),
    ),
  ])
}

///|UUID(a96a2c35-4d3d-40af-98bf-4caa3a52776d)
fn ElabCtx::elab_deriving_directive(
  self : Self,
  directive : DerivingDirective,
) -> Syntax {
  self.node("DerivingDirective", [
    self.field("type_name", self.elab_type_name(directive.type_name)),
    self.field(
      "args",
      self.list_node("DerivingDirective::Args", directive.args, fn(value) {
        self.elab_argument(value)
      }),
    ),
  ])
}

///|UUID(f04187ea-2945-441a-af06-befda367f752)
fn ElabCtx::elab_type_decl(self : Self, decl : TypeDecl) -> Syntax {
  self.node("TypeDecl", [
    self.field("tycon", self.type_atom(content=decl.tycon, loc=decl.tycon_loc)),
    self.field(
      "params",
      self.list_node("TypeDecl::Params", decl.params, fn(value) {
        self.elab_type_decl_binder(value)
      }),
    ),
    self.field("components", self.elab_type_desc(decl.components)),
    self.field(
      "attrs",
      self.list_node("TypeDecl::Attrs", decl.attrs, fn(value) {
        self.elab_attribute(value)
      }),
    ),
    self.field("doc", self.elab_doc_string(decl.doc)),
    self.field("type_vis", self.elab_visibility(decl.type_vis)),
    self.field(
      "deriving",
      self.list_node("TypeDecl::Deriving", decl.deriving, fn(value) {
        self.elab_deriving_directive(value)
      }),
    ),
    self.field_bool("is_declare", decl.is_declare),
  ])
}

///|UUID(89dde800-da7e-45ae-87be-97be65d4a5bf)
fn ElabCtx::elab_func_stubs(self : Self, stubs : FuncStubs) -> Syntax {
  // TODO: `FuncStubs` stores literal text but not the positions of the
  // string tokens inside the stub body.
  match stubs {
    Import(module_name~, func_name~, language~) =>
      self.node("FuncStubs::Import", [
        self.field("module_name", self.synthetic_atom(content=module_name)),
        self.field("func_name", self.synthetic_atom(content=func_name)),
        self.field(
          "language",
          self.option_node(language, fn(language) {
            self.synthetic_atom(content=language)
          }),
        ),
      ])
    Embedded(language~, code~) =>
      self.node("FuncStubs::Embedded", [
        self.field(
          "language",
          self.option_node(language, fn(language) {
            self.synthetic_atom(content=language)
          }),
        ),
        self.field("code", self.elab_embedded_code(code)),
      ])
  }
}

///|UUID(7c5e356b-9d30-4585-a847-58778c5f5bf8)
fn ElabCtx::elab_embedded_code(self : Self, code : EmbeddedCode) -> Syntax {
  // TODO: `EmbeddedCode` keeps only raw text; per-line locations are absent.
  match code {
    CodeString(value) =>
      self.node("EmbeddedCode::CodeString", [self.synthetic_atom(content=value)])
    CodeMultilineString(lines) =>
      self.node("EmbeddedCode::CodeMultilineString", [
        self.list_node("EmbeddedCode::CodeMultilineString::Lines", lines, fn(
          line,
        ) {
          self.synthetic_atom(content=line)
        }),
      ])
  }
}

///|UUID(273eff4f-e996-44a9-a043-0070d774fbef)
fn ElabCtx::elab_decl_body(self : Self, body : DeclBody) -> Syntax {
  match body {
    DeclBody(local_types~, expr~) =>
      self.node("DeclBody::DeclBody", [
        self.field(
          "local_types",
          self.list_node("DeclBody::LocalTypes", local_types, fn(value) {
            self.elab_local_type_decl(value)
          }),
        ),
        self.field("expr", self.elab_expr(expr)),
      ])
    DeclStubs(stubs) =>
      self.node("DeclBody::DeclStubs", [
        self.field("stubs", self.elab_func_stubs(stubs)),
      ])
    DeclNone =>
      // TODO: `DeclBody::DeclNone` carries no source location.
      self.node("DeclBody::DeclNone", [])
  }
}

///|UUID(dda25ac8-8bdb-42aa-b8a5-9df591630071)
fn ElabCtx::elab_fun_decl(self : Self, decl : FunDecl) -> Syntax {
  self.node("FunDecl", [
    self.field_option("type_name", decl.type_name, fn(value) {
      self.elab_type_name(value)
    }),
    self.field("name", self.elab_binder(decl.name)),
    self.field_option("has_error", decl.has_error, fn(loc) {
      self.keyword_atom(content="raise", loc~)
    }),
    self.field_option("is_async", decl.is_async, fn(loc) {
      self.keyword_atom(content="async", loc~)
    }),
    self.field(
      "decl_params",
      self.option_node(decl.decl_params, fn(params) {
        self.list_node("FunDecl::Params", params, fn(value) {
          self.elab_parameter(value)
        })
      }),
    ),
    self.field(
      "quantifiers",
      self.list_node("FunDecl::Quantifiers", decl.quantifiers, fn(value) {
        self.elab_type_var_binder(value)
      }),
    ),
    self.field_option("return_type", decl.return_type, fn(value) {
      self.elab_type(value)
    }),
    self.field("error_type", self.elab_error_type(decl.error_type)),
    self.field("vis", self.elab_visibility(decl.vis)),
    self.field(
      "attrs",
      self.list_node("FunDecl::Attrs", decl.attrs, fn(value) {
        self.elab_attribute(value)
      }),
    ),
    self.field("doc", self.elab_doc_string(decl.doc)),
  ])
}

///|UUID(86c60871-a051-42fe-ba5d-f346c39e537f)
fn ElabCtx::elab_trait_method_decl(
  self : Self,
  decl : TraitMethodDecl,
) -> Syntax {
  self.node("TraitMethodDecl", [
    self.field("name", self.elab_binder(decl.name)),
    self.field_option("has_error", decl.has_error, fn(loc) {
      self.keyword_atom(content="raise", loc~)
    }),
    self.field_option("is_async", decl.is_async, fn(loc) {
      self.keyword_atom(content="async", loc~)
    }),
    self.field(
      "quantifiers",
      self.list_node("TraitMethodDecl::Quantifiers", decl.quantifiers, fn(
        value,
      ) {
        self.elab_type_var_binder(value)
      }),
    ),
    self.field(
      "params",
      self.list_node("TraitMethodDecl::Params", decl.params, fn(value) {
        self.elab_parameter(value)
      }),
    ),
    self.field_option("return_type", decl.return_type, fn(value) {
      self.elab_type(value)
    }),
    self.field("error_type", self.elab_error_type(decl.error_type)),
    self.field_option("has_default", decl.has_default, fn(loc) {
      self.keyword_atom(content="default", loc~)
    }),
    self.field(
      "attrs",
      self.list_node("TraitMethodDecl::Attrs", decl.attrs, fn(value) {
        self.elab_attribute(value)
      }),
    ),
  ])
}

///|UUID(0dacaa83-bd09-4604-a0d6-5911112e7bfa)
fn ElabCtx::elab_trait_decl(self : Self, decl : TraitDecl) -> Syntax {
  self.node("TraitDecl", [
    self.field("name", self.elab_binder(decl.name)),
    self.field(
      "supers",
      self.list_node("TraitDecl::Supers", decl.supers, fn(value) {
        self.elab_type_var_constraint(value)
      }),
    ),
    self.field(
      "methods",
      self.list_node("TraitDecl::Methods", decl.methods, fn(value) {
        self.elab_trait_method_decl(value)
      }),
    ),
    self.field("vis", self.elab_visibility(decl.vis)),
    self.field(
      "attrs",
      self.list_node("TraitDecl::Attrs", decl.attrs, fn(value) {
        self.elab_attribute(value)
      }),
    ),
    self.field("doc", self.elab_doc_string(decl.doc)),
    self.field_bool("is_declare", decl.is_declare),
  ])
}

///|UUID(cb392db1-0135-44ae-94b8-a017793a7bf1)
fn ElabCtx::elab_using_kind(self : Self, kind : UsingKind) -> Syntax {
  ignore(self)
  match kind {
    UsingKind::Value => self.node("UsingKind::Value", [])
    Type => self.node("UsingKind::Type", [])
    Trait => self.node("UsingKind::Trait", [])
  }
}

///|UUID(db09c59d-7e60-436a-9737-ea856f8ff0d6)
fn ElabCtx::elab_alias_using_pair(
  self : Self,
  pair : (AliasTarget, UsingKind),
) -> Syntax {
  let (target, kind) = pair
  self.node("AliasUsingPair", [
    self.field("target", self.elab_alias_target(target)),
    self.field("kind", self.elab_using_kind(kind)),
  ])
}

///|UUID(6094e4c4-1b51-4310-89d9-c32f66988f67)
pub fn ElabCtx::elab_impl(self : Self, impl_ : Impl) -> Syntax {
  match impl_ {
    TopExpr(expr~, is_main~, local_types~, is_async~, loc=_) =>
      self.node("Impl::TopExpr", [
        self.field("expr", self.elab_expr(expr)),
        self.field_bool("is_main", is_main),
        self.field(
          "local_types",
          self.list_node("Impl::TopExpr::LocalTypes", local_types, fn(value) {
            self.elab_local_type_decl(value)
          }),
        ),
        self.field_option("is_async", is_async, fn(loc) {
          self.keyword_atom(content="async", loc~)
        }),
      ])
    TopTest(expr~, name~, params~, local_types~, is_async~, loc=_, attrs~, doc~) =>
      self.node("Impl::TopTest", [
        self.field("expr", self.elab_expr(expr)),
        self.field(
          "name",
          self.option_node(name, fn(name) {
            let (value, loc) = name
            self.string_atom(content=value, loc~)
          }),
        ),
        self.field(
          "params",
          self.option_node(params, fn(params) {
            self.list_node("Impl::TopTest::Params", params, fn(value) {
              self.elab_parameter(value)
            })
          }),
        ),
        self.field(
          "local_types",
          self.list_node("Impl::TopTest::LocalTypes", local_types, fn(value) {
            self.elab_local_type_decl(value)
          }),
        ),
        self.field_option("is_async", is_async, fn(loc) {
          self.keyword_atom(content="async", loc~)
        }),
        self.field(
          "attrs",
          self.list_node("Impl::TopTest::Attrs", attrs, fn(value) {
            self.elab_attribute(value)
          }),
        ),
        self.field("doc", self.elab_doc_string(doc)),
      ])
    TopTypeDef(type_decl) =>
      self.node("Impl::TopTypeDef", [
        self.field("type_decl", self.elab_type_decl(type_decl)),
      ])
    TopFuncDef(fun_decl~, decl_body~, loc=_) =>
      self.node("Impl::TopFuncDef", [
        self.field("fun_decl", self.elab_fun_decl(fun_decl)),
        self.field("decl_body", self.elab_decl_body(decl_body)),
      ])
    TopFuncAlias(
      pkg~,
      type_name~,
      targets~,
      vis~,
      attrs~,
      is_list~,
      doc~,
      loc=_
    ) =>
      self.node("Impl::TopFuncAlias", [
        self.field_option("pkg", pkg, fn(value) { self.elab_label(value) }),
        self.field_option("type_name", type_name, fn(value) {
          self.elab_label(value)
        }),
        self.field(
          "targets",
          self.list_node("Impl::TopFuncAlias::Targets", targets, fn(value) {
            self.elab_alias_target(value)
          }),
        ),
        self.field("vis", self.elab_visibility(vis)),
        self.field(
          "attrs",
          self.list_node("Impl::TopFuncAlias::Attrs", attrs, fn(value) {
            self.elab_attribute(value)
          }),
        ),
        self.field_bool("is_list", is_list),
        self.field("doc", self.elab_doc_string(doc)),
      ])
    TopLetDef(
      binder~,
      ty~,
      expr~,
      vis~,
      is_constant~,
      loc=_,
      attrs~,
      doc~,
      is_declare~
    ) =>
      self.node("Impl::TopLetDef", [
        self.field("binder", self.elab_binder(binder)),
        self.field_option("ty", ty, fn(value) { self.elab_type(value) }),
        self.field("expr", self.elab_expr(expr)),
        self.field("vis", self.elab_visibility(vis)),
        self.field_bool("is_constant", is_constant),
        self.field(
          "attrs",
          self.list_node("Impl::TopLetDef::Attrs", attrs, fn(value) {
            self.elab_attribute(value)
          }),
        ),
        self.field("doc", self.elab_doc_string(doc)),
        self.field_bool("is_declare", is_declare),
      ])
    TopTrait(trait_decl) =>
      self.node("Impl::TopTrait", [
        self.field("trait_decl", self.elab_trait_decl(trait_decl)),
      ])
    TopBatchTypeAlias(pkg~, targets~, vis~, loc=_, attrs~, is_list~, doc~) =>
      self.node("Impl::TopBatchTypeAlias", [
        self.field_option("pkg", pkg, fn(value) { self.elab_label(value) }),
        self.field(
          "targets",
          self.list_node("Impl::TopBatchTypeAlias::Targets", targets, fn(
            value,
          ) {
            self.elab_alias_target(value)
          }),
        ),
        self.field("vis", self.elab_visibility(vis)),
        self.field(
          "attrs",
          self.list_node("Impl::TopBatchTypeAlias::Attrs", attrs, fn(value) {
            self.elab_attribute(value)
          }),
        ),
        self.field_bool("is_list", is_list),
        self.field("doc", self.elab_doc_string(doc)),
      ])
    TopBatchTraitAlias(pkg~, targets~, vis~, loc=_, attrs~, is_list~, doc~) =>
      self.node("Impl::TopBatchTraitAlias", [
        self.field_option("pkg", pkg, fn(value) { self.elab_label(value) }),
        self.field(
          "targets",
          self.list_node("Impl::TopBatchTraitAlias::Targets", targets, fn(
            value,
          ) {
            self.elab_alias_target(value)
          }),
        ),
        self.field("vis", self.elab_visibility(vis)),
        self.field(
          "attrs",
          self.list_node("Impl::TopBatchTraitAlias::Attrs", attrs, fn(value) {
            self.elab_attribute(value)
          }),
        ),
        self.field_bool("is_list", is_list),
        self.field("doc", self.elab_doc_string(doc)),
      ])
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
      loc=_,
      attrs~,
      doc~
    ) =>
      self.node("Impl::TopImpl", [
        self.field_option("self_ty", self_ty, fn(value) {
          self.elab_type(value)
        }),
        self.field("trait", self.elab_type_name(trait_)),
        self.field("method_name", self.elab_binder(method_name)),
        self.field_option("has_error", has_error, fn(loc) {
          self.keyword_atom(content="raise", loc~)
        }),
        self.field(
          "quantifiers",
          self.list_node("Impl::TopImpl::Quantifiers", quantifiers, fn(value) {
            self.elab_type_var_binder(value)
          }),
        ),
        self.field(
          "params",
          self.list_node("Impl::TopImpl::Params", params, fn(value) {
            self.elab_parameter(value)
          }),
        ),
        self.field_option("ret_ty", ret_ty, fn(value) { self.elab_type(value) }),
        self.field("err_ty", self.elab_error_type(err_ty)),
        self.field("body", self.elab_decl_body(body)),
        self.field("vis", self.elab_visibility(vis)),
        self.field(
          "attrs",
          self.list_node("Impl::TopImpl::Attrs", attrs, fn(value) {
            self.elab_attribute(value)
          }),
        ),
        self.field("doc", self.elab_doc_string(doc)),
      ])
    TopView(
      quantifiers~,
      source_ty~,
      view_type_name~,
      view_type_loc~,
      view_constrs~,
      view_func_name~,
      parameters~,
      params_loc=_,
      body~,
      vis~,
      loc=_,
      attrs~,
      doc~
    ) =>
      self.node("Impl::TopView", [
        self.field(
          "quantifiers",
          self.list_node("Impl::TopView::Quantifiers", quantifiers, fn(value) {
            self.elab_type_var_binder(value)
          }),
        ),
        self.field("source_ty", self.elab_type(source_ty)),
        self.field(
          "view_type_name",
          self.type_atom(content=view_type_name, loc=view_type_loc),
        ),
        self.field(
          "view_constrs",
          self.list_node("Impl::TopView::Constrs", view_constrs, fn(value) {
            self.elab_constr_decl(value)
          }),
        ),
        self.field("view_func_name", self.elab_binder(view_func_name)),
        self.field(
          "parameters",
          self.list_node("Impl::TopView::Parameters", parameters, fn(value) {
            self.elab_parameter(value)
          }),
        ),
        self.field("body", self.elab_expr(body)),
        self.field("vis", self.elab_visibility(vis)),
        self.field(
          "attrs",
          self.list_node("Impl::TopView::Attrs", attrs, fn(value) {
            self.elab_attribute(value)
          }),
        ),
        self.field("doc", self.elab_doc_string(doc)),
      ])
    TopImplRelation(
      self_ty~,
      trait_~,
      quantifiers~,
      vis~,
      attrs~,
      loc=_,
      doc~,
      is_declare~
    ) =>
      self.node("Impl::TopImplRelation", [
        self.field("self_ty", self.elab_type(self_ty)),
        self.field("trait", self.elab_type_name(trait_)),
        self.field(
          "quantifiers",
          self.list_node("Impl::TopImplRelation::Quantifiers", quantifiers, fn(
            value,
          ) {
            self.elab_type_var_binder(value)
          }),
        ),
        self.field("vis", self.elab_visibility(vis)),
        self.field(
          "attrs",
          self.list_node("Impl::TopImplRelation::Attrs", attrs, fn(value) {
            self.elab_attribute(value)
          }),
        ),
        self.field("doc", self.elab_doc_string(doc)),
        self.field_bool("is_declare", is_declare),
      ])
    TopUsing(pkg~, names~, vis~, attrs~, loc=_, doc~) =>
      self.node("Impl::TopUsing", [
        self.field("pkg", self.elab_label(pkg)),
        self.field(
          "names",
          self.list_node("Impl::TopUsing::Names", names, fn(value) {
            self.elab_alias_using_pair(value)
          }),
        ),
        self.field("vis", self.elab_visibility(vis)),
        self.field(
          "attrs",
          self.list_node("Impl::TopUsing::Attrs", attrs, fn(value) {
            self.elab_attribute(value)
          }),
        ),
        self.field("doc", self.elab_doc_string(doc)),
      ])
  }
}
