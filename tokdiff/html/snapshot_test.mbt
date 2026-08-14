///|
test "basic" (t : @test.Test) {
  let old = [
      "///| sum with default", "pub fn total(items : Array[Item]) -> Int {", "  let mut sum = 0",
      "  for item in items {", "    sum += item.price * item.count", "  }", "  sum // final",
      "}",
    ][:]
  let new = [
      "///| sum with tax", "pub fn total(items : Array[Item], tax~ : Int) -> Int {",
      "  let mut sum = 0", "  for item in items {", "    sum += item.price * item.count + tax",
      "  }", "  sum // final", "}",
    ][:]
  let body = StringBuilder::new()
  body <+ "<h3>Split view</h3>\n"
  body <+ "\{@html.side_by_side_html(old~, new~)}"
  body <+ "<h3>Unified view</h3>\n"
  body <+ "\{@html.unified_html(old~, new~)}"
  // attributes, Unicode comments, HTML-special characters
  let sp_old = [
      "#deprecated(\"use `f` instead\")", "fn g(a : Int) -> Int { a < 3 && a > 0 } // 判断范围",
    ][:]
  let sp_new = [
      "#deprecated(\"use `h` instead\")", "fn g(a : Int) -> Bool { a <= 3 && a > 0 } // 判断闭区间",
    ][:]
  body <+ "<h3>Attributes, Unicode, HTML-specials</h3>\n"
  body <+ "\{@html.side_by_side_html(old=sp_old, new=sp_new)}"
  t.write(@html.html_page(title="tokdiff basic", body.to_string()))
  t.snapshot(filename="basic.html")
}

///|
test "left leaning insert" (t : @test.Test) {
  let old = [
      "    match candidate.normalized_expr_identifier_name() {", "      Some(candidate_name) =>",
      "        Some(", "          bind_value(bindings, name, string_binding(candidate_name, candidate)),",
      "        )", "      None => Some(false)", "    }",
    ][:]
  let new = [
      "    if candidate.normalized_expr_identifier_name() is Some(candidate_name) {",
      "      Some(", "        bind_value(bindings, name, string_binding(candidate_name, candidate)),",
      "      )", "    } else {", "      Some(false)", "   }",
    ][:]
  let body = StringBuilder::new()
  body <+ "<h3>Split view</h3>\n"
  body <+ "\{@html.side_by_side_html(old~, new~)}"
  body <+ "<h3>Unified view</h3>\n"
  body <+ "\{@html.unified_html(old~, new~)}"
  t.write(@html.html_page(title="left leaning insert", body.to_string()))
  t.snapshot(filename="left_leaning_insert.html")
}

///|
test "html fallback resource path" (t : @test.Test) {
  let old = [
      "    path =>", "      match self.vfs.read(path) {", "        Some(content) => {",
      "          let content_type = match @path.Path::extname(path) {",
    ][:]
  let new = [
      "    path => {", "      let resource = if self.vfs.read(path) is Some(content) {",
      "        Some((path, content))", "      } else if request_accepts_html(request) &&",
      "        self.html_fallback_path is Some(fallback) {", "        self.vfs.read(fallback).map(content => (fallback, content))",
      "      } else {", "        None", "      }", "      match resource {", "        Some((resource_path, content)) => {",
      "          let content_type = match @path.Path::extname(resource_path) {",
    ][:]
  let body = StringBuilder::new()
  body <+ "<h3>Split view</h3>\n"
  body <+ "\{@html.side_by_side_html(old~, new~)}"
  body <+ "<h3>Unified view</h3>\n"
  body <+ "\{@html.unified_html(old~, new~)}"
  t.write(
    @html.html_page(title="html fallback resource path", body.to_string()),
  )
  t.snapshot(filename="html_fallback_resource_path.html")
}
