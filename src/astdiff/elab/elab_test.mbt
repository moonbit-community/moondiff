///|UUID(2dde4507-d810-4333-a0ae-173aa929afbb)
using @basic {type Location}

///|UUID(44282995-f14e-4eed-929e-7184bdf2b4b7)
using @dsyntax {type Syntax}

///|UUID(f5a17523-7a2f-4213-95d6-d4f8d19afa15)
fn loc(start_cnum : Int, end_cnum : Int, line? : Int = 1) -> Location {
  let start = @basic.Position::{
    fname: "",
    lnum: line,
    bol: 0,
    cnum: start_cnum,
  }
  let end = @basic.Position::{ fname: "", lnum: line, bol: 0, cnum: end_cnum }
  { start, end }
}

///|UUID(e31e6d63-9b05-416b-887b-39b4467ecbbe)
fn field_value(node : Syntax, tag : String) -> Syntax raise {
  match node {
    Syntax::List(children~, ..) =>
      for child in children {
        match child {
          Syntax::List(open_content~, children~, ..) if open_content == tag =>
            if children.length() == 1 {
              return children[0]
            } else {
              fail("expected single child field: \{tag}")
            }
          _ => ()
        }
      } nobreak {
        fail("missing field: \{tag}")
      }
    _ => fail("expected list node")
  }
}

///|UUID(c7223b88-e184-4405-97e5-c718dafef12b)
fn node_tag(node : Syntax) -> String raise {
  match node {
    Syntax::List(open_content~, ..) => open_content
    _ => fail("expected list node")
  }
}

///|UUID(5fd6f55e-e376-4863-8fb9-a5687729831a)
fn sexp(node : Syntax) -> String {
  @pp.render(node, width=200)
}

///|UUID(c4ddf6cb-e833-45d5-827a-6280dbcef994)
fn single_span_line(node : Syntax) -> Int raise {
  match node {
    Syntax::Atom(position~, ..) =>
      if position.length() == 1 {
        position[0].line
      } else {
        fail("expected single span")
      }
    _ => fail("expected atom")
  }
}

///|UUID(bfdebfae-866d-4972-8af6-68a959fbfd36)
fn only_child(node : Syntax) -> Syntax raise {
  match node {
    Syntax::List(children~, ..) =>
      if children.length() == 1 {
        children[0]
      } else {
        fail("expected single child")
      }
    _ => fail("expected list node")
  }
}

///|UUID(32b7d451-f83a-4bb6-b2d9-edec02309048)
fn list_children(node : Syntax) -> Array[Syntax] raise {
  match node {
    Syntax::List(children~, ..) => children
    _ => fail("expected list node")
  }
}

///|UUID(9db33348-9d9a-4b88-b49d-05c36042dea7)
test "elab parsed function keeps top-level shape and docstring" {
  let source =
    #|/// Adds one
    #|fn add(x : Int) -> Int { x }
  let (impls, reports) = @parser.parse_string(source)
  assert_true(reports.length() is 0)

  let syntax = elab_impls(source, impls)
  assert_true(syntax.length() is 1)
  assert_true(node_tag(syntax[0]) is "Impl::TopFuncDef")
  assert_true(
    sexp(syntax[0])
    is "((((()) ((add)) (()) (()) ((((((x)) ((((((Int))) (())))))))) (()) ((((((Int))) (())))) (()) (()) (()) (( Adds one)))) (((()) (((((x))))))))",
  )

  let fun_decl = field_value(syntax[0], "fun_decl")
  let name = field_value(fun_decl, "name")
  assert_true(sexp(name) is "(add)")
  assert_true(single_span_line(only_child(name)) is 2)

  let doc = field_value(fun_decl, "doc")
  assert_true(sexp(doc) is "( Adds one)")
  assert_true(single_span_line(only_child(doc)) is 1)
}

///|UUID(35058a48-ec09-4b30-947f-9532a9295a0f)
test "elab dotted type name uses tagged long ident" {
  let source = "pkg.Type"
  let ty = @past.Type::Name(
    constr_id=@past.ConstrId::{
      id: @past.LongIdent::Dot(pkg="pkg", id="Type"),
      loc: loc(0, 8),
    },
    tys=@list.empty(),
    loc=loc(0, 8),
  )

  let syntax = elab_type(source, ty)
  assert_true(node_tag(syntax) is "Type::Name")

  let constr_id = field_value(syntax, "constr_id")
  let ident = field_value(constr_id, "id")
  assert_true(sexp(ident) is "(pkg.Type)")
  assert_true(single_span_line(only_child(ident)) is 1)
}

///|UUID(2e8bd51d-71af-4423-9723-037e902204e7)
test "elab open array pattern keeps dotdot binder shape" {
  let source = "[head, ..rest]"
  let pat = @past.Pattern::Array(
    pats=@past.ArrayPatterns::Open(
      @list.from_array([
        @past.ArrayPattern::Pattern(
          @past.Pattern::Var(@past.Binder::{ name: "head", loc: loc(1, 5) }),
        ),
      ]),
      @list.empty(),
      @past.DotDotBinder::Binder(@past.Binder::{ name: "rest", loc: loc(9, 13) }),
    ),
    loc=loc(0, 14),
  )

  let syntax = elab_pattern(source, pat)
  let pats = field_value(syntax, "pats")
  assert_true(node_tag(pats) is "ArrayPatterns::Open")

  let binder = field_value(pats, "binder")
  assert_true(sexp(binder) is "(((rest)))")
  let binder_atom = only_child(field_value(binder, "binder"))
  assert_true(single_span_line(binder_atom) is 1)
}

///|UUID(1941b253-3c52-4e0d-aa82-09e7efee4309)
test "elab normalizes let chain into statement list" {
  let source =
    #|fn f() -> Int {
    #|  let a = 1
    #|  let b = 2
    #|  a + b
    #|}
  let (impls, reports) = @parser.parse_string(source)
  assert_true(reports.length() is 0)

  let syntax = elab_impls(source, impls)
  let decl_body = field_value(syntax[0], "decl_body")
  let expr = field_value(decl_body, "expr")
  assert_true(node_tag(expr) is "Expr::StmtChain")

  let stmts = field_value(expr, "stmts")
  assert_true(node_tag(stmts) is "Expr::StmtChain::Stmts")
  let stmt_children = list_children(stmts)
  assert_true(stmt_children.length() is 2)
  assert_true(node_tag(stmt_children[0]) is "Stmt::Let")
  assert_true(node_tag(stmt_children[1]) is "Stmt::Let")

  let tail = field_value(expr, "tail")
  assert_true(node_tag(tail) is "Expr::Infix")
}
