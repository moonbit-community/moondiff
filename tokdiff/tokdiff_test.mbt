///|
test "tokenizer is faithful and language-aware" {
  for
    line in [
      "let x = 1 // trailing", "/// doc comment", "///| x", "let s = \"a//b\" // real",
      "let 名 = \"é😀\"", "fn f(a : Int) -> Int { a + 1 }",
    ] {
    assert_eq(@tokdiff.tokenize_line(line).map(t => t.text()).join(""), line)
  }
  // a string literal is one Str token even when it contains `//`
  let toks = @tokdiff.tokenize_line("let s = \"a//b\" // real")
  @debug.debug_inspect(
    toks.filter(t => t.kind() is Str).map(t => t.text()),
    content=(
      #|["\"a//b\""]
    ),
  )
}

///|
test "similarity: comments help but cannot veto" {
  // similar comments pair; unrelated comments do not
  assert_true(@tokdiff.similarity("// add tax", "// add the tax") > 400)
  assert_true(
    @tokdiff.similarity(
      "// promoted; output is not", "// another topic entirely",
    ) <
    400,
  )
  // code identical, comment rewritten: still a strong pair
  assert_true(
    @tokdiff.similarity("let x = 1 // sum", "let x = 1 // total") > 900,
  )
  // identical comment beats a rewritten one (tie-breaker)
  assert_true(
    @tokdiff.similarity("let x = 1 // a", "let x = 1 // a") >
    @tokdiff.similarity("let x = 1 // a", "let x = 1 // b"),
  )
  // lines with nothing in common stay under the threshold
  assert_true(
    @tokdiff.similarity("alpha beta gamma delta eps", "one two three four five") <
    400,
  )
  // respacing barely matters
  assert_true(@tokdiff.similarity("f(a,b)", "f( a , b )") > 800)
  // zero-mass lines pair only when identical
  assert_true(@tokdiff.similarity("//", "") == 0)
  assert_true(@tokdiff.similarity("//", "//") == 1000)
}

///|
test "split view: alignment, highlights, escaping" {
  let old = [
      "fn total(items : Array[Item]) -> Int {", "  let mut sum = 0 // running total",
      "  // helper detail", "  sum", "}",
    ][:]
  let new = [
      "fn total(items : Array[Item], tax~ : Int) -> Int {", "  let mut sum = 0 // running total",
      "  sum + tax", "}",
    ][:]
  let html = @tokdiff_html.side_by_side_html(old~, new~, context=1)
  // paired rows carry word-level highlights
  assert_true(html.contains("<b class=\"wa\">"))
  // the unrelated comment line remains an unpaired deletion; the accepted
  // window projection may now emphasize its deleted semantic content
  assert_true(
    html.contains(
      "<td class=\"del\">  <b class=\"wd\">// helper detail</b></td><td class=\"empty\">",
    ),
  )
  // escaping
  let esc_html = @tokdiff_html.side_by_side_html(old=["if a < b && c > d {"], new=[
    "if a <= b && c > d {",
  ])
  assert_true(esc_html.contains("&lt;"))
  assert_true(esc_html.contains("<b class=\"wa\">"))
}

///|
test "whitespace-only edit runs avoid strong intraline highlights" {
  let old_indent = "  let value = item"
  let new_indent = "    let value = item"
  let split = @tokdiff_html.side_by_side_html(
    old=[old_indent],
    new=[new_indent],
    context=0,
  )
  assert_true(
    split.contains(
      "<td class=\"del\">\{old_indent}</td><td class=\"add\">\{new_indent}</td>",
    ),
  )
  assert_false(split.contains("<b class="))
  let unified = @tokdiff_html.unified_html(
    old=[old_indent],
    new=[new_indent],
    context=0,
  )
  assert_true(unified.contains("<span class=\"del\">-\{old_indent}</span>"))
  assert_true(unified.contains("<span class=\"add\">+\{new_indent}</span>"))
  assert_false(unified.contains("<b class="))

  let mixed = @tokdiff_html.side_by_side_html(
    old=["  let old = 1"],
    new=["    let new = 1"],
    context=0,
  )
  assert_true(
    mixed.contains(
      "<td class=\"del\">  let <b class=\"wd\">old</b> = 1</td><td class=\"add\">    let <b class=\"wa\">new</b> = 1</td>",
    ),
  )

  for pair in [("f( x)", "f(x)"), ("f(x)", "f( x)")] {
    let (old, new) = pair
    let spacing = @tokdiff_html.side_by_side_html(
      old=[old],
      new=[new],
      context=0,
    )
    assert_false(spacing.contains("<b class="))
  }

  let phrase = @tokdiff_html.side_by_side_html(
    old=["pub fn f()"],
    new=["pub fn f(a : Int)"],
    context=0,
  )
  assert_true(phrase.contains("<b class=\"wa\">a : Int</b>"))
}

