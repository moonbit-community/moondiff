///|
test "plain unified hunks preserve renderer boundaries and file-edge ranges" {
  let old = ["0", "old", "2", "3", "4", "5", "6", "gone", "8"]
  let new = ["0", "new", "2", "3", "4", "5", "6", "added", "8"]
  let document = @linediff.line_diff(old~, new~, context=0)
  let patches = @unified.render_unified_hunks(document)
  assert_eq(patches, [
    "@@ -2 +2 @@\n-old\n+new\n", "@@ -8 +8 @@\n-gone\n+added\n",
  ])
  let added = @linediff.line_diff(old=[], new=["x", ""], context=0)
  assert_eq(@unified.render_unified_hunks(added), ["@@ -0,0 +1,2 @@\n+x\n+\n"])
  let removed = @linediff.line_diff(old=["x", ""], new=[], context=0)
  assert_eq(@unified.render_unified_hunks(removed), ["@@ -1,2 +0,0 @@\n-x\n-\n"])
  for patch in patches {
    let header = patch.view(end_offset=patch.find("\n").unwrap())
    assert_true(
      @render_html.render_unified(document).contains(
        "<span class=\"hunk-header\">\{header}</span>",
      ),
    )
  }
}

///|
test "MoonBit hunks follow semantic line cleanup used by HTML" {
  let old = ["let a = old", "", "let b = old", "let c = old"]
  let new = ["let a = new", "let b = new", "let c = new", ""]
  let raw = @tokdiff.diff(old~, new~, context=0)
  assert_eq(@unified.render_unified_hunks(raw).length(), 2)
  let cleaned_document = @tokdiff.diff(old~, new~, context=0, line_cleanup=true)
  let cleaned = @unified.render_unified_hunks(cleaned_document)
  assert_eq(cleaned.length(), 1)
  assert_true(cleaned[0].contains("-let b = old\n"))
  assert_true(cleaned[0].contains("+let b = new\n"))
  let header = cleaned[0].view(end_offset=cleaned[0].find("\n").unwrap())
  assert_true(
    @render_html.render_side_by_side(cleaned_document).contains(
      "<td class=\"hunk-header\" colspan=\"2\">\{header}</td>",
    ),
  )
}

///|
test "hunk notes are escaped immediately after matching headers in all views" {
  let old = ["0", "old", "2", "3", "4", "5", "6", "gone", "8"]
  let new = ["0", "new", "2", "3", "4", "5", "6", "added", "8"]
  let notes : Array[@render_html.HunkNote?] = [
    Some({ title: "Group <&>", body: "Explain <old> & new.", }),
    None,
  ]
  let semantic_document = @tokdiff.diff(old~, new~, context=0)
  let plain_document = @linediff.line_diff(old~, new~, context=0)
  let split = @render_html.render_side_by_side(
    semantic_document,
    line_numbers=true,
    hunk_notes=notes,
  )
  let unified = @render_html.render_unified(semantic_document, hunk_notes=notes)
  let plain_split = @render_html.render_side_by_side(
    plain_document,
    hunk_notes=notes,
  )
  let plain_unified = @render_html.render_unified(
    plain_document,
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
  let semantic_document = @tokdiff.diff(old~, new~)
  let plain_document = @linediff.line_diff(old~, new~)
  assert_eq(
    @render_html.render_side_by_side(semantic_document),
    @render_html.render_side_by_side(semantic_document, hunk_notes=[]),
  )
  assert_eq(
    @render_html.render_unified(semantic_document),
    @render_html.render_unified(semantic_document, hunk_notes=[]),
  )
  assert_eq(
    @render_html.render_side_by_side(plain_document),
    @render_html.render_side_by_side(plain_document, hunk_notes=[]),
  )
  assert_eq(
    @render_html.render_unified(plain_document),
    @render_html.render_unified(plain_document, hunk_notes=[]),
  )
}

///|
test "per-hunk HTML renderers preserve indexes, wrappers, and notes" {
  let old = ["0", "old", "2", "3", "4", "5", "6", "gone", "8"]
  let new = ["0", "new", "2", "3", "4", "5", "6", "added", "8"]
  let notes : Array[@render_html.HunkNote?] = [
    Some({ title: "First <group>", body: "First explanation.", }),
    Some({ title: "Second & group", body: "Second explanation.", }),
  ]
  let semantic_document = @tokdiff.diff(old~, new~, context=0)
  let semantic_patches = @unified.render_unified_hunks(semantic_document)
  let plain_document = @linediff.line_diff(old~, new~, context=0)
  let plain_patches = @unified.render_unified_hunks(plain_document)
  let semantic_renderers = [
    @render_html.render_side_by_side_hunks(
      semantic_document,
      line_numbers=true,
      hunk_notes=notes,
    ),
    @render_html.render_unified_hunks(
      semantic_document,
      line_numbers=true,
      hunk_notes=notes,
    ),
  ]
  let plain_renderers = [
    @render_html.render_side_by_side_hunks(
      plain_document,
      line_numbers=true,
      hunk_notes=notes,
    ),
    @render_html.render_unified_hunks(
      plain_document,
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
  let empty_semantic = @tokdiff.diff(old=[], new=[])
  let empty_plain = @linediff.line_diff(old=[], new=[])
  assert_eq(@render_html.render_side_by_side_hunks(empty_semantic), [])
  assert_eq(@render_html.render_unified_hunks(empty_semantic), [])
  assert_eq(@render_html.render_side_by_side_hunks(empty_plain), [])
  assert_eq(@render_html.render_unified_hunks(empty_plain), [])
}
