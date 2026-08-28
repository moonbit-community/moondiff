///|
fn computation_stage_text(stage : @model.ComputationStage) -> String {
  match stage {
    TopLevelAlignment => "top-level alignment"
    SyntaxMatching => "syntax matching"
    IntralineMatching => "intraline matching"
  }
}

///|
fn fallback_sides_text(sides : ArrayView[@model.DiffSide]) -> String {
  let names = sides.map(side => {
    match side {
      Old => "old"
      New => "new"
    }
  })
  match names {
    [] => ""
    [side] => "the \{side} side"
    _ => "the \{names.join(" and ")} sides"
  }
}

///|
fn fallback_reason_text(reason : @model.FallbackReason) -> String {
  match reason {
    ParseError(detail~, ..) => detail
    SyntaxPositionsOutOfBounds(sides~) => {
      let side_text = fallback_sides_text(sides)
      if side_text.is_empty() {
        "syntax positions out of bounds"
      } else {
        "syntax positions out of bounds on \{side_text}"
      }
    }
    GraphLimitExceeded(limit~) => "graph limit exceeded (\{limit})"
    ComputationLimitExceeded(stage~, limit~) =>
      "computation limit exceeded (\{limit}) during \{computation_stage_text(stage)}"
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
fn range_text(range : @model.LineRange) -> String {
  if range.len <= 1 {
    "line \{range.start + 1}"
  } else {
    "lines \{range.start + 1}-\{range.start + range.len}"
  }
}

///|
fn optional_range_text(side : String, range : @model.LineRange?) -> String {
  range.map(value => "\{side} \{range_text(value)}").unwrap_or("\{side} absent")
}

///|
fn section_label(label : String, range : @model.LineRange?) -> String {
  range.map(value => "\{label}: \{range_text(value)}").unwrap_or(label)
}

///|
fn section_fragment(section : @model.DiffSection) -> @model.DiffFragment {
  match section {
    Matched(diff~, ..) | Deleted(diff~, ..) | Inserted(diff~, ..) => diff
  }
}

///|
fn section_old_range(section : @model.DiffSection) -> @model.LineRange? {
  match section {
    Matched(old~, ..) | Deleted(old~, ..) => Some(old)
    Inserted(..) => None
  }
}

///|
fn section_new_range(section : @model.DiffSection) -> @model.LineRange? {
  match section {
    Matched(new~, ..) | Inserted(new~, ..) => Some(new)
    Deleted(..) => None
  }
}

///|
fn section_old_context(section : @model.DiffSection) -> String? {
  match section {
    Matched(old_context~, ..) | Deleted(old_context~, ..) => old_context
    Inserted(..) => None
  }
}

///|
fn section_new_context(section : @model.DiffSection) -> String? {
  match section {
    Matched(new_context~, ..) | Inserted(new_context~, ..) => new_context
    Deleted(..) => None
  }
}

///|
fn declaration_context_text(
  old_context : String?,
  new_context : String?,
) -> String {
  match (old_context, new_context) {
    (None, None) => ""
    (Some(old), Some(new)) =>
      if old == new {
        old
      } else {
        "old: \{old} → new: \{new}"
      }
    (Some(old), None) => old
    (None, Some(new)) => new
  }
}

///|
fn section_context(section : @model.DiffSection) -> String {
  declaration_context_text(
    section_old_context(section),
    section_new_context(section),
  )
}

///|
fn section_kind(section : @model.DiffSection) -> String {
  match section {
    Matched(..) => "matched"
    Deleted(..) => "deleted"
    Inserted(..) => "inserted"
  }
}

///|
fn section_title(index : Int, section : @model.DiffSection) -> String {
  let old = section_old_range(section)
  let new = section_new_range(section)
  let title = "[section #\{index + 1} \{section_kind(section)}] " +
    optional_range_text("old", old) +
    "; " +
    optional_range_text("new", new)
  let context = section_context(section)
  if context.is_empty() {
    "\{title}\n"
  } else {
    "\{title} · \{context}\n"
  }
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
/// Keep established whole-file anchors for an entirely empty input. Semantic
/// sections never call this helper: a missing section side has no file range
/// and therefore is not assigned a fabricated cursor.
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
fn render_section_fragment(
  old_label : String,
  new_label : String,
  section_index : Int,
  section : @model.DiffSection,
  options : Options,
  old_line_count : Int,
  new_line_count : Int,
) -> String {
  let fragment = section_fragment(section)
  if fragment.document.hunks.is_empty() && fragment.fallbacks.is_empty() {
    return ""
  }
  let old_range = section_old_range(section)
  let new_range = section_new_range(section)
  let old_base = old_range.map(range => range.start).unwrap_or(0)
  let new_base = new_range.map(range => range.start).unwrap_or(0)
  let document = fragment.document.rebase(old_base, new_base)
  let buf = StringBuilder()
  buf.write_string(section_title(section_index, section))
  for fallback in fragment.fallbacks {
    buf <+ "note: fallback to tokdiff (\{fallback_reason_text(fallback)})\n"
  }
  if !document.hunks.is_empty() {
    buf.write_string(
      @terminal.render_document(
        section_label(old_label, old_range),
        section_label(new_label, new_range),
        document,
        options=terminal_options(options, old_line_count, new_line_count),
      ),
    )
  }
  buf.to_string()
}

///|
fn render_top_level_document(
  old_label : String,
  new_label : String,
  top : @model.TopLevelDiff,
  options : Options,
  old_line_count : Int,
  new_line_count : Int,
) -> String {
  let buf = StringBuilder()
  let wrote = Ref(false)
  for section_index in top.new_order {
    guard top.sections.get(section_index) is Some(section) else { continue }
    if section is Deleted(..) {
      continue
    }
    let rendered = render_section_fragment(
      old_label, new_label, section_index, section, options, old_line_count, new_line_count,
    )
    if !rendered.is_empty() {
      append_rendered_section(buf, wrote, rendered)
    }
  }

  let deleted : Array[Int] = []
  for section_index in top.old_order {
    if top.sections.get(section_index) is Some(Deleted(..)) {
      deleted.push(section_index)
    }
  }
  if deleted.any(section_index => {
      guard top.sections.get(section_index) is Some(section) else { false }
      let fragment = section_fragment(section)
      !fragment.document.hunks.is_empty() || !fragment.fallbacks.is_empty()
    }) {
    append_rendered_section(buf, wrote, "Deleted declarations (old order):\n")
    for section_index in deleted {
      guard top.sections.get(section_index) is Some(section) else { continue }
      let rendered = render_section_fragment(
        old_label, new_label, section_index, section, options, old_line_count, new_line_count,
      )
      if !rendered.is_empty() {
        append_rendered_section(buf, wrote, rendered)
      }
    }
  }
  buf.to_string()
}

///|
fn render_whole_document(
  old_label : String,
  new_label : String,
  document : @model.HunkDocument,
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
fn line_has_changed_segment(line : @model.DiffLine) -> Bool {
  line.segments.any(segment => segment.kind is Changed)
}

///|
fn mark_plain_row_changed(row : @model.DiffRow) -> @model.DiffRow {
  match row {
    Paired(old_line, new_line) =>
      if line_has_changed_segment(old_line) ||
        line_has_changed_segment(new_line) {
        Paired(old_line, new_line)
      } else {
        Paired(
          mark_plain_line_changed(old_line),
          mark_plain_line_changed(new_line),
        )
      }
    OldOnly(line) => OldOnly(mark_plain_line_changed(line))
    NewOnly(line) => NewOnly(mark_plain_line_changed(line))
  }
}

///|
/// Preserve bounded word refinement on paired plain-text rows. Rows without
/// refinement and unpaired insertions/deletions keep the terminal convention
/// of presenting their complete text as changed.
fn mark_plain_changes(document : @model.HunkDocument) -> @model.HunkDocument {
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
  let document = @linediff.line_diff(old~, new~, context=options.context_lines)
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
    options=@mbtdiff.DiffOptions(
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
    NoStructuralChanges =>
      match result.document() {
        Whole(_) => ""
        TopLevel(top) =>
          render_top_level_document(
            old_label,
            new_label,
            top,
            options,
            old.length(),
            new.length(),
          )
      }
    Reordered => {
      let summary = render_empty_state(
        old_label, new_label, "Top-level declarations reordered; no fragment-local changes.\n",
        options,
      )
      let details = match result.document() {
        Whole(_) => ""
        TopLevel(top) =>
          render_top_level_document(
            old_label,
            new_label,
            top,
            options,
            old.length(),
            new.length(),
          )
      }
      if details.is_empty() {
        summary
      } else {
        summary + "\n" + details
      }
    }
    Changed =>
      match result.document() {
        Whole(fragment) => {
          let buf = StringBuilder()
          for fallback in fragment.fallbacks {
            buf <+
              "note: fallback to tokdiff (\{fallback_reason_text(fallback)})\n"
          }
          buf.write_string(
            render_whole_document(
              old_label,
              new_label,
              fragment.document,
              options,
              old.length(),
              new.length(),
            ),
          )
          buf.to_string()
        }
        TopLevel(top) => {
          let rendered = render_top_level_document(
            old_label,
            new_label,
            top,
            options,
            old.length(),
            new.length(),
          )
          if top.reordered {
            "note: top-level declarations reordered\n" + rendered
          } else {
            rendered
          }
        }
      }
  }
}

///|
/// Calculate and render one CLI diff. Both labels must end in `.mbt` to select
/// MoonBit-aware calculation; all other pairs use the canonical plain Patience
/// line diff. Semantic fragments are explicitly selected and independently
/// rebased before the terminal renderer receives each `HunkDocument`.
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
