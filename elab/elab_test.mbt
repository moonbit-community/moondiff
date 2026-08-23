///|
using @dsyntax {type ListKind, type Syntax}

///|
fn source_lines(source : String) -> Array[Array[Char]] {
  let lines = Array::new()
  for line in source.split("\n") {
    lines.push(line.to_owned().to_array())
  } nobreak {
    lines
  }
}

///|
fn span_text(lines : Array[Array[Char]], span : @span.SingleLineSpan) -> String {
  let start_idx = if span.start_col == 0 { 0 } else { span.start_col - 1 }
  let end_idx = span.end_col - 1
  String::from_array(lines[span.line - 1][start_idx:end_idx].to_owned())
}

///|
fn positions_text(
  lines : Array[Array[Char]],
  positions : Array[@span.SingleLineSpan],
) -> String {
  let buf = StringBuilder()
  let mut first = true
  for position in positions {
    if first {
      first = false
    } else {
      buf.write_string("\n")
    }
    buf.write_string(span_text(lines, position))
  }
  buf.to_string()
}

///|
fn only_item(source : String) -> @cst.CstNode raise {
  let result = @cst.parse_structure(source)
  assert_true(result.diagnostics_view().is_empty())
  let item = Ref(None)
  for entry in result.root().children {
    let (label, child) = entry
    if label == Some("item") {
      if item.val is Some(_) {
        fail("expected one CST item")
      }
      item.val = Some(child)
    }
  }
  item.val.unwrap_or_else(() => fail("expected one CST item"))
}

///|
fn assert_source_faithful(source : String, syntax : Syntax) -> Unit raise {
  let lines = source_lines(source)

  fn walk(lines : Array[Array[Char]], syntax : Syntax) -> Unit raise {
    match syntax {
      Syntax::Atom(content~, position~, ..) => {
        assert_true(!position.is_empty())
        assert_eq(positions_text(lines, position), content)
      }
      Syntax::List(
        open_content~,
        open_position~,
        children~,
        close_content~,
        close_position~,
        ..
      ) => {
        if !open_content.is_empty() {
          assert_true(!open_position.is_empty())
          assert_eq(positions_text(lines, open_position), open_content)
        }
        if !close_content.is_empty() {
          assert_true(!close_position.is_empty())
          assert_eq(positions_text(lines, close_position), close_content)
        }
        for child in children {
          walk(lines, child)
        }
      }
    }
  }

  walk(lines, syntax)
}

///|
fn collect_delims(syntax : Syntax, delims : Array[(String, String)]) -> Unit {
  match syntax {
    Syntax::Atom(..) => ()
    Syntax::List(open_content~, children~, close_content~, ..) => {
      if !open_content.is_empty() || !close_content.is_empty() {
        delims.push((open_content, close_content))
      }
      for child in children {
        collect_delims(child, delims)
      }
    }
  }
}

///|
fn has_delim(
  delims : Array[(String, String)],
  open_ : String,
  close_ : String,
) -> Bool {
  for delim in delims {
    let (open_content, close_content) = delim
    if open_content == open_ && close_content == close_ {
      return true
    }
  }
  false
}

///|
fn syntax_contains(syntax : Syntax, content : String) -> Bool {
  match syntax {
    Syntax::Atom(content=atom_content, ..) => atom_content == content
    Syntax::List(open_content~, children~, close_content~, ..) => {
      if open_content == content || close_content == content {
        return true
      }
      children.any(fn(child) { syntax_contains(child, content) })
    }
  }
}

///|
fn atom_kind(syntax : Syntax, wanted : String) -> @dsyntax.AtomKind? {
  match syntax {
    Syntax::Atom(content~, kind~, ..) =>
      if content == wanted {
        Some(kind)
      } else {
        None
      }
    Syntax::List(children~, ..) => {
      for child in children {
        if atom_kind(child, wanted) is Some(kind) {
          return Some(kind)
        }
      }
      None
    }
  }
}

///|
fn collect_brace_blocks(syntax : Syntax, blocks : Array[Syntax]) -> Unit {
  match syntax {
    Syntax::Atom(..) => ()
    Syntax::List(open_content~, close_content~, children~, ..) => {
      if open_content == "{" && close_content == "}" {
        blocks.push(syntax)
      }
      for child in children {
        collect_brace_blocks(child, blocks)
      }
    }
  }
}

///|
fn push_line_once(lines : Array[Int], line : Int) -> Unit {
  if !lines.contains(line) {
    lines.push(line)
  }
}

