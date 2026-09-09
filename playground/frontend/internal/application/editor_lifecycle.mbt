///|
fn editor_after_update(model : Model) -> @rabbita.Cmd {
  let id = model.review.draft().map(d => d.id.key()).unwrap_or("")
  @cmd.custom_cmd(kind=@cmd.after_render, _ => restore_editor(id))
}

///|
// Capture before patching. Interaction belongs to the draft, not its container.
extern "js" fn capture_editor() -> Unit =
  #| () => {
  #|   if (typeof document === 'undefined') return;
  #|   const state = globalThis.__moondiffEditorInteraction ??= { records: new Map(), active: '' };
  #|   const el = document.querySelector('textarea[data-draft-id]');
  #|   if (!el) {
  #|     for (const saved of state.records.values()) saved.focused = false;
  #|     return;
  #|   }
  #|   state.records.set(el.dataset.draftId, {
  #|     node: el, start: el.selectionStart, end: el.selectionEnd,
  #|     direction: el.selectionDirection, top: el.scrollTop,
  #|     focused: document.activeElement === el
  #|   });
  #| }

///|
extern "js" fn restore_editor(id : String) -> Unit =
  #| id => {
  #|   if (typeof document === 'undefined') return;
  #|   const state = globalThis.__moondiffEditorInteraction ??= { records: new Map(), active: '' };
  #|   const fresh = id && state.active !== id && !state.records.has(id);
  #|   state.active = id;
  #|   for (const key of state.records.keys()) if (key !== id) state.records.delete(key);
  #|   const el = document.querySelector('textarea[data-draft-id]');
  #|   if (!el || el.dataset.draftId !== id) return;
  #|   const saved = state.records.get(id);
  #|   if (fresh || (saved?.focused && saved.node !== el)) el.focus({ preventScroll: true });
  #|   if (saved && saved.node !== el) {
  #|     el.setSelectionRange(saved.start, saved.end, saved.direction);
  #|     el.scrollTop = saved.top;
  #|   }
  #| }
