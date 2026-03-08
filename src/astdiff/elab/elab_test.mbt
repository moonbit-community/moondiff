///|
using @basic {type Location}

///|
using @dsyntax {type Syntax}

///|
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

///|
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

///|
fn node_tag(node : Syntax) -> String raise {
  match node {
    Syntax::List(open_content~, ..) => open_content
    _ => fail("expected list node")
  }
}

///|
fn sexp(node : Syntax) -> String {
  @pp.render(node, width=200)
}

///|
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

///|
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

///|
test "elab parsed function keeps top-level shape and docstring" {
  let source =
    #|/// Adds one
    #|fn add(x : Int) -> Int { x }
  let (impls, reports) = @parser.parse_string(source)
  inspect(reports.length(), content="0")

  let syntax = elab_impls(source, impls)
  inspect(syntax.length(), content="1")
  inspect(node_tag(syntax[0]), content="Impl::TopFuncDef")
  inspect(
    sexp(syntax[0]),
    content=(
      #|((((()) ((add)) (()) (()) ((((((x)) ((((((Int))) (())))))))) (()) ((((((Int))) (())))) (()) (()) (()) (( Adds one)))) (((()) (((((x))))))))
    ),
  )

  let fun_decl = field_value(syntax[0], "fun_decl")
  let name = field_value(fun_decl, "name")
  inspect(sexp(name), content="(add)")
  inspect(single_span_line(only_child(name)), content="2")

  let doc = field_value(fun_decl, "doc")
  inspect(sexp(doc), content="( Adds one)")
  inspect(single_span_line(only_child(doc)), content="1")
}

///|
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
  inspect(node_tag(syntax), content="Type::Name")

  let constr_id = field_value(syntax, "constr_id")
  let ident = field_value(constr_id, "id")
  inspect(sexp(ident), content="(pkg.Type)")
  inspect(single_span_line(only_child(ident)), content="1")
}

///|
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
  inspect(node_tag(pats), content="ArrayPatterns::Open")

  let binder = field_value(pats, "binder")
  inspect(sexp(binder), content="(((rest)))")
  let binder_atom = only_child(field_value(binder, "binder"))
  inspect(single_span_line(binder_atom), content="1")
}
