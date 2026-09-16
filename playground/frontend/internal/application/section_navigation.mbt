///|
pub fn file_navigation_enabled(model : Model, index : Int) -> Bool {
  guard model.phase is Showing(view) &&
    view.files.get(index) is Some(file) &&
    file.expanded else {
    return false
  }
  if view.reference.target is PullRequest(_) &&
    model.viewed.files.get(index) is Some({ state: Some(Viewed), .. }) {
    return false
  }
  @change.has_navigable_changes(
    file,
    model.diff_algorithm,
    ignore_comments=model.ignore_comments,
    ignore_tests=model.ignore_tests,
  )
}

///|
pub fn navigate_section_change(
  event : @dom.MouseEvent,
  generation : Int,
  direction : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  find_section_change(
    event,
    generation,
    direction,
    section_change_inset,
    (file_index, key, block) => {
      emit(Load(NavigateChange(generation, file_index, key, block, direction)))
    },
    @rabbita.none,
  )
}

///|
// The same measured stack determines selection and landing, even when the
// target section is still collapsed or has not reached its sticky position.
extern "js" fn section_change_inset(section : @dom.Element) -> Double =
  #| section => {
  #|   const summary = section.querySelector('.semantic-section-title');
  #|   const heading = section.closest('.file-card').querySelector('.file-heading');
  #|   const toolbar = document.querySelector('.hero-workspace');
  #|   const title = section.closest('.change-main').querySelector('.change-titlebar');
  #|   return toolbar.getBoundingClientRect().height + title.getBoundingClientRect().height +
  #|     heading.getBoundingClientRect().height + summary.getBoundingClientRect().height + 8;
  #| }

///|
// Flatten DOM order, including the trailing group of deleted declarations.
// Eligibility and geometry are re-read on every activation; hidden rows in a
// collapsed section are targets, but cannot supply a reading position.
extern "js" fn find_section_change(
  event : @dom.MouseEvent,
  generation : Int,
  direction : Int,
  inset : (@dom.Element) -> Double,
  navigate : (Int, String, Int) -> @rabbita.Cmd,
  none : @rabbita.Cmd,
) -> @rabbita.Cmd =
  #| (event, generation, direction, inset, navigate, none) => {
  #|   event.preventDefault();
  #|   event.stopPropagation();
  #|   const main = event.currentTarget.closest('.change-main');
  #|   if (main?.dataset.navigationGeneration !== String(generation)) return none;
  #|   const targets = [];
  #|   let current = -1;
  #|   let boundary = 0;
  #|   for (const file of main.querySelectorAll('.file-card.expanded[data-navigation-enabled="true"]')) {
  #|     if (file.dataset.navigationGeneration !== String(generation)) continue;
  #|     for (const section of file.querySelectorAll('.semantic-section')) {
  #|       if (section.dataset.navigationGeneration !== String(generation)) continue;
  #|       const rows = Array.from(section.querySelectorAll('[data-change-block-start]'));
  #|       const edge = inset(section) + 1;
  #|       const headingEdge = edge - section.querySelector('summary').getBoundingClientRect().height - 8;
  #|       const rect = section.getBoundingClientRect();
  #|       const start = targets.length;
  #|       for (const row of rows) targets.push({ file, section, row });
  #|       if (rect.bottom <= headingEdge) {
  #|         boundary = targets.length;
  #|       } else if (rect.top <= headingEdge) {
  #|         // Before a section's first change, or inside a collapsed section,
  #|         // Previous selects the preceding block rather than skipping it.
  #|         boundary = start;
  #|         for (let i = 0; section.open && i < rows.length; i++) {
  #|           if (rows[i].getBoundingClientRect().top > edge) break;
  #|           current = start + i;
  #|         }
  #|       }
  #|     }
  #|   }
  #|   if (!targets.length) return none;
  #|   const landing = main.__moondiffChangeLanding;
  #|   const landed = landing ? targets.findIndex(target => target.row === landing.target) : -1;
  #|   const atLanding = landed >= 0 && targets[landed].section.open &&
  #|     Math.abs(window.scrollY - landing.scrollY) <= 1 &&
  #|     document.documentElement.scrollHeight === landing.scrollHeight &&
  #|     Math.abs(landing.target.getBoundingClientRect().top - landing.top) <= 1;
  #|   if (atLanding) current = landed;
  #|   else if (window.scrollY <= 1) { current = -1; boundary = 0; }
  #|   const next = (current < 0 ? boundary + (direction > 0 ? 0 : -1) : current + direction);
  #|   const { file, section, row } = targets[(next + targets.length) % targets.length];
  #|   return navigate(Number(file.dataset.fileIndex), section.dataset.sectionKey, Number(row.dataset.changeBlockStart));
  #| }

///|
fn navigate_change_after_render(
  generation : Int,
  file_index : Int,
  section_key : String,
  block : Int,
  direction : Int,
) -> @rabbita.Cmd {
  @cmd.custom_cmd(kind=@cmd.after_render, _ => {
    scroll_to_section_change(
      generation,
      file_dom_id(file_index),
      section_key,
      block,
      direction,
      section_change_inset,
    )
  })
}

///|
extern "js" fn scroll_to_section_change(
  generation : Int,
  file_id : String,
  section_key : String,
  block : Int,
  direction : Int,
  inset : (@dom.Element) -> Double,
) -> Unit =
  #| (generation, fileId, sectionKey, block, direction, inset) => {
  #|   const file = document.getElementById(fileId);
  #|   if (!file?.matches('.expanded[data-navigation-enabled="true"]') ||
  #|       file.dataset.navigationGeneration !== String(generation)) return;
  #|   const main = file.closest('.change-main');
  #|   if (main?.dataset.navigationGeneration !== String(generation)) return;
  #|   const section = Array.from(file.querySelectorAll('.semantic-section')).find(
  #|     element => element.dataset.sectionKey === sectionKey && element.dataset.navigationGeneration === String(generation)
  #|   );
  #|   if (!section?.open) return;
  #|   const target = section.querySelector(`[data-change-block-start="${block}"]`);
  #|   if (!target) return;
  #|   const top = window.scrollY + target.getBoundingClientRect().top - inset(section);
  #|   const max = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
  #|   window.scrollTo({ top: Math.max(0, Math.min(top, max)), behavior: 'instant' });
  #|   main.__moondiffChangeLanding = top > max || top < 0 ? {
  #|     target,
  #|     scrollY: window.scrollY,
  #|     scrollHeight: document.documentElement.scrollHeight,
  #|     top: target.getBoundingClientRect().top,
  #|   } : null;
  #|   main.querySelector(`.change-titlebar [data-change-direction="${direction}"]`)?.focus({ preventScroll: true });
  #| }
