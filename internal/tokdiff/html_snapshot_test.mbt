///|
fn escape_page_title(text : String) -> String {
  let buf = StringBuilder()
  for char in text {
    match char {
      '&' => buf <+ "&amp;"
      '<' => buf <+ "&lt;"
      '>' => buf <+ "&gt;"
      _ => buf.write_char(char)
    }
  }
  buf.to_string()
}

///|
fn snapshot_page(title~ : String, body : String) -> String {
  let buf = StringBuilder()
  buf <+ "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\">"
  buf <+ "<title>\{escape_page_title(title)}</title><style>\n"
  buf <+ "body { font-family: monospace; }\n"
  buf <+ ".hunk-header { color: #00a; }\n"
  buf <+ ".del { background: #ffecec; }\n"
  buf <+ ".add { background: #eaffea; }\n"
  buf <+ "td.empty { background: #fafafa; }\n"
  buf <+ "b.wd { background: #f8b4b4; font-weight: normal; }\n"
  buf <+ "b.wa { background: #97e0a0; font-weight: normal; }\n"
  buf <+ ".ignored-context { background: white; font-weight: normal; }\n"
  buf <+ "pre.unified span { display: block; }\n"
  buf <+
    "table.split, table.unified { border-collapse: collapse; width: 100%; }\n"
  buf <+ "table.split td { width: 50%; vertical-align: top;\n"
  buf <+ "  white-space: pre-wrap; border: 1px solid #eee; }\n"
  buf <+
    "table.unified td { vertical-align: top; white-space: pre-wrap; border: 1px solid #eee; }\n"
  buf <+ "td.line-number { width: 1%; min-width: 3em; padding: 0 .5em;\n"
  buf <+
    "  color: #6e7781; background: #f6f8fa; text-align: right; user-select: none; }\n"
  buf <+ "table.unified td:last-child { width: 100%; }\n"
  buf <+ "</style></head><body>\n"
  buf <+ "\{body}"
  buf <+ "</body></html>\n"
  buf.to_string()
}

///|
test "snapshot page helper escapes its title and preserves rendered body" {
  let page = snapshot_page(title="<diff & review>", "<main>body</main>")
  assert_true(
    page.contains("<title>&lt;diff &amp; review&gt;</title>"),
    msg=page,
  )
  assert_true(page.contains("<main>body</main>"), msg=page)
}

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
  let body = StringBuilder()
  let document = @tokdiff.diff(old~, new~)
  body <+ "<h3>Split view</h3>\n"
  body <+ "\{@render_html.render_side_by_side(document)}"
  body <+ "<h3>Unified view</h3>\n"
  body <+ "\{@render_html.render_unified(document)}"
  // attributes, Unicode comments, HTML-special characters
  let sp_old = [
      "#deprecated(\"use `f` instead\")", "fn g(a : Int) -> Int { a < 3 && a > 0 } // 判断范围",
    ][:]
  let sp_new = [
      "#deprecated(\"use `h` instead\")", "fn g(a : Int) -> Bool { a <= 3 && a > 0 } // 判断闭区间",
    ][:]
  let special_document = @tokdiff.diff(old=sp_old, new=sp_new)
  body <+ "<h3>Attributes, Unicode, HTML-specials</h3>\n"
  body <+ "\{@render_html.render_side_by_side(special_document)}"
  t.write(snapshot_page(title="tokdiff basic", body.to_string()))
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
  let body = StringBuilder()
  let document = @tokdiff.diff(old~, new~)
  body <+ "<h3>Split view</h3>\n"
  body <+ "\{@render_html.render_side_by_side(document)}"
  body <+ "<h3>Unified view</h3>\n"
  body <+ "\{@render_html.render_unified(document)}"
  t.write(snapshot_page(title="left leaning insert", body.to_string()))
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
  let body = StringBuilder()
  let document = @tokdiff.diff(old~, new~)
  body <+ "<h3>Split view</h3>\n"
  body <+ "\{@render_html.render_side_by_side(document)}"
  body <+ "<h3>Unified view</h3>\n"
  body <+ "\{@render_html.render_unified(document)}"
  t.write(snapshot_page(title="html fallback resource path", body.to_string()))
  t.snapshot(filename="html_fallback_resource_path.html")
}
