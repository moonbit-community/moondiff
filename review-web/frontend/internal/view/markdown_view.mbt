///|
fn markdown_html(source : String) -> String raise {
  // GitHub discussions preserve single line breaks. Keep cmark's safe HTML
  // renderer for every other node, including links, images and extensions.
  let breaks = @cmark_renderer.Renderer::new(inline=fn(context, inline) {
    match inline {
      Break(_) => {
        context.string("<br>\n")
        true
      }
      _ => false
    }
  })
  @cmark_html.renderer(safe=true)
  .compose(breaks)
  .doc_to_string(@cmark.Doc::from_string(strict=false, source))
  .trim_end(chars="\n")
  .to_owned()
}

///|
#warnings("-alert_xss_vulnerable")
fn markdown_view(source : String, class~ : String) -> @rabbita.Html {
  try markdown_html(source) catch {
    // A rendering failure must not hide a discussion or interrupt the diff.
    _ => @html.div(class="\{class} markdown-body markdown-fallback", source)
  } noraise {
    rendered =>
      // Only cmark's safe renderer output reaches this HTML sink.
      @html.div(
        class="\{class} markdown-body",
        attrs=@html.Attrs::build().inner_html(rendered),
        @html.nothing,
      )
  }
}
