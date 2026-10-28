///|
priv struct CommentBody {
  body : @dom.Element
  clip : @dom.Element
  button : @dom.Element
}

///|
priv struct CommentBodies {
  host : @dom.Element
  mut entries : Array[CommentBody]
}

///|
fn CommentBodies::sync(
  self : CommentBodies,
  observer : @dom.ResizeObserver,
) -> Unit {
  let entries : Array[CommentBody] = []
  for
    container in self.host.query_selector_all(".github-comment-content").iter() {
    if container.query_selector(".github-comment-body") is Some(body) &&
      container.query_selector(".comment-body-clip") is Some(clip) &&
      container.query_selector(".comment-body-toggle") is Some(button) {
      entries.push({ body, clip, button, })
      if !self.entries.any(entry => @browser.same(entry.body, body)) {
        // The inner Markdown always keeps its natural height, including images.
        observer.observe(body)
      }
    }
  }
  for entry in self.entries {
    if !entries.any(next => @browser.same(entry.body, next.body)) {
      observer.unobserve(entry.body)
    }
  }
  self.entries = entries
}

///|
fn CommentBodies::read(self : CommentBodies) -> Array[Double] {
  let heights : Array[Double] = []
  for entry in self.entries {
    let style = @dom.window().get_computed_style(entry.body)
    heights.push(@browser.parse_float(style["line-height"]) * 5.0)
    heights.push(entry.body.get_bounding_client_rect().get_height())
  }
  heights
}

///|
fn CommentBodies::write(
  self : CommentBodies,
  heights : ArrayView[Double],
) -> Unit {
  for index, entry in self.entries {
    let preview = heights[index * 2]
    let natural = heights[index * 2 + 1]
    if !@browser.finite(preview) || preview <= 0.0 {
      continue
    }
    @browser.style(entry.clip).set_property(
      "--comment-preview-height",
      "\{preview}px",
    )
    // Allow subpixel layout rounding at the exact five-line boundary.
    if natural > preview + 0.5 {
      entry.button.remove_attribute("hidden")
    } else {
      entry.button.set_attribute("hidden", "")
    }
  }
}
