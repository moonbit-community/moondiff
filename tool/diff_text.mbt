///|UUID(418e4bf6-de65-4cf2-a04e-b5e635f0f368)
// Collapse parser diagnostics into the short reason printed before a fallback
// line diff. Multiple diagnostics are intentionally summarized so the diff
// output stays readable.
fn parse_report_summary(
  label : String,
  reports : Array[@basic.Report],
) -> String? {
  if reports.is_empty() {
    None
  } else if reports.length() == 1 {
    Some("\{label}: \{reports[0]}")
  } else {
    Some("\{label}: \{reports.length()} parse errors, first: \{reports[0]}")
  }
}

///|UUID(fb09927f-8d77-415f-9b0e-b40809807775)
// Parser failures should still produce a useful textual diff. Match
// difftastic's behavior by making the fallback explicit in the output.
fn render_text_fallback(
  reason : String,
  old_label : String,
  old_source : String,
  new_label : String,
  new_source : String,
  options : DiffOptions,
) -> String {
  "note: fallback to line diff (\{reason})\n" +
  @render.render_line_diff(
    old_label,
    old_source,
    new_label,
    new_source,
    None,
    None,
    options.render_options(),
  )
}

///|UUID(4dc6c7bd-e552-4ca2-b156-8b254afe1200)
// Parse both inputs, render an AST-aware diff when possible, and fall back to a
// plain line diff when either side cannot be parsed.
pub fn diff_text(
  old_label : String,
  old_source : String,
  new_label : String,
  new_source : String,
  options? : DiffOptions = DiffOptions::default(),
) -> DiffResult {
  let has_changes = old_source != new_source

  let (old_impls, old_reports) = @parser.parse_string(old_source)
  let (new_impls, new_reports) = @parser.parse_string(new_source)
  let parser_reason = match
    (
      parse_report_summary("old", old_reports),
      parse_report_summary("new", new_reports),
    ) {
    (Some(old_reason), Some(new_reason)) => Some(old_reason + "; " + new_reason)
    (Some(reason), None) | (None, Some(reason)) => Some(reason)
    (None, None) => None
  }
  if parser_reason is Some(reason) {
    return DiffResult::{
      kind: TextFallback(reason~),
      rendered: render_text_fallback(
        reason, old_label, old_source, new_label, new_source, options,
      ),
      has_changes,
    }
  }

  let rendered = @alignment.render_aligned_impl_diffs(
    old_label,
    old_source,
    old_impls,
    new_label,
    new_source,
    new_impls,
    options.graph_limit,
    options.render_options(),
  )
  DiffResult::{ kind: Ast, rendered, has_changes }
}
