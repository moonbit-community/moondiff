///|
pub fn cli_rendering(edits : ArrayView[Edit[Array[Char]]]) -> String {
  let red = @chalk.chalk().color(Red).modifier(Bold)
  let green = @chalk.chalk().color(Green).modifier(Bold)
  let buf = StringBuilder::new(size_hint=edits.length() * 20)
  for edit in edits {
    match edit {
      Delete(old~) => buf.write_string(red.render(old))
      Insert(new~) => buf.write_string(green.render(new))
      Equal(new~, ..) => buf.write_iter(new.iter())
    }
  } else {
    buf.to_string()
  }
}

///|
pub let html_header =
  #|<!DOCTYPE html>
  #|<html>
  #|<head>
  #|<style>
  #|  /* 自定义删除线样式 */
  #|  del {
  #|    background-color: #ffe6e6;
  #|    color: #c00;
  #|    text-decoration: line-through;
  #|  }
  #|
  #|  /* 自定义下划线样式 */
  #|  ins {
  #|    background-color: #e6ffe6;
  #|    color: #008000;
  #|    text-decoration: none;
  #|  }
  #|
  #|  /* 应用于代码块的样式 */
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
pub let code_header =
  #|<pre>
  #|<code>

///|
pub let code_footer =
  #|</code>
  #|</pre>

///|
fn write_with_del(self : StringBuilder, str : Array[Char]) -> Unit {
  if str.is_empty() {
    return
  }
  self.write_string("<del>")
  self.write_iter(str.iter())
  self.write_string("</del>")
}

///|
fn write_with_ins(self : StringBuilder, str : Array[Char]) -> Unit {
  if str.is_empty() {
    return
  }
  self.write_string("<ins>")
  self.write_iter(str.iter())
  self.write_string("</ins>")
}

///|
pub fn web_rendering_to_buf(
  buf : StringBuilder,
  edits : ArrayView[Edit[Array[Char]]],
) -> Unit {
  for edit in edits {
    match edit {
      Delete(old~) => buf.write_with_del(old)
      Insert(new~) => buf.write_with_ins(new)
      Equal(new~, ..) => {
        if new.is_empty() {
          continue
        }
        buf.write_string(String::from_array(new))
      }
    }
  }
}

///|
pub fn web_rendering(edits : Array[Edit[Array[Char]]]) -> String {
  let buf = StringBuilder::new(size_hint=edits.length() * 20)
  buf.write_string(html_header)
  buf.write_char('\n')
  buf.write_string(code_header)
  buf.write_char('\n')
  web_rendering_to_buf(buf, edits)
  buf.write_char('\n')
  buf.write_string(code_footer)
  buf.write_char('\n')
  buf.write_string(html_footer)
  buf.to_string()
}

///|
fn Array::split_by_newline(self : Array[Char]) -> Array[ArrayView[Char]] {
  if self.is_empty() {
    return [self[:]]
  }
  let res = Array::new(capacity=self.length() / 8)
  let mut prev = 0
  let mut curr = 0
  loop self[:] {
    [] => {
      res.push(self[prev:curr])
      return res
    }
    ['\r', '\n', .. rest] => {
      res.push(self[prev:curr])
      prev = curr + 2
      curr += 2
      continue rest
    }
    ['\n' | '\r', .. rest] => {
      res.push(self[prev:curr])
      prev = curr + 1
      curr += 1
      continue rest
    }
    [_, .. rest] => {
      curr += 1
      continue rest
    }
  }
}

///|
test {
  inspect(
    ['a', 'b', 'c', '\n', 'd'].split_by_newline(),
    content="[['a', 'b', 'c'], ['d']]",
  )
  inspect(
    ['a', 'b', 'c', '\r', 'd'].split_by_newline(),
    content="[['a', 'b', 'c'], ['d']]",
  )
  inspect(
    ['a', 'b', 'c', '\r', '\n', 'd'].split_by_newline(),
    content="[['a', 'b', 'c'], ['d']]",
  )
  inspect(
    ['a', 'b', 'c', '\n'].split_by_newline(),
    content="[['a', 'b', 'c'], []]",
  )
  inspect(
    ['\n', 'a', 'b', 'c'].split_by_newline(),
    content="[[], ['a', 'b', 'c']]",
  )
}
