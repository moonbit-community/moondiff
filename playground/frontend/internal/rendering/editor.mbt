///|
// Capture at the business event boundary, before the browser can normalize a
// blurred selection in a later frame. Inspect only the registered editor node.
extern "js" fn capture_editor() -> Unit =
  #| () => {
  #|   const state = globalThis.__moondiffEditorInteraction;
  #|   const saved = state?.records.get(state.active);
  #|   const el = saved?.node;
  #|   // A region may remove the old editor before its destination commits.
  #|   // Background responses in that gap must preserve the entire interaction.
  #|   if (!state?.visible || !el?.isConnected) return;
  #|   if (document.activeElement !== el) state.focusIntent = false;
  #|   Object.assign(saved, {
  #|     start: el.selectionStart, end: el.selectionEnd, direction: el.selectionDirection,
  #|     top: el.scrollTop });
  #| }

///|
extern "js" fn restore_editor(host : String, id : String) -> Unit =
  #| (host, id) => {
  #|   const state = globalThis.__moondiffEditorInteraction;
  #|   if (!state?.visible || !id || id !== state.active) return;
  #|   const records = state.records;
  #|   const el = document.getElementById(host)?.querySelector('textarea[data-draft-id]');
  #|   if (el?.isConnected && el.dataset.draftId === id) {
  #|     const saved = records.get(id);
  #|     // Register before focus() so our focusin listener recognizes this node.
  #|     const record = { host, node: el };
  #|     records.set(id, record);
  #|     if (state.focusIntent && saved?.node !== el) el.focus({ preventScroll: true });
  #|     if (saved && saved.node !== el) {
  #|       el.setSelectionRange(saved.start, saved.end, saved.direction);
  #|       el.scrollTop = saved.top;
  #|     }
  #|     Object.assign(record, { start: el.selectionStart, end: el.selectionEnd,
  #|       direction: el.selectionDirection, top: el.scrollTop });
  #|   }
  #| }

///|
extern "js" fn dispose_editor(host : String) -> Unit =
  #| host => {
  #|   const state = globalThis.__moondiffEditorInteraction;
  #|   if (!state) return;
  #|   for (const [key, record] of state.records) {
  #|     if (record.host !== host) continue;
  #|     state.records.delete(key);
  #|     if (key === state.active) {
  #|       state.focusIntent = false;
  #|       state.stopListening?.();
  #|       state.stopListening = null;
  #|     }
  #|   }
  #| }

///|
extern "js" fn active_draft(
  id : String,
  visible : Bool,
  generation : Int,
) -> Unit =
  #| (id, visible, generation) => {
  #|   const state = globalThis.__moondiffEditorInteraction ??= {
  #|     records: new Map(), active: '', visible: false, generation,
  #|     focusIntent: false, stopListening: null,
  #|   };
  #|   if (id !== state.active || generation !== state.generation) {
  #|     state.records.clear();
  #|     state.focusIntent = id !== state.active && !!id && visible;
  #|   }
  #|   state.active = id;
  #|   state.generation = generation;
  #|   state.visible = !!id && visible;
  #|   // Authentication can hide a retained draft. Keep its selection, but do
  #|   // not revive the previous focus intent when the editor becomes visible.
  #|   if (!state.visible) {
  #|     state.focusIntent = false;
  #|     state.stopListening?.();
  #|     state.stopListening = null;
  #|   } else if (!state.stopListening) {
  #|     const interact = event => {
  #|       state.focusIntent = event.target === state.records.get(state.active)?.node;
  #|     };
  #|     document.addEventListener('focusin', interact, true);
  #|     document.addEventListener('pointerdown', interact, true);
  #|     state.stopListening = () => {
  #|       document.removeEventListener('focusin', interact, true);
  #|       document.removeEventListener('pointerdown', interact, true);
  #|     };
  #|   }
  #| }
