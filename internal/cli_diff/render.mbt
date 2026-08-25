///|
fn computation_stage_text(stage : @model.ComputationStage) -> String {
  match stage {
    TopLevelAlignment => "top-level alignment"
    SyntaxMatching => "syntax matching"
    IntralineMatching => "intraline matching"
  }
}

///|
fn fallback_location(scope : @model.FallbackScope) -> String {
  match scope {
    WholeFile => ""
    Region(old~, new~) => {
      let parts : Array[String] = []
      if old is Some(range) {
        parts.push("old line \{range.start + 1}")
      }
      if new is Some(range) {
        parts.push("new line \{range.start + 1}")
      }
      if parts.is_empty() {
        "file"
      } else {
        parts.join(", ")
      }
    }
  }
}

///|
fn fallback_reason_text(fallback : @model.FallbackInfo) -> String {
  match fallback.reason {
    ParseError(detail~, ..) => detail
    GraphLimitExceeded(limit~) => {
      let base = "graph limit exceeded (\{limit})"
      let location = fallback_location(fallback.scope)
      if location.is_empty() {
        base
      } else {
        "\{base} at \{location}"
      }
    }
    ComputationLimitExceeded(stage~, limit~) => {
      let base = "computation limit exceeded (\{limit}) during \{computation_stage_text(stage)}"
      let location = fallback_location(fallback.scope)
      if location.is_empty() {
        base
      } else {
        "\{base} at \{location}"
      }
    }
    TopLevelReordering =>
      "top-level reordering has no changes inside aligned declarations"
  }
}

///|
fn source_lines(source : String) -> Array[String] {
  if source.is_empty() {
    []
  } else {
    @source_text.split_lines(source)
  }
}

///|
fn terminal_options(
  options : Options,
  old_max_line : Int,
  new_max_line : Int,
) -> @terminal.RenderOptions {
  @terminal.RenderOptions::new(
    use_color=options.use_color,
    old_max_line~,
    new_max_line~,
  )
}

///|
fn render_empty_state(
  old_label : String,
  new_label : String,
  message : String,
  options : Options,
) -> String {
  @terminal.render_document(
    old_label,
    new_label,
    { hunks: [] },
    options=@terminal.RenderOptions::new(use_color=options.use_color),
  ) +
  message
}

///|
fn section_label(label : String, range : @model.LineRange?) -> String {
  if range is Some(range) {
    "\{label}: line \{range.start + 1}"
  } else {
    label
  }
}

///|
fn range_overlaps_hunk(
  range : @model.LineRange?,
  start : Int,
  len : Int,
) -> Bool {
  if range is Some(range) {
    if len == 0 {
      range.start <= start && start <= range.start + range.len
    } else if range.len == 0 {
      start <= range.start && range.start <= start + len
    } else {
      start < range.start + range.len && range.start < start + len
    }
  } else {
    false
  }
}

///|
fn ranges_overlap(left : @model.LineRange?, right : @model.LineRange?) -> Bool {
  match (left, right) {
    (Some(left), Some(right)) =>
      if left.len == 0 || right.len == 0 {
        left.start <= right.start + right.len &&
        right.start <= left.start + left.len
      } else {
        left.start < right.start + right.len &&
        right.start < left.start + left.len
      }
    _ => false
  }
}

///|
fn fallback_matches_section(
  fallback : @model.FallbackInfo,
  section : @model.DiffSection,
) -> Bool {
  match fallback.scope {
    WholeFile => false
    Region(old~, new~) =>
      ranges_overlap(old, section.old) || ranges_overlap(new, section.new)
  }
}

///|
fn hunk_matches_section(
  hunk : @model.DiffHunk,
  section : @model.DiffSection,
) -> Bool {
  if hunk.old_len == 0 && hunk.new_len > 0 {
    range_overlaps_hunk(section.new, hunk.new_start, hunk.new_len)
  } else if hunk.new_len == 0 && hunk.old_len > 0 {
    range_overlaps_hunk(section.old, hunk.old_start, hunk.old_len)
  } else {
    range_overlaps_hunk(section.old, hunk.old_start, hunk.old_len) ||
    range_overlaps_hunk(section.new, hunk.new_start, hunk.new_len)
  }
}

///|
fn section_max_line(range : @model.LineRange?) -> Int {
  if range is Some(range) {
    @cmp.maximum(range.start + range.len, 1)
  } else {
    1
  }
}

