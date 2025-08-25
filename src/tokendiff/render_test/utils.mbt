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
  let (prefix, suffix, old, new) = @preopt.separate_common_prefix_and_suffix(
    old~,
    new~,
  )
  let edits = @myers.diff(old~, new~)
  let str = @render.web_rendering(prefix~, edits, suffix~)
  t.writeln(str)
  t.snapshot(filename="\{name}.html")
}
