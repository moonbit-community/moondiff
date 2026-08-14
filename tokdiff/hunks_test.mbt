///|
test "plain unified hunks preserve renderer boundaries and file-edge ranges" {
  let old = ["0", "old", "2", "3", "4", "5", "6", "gone", "8"]
  let new = ["0", "new", "2", "3", "4", "5", "6", "added", "8"]
  assert_eq(@tokdiff_text.unified_line_hunks(old~, new~, context=0), [
    "@@ -2 +2 @@\n-old\n+new\n", "@@ -8 +8 @@\n-gone\n+added\n",
  ])
  assert_eq(
    @tokdiff_text.unified_line_hunks(old=[], new=["x", ""], context=0),
    ["@@ -0,0 +1,2 @@\n+x\n+\n"],
  )
  assert_eq(
    @tokdiff_text.unified_line_hunks(old=["x", ""], new=[], context=0),
    ["@@ -1,2 +0,0 @@\n-x\n-\n"],
  )
  for patch in @tokdiff_text.unified_line_hunks(old~, new~, context=0) {
    let header = patch.view(end_offset=patch.find("\n").unwrap())
    assert_true(
      @tokdiff_html.unified_line_html(old~, new~, context=0).contains(
        "<span class=\"hunk-header\">\{header}</span>",
      ),
    )
  }
}

///|
test "MoonBit hunks follow semantic line cleanup used by HTML" {
  let old = ["let a = old", "", "let b = old", "let c = old"]
  let new = ["let a = new", "let b = new", "let c = new", ""]
  assert_eq(@tokdiff_text.unified_hunks(old~, new~, context=0).length(), 2)
  let cleaned = @tokdiff_text.unified_hunks(
    old~,
    new~,
    context=0,
    line_cleanup=true,
  )
  assert_eq(cleaned.length(), 1)
  assert_true(cleaned[0].contains("-let b = old\n"))
  assert_true(cleaned[0].contains("+let b = new\n"))
  let header = cleaned[0].view(end_offset=cleaned[0].find("\n").unwrap())
  assert_true(
    @tokdiff_html.side_by_side_html(old~, new~, context=0, line_cleanup=true).contains(
      "<td class=\"hunk-header\" colspan=\"2\">\{header}</td>",
    ),
  )
}

///|
test "hunk notes are escaped immediately after matching headers in all views" {
  let old = ["0", "old", "2", "3", "4", "5", "6", "gone", "8"]
  let new = ["0", "new", "2", "3", "4", "5", "6", "added", "8"]
  let notes : Array[@tokdiff_html.HunkNote?] = [
    Some({ title: "Group <&>", body: "Explain <old> & new." }),
    None,
  ]
  let split = @tokdiff_html.side_by_side_html(
    old~,
    new~,
    context=0,
    line_numbers=true,
    hunk_notes=notes,
  )
  let unified = @tokdiff_html.unified_html(
    old~,
    new~,
    context=0,
    hunk_notes=notes,
  )
  let plain_split = @tokdiff_html.side_by_side_line_html(
    old~,
    new~,
    context=0,
    hunk_notes=notes,
  )
  let plain_unified = @tokdiff_html.unified_line_html(
    old~,
    new~,
    context=0,
    line_numbers=true,
    hunk_notes=notes,
  )
  let escaped = "<b class=\"hunk-note-title\">Group &lt;&amp;&gt;</b>: Explain &lt;old&gt; &amp; new."
  assert_true(split.contains("class=\"hunk-note\" colspan=\"4\">\{escaped}"))
  assert_true(unified.contains("<span class=\"hunk-note\">\{escaped}</span>"))
  assert_true(
    plain_split.contains("class=\"hunk-note\" colspan=\"2\">\{escaped}"),
  )
  assert_true(
    plain_unified.contains("class=\"hunk-note\" colspan=\"3\">\{escaped}"),
  )
  for html in [split, unified, plain_split, plain_unified] {
    let header = html.find("@@ -2 +2 @@").unwrap()
    let note = html.find("class=\"hunk-note\"").unwrap()
    let change = html.find("class=\"del\"").unwrap()
    assert_true(header < note)
    assert_true(note < change)
    assert_eq(
      html.split("class=\"hunk-note\"").length(),
      2,
      msg="only the first of two hunks has a note",
    )
  }
}

