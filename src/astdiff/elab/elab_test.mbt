///|UUID(2dde4507-d810-4333-a0ae-173aa929afbb)
using @dsyntax {type Syntax}

///|UUID(7d567fd1-0f85-44a7-99a1-d18df1d56665)
fn source_lines(source : String) -> Array[Array[Char]] {
  let lines = Array::new()
  for line in source.split("\n") {
    lines.push(line.to_owned().to_array())
  } nobreak {
    lines
  }
}

///|UUID(81551d34-5425-46e8-968b-f16351c60dd4)
fn span_text(lines : Array[Array[Char]], span : @span.SingleLineSpan) -> String {
  let start_idx = if span.start_col == 0 { 0 } else { span.start_col - 1 }
  let end_idx = span.end_col - 1
  String::from_array(lines[span.line - 1][start_idx:end_idx].to_owned())
}

///|UUID(738ecb58-db28-4f89-adbb-bf26ad8a4b19)
fn positions_text(
  lines : Array[Array[Char]],
  positions : Array[@span.SingleLineSpan],
) -> String {
  let buf = StringBuilder::new()
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

///|UUID(29253b8d-1faf-4d5e-bf49-70e5887a84e5)
fn only_impl(impls : @list.List[@past.Impl]) -> @past.Impl raise {
  match impls {
    @list.More(impl_, tail=@list.Empty) => impl_
    _ => fail("expected single impl")
  }
}

///|UUID(9864c703-6c25-4ec0-b8f0-caef7990d5c1)
fn assert_source_faithful(source : String, syntax : Syntax) -> Unit raise {
  let lines = source_lines(source)

  fn walk(lines : Array[Array[Char]], syntax : Syntax) -> Unit raise {
    match syntax {
      Syntax::Atom(content~, position~, ..) => {
        assert_true(!position.is_empty())
        assert_true(positions_text(lines, position) == content)
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
          assert_true(positions_text(lines, open_position) == open_content)
        }
        if !close_content.is_empty() {
          assert_true(!close_position.is_empty())
          assert_true(positions_text(lines, close_position) == close_content)
        }
        for child in children {
          walk(lines, child)
        }
      }
    }
  }

  walk(lines, syntax)
}

///|UUID(0264a484-ff1e-494d-a90c-7733739fd1d6)
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

///|UUID(c0b78f9f-5d40-47bf-833a-c3d147fe7e2d)
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

///|UUID(0a45c58a-1e09-465d-b0a5-a16f329af536)
fn syntax_contains(syntax : Syntax, content : String) -> Bool {
  match syntax {
    Syntax::Atom(content=atom_content, ..) => atom_content == content
    Syntax::List(open_content~, children~, close_content~, ..) => {
      if open_content == content || close_content == content {
        return true
      }
      for child in children {
        if syntax_contains(child, content) {
          return true
        }
      }
      false
    }
  }
}

///|UUID(480238d4-3c5c-4052-a17f-dc5a6d57e1ab)
fn assert_contains(syntax : Syntax, content : String) -> Unit raise {
  assert_true(syntax_contains(syntax, content))
}

///|UUID(13f1e0a5-29a1-431e-89f8-652f99cef0e2)
test "elab atoms and delimiters map back to source" {
  let source =
    #|/// Adds one
    #|pub fn add(x : Int, y : Int) -> Int {
    #|  foo([x], { baz: y })
    #|}
  let (impls, reports) = @parser.parse_string(source)
  assert_true(reports.is_empty())

  let syntax = elab_impl(source, only_impl(impls))
  assert_source_faithful(source, syntax)
}

///|UUID(944b0d47-3581-4c4a-a565-b1660d510e30)
test "elab keeps raise keyword in explicit error type" {
  let source = "fn f() -> Unit raise E { () }"
  let (impls, reports) = @parser.parse_string(source)
  assert_true(reports.is_empty())

  let syntax = elab_impl(source, only_impl(impls))
  assert_source_faithful(source, syntax)
  assert_contains(syntax, "raise")
}

///|UUID(2d1c37d8-ccbc-4e9d-a6d9-df191fae0b89)
test "elab keeps equal sign in function stubs" {
  let source =
    #|fn ffi(x : Int) -> Int = "module" "function"
  let (impls, reports) = @parser.parse_string(source)
  assert_true(reports.is_empty())

  let syntax = elab_impl(source, only_impl(impls))
  assert_source_faithful(source, syntax)
  assert_contains(syntax, "=")
}

///|UUID(8d704ff0-86ff-41ce-b6c5-3149e7056cf4)
test "elab preserves nested paren bracket brace delimiters" {
  let source = "fn f() { foo([bar], { baz: qux }) }"
  let (impls, reports) = @parser.parse_string(source)
  assert_true(reports.is_empty())

  let syntax = elab_impl(source, only_impl(impls))
  let delims = Array::new()
  collect_delims(syntax, delims)

  assert_true(has_delim(delims, "(", ")"))
  assert_true(has_delim(delims, "[", "]"))
  assert_true(has_delim(delims, "{", "}"))
}

///|UUID(5d33875a-7831-4215-ad6f-c1b18bbdce6e)
test "elab uses bracket delimiters for array indexing" {
  let source = "let y = xs[i:j]"
  let (impls, reports) = @parser.parse_string(source)
  assert_true(reports.is_empty())

  let syntax = elab_impl(source, only_impl(impls))
  let delims = Array::new()
  collect_delims(syntax, delims)

  assert_source_faithful(source, syntax)
  assert_true(has_delim(delims, "[", "]"))
}

///|UUID(f7398ef1-020e-4754-9b09-72bb5050a3ae)
test "elab recovers using type and trait items from source gaps" {
  let source = "using @pkg { type Foo as Bar, trait Baz }"
  let (impls, reports) = @parser.parse_string(source)
  assert_true(reports.is_empty())

  let syntax = elab_impl(source, only_impl(impls))
  assert_source_faithful(source, syntax)
}
