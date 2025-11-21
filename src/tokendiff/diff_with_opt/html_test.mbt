///|UUID(bc9d004f-1861-42dd-9d7c-254ee4e062e0)
test "fn_insert_funcall" (t : @test.Test) {
  test_web_rendering(t, "fn_insert_funcall")
}

///|UUID(49082642-d53b-43af-9843-4316a1d886d1)
test "fn_insert_comments" (t : @test.Test) {
  test_web_rendering(t, "fn_insert_comments")
}

///|UUID(b3d8475e-f8dd-4e61-b231-2628e58d5abe)
test "fn_modify_then_insert" (t : @test.Test) {
  test_web_rendering(t, "fn_modify_then_insert")
}

///|UUID(cc0df378-8ce1-47b1-82f2-85737aea4d7e)
test "struct_modify_field_type_and_delete_field" (t : @test.Test) {
  test_web_rendering(t, "struct_modify_field_type_and_delete_field")
}

///|UUID(5e669ed7-1681-4bc9-a0e2-7ebadd458256)
test "fn_insert_errorpoly" (t : @test.Test) {
  test_web_rendering(t, "fn_insert_errorpoly")
}

///|UUID(2c52e358-4267-4a6c-b3f5-3f315f4c0780)
test "fn_insert_argument_and_stmt" (t : @test.Test) {
  test_web_rendering(t, "fn_insert_argument_and_stmt")
}

///|UUID(1ba8a816-d4f8-41bc-bf2a-21635ef2bae9)
test "line_group" (t : @test.Test) {
  test_web_rendering(t, "line_group")
}

///|UUID(fd14d3ff-7025-40b8-9a0e-7f2f3b6736be)
let source_dir = "src/tokendiff/diff_with_opt/sources"

///|UUID(7082c9e5-4419-47e3-afda-cb058464fba7)
fn test_web_rendering(t : @test.Test, name : String) -> Unit raise {
  let old = @fs.read_file_to_string("\{source_dir}/\{name}.old")
  let new = @fs.read_file_to_string("\{source_dir}/\{name}.new")
  let old = @mbttoken.MbtToken::from_str(old)
  let new = @mbttoken.MbtToken::from_str(new)
  let edits = @diff_with_opt.diff_with_opt(old~, new~)
  let buf = StringBuilder::new(size_hint=edits.length() * 20)
  buf.write_string(html_header)
  web_rendering(buf, edits)
  buf.write_string(html_footer)
  let str = buf.to_string()
  t.writeln(str)
  t.snapshot(filename="\{name}.html")
}

///|UUID(78382dc6-24aa-40ff-b76e-a7b205f7939d)
let html_header =
  #|<!DOCTYPE html>
  #|<html>
  #|<head>
  #|<style>
  #|
  #|  del {
  #|    background-color: #ffe6e6;
  #|    color: #c00;
  #|    text-decoration: line-through;
  #|  }
  #|
  #|  ins {
  #|    background-color: #e6ffe6;
  #|    color: #008000;
  #|    text-decoration: none;
  #|  }
  #|
  #|  pre {
  #|    background-color: #f4f4f4;
  #|    padding: 1em;
  #|    border-radius: 5px;
  #|    white-space: pre-wrap;
  #|  }
  #|  code {
  #|    font-family: 'Courier New', Courier, monospace;
  #|  }
  #|</style>
  #|</head>
  #|<body>

///|UUID(df236f22-cb02-4fca-b902-58de4bf842fe)
let html_footer =
  #|</body>
  #|</html>

///|UUID(6d6e4fba-3911-4360-acbb-20ed940b6195)
let code_header = "<pre><code>"

///|UUID(042bdcbd-36af-4b28-94ba-5a0429f8493a)
let code_footer = "</code></pre>"

///|UUID(5d764083-686b-411a-a9a3-1400a206c3c7)
fn StringBuilder::write_with_del(
  self : StringBuilder,
  tokens : ArrayView[@mbttoken.MbtToken],
) -> Unit {
  self.write_string("<del>")
  self.write_with_eqn(tokens)
  self.write_string("</del>")
}

///|UUID(8b823b79-d609-4b54-914f-bfddee553adb)
fn StringBuilder::write_with_ins(
  self : StringBuilder,
  tokens : ArrayView[@mbttoken.MbtToken],
) -> Unit {
  self.write_string("<ins>")
  self.write_with_eqn(tokens)
  self.write_string("</ins>")
}

///|UUID(953a05bb-4d47-4335-8e90-c376b9229de2)
fn StringBuilder::write_with_eqn(
  self : StringBuilder,
  tokens : ArrayView[@mbttoken.MbtToken],
) -> Unit {
  for token in tokens {
    self.write_iter(token.to_text().iter())
    // match token {
    //   Visible(repr~, ..) => ...
    //   Invisible(widths) => ...
    //   Barrier => ()
    // }
  }
}

///|UUID(0a94aba9-9370-4e41-acb1-d1a17c64c6d2)
fn web_rendering(
  buf : StringBuilder,
  edits : Array[@edit.Edit[Array[@mbttoken.MbtToken]]],
) -> Unit {
  buf.write_char('\n')
  buf.write_string(code_header)
  buf.write_char('\n')
  for edit in edits {
    match edit {
      Delete(old~) => buf.write_with_del(old)
      Insert(..) => ()
      Equal(old~, ..) => buf.write_with_eqn(old)
    }
  } else {
    buf.write_char('\n')
    buf.write_string(code_footer)
    buf.write_char('\n')
  }
  buf.write_char('\n')
  buf.write_string(code_header)
  buf.write_char('\n')
  for edit in edits {
    match edit {
      Insert(new~) => buf.write_with_ins(new)
      Delete(..) => ()
      Equal(new~, ..) => buf.write_with_eqn(new)
    }
  } else {
    buf.write_char('\n')
    buf.write_string(code_footer)
    buf.write_char('\n')
  }
}
