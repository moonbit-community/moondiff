///|
fn markdown_html(
  source : String,
  scope~ : String,
  markdown? : MarkdownContext,
) -> String raise {
  let safe = @cmark_html.renderer(safe=true)
  let linked = Ref(0)
  let discussion = @cmark_renderer.Renderer::new(
    inline=fn(context, inline) raise {
      match inline {
        Break(_) => {
          context.string("<br>\n")
          true
        }
        Link(link) =>
          match link.v.reference_definition(context.doc.defs) {
            Some(LinkDef(definition)) => {
              guard markdown_link_destination(
                  definition.v.dest.map(n => n.v).unwrap_or(""),
                  markdown,
                )
                is Some(destination) else {
                context.inline(link.v.text)
                return true
              }
              context.string(
                markdown_link_open(
                  destination,
                  definition.v.title.map(lines => {
                    lines.iter().map(t => t.node.v).join("\n")
                  }),
                ),
              )
              // Child images reuse the outer link instead of nesting an anchor.
              linked.val += 1
              defer {
                linked.val -= 1
              }
              context.inline(link.v.text)
              context.string("</a>")
              true
            }
            // Generated footnotes keep their document-local fragment links.
            _ => {
              linked.val += 1
              defer {
                linked.val -= 1
              }
              (safe.inline)(context, inline)
            }
          }
        Autolink(link) => {
          let source = (if link.v.is_email { "mailto:" } else { "" }) +
            link.v.link.v
          if markdown_link_destination(source, markdown) is Some(destination) {
            context.string(markdown_link_open(destination, None))
            context.string(markdown_escape(link.v.link.v))
            context.string("</a>")
          } else {
            context.string(markdown_escape(link.v.link.v))
          }
          true
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
          context.string(
            markdown_raw_html(source, markdown, linked.val > 0, block=false),
          )
          true
        }
        _ => false
      }
    },
    block=fn(context, block) {
      guard block is HtmlBlock(raw) else { return false }
      context.string(
        markdown_raw_html(
          raw.v.0.iter().map(n => n.v).join("\n"),
          markdown,
          linked.val > 0,
          block=true,
        ),
      )
      context.string("\n")
      true
    },
  )
  safe
  .compose(discussion)
  .doc_to_string(
    markdown_scope_footnotes(
      @cmark.Doc::from_string(strict=false, source),
      scope,
    ),
  )
  .trim_end(chars="\n")
  .to_owned()
}

///|
#warnings("-alert_xss_vulnerable")
fn markdown_view(
  source : String,
  class~ : String,
  scope~ : String,
  markdown? : MarkdownContext,
) -> @rabbita.Html {
  try markdown_html(source, scope~, markdown?) catch {
    // A rendering failure must not hide a discussion or interrupt the diff.
    _ => @html.div(class="\{class} markdown-body markdown-fallback", source)
  } noraise {
    rendered =>
      // Only safe cmark output, escaped HTML text and rebuilt images reach here.
      @html.div(
        class="\{class} markdown-body",
        attrs=@html.Attrs::build().inner_html(rendered),
        @html.nothing,
      )
  }
}

///|
fn pull_body_view(
  body : String?,
  user : @protocol.ApiCommentUser?,
  generation~ : Int32,
  markdown? : MarkdownContext,
) -> @rabbita.Html {
  guard body is Some(body) && !body.trim().is_empty() else {
    return @html.nothing
  }
  let author = author_label(user)
  @html.section(
    class="pull-description",
    attrs=@html.Attrs::build().aria_label("Pull request description"),
    [
      @html.div(class="github-comment-meta pull-description-meta", [
        comment_avatar(if author == "ghost" { None } else { Some(author) }),
        @html.div(class="comment-byline", @html.strong(author)),
      ]),
      markdown_view(
        body,
        class="pull-request-body",
        scope="\{generation}:pull-description",
        markdown?,
      ),
    ],
  )
}