///|
/// Keep the established CLI hunk anchors for pure insertions and deletions by
/// anchoring a missing side at line 1.
fn adjust_empty_side_hunk_anchors(
  hunks : ArrayView[@model.DiffHunk],
  old_missing : Bool,
  new_missing : Bool,
) -> Array[@model.DiffHunk] {
  hunks.map(fn(hunk) {
    {
      ..hunk,
      old_start: if old_missing && hunk.old_len == 0 {
        1
      } else {
        hunk.old_start
      },
      new_start: if new_missing && hunk.new_len == 0 {
        1
      } else {
        hunk.new_start
      },
    }
  })
}

///|
fn append_rendered_section(
  buf : StringBuilder,
  wrote : Ref[Bool],
  rendered : String,
) -> Unit {
  if wrote.val {
    buf.write_char('\n')
  }
  buf.write_string(rendered)
  wrote.val = true
}

///|
fn render_sectioned_document(
  old_label : String,
  new_label : String,
  document : @model.DiffDocument,
  fallbacks : ArrayView[@model.FallbackInfo],
  options : Options,
  sections : ArrayView[@model.DiffSection],
  old_line_count : Int,
  new_line_count : Int,
) -> String {
  let buf = StringBuilder()
  let used_hunks = Array::make(document.hunks.length(), false)
  let used_fallbacks = Array::make(fallbacks.length(), false)
  let wrote = Ref(false)
  for section in sections {
    let section_hunks : Array[@model.DiffHunk] = []
    for index, hunk in document.hunks {
      if !used_hunks[index] && hunk_matches_section(hunk, section) {
        section_hunks.push(hunk)
        used_hunks[index] = true
      }
    }
    let matching_fallbacks : Array[Int] = []
    for index, fallback in fallbacks {
      if !used_fallbacks[index] && fallback_matches_section(fallback, section) {
        matching_fallbacks.push(index)
        used_fallbacks[index] = true
      }
    }
    if section_hunks.is_empty() {
      continue
    }
    let section_buf = StringBuilder()
    for index in matching_fallbacks {
      section_buf <+
        "note: fallback to tokdiff (\{fallback_reason_text(fallbacks[index])})\n"
    }
    let rendered_hunks = if matching_fallbacks.is_empty() {
      adjust_empty_side_hunk_anchors(
        section_hunks,
        section.old is None,
        section.new is None,
      )
    } else {
      section_hunks
    }
    section_buf.write_string(
      @terminal.render_document(
        section_label(old_label, section.old),
        section_label(new_label, section.new),
        { hunks: rendered_hunks[:] },
        options=terminal_options(
          options,
          section_max_line(section.old),
          section_max_line(section.new),
        ),
      ),
    )
    append_rendered_section(buf, wrote, section_buf.to_string())
  }
  let unassigned : Array[@model.DiffHunk] = []
  for index, hunk in document.hunks {
    if !used_hunks[index] {
      unassigned.push(hunk)
    }
  }
  if !unassigned.is_empty() {
    append_rendered_section(
      buf,
      wrote,
      @terminal.render_document(
        old_label,
        new_label,
        { hunks: unassigned[:] },
        options=terminal_options(options, old_line_count, new_line_count),
      ),
    )
  }
  buf.to_string()
}

///|
fn render_whole_document(
  old_label : String,
  new_label : String,
  document : @model.DiffDocument,
  options : Options,
  old_line_count : Int,
  new_line_count : Int,
) -> String {
  let hunks = adjust_empty_side_hunk_anchors(
    document.hunks,
    old_line_count == 0,
    new_line_count == 0,
  )
  @terminal.render_document(
    old_label,
    new_label,
    { hunks: hunks[:] },
    options=terminal_options(options, old_line_count, new_line_count),
  )
}

///|
fn mark_plain_line_changed(line : @model.DiffLine) -> @model.DiffLine {
  if line.segments.is_empty() {
    line
  } else {
    { index: line.index, segments: [{ kind: Changed, text: line.text() }] }
  }
}

///|
fn mark_plain_row_changed(row : @model.DiffRow) -> @model.DiffRow {
  match row {
    Paired(old_line, new_line) =>
      Paired(
        mark_plain_line_changed(old_line),
        mark_plain_line_changed(new_line),
      )
    OldOnly(line) => OldOnly(mark_plain_line_changed(line))
    NewOnly(line) => NewOnly(mark_plain_line_changed(line))
  }
}