///|
fn collect_syntax_lines(syntax : Syntax, lines : Array[Int]) -> Unit {
  match syntax {
    Syntax::Atom(position~, ..) =>
      for span in position {
        push_line_once(lines, span.line)
      }
    Syntax::List(open_position~, children~, close_position~, ..) => {
      for span in open_position {
        push_line_once(lines, span.line)
      }
      for child in children {
        collect_syntax_lines(child, lines)
      }
      for span in close_position {
        push_line_once(lines, span.line)
      }
    }
  }
}

///|
fn syntax_lines(syntax : Syntax) -> Array[Int] {
  let lines = Array::new()
  collect_syntax_lines(syntax, lines)
  lines.sort()
  lines
}

///|
fn add_span_coverage(
  coverage : Array[Array[Int]],
  span : @span.SingleLineSpan,
) -> Unit {
  let line = span.line - 1
  let start = if span.start_col == 0 { 0 } else { span.start_col - 1 }
  let end_ = span.end_col - 1
  for column in start..<end_ {
    coverage[line][column] += 1
  }
}

///|
fn collect_coverage(syntax : Syntax, coverage : Array[Array[Int]]) -> Unit {
  match syntax {
    Syntax::Atom(position~, ..) =>
      for span in position {
        add_span_coverage(coverage, span)
      }
    Syntax::List(open_position~, children~, close_position~, ..) => {
      for span in open_position {
        add_span_coverage(coverage, span)
      }
      for child in children {
        collect_coverage(child, coverage)
      }
      for span in close_position {
        add_span_coverage(coverage, span)
      }
    }
  }
}

///|
fn assert_non_whitespace_covered_once(
  source : String,
  syntax : Syntax,
) -> Unit raise {
  let lines = source_lines(source)
  let coverage = lines.map(fn(line) { line.map(fn(_) { 0 }) })
  collect_coverage(syntax, coverage)
  for line_index in 0..<lines.length() {
    for column in 0..<lines[line_index].length() {
      let ch = lines[line_index][column]
      assert_true(coverage[line_index][column] <= 1)
      if ch != ' ' && ch != '\t' && ch != '\r' {
        assert_eq(coverage[line_index][column], 1)
      }
    }
  }
}

///|
test "CST elaboration preserves the exact list node kind" {
  let source = "fn f { () }"
  let node = only_item(source)
  assert_true(node.kind is @cst.Impl_Function)
  let syntax = @elab.elab_cst(source, node)
  guard syntax is Syntax::List(kind=Some(kind), ..) else {
    fail("expected the function item to elaborate to an identified list")
  }
  assert_true(kind == ListKind::from_node_kind(node.kind))
}

///|
test "CST atoms and delimiters map back to source" {
  let source =
    #|pub fn add(x : Int, y : Int) -> Int {
    #|  foo([x], { baz: y })
    #|}
  let syntax = @elab.elab_cst(source, only_item(source))
  assert_source_faithful(source, syntax)
  let delims = Array::new()
  collect_delims(syntax, delims)
  assert_true(has_delim(delims, "(", ")"))
  assert_true(has_delim(delims, "[", "]"))
  assert_true(has_delim(delims, "{", "}"))
}

///|
test "CST elaboration ignores lexer Unicode whitespace gaps" {
  let source = "let\u{00a0}value\u{3000}=\u{00a0}1"
  let syntax = @elab.elab_cst(source, only_item(source))
  assert_source_faithful(source, syntax)
  assert_false(syntax_contains(syntax, "\u{00a0}"))
  assert_false(syntax_contains(syntax, "\u{3000}"))
  assert_true(syntax_contains(syntax, "let"))
  assert_true(syntax_contains(syntax, "value"))
  assert_true(syntax_contains(syntax, "="))
  assert_true(syntax_contains(syntax, "1"))
}

///|
test "CST elaboration keeps error annotations and function stubs" {
  let raise_source = "fn f() -> Unit raise E { () }"
  let raise_syntax = @elab.elab_cst(raise_source, only_item(raise_source))
  assert_source_faithful(raise_source, raise_syntax)
  assert_true(syntax_contains(raise_syntax, "raise"))

  let stub_source = "fn ffi(x : Int) -> Int = \"module\" \"function\""
  let stub_syntax = @elab.elab_cst(stub_source, only_item(stub_source))
  assert_source_faithful(stub_source, stub_syntax)
  assert_true(syntax_contains(stub_syntax, "="))
}

