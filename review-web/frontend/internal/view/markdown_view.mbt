///|
fn markdown_html(source : String, markdown? : MarkdownContext) -> String raise {
  let safe = @cmark_html.renderer(safe=true)
  let linked = Ref(0)
  let images = @cmark_renderer.Renderer::new(
    inline=fn(context, inline) raise {
      match inline {
        Break(_) => {
          context.string("<br>\n")
          true
        }
        Link(_) => {
          // Let the safe renderer handle the outer link and its destination.
          // Child images reuse it instead of emitting a nested anchor.
          linked.val += 1
          defer {
            linked.val -= 1
          }
          (safe.inline)(context, inline)
        }
        Image(image) => {
          guard image.v.reference_definition(context.doc.defs)
            is Some(LinkDef(definition)) else {
            return false
          }
          context.string(
            markdown_image_html(
              {
                src: definition.v.dest.map(n => n.v).unwrap_or(""),
                alt: image.v.text
                .to_plain_text(break_on_soft=false)
                .iter()
                .map(line => line.iter().join(""))
                .join("\n"),
                title: definition.v.title.map(lines => {
                  lines.iter().map(t => t.node.v).join("\n")
                }),
                width: None,
                height: None,
              },
              markdown,
              linked.val > 0,
            ),
          )
          true
        }
        RawHtml(raw) => {
          let source = raw.v.0.iter().map(t => t.node.v).join("\n")
          guard parse_html_images(source) is Some(images) else { return false }
          for image in images {
            context.string(markdown_image_html(image, markdown, linked.val > 0))
          }
          true
        }
        _ => false
      }
    },
    block=fn(context, block) {
      guard block is HtmlBlock(raw) &&
        parse_html_images(raw.v.0.iter().map(n => n.v).join("\n"))
        is Some(images) else {
        return false
      }
      for image in images {
        context.string(markdown_image_html(image, markdown, linked.val > 0))
      }
      context.string("\n")
      true
    },
  )
  safe
  .compose(images)
  .doc_to_string(@cmark.Doc::from_string(strict=false, source))
  .trim_end(chars="\n")
  .to_owned()
}

///|
#warnings("-alert_xss_vulnerable")
fn markdown_view(
  source : String,
  class~ : String,
  markdown? : MarkdownContext,
) -> @rabbita.Html {
  try markdown_html(source, markdown?) catch {
    // A rendering failure must not hide a discussion or interrupt the diff.
    _ => @html.div(class="\{class} markdown-body markdown-fallback", source)
  } noraise {
    rendered =>
      // cmark safe output plus rebuilt, escaped image markup reaches this sink.
      @html.div(
        class="\{class} markdown-body",
        attrs=@html.Attrs::build().inner_html(rendered),
        @html.nothing,
      )
  }
}

///|
fn pull_body_view(body : String?, markdown? : MarkdownContext) -> @rabbita.Html {
  guard body is Some(body) && !body.trim().is_empty() else {
    return @html.nothing
  }
  @html.section(
    class="pull-description",
    attrs=@html.Attrs::build().aria_label("Pull request description"),
    markdown_view(body, class="pull-request-body", markdown?),
  )
}