///|
test "semantic highlights exclude boundary whitespace in both HTML views" {
  let count_split = @tokdiff_html.side_by_side_html(
    old=["count"],
    new=["count + tax"],
    context=0,
  )
  assert_true(
    count_split.contains(
      "<td class=\"del\">count</td><td class=\"add\">count <b class=\"wa\">+ tax</b></td>",
    ),
  )
  let count_unified = @tokdiff_html.unified_html(
    old=["count"],
    new=["count + tax"],
    context=0,
  )
  assert_true(
    count_unified.contains(
      "<span class=\"add\">+count <b class=\"wa\">+ tax</b></span>",
    ),
  )

  let parameter_split = @tokdiff_html.side_by_side_html(
    old=["f()"],
    new=["f( a : Int )"],
    context=0,
  )
  assert_true(
    parameter_split.contains(
      "<td class=\"del\">f()</td><td class=\"add\">f( <b class=\"wa\">a : Int</b> )</td>",
    ),
  )
  let parameter_unified = @tokdiff_html.unified_html(
    old=["f()"],
    new=["f( a : Int )"],
    context=0,
  )
  assert_true(
    parameter_unified.contains(
      "<span class=\"add\">+f( <b class=\"wa\">a : Int</b> )</span>",
    ),
  )
}

///|
test "budget fallbacks render plain rows" {
  // per-line token cap
  let big_old = "word ".repeat(600) + "same tail here"
  let big_new = "word ".repeat(600) + "same tail CHANGED"
  let html = @tokdiff_html.side_by_side_html(old=[big_old], new=[big_new])
  assert_false(html.contains("<b class="))
  // total cell budget
  let old_lines : Array[String] = []
  let new_lines : Array[String] = []
  for i in 0..<50 {
    let base = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi line\{i}"
    old_lines.push(base)
    new_lines.push(base + " tail")
  }
  let html2 = @tokdiff_html.side_by_side_html(old=old_lines, new=new_lines)
  assert_false(html2.contains("<b class="))
}

///|
fn kinds_of(line : String) -> String {
  @tokdiff.tokenize_line(line)
  .map(t => {
    match t.kind() {
      Word => "W"
      Str => "S"
      Punct => "P"
      Comment => "C"
      Filler => "F"
      Space => "_"
      Marker => "M"
    }
  })
  .join("")
}

///|
test "classification matrix" {
  // attributes and package references carry identifier-grade weight
  inspect(kinds_of("#deprecated(\"msg\")"), content="W")
  inspect(kinds_of("@debug.debug_inspect(x)"), content="W_WPWP")
  // Unicode identifiers are Word, not Punct
  inspect(kinds_of("let 名 = 1"), content="W_W_P_W")
  // `///|` is a full-weight structural marker
  inspect(kinds_of("///| about"), content="MFC")
  // string containing `//` is one Str token; unterminated is tolerated
  inspect(kinds_of("let s = \"a//b\""), content="W_W_P_S")
  inspect(kinds_of("\"unterminated"), content="S")
}

///|
test "zero-mass variants" {
  assert_true(@tokdiff.similarity("//", "//   ") == 0)
  assert_true(@tokdiff.similarity("", "") == 1000)
}

///|
test "comment line does not pair with a declaration" {
  assert_true(
    @tokdiff.similarity(
      "// promoted; `output` is not (use the trait or string interpolation).", "pub extend DiffAlgorithm with Eq::{equal}",
    ) <
    400,
  )
}

///|
test "split view: blank-but-present vs absent cells" {
  let html = @tokdiff_html.side_by_side_html(old=["foo(1)", "", "bar(2)"], new=[
    "foo(9)", "zzz qqq www",
  ])
  assert_true(html.contains("<td class=\"del\"></td>"))
  assert_true(html.contains("<td class=\"empty\"></td>"))
}

///|
test "unified view mirrors the split alignment" {
  let old = ["let total = a + b // sum", "unrelated_one"][:]
  let new = ["let sum = a + b // sum", "other_entirely stuff"][:]
  let html = @tokdiff_html.unified_html(old~, new~, context=0)
  // paired replacement: highlighted rename, deletions before insertions
  assert_true(html.contains("<b class=\"wd\">total</b>"))
  assert_true(html.contains("<b class=\"wa\">sum</b>"))
  let del_idx = html.find("class=\"del\"").unwrap()
  let add_idx = html.find("class=\"add\"").unwrap()
  assert_true(del_idx < add_idx)
}