///|
test "omitting notes remains byte-identical to an explicit empty array" {
  let old = ["old"]
  let new = ["new"]
  assert_eq(
    @tokdiff_html.side_by_side_html(old~, new~),
    @tokdiff_html.side_by_side_html(old~, new~, hunk_notes=[]),
  )
  assert_eq(
    @tokdiff_html.unified_html(old~, new~),
    @tokdiff_html.unified_html(old~, new~, hunk_notes=[]),
  )
  assert_eq(
    @tokdiff_html.side_by_side_line_html(old~, new~),
    @tokdiff_html.side_by_side_line_html(old~, new~, hunk_notes=[]),
  )
  assert_eq(
    @tokdiff_html.unified_line_html(old~, new~),
    @tokdiff_html.unified_line_html(old~, new~, hunk_notes=[]),
  )
}

///|
test "per-hunk HTML renderers preserve indexes, wrappers, and notes" {
  let old = ["0", "old", "2", "3", "4", "5", "6", "gone", "8"]
  let new = ["0", "new", "2", "3", "4", "5", "6", "added", "8"]
  let notes : Array[@tokdiff_html.HunkNote?] = [
    Some({ title: "First <group>", body: "First explanation." }),
    Some({ title: "Second & group", body: "Second explanation." }),
  ]
  let semantic_patches = @tokdiff_text.unified_hunks(old~, new~, context=0)
  let plain_patches = @tokdiff_text.unified_line_hunks(old~, new~, context=0)
  let semantic_renderers = [
    @tokdiff_html.side_by_side_hunks_html(
      old~,
      new~,
      context=0,
      line_numbers=true,
      hunk_notes=notes,
    ),
    @tokdiff_html.unified_hunks_html(
      old~,
      new~,
      context=0,
      line_numbers=true,
      hunk_notes=notes,
    ),
  ]
  let plain_renderers = [
    @tokdiff_html.side_by_side_line_hunks_html(
      old~,
      new~,
      context=0,
      line_numbers=true,
      hunk_notes=notes,
    ),
    @tokdiff_html.unified_line_hunks_html(
      old~,
      new~,
      context=0,
      line_numbers=true,
      hunk_notes=notes,
    ),
  ]
  for rendered_hunks in semantic_renderers {
    assert_eq(rendered_hunks.length(), semantic_patches.length())
    for index, rendered in rendered_hunks {
      let patch = semantic_patches[index]
      let header = patch.view(end_offset=patch.find("\n").unwrap())
      assert_true(rendered.contains(header))
      assert_eq(rendered.split("class=\"hunk-header\"").length(), 2)
    }
    assert_true(rendered_hunks[0].contains("First &lt;group&gt;"))
    assert_false(rendered_hunks[0].contains("Second &amp; group"))
    assert_true(rendered_hunks[1].contains("Second &amp; group"))
    assert_false(rendered_hunks[1].contains("First &lt;group&gt;"))
  }
  for rendered_hunks in plain_renderers {
    assert_eq(rendered_hunks.length(), plain_patches.length())
    for index, rendered in rendered_hunks {
      let patch = plain_patches[index]
      let header = patch.view(end_offset=patch.find("\n").unwrap())
      assert_true(rendered.contains(header))
      assert_eq(rendered.split("class=\"hunk-header\"").length(), 2)
    }
  }
  assert_eq(@tokdiff_html.side_by_side_hunks_html(old=[], new=[]), [])
  assert_eq(@tokdiff_html.unified_hunks_html(old=[], new=[]), [])
  assert_eq(@tokdiff_html.side_by_side_line_hunks_html(old=[], new=[]), [])
  assert_eq(@tokdiff_html.unified_line_hunks_html(old=[], new=[]), [])
}
