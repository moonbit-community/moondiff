///|UUID(fb09927f-8d77-415f-9b0e-b40809807775)
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
fn fallback_reason_text(
  fallback : @model.FallbackInfo,
  parser_reason : String?,
) -> String {
  match fallback.reason {
    ParseError(detail~, ..) => parser_reason.unwrap_or(detail)
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
  }
}

///|
fn section_label(label : String, range : @model.LineRange?) -> String {
  match range {
    None => label
    Some(range) => "\{label}: line \{range.start + 1}"
  }
}

///|
fn range_overlaps_hunk(
  range : @model.LineRange?,
  start : Int,
  len : Int,
) -> Bool {
  match range {
    None => false
    Some(range) =>
      if len == 0 {
        range.start <= start && start <= range.start + range.len
      } else if range.len == 0 {
        start <= range.start && range.start <= start + len
      } else {
        start < range.start + range.len && range.start < start + len
      }
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
  section : @alignment.DiffSection,
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
  section : @alignment.DiffSection,
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
  match range {
    None => 1
    Some(range) => @cmp.maximum(range.start + range.len, 1)
  }
}

///|
fn legacy_empty_side_hunks(
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
  parser_reason : String?,
  options : DiffOptions,
  sections : ArrayView[@alignment.DiffSection],
) -> String {
  let buf = StringBuilder::new()
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
    let section_buf = StringBuilder::new()
    for index in matching_fallbacks {
      section_buf <+
        "note: fallback to tokdiff (\{fallback_reason_text(fallbacks[index], parser_reason)})\n"
    }
    let rendered_hunks = if matching_fallbacks.is_empty() {
      legacy_empty_side_hunks(
        section_hunks,
        section.old is None,
        section.new is None,
      )
    } else {
      section_hunks
    }
    section_buf.write_string(
      @render.render_diff_document_with_max_lines(
        section_label(old_label, section.old),
        section_label(new_label, section.new),
        { hunks: rendered_hunks[:] },
        options.render_options(),
        section_max_line(section.old),
        section_max_line(section.new),
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
      @render.render_diff_document(
        old_label,
        new_label,
        { hunks: unassigned[:] },
        options.render_options(),
      ),
    )
  }
  buf.to_string()
}

///|
fn render_legacy_whole_ast_document(
  old_label : String,
  old_source : String,
  new_label : String,
  new_source : String,
  document : @model.DiffDocument,
  options : DiffOptions,
) -> String {
  let hunks = legacy_empty_side_hunks(
    document.hunks,
    old_source.is_empty(),
    new_source.is_empty(),
  )
  @render.render_diff_document_with_max_lines(
    old_label,
    new_label,
    { hunks, },
    options.render_options(),
    @render.split_lines(old_source).length(),
    @render.split_lines(new_source).length(),
  )
}

///|UUID(4dc6c7bd-e552-4ca2-b156-8b254afe1200)
// Render one shared alignment calculation, falling back to tokdiff when
// structural calculation cannot cover the whole input.
pub fn diff_text(
  old_label : String,
  old_source : String,
  new_label : String,
  new_source : String,
  options? : DiffOptions = DiffOptions::default(),
) -> DiffResult {
  let has_changes = old_source != new_source
  let calculation = @alignment.calculate_diff_document(
    old_source,
    new_source,
    old_name=old_label,
    new_name=new_label,
    context=options.context_lines,
    graph_limit=options.graph_limit,
    ignore_comments=options.ignore_comments,
  )
  let result = calculation.result
  let fallbacks = result.fallbacks
  let parser_reason = calculation.parser_reason
  let rendered = match result.status {
    Identical =>
      @render.render_file_headers(old_label, new_label, options.use_color) +
      "No changes.\n"
    IgnoredOnly =>
      @render.render_file_headers(old_label, new_label, options.use_color) +
      "No changes besides comments or blank lines.\n"
    NoStructuralChanges => ""
    Changed =>
      if fallbacks is [fallback] && fallback.scope is WholeFile {
        "note: fallback to tokdiff (\{fallback_reason_text(fallback, parser_reason)})\n" +
        @render.render_diff_document(
          old_label,
          new_label,
          result.document,
          options.render_options(),
        )
      } else if options.ignore_comments {
        let buf = StringBuilder::new()
        for fallback in fallbacks {
          buf <+
            "note: fallback to tokdiff (\{fallback_reason_text(fallback, parser_reason)})\n"
        }
        buf.write_string(
          @render.render_diff_document(
            old_label,
            new_label,
            result.document,
            options.render_options(),
          ),
        )
        buf.to_string()
      } else {
        match calculation.layout {
          WholeDocument =>
            render_legacy_whole_ast_document(
              old_label,
              old_source,
              new_label,
              new_source,
              result.document,
              options,
            )
          TopLevelSections(sections) =>
            render_sectioned_document(
              old_label,
              new_label,
              result.document,
              fallbacks,
              parser_reason,
              options,
              sections,
            )
        }
      }
  }
  let kind = if parser_reason is Some(reason) {
    TextFallback(reason~)
  } else {
    Ast
  }
  { kind, rendered, has_changes }
}