///|
test "line numbers are opt-in and preserve legacy HTML when disabled" {
  let old = ["a", "old", "same", "gone", "z"]
  let new = ["a", "new", "same", "added", "z"]
  assert_eq(
    @tokdiff_html.side_by_side_html(old~, new~, context=1),
    @tokdiff_html.side_by_side_html(old~, new~, context=1, line_numbers=false),
  )
  assert_eq(
    @tokdiff_html.unified_html(old~, new~, context=1),
    @tokdiff_html.unified_html(old~, new~, context=1, line_numbers=false),
  )
}

///|
test "numbered split has four columns and complete old and new positions" {
  let html = @tokdiff_html.side_by_side_html(
    old=["ctx", "old <tag>", "", "tail"],
    new=["ctx", "new & value", "inserted", "tail"],
    context=1,
    line_cleanup=true,
    line_numbers=true,
  )
  assert_true(html.contains("class=\"hunk-header\" colspan=\"4\""))
  assert_true(
    html.contains(
      "<td class=\"line-number old-line-number\">1</td><td class=\"ctx\">ctx</td><td class=\"line-number new-line-number\">1</td><td class=\"ctx\">ctx</td>",
    ),
  )
  assert_true(
    html.contains(
      "<td class=\"line-number old-line-number\">2</td><td class=\"del\"><b class=\"wd\">old &lt;tag&gt;</b></td>",
    ),
  )
  assert_true(
    html.contains(
      "<td class=\"line-number old-line-number\">3</td><td class=\"del\"></td>",
    ),
  )
  assert_true(
    html.contains(
      "<td class=\"line-number new-line-number\">3</td><td class=\"add\"><b class=\"wa\">inserted</b></td>",
    ),
  )
  assert_true(html.contains("<b class=\"wa\">new &amp; value</b>"))
}

///|
test "numbered unified has three columns across replacements and multiple hunks" {
  let old = ["0", "old", "2", "3", "4", "5", "6", "gone", "8"]
  let new = ["0", "new", "2", "3", "4", "5", "6", "added", "8"]
  let html = @tokdiff_html.unified_html(
    old~,
    new~,
    context=0,
    line_cleanup=true,
    line_numbers=true,
  )
  assert_true(html.has_prefix("<table class=\"unified numbered\">"))
  assert_true(html.contains("class=\"hunk-header\" colspan=\"3\""))
  assert_true(
    html.contains(
      "<td class=\"line-number old-line-number\">2</td><td class=\"line-number new-line-number\"></td><td class=\"del\">-<b class=\"wd\">old</b></td>",
    ),
  )
  assert_true(
    html.contains(
      "<td class=\"line-number old-line-number\"></td><td class=\"line-number new-line-number\">2</td><td class=\"add\">+<b class=\"wa\">new</b></td>",
    ),
  )
  assert_true(
    html.contains(
      "<td class=\"line-number old-line-number\">8</td><td class=\"line-number new-line-number\"></td><td class=\"del\">-<b class=\"wd\">gone</b></td>",
    ),
  )
  assert_true(
    html.contains(
      "<td class=\"line-number old-line-number\"></td><td class=\"line-number new-line-number\">8</td><td class=\"add\">+<b class=\"wa\">added</b></td>",
    ),
  )
}

///|
test "numbered pure add and delete use an empty number cell for the absent side" {
  inspect(
    @tokdiff_html.side_by_side_html(
      old=[],
      new=["名", ""],
      context=0,
      line_numbers=true,
    ),
    content=(
      #|<table class="split">
      #|<tr><td class="hunk-header" colspan="4">@@ -0,0 +1,2 @@</td></tr>
      #|<tr><td class="line-number old-line-number"></td><td class="empty"></td><td class="line-number new-line-number">1</td><td class="add">名</td></tr>
      #|<tr><td class="line-number old-line-number"></td><td class="empty"></td><td class="line-number new-line-number">2</td><td class="add"></td></tr>
      #|</table>
      #|
    ),
  )
  let deleted = @tokdiff_html.unified_html(
    old=["x", ""],
    new=[],
    context=0,
    line_numbers=true,
  )
  assert_true(
    deleted.contains(
      "<td class=\"line-number old-line-number\">2</td><td class=\"line-number new-line-number\"></td><td class=\"del\">-</td>",
    ),
  )
}
