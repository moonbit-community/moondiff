///|
pub fn cli_rendering(edits : ArrayView[Edit[MbtToken]]) -> String {
  let edits = compress_edits(edits) |> @postopt.align_edit_boundaries
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
  #|<pre>
  #|<code>

///|
pub let html_footer =
  #|</code>
  #|</pre>
  #|</body>
  #|</html>

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
  edits : ArrayView[Edit[MbtToken]],
) -> Unit {
  let edits = compress_edits(edits) |> @postopt.align_edit_boundaries
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
pub fn web_rendering(
  prefix~ : ArrayView[Edit[MbtToken]],
  edits : ArrayView[Edit[MbtToken]],
  suffix~ : ArrayView[Edit[MbtToken]],
) -> String {
  let buf = StringBuilder::new(size_hint=edits.length() * 20)
  buf.write_string(html_header)
  buf.write_char('\n')
  web_rendering_to_buf(buf, prefix)
  web_rendering_to_buf(buf, edits)
  web_rendering_to_buf(buf, suffix)
  buf.write_char('\n')
  buf.write_string(html_footer)
  buf.to_string()
}
