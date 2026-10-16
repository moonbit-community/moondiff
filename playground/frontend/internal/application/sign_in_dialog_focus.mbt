///|
priv struct SignInDialogFocus {
  generation : Int32
  expected : SignInDialog
  entry : SignInEntry?
  trigger : @dom.Element?
}

///|
let sign_in_dialog_focus : Ref[SignInDialogFocus?] = Ref(None)

///|
// Publish intent at the central event boundary. Regional DOM can still describe
// an older open/close revision while its next paint is queued.
pub fn prepare_sign_in_dialog(model : Model, msg : Msg) -> Unit {
  if sign_in_dialog_focus.val is Some(previous) &&
    previous.generation != model.generation {
    clear_sign_in_scroll_floor()
  }
  let previous = sign_in_dialog_focus.val.filter(state => {
    state.generation == model.generation
  })
  let opening = model.sign_in_dialog.entry is Some(_) &&
    previous
    .map(state => state.expected != model.sign_in_dialog)
    .unwrap_or(true)
  let trigger = if opening {
    match msg {
      Ui(OpenSignIn(_, _, trigger)) => trigger
      _ => @dom.document().get_active_element()
    }
  } else {
    match previous {
      Some(state) => state.trigger
      None => None
    }
  }
  sign_in_dialog_focus.val = Some({
    generation: model.generation,
    expected: model.sign_in_dialog,
    entry: match (model.sign_in_dialog.entry, previous) {
      (Some(entry), _) => Some(entry)
      (None, Some(state)) => state.entry
      _ => None
    },
    trigger,
  })
}

///|
fn commit_sign_in_dialog(
  generation : Int32,
  expected : SignInDialog,
) -> @rabbita.Cmd {
  @cmd.custom_cmd(_ => {
    guard sign_in_dialog_focus.val is Some(state) &&
      state.generation == generation &&
      state.expected == expected &&
      @browser.element("sign-in-dialog") is Some(element) &&
      element.get_is_connected() &&
      element.get_attribute("data-generation") == Some(generation.to_string()) &&
      element.get_attribute("data-revision") ==
      Some(expected.revision.to_string()) &&
      element.to_html_dialog_element() is Some(dialog) else {
      return
    }
    if expected.entry is Some(_) {
      let opening = !dialog.open()
      if opening {
        // Auth updates can shorten the inert background. Keep its scroll range
        // so browsers cannot clamp the reading position while the modal is open.
        let page = @dom.document().get_document_element().unwrap()
        @browser.style(page).set_property(
          "--sign-in-page-height",
          "\{page.get_scroll_height()}px",
        )
        dialog.show_modal()
      }
      // Preserve deliberate focus (e.g. Copy code/Cancel) across poll updates.
      let focus_missing = @dom.document()
        .get_active_element()
        .map(active => !element.contains(active.as_node()))
        .unwrap_or(true)
      let button = element.query_selector(
        ".review-sign-in-button:not(:disabled)",
      )
      let status_focused = @dom.document()
        .get_active_element()
        .map(active => {
          active.get_attribute("id") == Some("sign-in-dialog-status")
        })
        .unwrap_or(false)
      if opening || focus_missing || (status_focused && button is Some(_)) {
        if button is Some(button) {
          focus_sign_in_control(element, button)
        } else if @browser.element("sign-in-dialog-status") is Some(status) {
          focus_sign_in_control(element, status)
        }
      }
    } else if dialog.open() {
      dialog.close()
      clear_sign_in_scroll_floor()
      if state.entry is Some(entry) &&
        @browser.element(file_dom_id(entry.file_index())) is Some(file) {
        let trigger = state.trigger.filter(target => {
          target.get_is_connected() &&
          file.contains(target.as_node()) &&
          target.matches(".line-comment-button, .viewed-control input") &&
          !target.matches(":disabled") &&
          target.get_client_rects().get_length() > 0.0
        })
        let target = match trigger {
          Some(target) => Some(target)
          None => file.query_selector(".file-toggle")
        }
        if target is Some(target) {
          @browser.focus(target)
        }
      }
      sign_in_dialog_focus.val = Some({ ..state, entry: None, trigger: None, })
    }
  })
}

///|
fn clear_sign_in_scroll_floor() -> Unit {
  ignore(
    @browser.style(@dom.document().get_document_element().unwrap()).remove_property(
      "--sign-in-page-height",
    ),
  )
}

///|
// Keep keyboard targets visible by scrolling only the dialog's own viewport.
fn focus_sign_in_control(dialog : @dom.Element, target : @dom.Element) -> Unit {
  @browser.focus(target)
  let top = dialog.get_bounding_client_rect().get_top() +
    dialog.get_client_top() +
    4.0
  let bottom = top + dialog.get_client_height() - 8.0
  let rect = target.get_bounding_client_rect()
  let offset = if rect.get_top() < top || rect.get_height() > bottom - top {
    rect.get_top() - top
  } else if rect.get_bottom() > bottom {
    rect.get_bottom() - bottom
  } else {
    0.0
  }
  if offset != 0.0 {
    dialog.set_scroll_top(dialog.get_scroll_top() + offset)
  }
}

///|
pub fn trap_sign_in_focus(event : @dom.KeyboardEvent) -> Unit {
  guard event.key() == "Tab" &&
    @browser.current_element(event.current_target()) is Some(dialog) else {
    return
  }
  let controls = dialog
    .query_selector_all(
      "button:not(:disabled), a[href], input:not(:disabled), [tabindex=\"0\"]",
    )
    .iter()
    .filter(control => control.get_client_rects().get_length() > 0.0)
    .collect()
  guard !controls.is_empty() else { return }
  event.prevent_default()
  let active = @dom.document().get_active_element()
  let current = controls.search_by(control => {
    active.map(element => @browser.same(element, control)).unwrap_or(false)
  })
  let next = match current {
    Some(index) =>
      (index + (if event.shift_key() { -1 } else { 1 }) + controls.length()) %
      controls.length()
    None => if event.shift_key() { controls.length() - 1 } else { 0 }
  }
  focus_sign_in_control(dialog, controls[next])
}
