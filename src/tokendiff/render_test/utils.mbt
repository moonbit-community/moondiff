///|
using @edit {type Edit}

///|
let source_dir = "src/tokendiff/render_test/sources"

///|
pub fn test_web_rendering(t : @test.T, name : String) -> Unit raise {
  let old = @fs.read_file_to_string("\{source_dir}/\{name}.old")
  let new = @fs.read_file_to_string("\{source_dir}/\{name}.new")
  let old_linewidths = @span.LineWidths::from_str(old)
  let old = @mbttoken.MbtToken::from_triples(
    @lexer.tokens_from_string(comment=true, old).tokens,
    old_linewidths,
  )
  let new_linewidths = @span.LineWidths::from_str(new)
  let new = @mbttoken.MbtToken::from_triples(
    @lexer.tokens_from_string(comment=true, new).tokens,
    new_linewidths,
  )
  let edits = @diff_with_opt.diff_with_opt(old~, new~)
  let buf = StringBuilder::new(size_hint=edits.length() * 20)
  buf.write_string(html_header)
  web_rendering(buf, edits)
  buf.write_string(html_footer)
  let str = buf.to_string()
  t.writeln(str)
  t.snapshot(filename="\{name}.html")
}

///|
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

///|
let html_footer =
  #|</body>
  #|</html>

///|
let code_header = "<pre><code>"

///|
let code_footer = "</code></pre>"

///|
fn StringBuilder::write_with_del(
  self : StringBuilder,
  tokens : ArrayView[@mbttoken.MbtToken],
) -> Unit {
  self.write_string("<del>")
  self.write_with_eqn(tokens)
  self.write_string("</del>")
}

///|
fn StringBuilder::write_with_ins(
  self : StringBuilder,
  tokens : ArrayView[@mbttoken.MbtToken],
) -> Unit {
  self.write_string("<ins>")
  self.write_with_eqn(tokens)
  self.write_string("</ins>")
}

///|
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

///|
fn web_rendering(
  buf : StringBuilder,
  edits : Array[Edit[Array[@mbttoken.MbtToken]]],
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
