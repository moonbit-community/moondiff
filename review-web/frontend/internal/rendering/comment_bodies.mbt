///|
priv struct CommentBody {
  body : @dom.Element
  clip : @dom.Element
  button : @dom.Element
  mut candidates : Array[CommentBodyFocus]
}

///|
priv struct CommentBodyFocus {
  element : @dom.Element
  mut tabindex : String?
  mut suppressed : Bool
}

///|
priv struct CommentBodyLayout {
  entry : CommentBody
  preview : Double
  natural : Double
  expanded : Bool
  visible_candidates : Array[Bool]
  focus_hidden : Bool
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
      let entry = self.entries
        .iter()
        .find_first(entry => @browser.same(entry.body, body))
        .unwrap_or_else(() => {
          // The inner Markdown always keeps its natural height, including images.
          observer.observe(body)
          { body, clip, button, candidates: [], }
        })
      let candidates : Array[CommentBodyFocus] = []
      // innerHTML can replace focus candidates while retaining the Markdown container.
      for
        element in body
        .query_selector_all("a[href], pre, div[role=\"region\"], [tabindex]")
        .iter() {
        candidates.push(
          entry.candidates
          .iter()
          .find_first(candidate => @browser.same(candidate.element, element))
          .unwrap_or_else(() => {
            element,
            tabindex: comment_body_tabindex(element),
            suppressed: false,
          }),
        )
      }
      entry.candidates = candidates
      entries.push(entry)
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
fn CommentBodies::read(self : CommentBodies) -> Array[CommentBodyLayout] {
  let layouts : Array[CommentBodyLayout] = []
  let active = @dom.document().get_active_element()
  for entry in self.entries {
    let style = @dom.window().get_computed_style(entry.body)
    let preview = @browser.parse_float(style["line-height"]) * 5.0
    let body = entry.body.get_bounding_client_rect()
    let expanded = entry.clip.get_attribute("data-expanded") == Some("true")
    // Include focused fragment targets as well as tracked Tab candidates.
    let focus_hidden = !expanded &&
      active
      .map(active => {
        entry.body.contains(active.as_node()) &&
        !active
        .get_client_rects()
        .iter()
        .all(rect => {
          rect.get_top() >= body.get_top() - 0.5 &&
          rect.get_bottom() <= body.get_top() + preview + 0.5
        })
      })
      .unwrap_or(false)
    let visible_candidates = entry.candidates.map(candidate => {
      if !candidate.suppressed {
        candidate.tabindex = comment_body_tabindex(candidate.element)
      }
      let visible = if expanded {
        true
      } else {
        // Read every fragment of wrapped candidates relative to the natural body.
        // This remains correct when a prior focus/fragment jump scrolled the clip.
        let rects = candidate.element.get_client_rects()
        rects.length() > 0 &&
        rects
        .iter()
        .all(rect => {
          rect.get_top() >= body.get_top() - 0.5 &&
          rect.get_bottom() <= body.get_top() + preview + 0.5
        })
      }
      visible
    })
    layouts.push({
      entry,
      preview,
      natural: body.get_height(),
      expanded,
      visible_candidates,
      focus_hidden,
    })
  }
  layouts
}

///|
fn comment_body_tabindex(element : @dom.Element) -> String? {
  if element.get_attribute("data-comment-footnote-focus") is Some(_) {
    None
  } else {
    element.get_attribute("tabindex")
  }
}

///|
fn CommentBodies::write(
  _self : CommentBodies,
  layouts : ArrayView[CommentBodyLayout],
) -> Unit {
  for
    { entry, preview, natural, expanded, visible_candidates, focus_hidden, } in layouts {
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
    for index, candidate in entry.candidates {
      if !visible_candidates[index] {
        candidate.element.set_attribute("tabindex", "-1")
        candidate.suppressed = true
      } else if candidate.suppressed {
        match candidate.tabindex {
          Some(value) => candidate.element.set_attribute("tabindex", value)
          None => candidate.element.remove_attribute("tabindex")
        }
        candidate.suppressed = false
      }
    }
    if !expanded {
      entry.clip.set_scroll_top(0.0)
    }
    if focus_hidden {
      @browser.focus(entry.button)
    }
  }
}
