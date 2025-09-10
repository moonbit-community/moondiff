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
let code_header = "<pre><code>"

///|
let code_footer = "</code></pre>"

///|
let table_header = "<table border=\"1\">"

///|
let table_footer = "</table>"

///|
let data_cell_header = "<tr><td>"

///|
let data_cell_footer = "</td></tr>"

///|
fn write_with_del(self : StringBuilder, str : ArrayView[Char]) -> Unit {
  if str.length() == 0 {
    return
  }
  self.write_string("<del>")
  self.write_iter(str.iter())
  self.write_string("</del>")
}

///|
fn write_with_ins(self : StringBuilder, str : ArrayView[Char]) -> Unit {
  if str.length() == 0 {
    return
  }
  self.write_string("<ins>")
  self.write_iter(str.iter())
  self.write_string("</ins>")
}

///|
fn multiple_write_with_del(
  self : StringBuilder,
  lines : ArrayView[ArrayView[Char]],
) -> Unit {
  let mut first = true
  for line in lines {
    if !first {
      self.write_string(code_footer)
      self.write_string(data_cell_footer)
      self.write_char('\n')
      self.write_string(data_cell_header)
      self.write_string(code_header)
    }
    first = false
    self.write_with_del(line)
  }
}

///|
fn multiple_write_with_ins(
  self : StringBuilder,
  lines : ArrayView[ArrayView[Char]],
) -> Unit {
  let mut first = true
  for line in lines {
    if !first {
      self.write_string(code_footer)
      self.write_string(data_cell_footer)
      self.write_char('\n')
      self.write_string(data_cell_header)
      self.write_string(code_header)
    }
    first = false
    self.write_with_ins(line)
  }
}

///|
fn multiple_write_with_eqn(
  self : StringBuilder,
  lines : ArrayView[ArrayView[Char]],
) -> Unit {
  let mut first = true
  for line in lines {
    if !first {
      self.write_string(code_footer)
      self.write_string(data_cell_footer)
      self.write_char('\n')
      self.write_string(data_cell_header)
      self.write_string(code_header)
    }
    first = false
    self.write_iter(line.iter())
  }
}

///|
pub fn web_rendering(
  buf : StringBuilder,
  edits : Array[Edit[Array[Char]]],
) -> Unit {
  buf.write_string(table_header)
  buf.write_char('\n')
  buf.write_string(data_cell_header)
  buf.write_string(code_header)
  for edit in edits {
    match edit {
      Delete(old~) => buf.multiple_write_with_del(old.split_by_newline())
      Insert(new~) => buf.multiple_write_with_ins(new.split_by_newline())
      Equal(new~, ..) => buf.multiple_write_with_eqn(new.split_by_newline())
    }
  } else {
    buf.write_string(code_footer)
    buf.write_string(data_cell_footer)
    buf.write_char('\n')
    buf.write_string(table_footer)
  }
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
