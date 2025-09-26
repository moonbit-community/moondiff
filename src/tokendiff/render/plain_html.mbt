///|
pub let html_header =
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
pub let html_footer =
  #|</body>
  #|</html>

///|
let code_header = "<pre><code>"

///|
let code_footer = "</code></pre>"

///|
fn write_with_del(
  self : StringBuilder,
  tokens : ArrayView[@mbttoken.MbtToken],
) -> Unit {
  self.write_string("<del>")
  self.write_with_eqn(tokens)
  self.write_string("</del>")
}

///|
fn write_with_ins(
  self : StringBuilder,
  tokens : ArrayView[@mbttoken.MbtToken],
) -> Unit {
  self.write_string("<ins>")
  self.write_with_eqn(tokens)
  self.write_string("</ins>")
}

///|
fn write_with_eqn(
  self : StringBuilder,
  tokens : ArrayView[@mbttoken.MbtToken],
) -> Unit {
  for token in tokens {
    let token = token.to_text()
    self.write_iter(token.iter())
  }
}

///|
pub fn web_rendering(
  buf : StringBuilder,
  edits : Array[Edit[Array[@mbttoken.MbtToken]]],
) -> Unit {
  buf.write_char('\n')
  buf.write_string(code_header)
  buf.write_char('\n')
  for edit in edits {
    match edit {
      Delete(old~) => buf.write_with_del(old)
      Insert(new~) => buf.write_with_ins(new)
      Equal(new~, ..) => buf.write_with_eqn(new)
    }
  } else {
    buf.write_char('\n')
    buf.write_string(code_footer)
    buf.write_char('\n')
  }
}

///|
pub fn web_rendering_delete_block(
  buf : StringBuilder,
  old~ : Array[Char],
) -> Unit {
  buf.write_string(code_header)
  buf.write_string("<del>")
  buf.write_iter(old.iter())
  buf.write_string("</del>")
  buf.write_string(code_footer)
}

///|
pub fn web_rendering_insert_block(
  buf : StringBuilder,
  new~ : Array[Char],
) -> Unit {
  buf.write_string(code_header)
  buf.write_string("<ins>")
  buf.write_iter(new.iter())
  buf.write_string("</ins>")
  buf.write_string(code_footer)
}

// fn Array::split_by_newline(self : Array[Char]) -> Array[ArrayView[Char]] {
//   if self.is_empty() {
//     return [self[:]]
//   }
//   let res = Array::new(capacity=self.length() / 8)
//   let mut prev = 0
//   let mut curr = 0
//   loop self[:] {
//     [] => {
//       res.push(self[prev:curr])
//       return res
//     }
//     ['\r', '\n', .. rest] => {
//       res.push(self[prev:curr])
//       prev = curr + 2
//       curr += 2
//       continue rest
//     }
//     ['\n' | '\r', .. rest] => {
//       res.push(self[prev:curr])
//       prev = curr + 1
//       curr += 1
//       continue rest
//     }
//     [_, .. rest] => {
//       curr += 1
//       continue rest
//     }
//   }
// }
// 
// test {
//   inspect(
//     ['a', 'b', 'c', '\n', 'd'].split_by_newline(),
//     content="[['a', 'b', 'c'], ['d']]",
//   )
//   inspect(
//     ['a', 'b', 'c', '\r', 'd'].split_by_newline(),
//     content="[['a', 'b', 'c'], ['d']]",
//   )
//   inspect(
//     ['a', 'b', 'c', '\r', '\n', 'd'].split_by_newline(),
//     content="[['a', 'b', 'c'], ['d']]",
//   )
//   inspect(
//     ['a', 'b', 'c', '\n'].split_by_newline(),
//     content="[['a', 'b', 'c'], []]",
//   )
//   inspect(
//     ['\n', 'a', 'b', 'c'].split_by_newline(),
//     content="[[], ['a', 'b', 'c']]",
//   )
// }
//