///|
test "CST elaboration exposes block statements as siblings" {
  let source =
    #|fn init {
    #|  // case 002
    #|  let marker = "case-002"
    #|  println(marker)
    #|  println(fib(8))
    #|}
  let syntax = @elab.elab_cst(source, only_item(source))
  let blocks = Array::new()
  collect_brace_blocks(syntax, blocks)
  assert_eq(blocks.length(), 1)
  guard blocks[0] is Syntax::List(children~, ..) else {
    fail("expected block list")
  }
  let line_sets = children.map(syntax_lines)
  assert_true(line_sets.any(fn(lines) { lines == [3] }))
  assert_true(line_sets.any(fn(lines) { lines == [4] }))
  assert_true(line_sets.any(fn(lines) { lines == [5] }))
}

///|
test "CST elaboration keeps using package tokens intact" {
  let source = "using @pkg { type Foo as Bar, trait Baz, func }"
  let syntax = @elab.elab_cst(source, only_item(source))
  assert_source_faithful(source, syntax)
  assert_true(syntax_contains(syntax, "@pkg"))
  assert_false(syntax_contains(syntax, "@"))
}

///|
test "CST elaboration covers interpolation and encoded punctuation once" {
  let source =
    #|fn render(obj : Object) {
    #|  let text = "value=\{obj.field}"
    #|  let emoji = "😀".length()
    #|  println(@pkg.format(text))
    #|}
  let syntax = @elab.elab_cst(source, only_item(source))
  assert_source_faithful(source, syntax)
  assert_non_whitespace_covered_once(source, syntax)
}

///|
test "new CST semantic metadata does not duplicate source syntax" {
  let sources = [
    "pub fn f(x : Int) -> Int { x }", "let x : Int = 1", "const X : Int = 1", "type T[A] = Array[A]",
    "struct S { pub mut x : Int }", "enum E { A(x~ : Int) }", "trait Show { show(Self) -> String }",
    "impl Show for S with show(self) { \"S\" }", "test { inspect(1, content=\"1\") }",
    "using @pkg { func as func2 }", "extenum Open += { More }", "suberror Failure { Invalid(String) }",
    "import { \"pkg/core\", \"pkg/other\" @other } for \"native\"", "extend @pkg.Type with @pkg.Trait::{method}",
    "fn labelled { let value = done~: { break done~ 1 }; value }", "fn guarded(value : Int?) -> Int { guard! value is Some(inner); inner }",
    "fn matched(x : Int?) -> Int { match x { Some(a) | (None with a = 0) => a } }",
  ]
  for source in sources {
    let result = @cst.parse_structure(source)
    assert_true(result.diagnostics_view().is_empty())
    let syntax = @elab.elab_cst(source, result.root())
    assert_source_faithful(source, syntax)
    assert_non_whitespace_covered_once(source, syntax)
  }
}

///|
test "new CST syntax kinds retain display atom categories" {
  let source =
    #|fn render {
    #|  let value : @pkg.Type = @pkg.Ctor
    #|  let truth = true
    #|  let count = 42
    #|  let text = "value=\{value}"
    #|  // note
    #|}
  let syntax = @elab.elab_cst(source, only_item(source))
  assert_true(atom_kind(syntax, "fn") == Some(@dsyntax.AtomKind::Keyword))
  assert_true(atom_kind(syntax, "true") == Some(@dsyntax.AtomKind::Keyword))
  assert_true(atom_kind(syntax, "42") == Some(@dsyntax.AtomKind::Normal))
  assert_true(
    atom_kind(syntax, "\"value=\\{value}\"") ==
    Some(@dsyntax.AtomKind::String(@dsyntax.StringKind::StringLiteral)),
  )
  assert_true(atom_kind(syntax, "@pkg") == Some(@dsyntax.AtomKind::Type))
  assert_true(atom_kind(syntax, "Type") == Some(@dsyntax.AtomKind::Type))
  let operator_keyword_source = "pub(readonly) fn extend(a : Bool, b : Bool) { a → b }"
  let operator_keyword_syntax = @elab.elab_cst(
    operator_keyword_source,
    only_item(operator_keyword_source),
  )
  assert_true(
    atom_kind(operator_keyword_syntax, "readonly") ==
    Some(@dsyntax.AtomKind::Keyword),
  )
  assert_true(
    atom_kind(operator_keyword_syntax, "extend") ==
    Some(@dsyntax.AtomKind::Keyword),
  )
  assert_true(
    atom_kind(operator_keyword_syntax, "→") ==
    Some(@dsyntax.AtomKind::Keyword),
  )
  let comment_source = "// note\nlet x = 1"
  let comment_syntax = @elab.elab_cst(
    comment_source,
    @cst.parse_structure(comment_source).root(),
  )
  assert_true(
    atom_kind(comment_syntax, "// note") == Some(@dsyntax.AtomKind::Comment),
  )
}