///|
/// Plain line calculation intentionally has no intraline classification. Mark
/// each changed row as a full-line change for the terminal color convention
/// while preserving the Patience hunk and row alignment verbatim.
fn mark_plain_changes(document : @model.DiffDocument) -> @model.DiffDocument {
  let hunks : Array[@model.DiffHunk] = []
  for hunk in document.hunks {
    let blocks : Array[@model.DiffBlock] = []
    for block in hunk.blocks {
      blocks.push(
        match block {
          ContextBlock(lines) => ContextBlock(lines)
          ChangeBlock(rows) => ChangeBlock(rows.map(mark_plain_row_changed))
          IgnoredBlock(rows) => IgnoredBlock(rows)
        },
      )
    }
    hunks.push({ ..hunk, blocks: blocks[:] })
  }
  { hunks: hunks[:] }
}

///|
fn render_plain_text(
  old_label : String,
  old_source : String,
  new_label : String,
  new_source : String,
  options : Options,
) -> String {
  let old = source_lines(old_source)
  let new = source_lines(new_source)
  let document = @tokdiff.line_diff(old~, new~, context=options.context_lines)
  if document.hunks.is_empty() {
    render_empty_state(old_label, new_label, "No changes.\n", options)
  } else {
    render_whole_document(
      old_label,
      new_label,
      mark_plain_changes(document),
      options,
      old.length(),
      new.length(),
    )
  }
}

///|
fn ignored_only_message(options : Options) -> String {
  if options.ignore_comments && options.ignore_tests {
    "No changes besides MoonBit test blocks, comments, or blank lines.\n"
  } else if options.ignore_tests {
    "No changes besides MoonBit test blocks.\n"
  } else {
    "No changes besides comments or blank lines.\n"
  }
}

///|
fn render_moonbit(
  old_label : String,
  old_source : String,
  new_label : String,
  new_source : String,
  options : Options,
) -> String {
  let old = source_lines(old_source)
  let new = source_lines(new_source)
  let result = @mbtdiff.diff(
    old_source,
    new_source,
    old_name=old_label,
    new_name=new_label,
    options=@mbtdiff.DiffOptions::new(
      context_lines=options.context_lines,
      graph_limit=options.graph_limit,
      ignore_comments=options.ignore_comments,
      ignore_tests=options.ignore_tests,
    ),
  )
  match result.status() {
    Identical =>
      render_empty_state(old_label, new_label, "No changes.\n", options)
    IgnoredOnly =>
      render_empty_state(
        old_label,
        new_label,
        ignored_only_message(options),
        options,
      )
    NoStructuralChanges => ""
    Changed => {
      let document = result.document()
      let fallbacks = result.fallbacks()
      if fallbacks is [fallback] && fallback.scope is WholeFile {
        "note: fallback to tokdiff (\{fallback_reason_text(fallback)})\n" +
        render_whole_document(
          old_label,
          new_label,
          document,
          options,
          old.length(),
          new.length(),
        )
      } else if options.ignore_comments {
        let buf = StringBuilder()
        for fallback in fallbacks {
          buf <+
            "note: fallback to tokdiff (\{fallback_reason_text(fallback)})\n"
        }
        buf.write_string(
          render_whole_document(
            old_label,
            new_label,
            document,
            options,
            old.length(),
            new.length(),
          ),
        )
        buf.to_string()
      } else {
        match result.layout() {
          WholeDocument =>
            render_whole_document(
              old_label,
              new_label,
              document,
              options,
              old.length(),
              new.length(),
            )
          TopLevelSections(sections) =>
            render_sectioned_document(
              old_label,
              new_label,
              document,
              fallbacks,
              options,
              sections,
              old.length(),
              new.length(),
            )
        }
      }
    }
  }
}

///|
/// Calculate and render one CLI diff. Both labels must end in `.mbt` to select
/// MoonBit-aware calculation; all other pairs use the canonical plain Patience
/// line diff. Rendering itself is delegated a completed `DiffDocument`.
pub fn render(
  old_label : String,
  old_source : String,
  new_label : String,
  new_source : String,
  options? : Options = Default::default(),
) -> String {
  if old_label.has_suffix(".mbt") && new_label.has_suffix(".mbt") {
    render_moonbit(old_label, old_source, new_label, new_source, options)
  } else {
    render_plain_text(old_label, old_source, new_label, new_source, options)
  }
}
